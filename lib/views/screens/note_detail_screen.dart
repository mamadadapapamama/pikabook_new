import 'package:flutter/material.dart';
import 'dart:io';
import '../../models/note.dart';
import '../../models/page.dart' as page_model;
import '../../models/text_processing_mode.dart';
import '../../models/text_segment.dart';
import '../../services/note_service.dart';
import '../../services/page_service.dart';
import '../../services/image_service.dart';
import '../../services/flashcard_service.dart' hide debugPrint;
import '../../services/dictionary_service.dart';
import '../../services/tts_service.dart';
import '../../services/enhanced_ocr_service.dart';
import '../../services/user_preferences_service.dart';
import '../../services/page_content_service.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/note_detail_app_bar.dart';
import '../../widgets/note_action_bottom_sheet.dart';
import '../../widgets/page_content_widget.dart';
import '../../widgets/edit_title_dialog.dart';
import '../../widgets/note_detail_bottom_bar.dart';
import '../../widgets/note_page_manager.dart';
import '../../widgets/note_segment_manager.dart';
import '../../utils/text_display_mode.dart';
import 'flashcard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async'; // Timer 클래스를 사용하기 위한 import 추가
import '../../services/unified_cache_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/text_reader_service.dart';

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

class _NoteDetailScreenState extends State<NoteDetailScreen> {
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
  
  // 관리자 클래스 인스턴스
  late NotePageManager _pageManager;
  late NoteSegmentManager _segmentManager;

  // 상태 변수
  Note? _note;
  bool _isLoading = true;
  String? _error;
  bool _isFavorite = false;
  bool _isCreatingFlashCard = false;
  TextProcessingMode _textProcessingMode = TextProcessingMode.languageLearning;
  TextDisplayMode _textDisplayMode = TextDisplayMode.all;
  Timer? _backgroundCheckTimer;

  @override
  void initState() {
    super.initState();
    _pageManager = NotePageManager(noteId: widget.noteId);
    _segmentManager = NoteSegmentManager();
    _loadNote();
    _initTts();
    _loadUserPreferences();
    _setupBackgroundProcessingCheck();
  }

  @override
  void dispose() {
    _backgroundCheckTimer?.cancel();
    _ttsService.stop();
    super.dispose();
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
        });

        // 페이지 수 로그 출력
        debugPrint('노트에 ${_pageManager.pages.length}개의 페이지가 있습니다. (캐시에서 로드: $isFromCache)');

        // 각 페이지의 이미지 로드
        _pageManager.loadAllPageImages();

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
    _pageManager.changePage(index);
    setState(() {}); // UI 업데이트
  }

  // ===== 메뉴 및 다이얼로그 관련 메서드 =====

  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => NoteActionBottomSheet(
        onEditTitle: _showEditTitleDialog,
        onDeleteNote: _confirmDelete,
        onShowTextProcessingModeDialog: _showTextProcessingModeDialog,
        textProcessingMode: _textProcessingMode,
      ),
    );
  }

  // ===== 사용자 설정 관련 메서드 =====

  Future<void> _loadUserPreferences() async {
    try {
      final mode = await _preferencesService.getTextProcessingMode();
      if (mounted) {
        setState(() {
          _textProcessingMode = mode;
        });
      }
    } catch (e) {
      debugPrint('사용자 기본 설정 로드 중 오류 발생: $e');
    }
  }

  Future<void> _changeTextProcessingMode(TextProcessingMode mode) async {
    setState(() {
      _textProcessingMode = mode;
    });

    try {
      // 앱 전체 설정 업데이트
      await _preferencesService.setDefaultTextProcessingMode(mode);
    } catch (e) {
      debugPrint('텍스트 처리 모드 저장 중 오류 발생: $e');
    }
  }

  void _showTextProcessingModeDialog() {
    showDialog(
      context: context,
      builder: (context) => TextProcessingModeDialog(
        currentMode: _textProcessingMode,
        onModeChanged: _changeTextProcessingMode,
      ),
    );
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

        // 노트 정보가 변경되었으므로 캐시도 무효화
        await _cacheService.removeCachedNote(widget.noteId);
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
          setState(() {
            _note = Note.fromFirestore(noteDoc);
            debugPrint(
                '노트 ${widget.noteId}의 플래시카드 카운터 업데이트: ${_note!.flashcardCount}개');
          });
        }
      }
    }
  }

  // 세그먼트 삭제 처리 메서드
  void _handleDeleteSegment(int segmentIndex) async {
    final currentPage = _pageManager.currentPage;
    if (currentPage == null || currentPage.id == null) return;
    
    // 세그먼트 매니저로 세그먼트 삭제
    final updatedPage = await _segmentManager.deleteSegment(
      noteId: widget.noteId,
      page: currentPage,
      segmentIndex: segmentIndex,
    );
    
    if (updatedPage != null && mounted) {
      setState(() {
        // 페이지 매니저 업데이트
        _pageManager.updateCurrentPage(updatedPage);
      });
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('세그먼트 삭제 중 오류가 발생했습니다.')),
      );
    }
  }

  // 텍스트 디스플레이 모드 변경 처리
  void _handleTextDisplayModeChanged(TextDisplayMode mode) {
    setState(() {
      _textDisplayMode = mode;
      
      // 현재 페이지의 ProcessedText 업데이트
      final currentPage = _pageManager.currentPage;
      if (currentPage != null && currentPage.id != null) {
        // 텍스트 모드에 따라 표시 설정 변경
        _segmentManager.updateTextDisplayMode(
          pageId: currentPage.id!,
          showFullText: mode == TextDisplayMode.original,
          showPinyin: mode == TextDisplayMode.pinyin || mode == TextDisplayMode.all,
          showTranslation: mode == TextDisplayMode.translation || mode == TextDisplayMode.all,
        );
      }
    });
  }
  
  // 재생/일시정지 버튼 처리
  void _handlePlayPausePressed() {
    final currentPage = _pageManager.currentPage;
    if (currentPage == null) return;
    
    if (_textReaderService.isPlaying) {
      _textReaderService.stop();
    } else if (currentPage.originalText.isNotEmpty) {
      _textReaderService.readTextBySentences(currentPage.originalText);
    }
    
    setState(() {});
  }

  // ===== UI 빌드 메서드 =====

  @override
  Widget build(BuildContext context) {
    // 노트가 유효하지 않은 경우 로딩 표시
    if (_note == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('로딩 중...')),
        body: _isLoading
            ? const Center(child: LoadingIndicator(message: '노트 로딩 중...'))
            : Center(child: Text(_error ?? '노트를 불러올 수 없습니다.')),
      );
    }

    return Scaffold(
      appBar: NoteDetailAppBar(
        note: _note!,
        isFavorite: _isFavorite,
        onEditTitle: _showEditTitleDialog,
        onToggleFavorite: _toggleFavorite,
        onShowMoreOptions: _showMoreOptions,
        onFlashCardPressed: _navigateToFlashcards,
      ),
      body: Column(
        children: [
          // 페이지 내용 (Expanded로 감싸 남은 공간 채우기)
          Expanded(
            child: _buildCurrentPageContent(),
          ),
        ],
      ),
      bottomNavigationBar: NoteDetailBottomBar(
        currentPage: _pageManager.currentPage,
        imageFile: _pageManager.currentImageFile,
        currentPageIndex: _pageManager.currentPageIndex,
        totalPages: _pageManager.pages.length,
        onPageChanged: _changePage,
        textDisplayMode: _textDisplayMode,
        onTextDisplayModeChanged: _handleTextDisplayModeChanged,
        isPlaying: _textReaderService.isPlaying,
        onPlayPausePressed: _handlePlayPausePressed,
        pageContentService: _pageContentService,
        textReaderService: _textReaderService,
      ),
    );
  }
  
  // 현재 페이지 내용 빌드
  Widget _buildCurrentPageContent() {
    final currentPage = _pageManager.currentPage;
    final imageFile = _pageManager.currentImageFile;
    
    if (currentPage == null) {
      return const Center(child: Text('페이지를 찾을 수 없습니다.'));
    }

    final bool isLoadingImage =
        imageFile == null && currentPage.imageUrl != null;

    // 이미지가 로딩 중이면 로딩 인디케이터 표시
    if (isLoadingImage) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('페이지 로딩 중...', style: TextStyle(fontSize: 16)),
          ],
        ),
      );
    }

    return PageContentWidget(
      key: ValueKey('page_content_${currentPage.id}_${_pageManager.currentPageIndex}'),
      page: currentPage,
      imageFile: imageFile,
      isLoadingImage: false,
      noteId: widget.noteId,
      onCreateFlashCard: _createFlashCard,
      textProcessingMode: _textProcessingMode,
      flashCards: _note?.flashCards,
      onDeleteSegment: _handleDeleteSegment,
    );
  }
}

// TextProcessingMode 대화상자 (코드 길이 줄이기)
class TextProcessingModeDialog extends StatelessWidget {
  final TextProcessingMode currentMode;
  final Function(TextProcessingMode) onModeChanged;

  const TextProcessingModeDialog({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('텍스트 처리 모드'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeOption(
            context,
            TextProcessingMode.professionalReading,
            '원본 텍스트',
            '텍스트를 가공하지 않고 원본 그대로 표시합니다.',
          ),
          _buildModeOption(
            context,
            TextProcessingMode.languageLearning,
            '언어 학습 모드',
            '문장별로 분리하여 병음, 번역, 단어 검색 기능을 제공합니다.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('닫기'),
        ),
      ],
    );
  }

  Widget _buildModeOption(
    BuildContext context,
    TextProcessingMode mode,
    String title,
    String description,
  ) {
    return RadioListTile<TextProcessingMode>(
      title: Text(title),
      subtitle: Text(description),
      value: mode,
      groupValue: currentMode,
      onChanged: (value) {
        if (value != null) {
          onModeChanged(value);
          Navigator.pop(context);
        }
      },
    );
  }
}
