import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import '../../models/note.dart';
import '../../models/page.dart' as page_model;
import '../../models/processed_text.dart';
import '../../services/note_service.dart';
import '../../services/page_service.dart';
import '../../services/image_service.dart';
import '../../services/flashcard_service.dart' hide debugPrint;
import '../../services/dictionary_service.dart';
import '../../services/tts_service.dart';
import '../../services/enhanced_ocr_service.dart';
import '../../services/user_preferences_service.dart';
import '../../services/page_content_service.dart';
import '../../widgets/note_action_bottom_sheet.dart';
import '../../widgets/page_content_widget.dart';
import '../../widgets/edit_title_dialog.dart';
import '../../widgets/note_detail_bottom_bar.dart';
import '../../widgets/note_page_manager.dart';
import '../../widgets/note_segment_manager.dart';
import '../../utils/text_display_mode.dart';
import 'flashcard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/unified_cache_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/text_reader_service.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/tokens/color_tokens.dart';
import 'full_image_screen.dart';
import '../../services/screenshot_service.dart';
import '../../widgets/dot_loading_indicator.dart';
import '../../widgets/common/pika_app_bar.dart';
import '../../theme/tokens/typography_tokens.dart';

/// 노트 상세 화면
/// 페이지 탐색, 노트 액션, 백그라운드 처리, 이미지 로딩 등의 기능

class NoteDetailScreen extends StatefulWidget {
  final String noteId;
  final bool isProcessingBackground;

  const NoteDetailScreen({
    super.key,
    required this.noteId,
    this.isProcessingBackground = false,
  });

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> with WidgetsBindingObserver {
  // 서비스 인스턴스
  final NoteService _noteService = NoteService();
  final PageService _pageService = PageService();
  final ImageService _imageService = ImageService();
  final FlashCardService _flashCardService = FlashCardService();
  final TtsService _ttsService = TtsService();
  final EnhancedOcrService _ocrService = EnhancedOcrService();
  final UserPreferencesService _preferencesService = UserPreferencesService();
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  final PageContentService _pageContentService = PageContentService();
  final TextReaderService _textReaderService = TextReaderService();
  final ScreenshotService _screenshotService = ScreenshotService();
  
  // 관리자 클래스 인스턴스
  late NotePageManager _pageManager;
  late NoteSegmentManager _segmentManager;

  // 상태 변수
  Note? _note;
  bool _isLoading = true;
  String? _error;
  bool _isFavorite = false;
  bool _isCreatingFlashCard = false;
  TextDisplayMode _textDisplayMode = TextDisplayMode.all;
  Timer? _backgroundCheckTimer;
  bool _isProcessingText = false;
  File? _imageFile;
  Note? _processingPage;
  bool _useSegmentMode = true; // 기본값은 세그먼트 모드
  bool _isShowingScreenshotWarning = false;
  Timer? _screenshotWarningTimer;
  Set<int> _previouslyVisitedPages = <int>{};
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageManager = NotePageManager(noteId: widget.noteId);
    _segmentManager = NoteSegmentManager();
    _previouslyVisitedPages = <int>{};
    _pageController = PageController();
    _loadNote();
    _initTts();
    _loadUserPreferences();
    _setupBackgroundProcessingCheck();
    _initScreenshotDetection();
  }

  @override
  void dispose() {
    _backgroundCheckTimer?.cancel();
    _screenshotWarningTimer?.cancel();
    _screenshotService.stopDetection();
    WidgetsBinding.instance.removeObserver(this);
    _ttsService.stop();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 앱 상태 변경 감지
    if (state == AppLifecycleState.resumed) {
      // 앱이 다시 활성화되면 스크린샷 감지 재시작
      _screenshotService.startDetection();
    } else if (state == AppLifecycleState.paused) {
      // 앱이 백그라운드로 가면 스크린샷 감지 중지
      _screenshotService.stopDetection();
    }
  }

  /// 스크린샷 감지 초기화
  Future<void> _initScreenshotDetection() async {
    await _screenshotService.initialize(() {
      if (mounted) {
        _showScreenshotWarning();
      }
    });
    
    await _screenshotService.startDetection();
  }

  // 스크린샷 경고 메시지 표시
  void _showScreenshotWarning() {
    setState(() {
      _isShowingScreenshotWarning = true;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '원서 내용을 무단으로 공유, 배포할 경우 법적 제재를 받을 수 있습니다.',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: ColorTokens.black,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
    
    // 일정 시간 후 경고 상태 초기화
    _screenshotWarningTimer?.cancel();
    _screenshotWarningTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) {
        setState(() {
          _isShowingScreenshotWarning = false;
        });
      }
    });
  }

  // ===== 데이터 로딩 관련 메서드 =====

  Future<void> _loadNote() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 백그라운드 처리 중인 경우 스낵바 표시
      if (widget.isProcessingBackground && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('추가 페이지를 백그라운드에서 처리 중입니다...'),
            duration: Duration(seconds: 3),
          ),
        );
      }

      // 노트와 페이지를 함께 로드 (캐싱 활용)
      final result = await _noteService.getNoteWithPages(widget.noteId);
      final note = result['note'] as Note;
      final serverPages = result['pages'] as List<dynamic>;
      final isFromCache = result['isFromCache'] as bool;
      final isProcessingBackground =
          result['isProcessingBackground'] as bool? ?? false;
      final processingCompleted = note.processingCompleted ?? false;

      if (mounted) {
        setState(() {
          _note = note;
          _isFavorite = note.isFavorite;

          // 페이지 매니저에 페이지 설정
          final typedServerPages = serverPages.cast<page_model.Page>();
          _pageManager.setPages(typedServerPages);
          
          _isLoading = false;
          
          // 첫 번째 페이지를 방문한 페이지로 표시
          if (_pageManager.pages.isNotEmpty) {
            _previouslyVisitedPages.add(0);
          }
        });

        // 페이지 수 로그 출력
        debugPrint('노트에 ${_pageManager.pages.length}개의 페이지가 있습니다. (캐시에서 로드: $isFromCache)');

        // 각 페이지의 이미지 로드
        _pageManager.loadAllPageImages();
        
        // 현재 페이지의 ProcessedText 초기화
        _processTextForCurrentPage();

        // 다음 조건에서 페이지 서비스에 다시 요청
        if ((_pageManager.pages.length <= 1 && isFromCache) || processingCompleted) {
          debugPrint(
              '페이지 다시 로드 조건 충족: 페이지 수=${_pageManager.pages.length}, 캐시=$isFromCache, 처리완료=$processingCompleted');
          _reloadPages(forceReload: processingCompleted);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '노트를 불러오는 중 오류가 발생했습니다: $e';
          _isLoading = false;
        });
      }
    }
  }

  // 백그라운드 처리 완료 확인을 위한 타이머 설정
  void _setupBackgroundProcessingCheck() {
    // 기존 타이머가 있으면 취소
    _backgroundCheckTimer?.cancel();

    // 타이머 생성 전 로그 출력
    debugPrint('백그라운드 처리 확인 타이머 설정: ${widget.noteId}');

    // 5초마다 백그라운드 처리 상태 확인하는 주기적 타이머 설정
    _backgroundCheckTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
      if (!mounted) {
        debugPrint('화면이 더 이상 마운트되지 않음 - 타이머 취소');
        timer.cancel();
        return;
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        final pagesUpdated =
            prefs.getBool('pages_updated_${widget.noteId}') ?? false;

        if (pagesUpdated) {
          // 페이지 업데이트가 완료된 경우
          final updatedPageCount =
              prefs.getInt('updated_page_count_${widget.noteId}') ?? 0;
          debugPrint('백그라운드 처리 완료 감지: $updatedPageCount 페이지 업데이트됨');

          // 플래그 초기화
          await prefs.remove('pages_updated_${widget.noteId}');
          await prefs.remove('updated_page_count_${widget.noteId}');

          // 페이지 다시 로드
          _reloadPages(forceReload: true);

          // 완료 메시지 표시
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$updatedPageCount개의 추가 페이지 처리가 완료되었습니다.'),
                duration: Duration(seconds: 3),
              ),
            );
          }

          // 업데이트가 완료되었으므로 타이머 취소
          debugPrint('백그라운드 처리 완료 - 타이머 취소');
          timer.cancel();
        }
      } catch (e) {
        debugPrint('백그라운드 처리 상태 확인 중 오류 발생: $e');
      }
    });
  }

  // 페이지 다시 로드 
  Future<void> _reloadPages({bool forceReload = false}) async {
    try {
      // 이미 로드 중인지 확인
      if (_isLoading) return;

      setState(() {
        _isLoading = true;
      });

      // 노트 문서에서 처리 완료 상태 확인
      bool processingCompleted = false;
      if (_note != null && _note!.id != null) {
        try {
          final noteDoc = await FirebaseFirestore.instance
              .collection('notes')
              .doc(_note!.id)
              .get();
          if (noteDoc.exists) {
            final data = noteDoc.data();
            processingCompleted =
                data?['processingCompleted'] as bool? ?? false;
            if (processingCompleted) {
              debugPrint('노트 문서에서 백그라운드 처리 완료 상태 확인: $processingCompleted');
              forceReload = true; // 처리가 완료된 경우 강제 로드
            }
          }
        } catch (e) {
          debugPrint('노트 문서 확인 중 오류 발생: $e');
        }
      }

      // 페이지 매니저로 서버에서 페이지 로드
      await _pageManager.loadPagesFromServer();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('페이지 다시 로드 중 오류 발생: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 텍스트 처리 메서드
  Future<void> _processTextForCurrentPage() async {
    final currentPage = _pageManager.currentPage;
    if (currentPage == null) {
      return;
    }

    setState(() {
      _isProcessingText = true;
    });

    try {
      // 텍스트 처리
      final processedText = await _pageContentService.processPageText(
        page: currentPage,
        imageFile: _pageManager.currentImageFile,
      );
      
      if (processedText != null && currentPage.id != null) {
        // 기본 표시 설정 지정
        final updatedProcessedText = processedText.copyWith(
          showFullText: false, // 기본값: 세그먼트 모드
          showPinyin: _textDisplayMode == TextDisplayMode.all, // 토글 모드에 따라 병음 표시
          showTranslation: true, // 번역은 항상 표시
        );
        
        // 업데이트된 텍스트 캐싱 (메모리 캐시만)
        _pageContentService.setProcessedText(currentPage.id!, updatedProcessedText);
        
        debugPrint('텍스트 처리 완료: showFullText=${updatedProcessedText.showFullText}, '
            'showPinyin=${updatedProcessedText.showPinyin}, '
            'showTranslation=${updatedProcessedText.showTranslation}, '
            'segments=${updatedProcessedText.segments?.length ?? 0}개');
      }
    } catch (e) {
      debugPrint('텍스트 처리 중 오류 발생: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingText = false;
        });
      }
    }
  }

  // ===== TTS 관련 메서드 =====

  void _initTts() {
    _ttsService.init();
  }

  // ===== 노트 액션 관련 메서드 =====

  Future<void> _toggleFavorite() async {
    if (_note == null || _note?.id == null) return;

    final newValue = !_isFavorite;

    setState(() {
      _isFavorite = newValue;
    });

    try {
      await _noteService.toggleFavorite(_note!.id!, newValue);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFavorite = !newValue; // 실패 시 원래 값으로 되돌림
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('즐겨찾기 설정 중 오류가 발생했습니다: $e')));
      }
    }
  }

  Future<void> _deleteNote() async {
    if (_note == null || _note?.id == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // 페이지 삭제
      await _pageService.deleteAllPagesForNote(_note!.id!);

      // 노트 삭제
      await _noteService.deleteNote(_note!.id!);

      if (mounted) {
        Navigator.of(context).pop(); // 삭제 후 이전 화면으로 돌아가기
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('노트 삭제 중 오류가 발생했습니다: $e')));
      }
    }
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('노트 삭제'),
        content: const Text('이 노트를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteNote();
            },
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  void _showEditTitleDialog() {
    if (_note == null) return;

    showDialog(
      context: context,
      builder: (context) => EditTitleDialog(
        currentTitle: _note!.originalText,
        onTitleUpdated: _updateNoteTitle,
      ),
    );
  }

  Future<void> _updateNoteTitle(String newTitle) async {
    if (_note == null || _note?.id == null) return;

    // 즉시 UI 업데이트 (낙관적 업데이트)
    final previousTitle = _note!.originalText;
    setState(() {
      _note = _note!.copyWith(
        originalText: newTitle,
        updatedAt: DateTime.now(),
      );
      _isLoading = true;
    });

    try {
      // Firestore 업데이트
      await _noteService.updateNote(_note!.id!, _note!);

      // 업데이트 완료
      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('노트 제목이 변경되었습니다.')),
        );
      }
    } catch (e) {
      // 오류 발생 시 이전 제목으로 복원
      if (mounted) {
        setState(() {
          _note = _note!.copyWith(
            originalText: previousTitle,
          );
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('노트 제목 변경 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  // ===== 페이지 탐색 관련 메서드 =====

  void _changePage(int index) {
    if (index < 0 || index >= _pageManager.pages.length) return;
    
    final previousPageIndex = _pageManager.currentPageIndex;
    final isSwitchingBack = _previouslyVisitedPages.contains(index);
    
    debugPrint('페이지 변경: $previousPageIndex -> $index (이전에 방문한 페이지: $isSwitchingBack)');
    
    // PageController를 통한 페이지 이동 (화살표 버튼으로 이동할 때)
    // PageView의 onPageChanged에서 호출되는 경우에는 이미 페이지가 변경된 상태
    if (index != _pageManager.currentPageIndex) {
      try {
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } catch (e) {
        debugPrint('페이지 애니메이션 오류: $e');
      }
    }
    
    // 페이지 매니저에서 페이지 변경
    _pageManager.changePage(index);
    
    // 이전에 방문한 페이지가 아닌 경우에만 방문 기록 추가
    if (!_previouslyVisitedPages.contains(index)) {
      _previouslyVisitedPages.add(index);
      debugPrint('방문 기록 추가: $index, 총 방문 페이지: ${_previouslyVisitedPages.length}개');
    }
    
    // 페이지가 변경되면 새 페이지의 ProcessedText 초기화
    _processTextForCurrentPage();
    
    // UI 업데이트
    setState(() {});
  }
  
  // 페이지가 완전히 로드되었는지 확인
  bool _isPageFullyLoaded(page_model.Page? page) {
    if (page == null) return false;
    if (page.originalText.isEmpty || page.originalText == 'processing') return false;
    return true;
  }

  // ===== 메뉴 및 다이얼로그 관련 메서드 =====

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => NoteActionBottomSheet(
        onEditTitle: _showEditTitleDialog,
        onDeleteNote: _confirmDelete,
        onToggleFullTextMode: _toggleFullTextMode,
        onToggleFavorite: _toggleFavorite,
        isFullTextMode: _pageManager.currentPage?.id != null 
            ? _pageContentService.getProcessedText(_pageManager.currentPage!.id!)?.showFullText ?? true
            : true,
        isFavorite: _isFavorite,
      ),
    );
  }

  // ===== 사용자 설정 관련 메서드 =====

  Future<void> _loadUserPreferences() async {
    try {
      // 사용자가 선택한 번역 모드 가져오기
      final noteViewMode = await _preferencesService.getDefaultNoteViewMode();
      final useSegmentMode = await _preferencesService.getUseSegmentMode();
      
      if (mounted) {
        setState(() {
          // TextDisplayMode는 병음 표시 여부에 관한 것이므로 별도로 처리
          _textDisplayMode = TextDisplayMode.all; // 기본값으로 모든 정보 표시
          
          // 세그먼트 모드 여부는 별도 변수로 저장
          _useSegmentMode = useSegmentMode;
        });
      }
      debugPrint('노트 뷰 모드 로드됨: ${noteViewMode.toString()}, 세그먼트 모드 사용: $_useSegmentMode');
    } catch (e) {
      debugPrint('사용자 기본 설정 로드 중 오류 발생: $e');
      // 오류 발생 시 기본 모드 사용
      if (mounted) {
    setState(() {
          _textDisplayMode = TextDisplayMode.all;
          _useSegmentMode = true; // 기본값은 세그먼트 모드
        });
      }
    }
  }

  // ===== 플래시카드 관련 메서드 =====

  Future<void> _createFlashCard(String front, String back,
      {String? pinyin}) async {
    if (_isCreatingFlashCard) return;

    setState(() {
      _isCreatingFlashCard = true;
    });

    try {
      // 빈 문자열이 전달된 경우 (SegmentedTextWidget에서 호출된 경우)
      // 플래시카드 생성을 건너뛰고 노트 상태만 업데이트
      if (front.isEmpty && back.isEmpty) {
        debugPrint('SegmentedTextWidget에서 호출: 노트 상태만 업데이트');
      } else {
        // 사전에서 단어 정보 찾기
        final dictionaryService = DictionaryService();
        final dictionaryEntry = dictionaryService.lookupWord(front);

        // 사전에 단어가 있으면 병음과 의미 사용
        final String finalBack;
        final String? finalPinyin;

        if (dictionaryEntry != null) {
          finalBack = dictionaryEntry.meaning;
          finalPinyin = dictionaryEntry.pinyin;
        } else {
          finalBack = back;
          finalPinyin = pinyin;
        }

        // 플래시카드 생성
        await _flashCardService.createFlashCard(
          front: front,
          back: finalBack,
          pinyin: finalPinyin,
          noteId: widget.noteId,
        );
      }

      // 캐시 무효화
      await _cacheService.removeCachedNote(widget.noteId);

      // Firestore에서 직접 노트 가져오기
      final noteDoc = await FirebaseFirestore.instance
          .collection('notes')
          .doc(widget.noteId)
          .get();

      if (noteDoc.exists && mounted) {
        final updatedNote = Note.fromFirestore(noteDoc);
        setState(() {
          _note = updatedNote;
          debugPrint(
              '노트 ${widget.noteId}의 플래시카드 카운터 업데이트: ${_note!.flashcardCount}개');
        });
      }
    } catch (e) {
      debugPrint('플래시카드 생성 중 오류 발생: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingFlashCard = false;
        });
      }
    }
  }

  // ===== 플래시카드 화면 이동 관련 메서드 =====

  Future<void> _navigateToFlashcards() async {
    if (_note == null) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FlashCardScreen(
          noteId: widget.noteId,
        ),
      ),
    );

    // 플래시카드가 변경되었으면 노트 정보 다시 로드
    if (result != null && mounted) {
      if (result is Note) {
        // 플래시카드 화면에서 직접 업데이트된 노트 객체를 받은 경우
        setState(() {
          _note = result;
          debugPrint(
              '노트 ${widget.noteId}의 플래시카드 카운터 업데이트: ${_note!.flashcardCount}개');
        });

        // 노트 정보가 변경되었으므로 캐시도 업데이트
        await _cacheService.cacheNote(_note!);
      } else if (result == true) {
        // 이전 방식과의 호환성을 위해 boolean 결과도 처리
        // 캐시 무효화
        await _cacheService.removeCachedNote(widget.noteId);

        // Firestore에서 직접 노트 가져오기
        final noteDoc = await FirebaseFirestore.instance
            .collection('notes')
            .doc(widget.noteId)
            .get();

        if (noteDoc.exists && mounted) {
          final updatedNote = Note.fromFirestore(noteDoc);
          setState(() {
            _note = updatedNote;
            debugPrint(
                '노트 ${widget.noteId}의 플래시카드 카운터 업데이트: ${_note!.flashcardCount}개');
          });
          
          // 업데이트된 노트 캐싱
          await _cacheService.cacheNote(updatedNote);
        }
      }
    }
  }

  // 세그먼트 삭제 처리
  Future<void> _handleDeleteSegment(int segmentIndex) async {
    debugPrint('세그먼트 삭제 요청: index=$segmentIndex');
    
    final currentPage = _pageManager.currentPage;
    if (currentPage == null || currentPage.id == null || _note == null || _note!.id == null) {
      debugPrint('현재 페이지 또는 노트 없음 - 삭제할 수 없음');
      return;
    }
    
    // NoteSegmentManager를 사용하여 세그먼트 삭제
    final segmentManager = NoteSegmentManager();
    final updatedPage = await segmentManager.deleteSegment(
      noteId: _note!.id!,
      page: currentPage,
      segmentIndex: segmentIndex,
    );
    
    if (updatedPage == null) {
      debugPrint('세그먼트 삭제 실패');
      return;
    }
    
    // 화면 갱신을 위한 페이지 업데이트
    setState(() {
      // 페이지 매니저의 현재 페이지 업데이트
      _pageManager.updateCurrentPage(updatedPage);
      
      // 페이지 콘텐츠 서비스에서 ProcessedText 다시 가져오기
      if (updatedPage.id != null) {
        final processedText = _pageContentService.getProcessedText(updatedPage.id!);
        if (processedText != null) {
          debugPrint('삭제 후 ProcessedText 업데이트: ${processedText.segments?.length ?? 0}개 세그먼트');
        }
      }
      
      debugPrint('세그먼트 삭제 후 UI 업데이트 완료');
    });
    
    // 노트 캐시 업데이트를 위해 노트 서비스 호출
    try {
      await _noteService.getNoteWithPages(_note!.id!);
      debugPrint('세그먼트 삭제 후 노트 및 페이지 캐시 새로고침 완료');
    } catch (e) {
      debugPrint('세그먼트 삭제 후 노트 캐시 새로고침 중 오류 발생: $e');
    }
  }

  // 텍스트 디스플레이 모드 변경 처리
  void _handleTextDisplayModeChanged(TextDisplayMode mode) {
    debugPrint('=====================================================');
    debugPrint('텍스트 디스플레이 모드 변경 요청: $mode');
    
    setState(() {
      // 모드 변경
      _textDisplayMode = mode;
      
      // 현재 페이지의 ProcessedText 업데이트
      final currentPage = _pageManager.currentPage;
      if (currentPage != null && currentPage.id != null) {
        debugPrint('현재 페이지 ID: ${currentPage.id}');
        
        // 캐시된 processedText 가져오기
        final processedText = _pageContentService.getProcessedText(currentPage.id!);
        
        if (processedText != null) {
          // 기존 상태 로깅
          debugPrint('기존 ProcessedText 상태: '
              'showFullText=${processedText.showFullText}, '
              'showPinyin=${processedText.showPinyin}, '
              'showTranslation=${processedText.showTranslation}');
              
          // 병음 토글 처리
          bool showPinyin = (mode == TextDisplayMode.all);
          debugPrint('병음 표시 설정 변경: $showPinyin (모드: $mode)');
          
          // processedText 업데이트
          final updatedText = processedText.copyWith(
            showFullText: processedText.showFullText, // 전체/세그먼트 모드는 유지
            showPinyin: showPinyin,           // 병음 표시 여부 업데이트
            showTranslation: true,            // 번역은 항상 표시
          );
          
          // 업데이트 내용 확인
          debugPrint('업데이트할 ProcessedText 상태: '
              'showFullText=${updatedText.showFullText}, '
              'showPinyin=${updatedText.showPinyin}, '
              'showTranslation=${updatedText.showTranslation}');
              
          // 업데이트된 ProcessedText 저장
          _pageContentService.setProcessedText(currentPage.id!, updatedText);
          
          // 변경 후 캐시 상태 확인
          final afterUpdate = _pageContentService.getProcessedText(currentPage.id!);
          if (afterUpdate != null) {
            debugPrint('업데이트 후 캐시된 ProcessedText 상태: '
                'showFullText=${afterUpdate.showFullText}, '
                'showPinyin=${afterUpdate.showPinyin}, '
                'showTranslation=${afterUpdate.showTranslation}');
          }
        } else {
          debugPrint('ProcessedText가 null임 - 업데이트 건너뜀');
        }
      } else {
        debugPrint('현재 페이지 없음 - 업데이트 건너뜀');
      }
    });
    
    debugPrint('=====================================================');
  }
  
  // 세그먼트/전체 텍스트 모드 전환 처리 메서드
  void _toggleFullTextMode() {
    final currentPage = _pageManager.currentPage;
    if (currentPage == null || currentPage.id == null) {
      return;
    }
    
    // 캐시된 processedText 가져오기
    final processedText = _pageContentService.getProcessedText(currentPage.id!);
    if (processedText == null) {
      return;
    }
    
    debugPrint('모드 전환 요청: 현재 showFullText=${processedText.showFullText}, '
        'showFullTextModified=${processedText.showFullTextModified}');
    
    setState(() {
      // toggleDisplayMode 메서드 사용 (showFullTextModified를 true로 설정)
      final updatedText = processedText.toggleDisplayMode();
      
      // 업데이트된 ProcessedText 저장
      _pageContentService.setProcessedText(currentPage.id!, updatedText);
      
      debugPrint('모드 전환 완료: 변경 후 showFullText=${updatedText.showFullText}, '
          'showFullTextModified=${updatedText.showFullTextModified}');
    });
  }
  
  // 재생/일시정지 버튼 처리
  void _handlePlayPausePressed() {
    final currentPage = _pageManager.currentPage;
    if (currentPage == null) return;
    
    debugPrint('재생/일시정지 버튼 클릭: isPlaying=${_textReaderService.isPlaying}');
    
    if (_textReaderService.isPlaying) {
      _textReaderService.stop();
      setState(() {});
    } else if (currentPage.originalText.isNotEmpty) {
      // ProcessedText 가져오기
      final processedText = _pageContentService.getProcessedText(currentPage.id!);
      if (processedText != null) {
        debugPrint('텍스트 재생 시작: 길이=${currentPage.originalText.length}자, 세그먼트=${processedText.segments?.length ?? 0}개');
        
        // 세그먼트 모드일 때는 readAllSegments, 전체 텍스트 모드일 때는 readText 사용
        if (processedText.segments != null && processedText.segments!.isNotEmpty) {
          debugPrint('세그먼트 모드로 텍스트 재생');
          _textReaderService.readAllSegments(processedText);
        } else {
          debugPrint('전체 텍스트 모드로 텍스트 재생');
          _textReaderService.readText(currentPage.originalText);
        }
        
        setState(() {});
      } else {
        debugPrint('ProcessedText가 null임 - 재생할 수 없음');
      }
    } else {
      debugPrint('텍스트가 비어 있음 - 재생할 수 없음');
    }
  }

  // ===== UI 빌드 메서드 =====

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _isLoading || _error != null
          ? null // 로딩 중이거나 오류 상태에서는 앱바 없음
          : PikaAppBar.noteDetail(
              title: _note?.originalText ?? 'Note',
              onBackPressed: () => Navigator.of(context).pop(),
              onShowMoreOptions: _showMoreOptions,
              onFlashCardPressed: _navigateToFlashcards,
              flashcardCount: _note?.flashcardCount ?? 0,
              noteId: widget.noteId,
              currentPageIndex: _pageManager.currentPageIndex,
              totalPages: _pageManager.pages.length,
            ),
      body: _isLoading
          ? const Center(
              child: DotLoadingIndicator(
                message: '노트 로딩 중...',
              ),
            )
          : _error != null
              ? Center(child: Text(_error ?? '노트를 불러올 수 없습니다.'))
              : _buildBody(),
      bottomNavigationBar: !_isLoading && _error == null && _note != null 
          ? NoteDetailBottomBar(
              currentPage: _pageManager.currentPage,
              currentPageIndex: _pageManager.currentPageIndex,
              totalPages: _pageManager.pages.length,
              onPageChanged: _changePage,
              textDisplayMode: _textDisplayMode,
              onTextDisplayModeChanged: _handleTextDisplayModeChanged,
              isPlaying: _textReaderService.isPlaying,
              onPlayPausePressed: _handlePlayPausePressed,
              pageContentService: _pageContentService,
              textReaderService: _textReaderService,
            )
          : null,
    );
  }
  
  // 메인 UI 구성 (로딩 및 오류 처리 이후)
  Widget _buildBody() {
    final currentImageFile = _pageManager.currentImageFile;
    final String pageNumberText = '${_pageManager.currentPageIndex + 1}/${_pageManager.pages.length}';
    
    return PageView.builder(
      itemCount: _pageManager.pages.length,
      controller: _pageController,
      onPageChanged: (index) {
        debugPrint('PageView 스와이프: 페이지 변경 ($index) - 이전 방문: ${_previouslyVisitedPages.contains(index)}');
        
        // 이전에 방문하지 않은 페이지라면 방문 기록에 추가
        _previouslyVisitedPages.add(index);
        
        _changePage(index);
      },
      itemBuilder: (context, index) {
        // 현재 표시할 페이지 인덱스의 페이지 빌드
        if (index == _pageManager.currentPageIndex) {
          return Column(
            children: [
              // 페이지 썸네일 이미지 (있는 경우)
              if (currentImageFile != null || _pageManager.currentPage?.imageUrl != null)
                Stack(
                  children: [
                    // 이미지 컨테이너
                    Container(
                      height: 200, // 높이를 200으로 고정
                      width: double.infinity, // 화면 너비를 꽉 채움
                      decoration: BoxDecoration(
                        image: currentImageFile != null
                            ? DecorationImage(
                                image: FileImage(currentImageFile),
                                fit: BoxFit.cover,
                              )
                            : _pageManager.currentPage?.imageUrl != null
                                ? DecorationImage(
                                    image: NetworkImage(_pageManager.currentPage!.imageUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                        color: Colors.grey.shade200,
                      ),
                      child: (currentImageFile == null && _pageManager.currentPage?.imageUrl == null)
                          ? Container(
                              color: Colors.grey[100],
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.asset(
                                    'assets/images/image_empty.png',
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.contain,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '이미지를 추가해주세요',
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 14,
                                      color: ColorTokens.textGrey,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : null,
                    ),
                    
                    // '이미지 전체보기' 버튼
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => FullImageScreen(
                                imageFile: currentImageFile,
                                imageUrl: _pageManager.currentPage?.imageUrl,
                                title: '이미지',
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black.withOpacity(0.5),
                          foregroundColor: Colors.white,
                          elevation: 0,
                        ),
                        child: Text(
                          '이미지 전체보기',
                          style: TypographyTokens.caption.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              
              // 페이지 내용 (Expanded로 감싸 남은 공간 채우기)
              Expanded(
                child: Container(
                  color: Colors.white, // 배경색 흰색
                  padding: const EdgeInsets.all(0), // 패딩 0으로 설정 (ProcessedTextWidget에서 패딩 적용)
                  child: _buildCurrentPageContent(),
                ),
              ),
            ],
          );
        } else {
          // 다른 페이지는 페이지 매니저에서 해당 인덱스의 페이지를 가져와서 미리 로드
          final page = _pageManager.getPageAtIndex(index);
          final imageFile = _pageManager.getImageFileForPage(page);
          
          return Column(
        children: [
              // 페이지 썸네일 이미지 (있는 경우)
              if (imageFile != null || page?.imageUrl != null)
                Stack(
                  children: [
                    // 이미지 컨테이너
                    Container(
                      height: 200, // 높이를 200으로 고정
                      width: double.infinity, // 화면 너비를 꽉 채움
                      decoration: BoxDecoration(
                        image: imageFile != null
                            ? DecorationImage(
                                image: FileImage(imageFile),
                                fit: BoxFit.cover,
                              )
                            : page?.imageUrl != null
                                ? DecorationImage(
                                    image: NetworkImage(page!.imageUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                        color: Colors.grey.shade200,
                      ),
                      child: (imageFile == null && page?.imageUrl == null)
                          ? Container(
                              color: Colors.grey[100],
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Image.asset(
                                    'assets/images/image_empty.png',
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.contain,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '이미지를 추가해주세요',
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 14,
                                      color: ColorTokens.textGrey,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : null,
                    ),
                    
                    // '이미지 전체보기' 버튼
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => FullImageScreen(
                                imageFile: imageFile,
                                imageUrl: page?.imageUrl,
                                title: '이미지',
                              ),
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black.withOpacity(0.5),
                          foregroundColor: Colors.white,
                          elevation: 0,
                        ),
                        child: Text(
                          '이미지 전체보기',
                          style: TypographyTokens.caption.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              
              // 페이지 내용을 위한 공간
              const Expanded(
                child: Center(
                  child: DotLoadingIndicator(
                    message: '다음 페이지를 준비하고 있어요.',
                    dotColor: Color(0xFFFFD53C),
                  ),
                ),
              ),
            ],
          );
        }
      },
    );
  }

  // 현재 페이지 내용 빌드
  Widget _buildCurrentPageContent() {
    final currentPage = _pageManager.currentPage;
    final currentImageFile = _pageManager.currentImageFile;
    
    // 페이지 없음 (비어있는 노트)
    if (currentPage == null) {
      return const Center(
        child: Text('페이지가 없습니다. 페이지를 추가해주세요.'),
      );
    }
    
    // 디버그 로깅 - 현재 상태 확인 
    debugPrint('현재 페이지 상태 확인 - ID: ${currentPage.id}, 텍스트 길이: ${currentPage.originalText.length}자');
    
    // 이전에 방문한 페이지인지 확인 (현재 페이지 인덱스가 이미 방문 기록에 있는지)
    final bool wasVisitedBefore = _previouslyVisitedPages.contains(_pageManager.currentPageIndex);
    
    // 페이지 처리가 완료되지 않은 경우 (백그라운드 처리 중)
    if ((currentPage.originalText.isEmpty || currentPage.originalText == 'processing') && !wasVisitedBefore) {
      // 이전 페이지와 같은 페이지인지 확인 (무한 로딩 방지)
      if (_processingPage != null && _processingPage!.id == _note!.id) {
        final now = DateTime.now();
        final diff = now.difference(_processingPage!.updatedAt);
        
        // 5분 이상 처리 중이면 에러로 간주
        if (diff.inMinutes > 5) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                const Text('페이지 처리 중 오류가 발생했습니다.'),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    _loadNote(); // 다시 로드 시도
                  },
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          );
        }
      }
      
      // 처리 중인 페이지 정보 저장
      _processingPage = _note;
      
      // 페이지가 준비 중인 경우 - 백그라운드 처리를 체크하기 위한 로직 추가
      if (currentPage.id != null) {
        // 페이지 정보를 서버에서 다시 확인
        _refreshPageFromServer(currentPage.id!);
      }
      
      debugPrint('페이지 준비 중 화면 표시 (이전 방문: $wasVisitedBefore)');
      
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              '페이지 준비 중...',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: ColorTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '이미지 인식 및 번역을 진행하고 있습니다.',
              style: TextStyle(
                fontSize: 14,
                color: ColorTokens.textGrey,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _forceRefreshPage(),
              child: const Text('새로고침'),
            ),
          ],
        ),
      );
    }
    
    // 텍스트 처리 중인 경우
    if (_isProcessingText) {
      debugPrint('텍스트 처리 중 화면 표시');
      return const Center(
        child: DotLoadingIndicator(message: '텍스트 처리 중...'),
      );
    }
    
    // 일반 페이지 컨텐츠 표시
    debugPrint('일반 페이지 컨텐츠 표시 (이전 방문: $wasVisitedBefore)');
    return PageContentWidget(
      key: ValueKey('page_content_${currentPage.id}_${currentPage.updatedAt.toString()}'),
      page: currentPage,
      imageFile: currentImageFile,
      isLoadingImage: _isProcessingText,
      noteId: widget.noteId,
      onCreateFlashCard: _createFlashCard,
      flashCards: _note?.flashCards,
      onDeleteSegment: _handleDeleteSegment,
      useSegmentMode: _useSegmentMode,
    );
  }
  
  // 페이지 처리 상태 확인 메서드
  Future<void> _refreshPageFromServer(String pageId) async {
    debugPrint('서버에서 페이지 정보 새로 가져오기: $pageId');
    
    try {
      // 페이지 정보를 서버에서 다시 가져오기 
      final pageDoc = await FirebaseFirestore.instance
        .collection('pages')
        .doc(pageId)
        .get();
      
      if (!pageDoc.exists) {
        debugPrint('페이지를 찾을 수 없음: $pageId');
        return;
      }
      
      final serverPage = page_model.Page.fromFirestore(pageDoc);
      
      // 페이지가 이미 처리 완료되었으나 로컬 상태가 업데이트되지 않은 경우
      if (serverPage.originalText.isNotEmpty && serverPage.originalText != 'processing') {
        debugPrint('서버에서 처리 완료된 페이지 발견: $pageId, 로컬 상태 업데이트');
        
        if (mounted) {
          // 페이지 매니저 내 페이지 목록 업데이트
          final updatedPages = _pageManager.pages.map((p) {
            return p.id == pageId ? serverPage : p;
          }).toList();
          _pageManager.setPages(updatedPages);
          
          _processTextForCurrentPage(); // 텍스트 처리 시작
          setState(() {}); // UI 갱신
        }
      } else {
        debugPrint('페이지 $pageId는 여전히 처리 중: 텍스트=${serverPage.originalText.substring(0, 
          serverPage.originalText.length > 10 ? 10 : serverPage.originalText.length)}...');
      }
    } catch (e) {
      debugPrint('페이지 정보 갱신 중 오류: $e');
    }
  }
  
  // 페이지 강제 새로고침 메서드
  void _forceRefreshPage() {
    debugPrint('페이지 강제 새로고침');
    
    // 캐시 무효화
    if (_pageManager.currentPage?.id != null) {
      _cacheService.removeCachedNote(widget.noteId);
    }
    
    // 노트 다시 로드
    _loadNote();
  }

  // 프로그레스 바 위젯 (NoteDetailBottomBar에서 가져옴)
  Widget _buildProgressBar() {
    final screenWidth = MediaQuery.of(context).size.width;
    final progressWidth = _pageManager.pages.isNotEmpty 
        ? (_pageManager.currentPageIndex + 1) / _pageManager.pages.length * screenWidth 
        : 0.0;
    
    return Container(
      height: 2,
      width: double.infinity,
      color: const Color(0xFFFFF0E8),
      child: Row(
        children: [
          // 진행된 부분 (현재 페이지까지)
          Container(
            width: progressWidth,
            color: ColorTokens.primary,
          ),
        ],
      ),
    );
  }
}
