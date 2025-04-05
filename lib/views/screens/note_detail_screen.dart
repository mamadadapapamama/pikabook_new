import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/note.dart';
import '../../models/page.dart' as page_model;
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
import '../../theme/tokens/color_tokens.dart';
import 'full_image_screen.dart';
import '../../services/screenshot_service.dart';
import '../../widgets/dot_loading_indicator.dart';
import '../../widgets/common/pika_app_bar.dart';
import '../../theme/tokens/typography_tokens.dart';
import '../../widgets/common/help_text_tooltip.dart';
import '../../theme/tokens/spacing_tokens.dart';
import 'package:image_picker/image_picker.dart';
import '../../widgets/common/usage_dialog.dart';
import '../../services/usage_limit_service.dart';
import '../../utils/debug_utils.dart';
import 'home_screen.dart';
import '../../services/translation_service.dart';
import '../../models/flash_card.dart';
import '../../models/processed_text.dart';

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
  Timer? _backgroundCheckTimer;
  bool _isProcessingText = false;
  File? _imageFile;
  Note? _processingPage;
  bool _useSegmentMode = true; // 기본값은 세그먼트 모드
  bool _isShowingScreenshotWarning = false;
  Timer? _screenshotWarningTimer;
  Set<int> _previouslyVisitedPages = <int>{};
  late PageController _pageController;
  bool _showTooltip = false; // 툴팁 표시 여부

  // 의존성 관련 변수들
  ThemeData? _theme;
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 여기서 Theme.of 등 상속된 위젯에 의존하는 정보를 안전하게
    // 초기화합니다.
    _theme = Theme.of(context);
    
    // 상태가 변경되었을 수 있으므로 갱신
    if (mounted && _note != null) {
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageManager = NotePageManager(noteId: widget.noteId);
    _segmentManager = NoteSegmentManager();
    _previouslyVisitedPages = <int>{};
    _pageController = PageController();
    
    // 상태표시줄 설정
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.dark,
        ),
      );
    });
    
    // 의존성 관련 문제를 해결하기 위해 포스트 프레임 콜백 사용
    WidgetsBinding.instance.addPostFrameCallback((_) {
    _loadNote();
    _initTts();
    _loadUserPreferences();
    _setupBackgroundProcessingCheck();
    _initScreenshotDetection();
      if (mounted) {
        setState(() {
          // 상태 초기화
        });
      }
    });
  }

  @override
  void dispose() {
    _backgroundCheckTimer?.cancel();
    _screenshotWarningTimer?.cancel();
    _screenshotService.stopDetection();
    WidgetsBinding.instance.removeObserver(this);
    if (_textReaderService.isPlaying) {
      _textReaderService.stop();
    }
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
    // 이미 경고 메시지가 표시 중이면 무시
    if (_isShowingScreenshotWarning) {
      return;
    }
    
    // 경고 상태 설정
    setState(() {
      _isShowingScreenshotWarning = true;
    });
    
    // 스낵바 표시
    ScaffoldMessenger.of(context).clearSnackBars(); // 기존 스낵바 제거
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
        onVisible: () {
          // 스낵바가 표시되었을 때 타이머 시작
    _screenshotWarningTimer?.cancel();
          _screenshotWarningTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _isShowingScreenshotWarning = false;
        });
      }
    });
        },
      ),
    );
  }

  // ===== 데이터 로딩 관련 메서드 =====

  /// 노트 데이터 로드
  Future<void> _loadNote() async {
    try {
      setState(() {
        _isLoading = true;
      });

      // 노트 로드
      final note = await _noteService.getNoteById(widget.noteId);
      
      if (note == null) {
        setState(() {
          _error = '노트를 찾을 수 없습니다. 삭제되었거나 접근 권한이 없습니다.';
          _isLoading = false;
        });
        return;
      }
      
      // 로드된 노트 정보 반영
      setState(() {
        _note = note;
        _isFavorite = note.isFavorite;
      });
      
      // 페이지 로드
      await _pageManager.loadPagesFromServer();
      
      // 노트에 백그라운드 처리 상태 확인
      final bool isProcessingBackground = await _checkBackgroundProcessingStatus(note.id!);
      
      // 백그라운드 처리 중이 아니라면 처리 완료된 페이지가 있는지 확인
      if (!isProcessingBackground) {
        final prefs = await SharedPreferences.getInstance();
        final pagesUpdated = prefs.getBool('pages_updated_${widget.noteId}') ?? false;
        
        if (pagesUpdated) {
          final updatedPageCount = prefs.getInt('updated_page_count_${widget.noteId}') ?? 0;
          debugPrint('노트 로드 시 완료된 페이지 발견: $updatedPageCount개');
          
          // 플래그 초기화
          await prefs.remove('pages_updated_${widget.noteId}');
          await prefs.remove('updated_page_count_${widget.noteId}');
          
          // 메시지 표시
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$updatedPageCount개의 추가 페이지가 처리되었습니다.'),
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      }
      
      // 텍스트 처리
      await _processTextForCurrentPage();
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('노트 로드 중 오류 발생: $e');
      setState(() {
        _error = '노트 로드 중 오류가 발생했습니다: $e';
        _isLoading = false;
      });
    }
  }
  
  /// 백그라운드 처리 상태 확인
  Future<bool> _checkBackgroundProcessingStatus(String noteId) async {
    try {
      final noteDoc = await FirebaseFirestore.instance
          .collection('notes')
          .doc(noteId)
          .get();
          
      if (noteDoc.exists) {
        final data = noteDoc.data();
        final isProcessingBackground = data?['isProcessingBackground'] as bool? ?? false;
        final processingCompleted = data?['processingCompleted'] as bool? ?? false;
        
        debugPrint('백그라운드 처리 상태 확인: 처리 중=$isProcessingBackground, 완료=$processingCompleted');
        
        return isProcessingBackground && !processingCompleted;
      }
      
      return false;
    } catch (e) {
      debugPrint('백그라운드 처리 상태 확인 중 오류: $e');
      return false;
    }
  }

  // 백그라운드 처리 완료 확인을 위한 타이머 설정
  void _setupBackgroundProcessingCheck() {
    // 기존 타이머가 있으면 취소
    _backgroundCheckTimer?.cancel();

    // 타이머 생성 전 로그 출력
    debugPrint('백그라운드 처리 확인 타이머 설정: ${widget.noteId}');

    // 로컬에 저장된 처리 완료 상태 확인
    _checkLocalProcessingCompletedStatus().then((bool alreadyProcessed) {
      if (alreadyProcessed) {
        debugPrint('이미 완료 처리된 노트 - 타이머 설정 생략');
        return;
      }

      // 5초마다 백그라운드 처리 상태 확인하는 주기적 타이머 설정
      _backgroundCheckTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
        if (!mounted) {
          debugPrint('화면이 더 이상 마운트되지 않음 - 타이머 취소');
          timer.cancel();
          return;
        }

        try {
          // 1. 공유 환경설정에서 페이지 업데이트 여부 확인
          final prefs = await SharedPreferences.getInstance();
          final pagesUpdated =
              prefs.getBool('pages_updated_${widget.noteId}') ?? false;

          // 2. Firestore에서 직접 노트 문서 확인하여 최신 상태 체크
          bool firestoreUpdated = false;
          if (!pagesUpdated && _note != null && _note!.id != null) {
            try {
              final noteDoc = await FirebaseFirestore.instance
                  .collection('notes')
                  .doc(_note!.id)
                  .get();
                  
              if (noteDoc.exists) {
                final data = noteDoc.data();
                final processingCompleted = data?['processingCompleted'] as bool? ?? false;
                final isProcessingBackground = data?['isProcessingBackground'] as bool? ?? false;
                
                // 처리 완료 + 백그라운드 처리 플래그 False 인 경우 업데이트
                if (processingCompleted && !isProcessingBackground) {
                  firestoreUpdated = true;
                  debugPrint('Firestore에서 백그라운드 처리 완료 확인됨');
                }
              }
            } catch (e) {
              debugPrint('Firestore 노트 확인 중 오류: $e');
            }
          }

          if (pagesUpdated || firestoreUpdated) {
            // 페이지 업데이트가 완료된 경우
            final updatedPageCount =
                prefs.getInt('updated_page_count_${widget.noteId}') ?? _note?.imageCount ?? 0;
            debugPrint('백그라운드 처리 완료 감지: $updatedPageCount 페이지 업데이트됨');

            // 플래그 초기화
            if (pagesUpdated) {
              await prefs.remove('pages_updated_${widget.noteId}');
              await prefs.remove('updated_page_count_${widget.noteId}');
            }
            
            // 현재 페이지 인덱스 저장
            final currentIndex = _pageManager.currentPageIndex;

            // 페이지 다시 로드
            await _reloadPages(forceReload: true);

            // 완료 메시지 표시
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('추가 페이지 처리가 완료되었습니다. 이제 다음 페이지로 이동할 수 있습니다.'),
                  duration: Duration(seconds: 5),
                ),
              );
            }

            // 로컬에 처리 완료 상태 저장
            await _saveLocalProcessingCompletedStatus();

            // 업데이트가 완료되었으므로 타이머 취소
            debugPrint('백그라운드 처리 완료 - 타이머 취소');
            timer.cancel();
          }
        } catch (e) {
          debugPrint('백그라운드 처리 상태 확인 중 오류 발생: $e');
        }
      });
    });
  }
  
  // 로컬에 저장된 처리 완료 상태 확인
  Future<bool> _checkLocalProcessingCompletedStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'note_processing_completed_${widget.noteId}';
      return prefs.getBool(key) ?? false;
    } catch (e) {
      debugPrint('로컬 처리 완료 상태 확인 중 오류: $e');
      return false;
    }
  }
  
  // 로컬에 처리 완료 상태 저장
  Future<void> _saveLocalProcessingCompletedStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'note_processing_completed_${widget.noteId}';
      await prefs.setBool(key, true);
      debugPrint('노트 처리 완료 상태 로컬에 저장됨: ${widget.noteId}');
    } catch (e) {
      debugPrint('로컬 처리 완료 상태 저장 중 오류: $e');
    }
  }
  
  // 처리된 다음 페이지로 이동
  void _navigateToNextProcessedPage(int currentIndex) {
    try {
      // 현재 총 페이지 수 확인
      final int totalPages = _pageManager.pages.length;
      
      // 현재 페이지 이후의 페이지가 있는지 확인
      if (currentIndex < totalPages - 1) {
        // 다음 페이지로 이동
        _changePage(currentIndex + 1);
        debugPrint('다음 처리된 페이지(${currentIndex + 1})로 이동');
      }
    } catch (e) {
      debugPrint('다음 페이지 이동 중 오류 발생: $e');
    }
  }

  // 페이지 다시 로드 
  Future<void> _reloadPages({bool forceReload = false}) async {
    try {
      // 이미 로드 중인지 확인
      if (_isLoading && !forceReload) return;

      setState(() {
        _isLoading = true;
      });

      // 노트 문서에서 처리 완료 상태 확인
      bool processingCompleted = false;
      if (_note != null && _note!.id != null) {
        try {
          // 로컬에서 처리 완료 상태 확인
          final localCompleted = await _checkLocalProcessingCompletedStatus();
          if (localCompleted && !forceReload) {
            debugPrint('로컬에 저장된 처리 완료 상태 확인: 이미 처리 완료됨');
            // 로컬 상태가 이미 완료인 경우 Firestore 검사 생략
          } else {
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
                
                // 로컬에 처리 완료 상태 저장 (중복 알림 방지)
                await _saveLocalProcessingCompletedStatus();
              }
            }
          }
        } catch (e) {
          debugPrint('노트 문서 확인 중 오류 발생: $e');
        }
      }

      // 페이지 매니저로 서버에서 페이지 로드
      await _pageManager.loadPagesFromServer(forceReload: forceReload);
      
      // 이미지 로드
      _pageManager.loadAllPageImages();
      
      // 방문한 페이지 초기화 - 첫 페이지만 방문한 것으로 설정
      _previouslyVisitedPages.clear();
      if (_pageManager.pages.isNotEmpty) {
        _previouslyVisitedPages.add(_pageManager.currentPageIndex);
      }
      
      // 현재 페이지 텍스트 처리
      await _processTextForCurrentPage();
      
      debugPrint('페이지 다시 로드 완료: ${_pageManager.pages.length}개 페이지, 현재 페이지 인덱스: ${_pageManager.currentPageIndex}');

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
      debugPrint('페이지 텍스트 처리 시작: ${currentPage.id}');
      
      // 텍스트 처리
      final processedText = await _pageContentService.processPageText(
        page: currentPage,
        imageFile: _pageManager.currentImageFile,
      );
      
      if (processedText != null && currentPage.id != null) {
        try {
        // 기본 표시 설정 지정
        final updatedProcessedText = processedText.copyWith(
          showFullText: false, // 기본값: 세그먼트 모드
          showPinyin: true, // 병음 표시는 기본적으로 활성화
          showTranslation: true, // 번역은 항상 표시
        );
        
        // 업데이트된 텍스트 캐싱 (메모리 캐시만)
        _pageContentService.setProcessedText(currentPage.id!, updatedProcessedText);
        
          debugPrint('텍스트 처리 완료: ${currentPage.id}');
          debugPrint('텍스트 처리 결과: showFullText=${updatedProcessedText.showFullText}, '
            'showPinyin=${updatedProcessedText.showPinyin}, '
            'showTranslation=${updatedProcessedText.showTranslation}, '
            'segments=${updatedProcessedText.segments?.length ?? 0}개');
          
          // 첫 노트의 첫 페이지 텍스트 처리 완료 기록 저장
          _checkFirstNoteTextProcessing();
        } catch (e) {
          debugPrint('페이지 텍스트 처리 중 오류 발생: ProcessedText 객체 변환 실패: $e');
          // 캐시 삭제 및 다시 로드 시도
          _pageContentService.removeProcessedText(currentPage.id!);
        }
      } else {
        debugPrint('페이지 텍스트 처리 결과가 null이거나 페이지 ID가 null임');
      }
    } catch (e) {
      debugPrint('페이지 텍스트 처리 중 오류 발생: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingText = false;
        });
      }
    }
  }
  
  // 첫 노트의 첫 페이지 텍스트 처리 완료 여부 확인 및 기록
  Future<void> _checkFirstNoteTextProcessing() async {
    if (!mounted) return;
    
    try {
      // 현재 첫 번째 페이지인지 확인
      final isFirstPage = _pageManager.currentPageIndex == 0;
      if (!isFirstPage) return;
      
      final prefs = await SharedPreferences.getInstance();
      
      // 첫 노트 생성 여부 확인 (홈 화면에서 설정됨)
      final bool isFirstNote = prefs.getBool('first_note_created') ?? true; // 기본값 true로 설정하여 기존 사용자도 체험할 수 있게 함
      
      // 이미 텍스트 처리 완료 상태인지 확인
      final bool textProcessingCompleted = prefs.getBool('first_note_text_processing_completed') ?? false;
      final bool tooltipShown = prefs.getBool('tooltip_shown_after_first_page') ?? false;
      
      debugPrint('첫 노트 텍스트 처리 체크: 첫 노트=$isFirstNote, 첫 페이지=$isFirstPage, 텍스트 처리 완료=$textProcessingCompleted, 툴팁 표시됨=$tooltipShown');
      
      // 첫 노트의 첫 페이지이고 아직 텍스트 처리가 완료되지 않은 경우
      if (isFirstNote && isFirstPage && !textProcessingCompleted) {
        // 텍스트 처리 완료 기록
        await prefs.setBool('first_note_text_processing_completed', true);
        
        // 노트 생성 기록도 저장 (홈 화면에서 설정되지 않았을 경우를 대비)
        if (!isFirstNote) {
          await prefs.setBool('first_note_created', true);
        }
        
        debugPrint('첫 노트의 첫 페이지 텍스트 처리 완료 기록 저장');
        
        // 툴팁을 아직 표시하지 않았다면 표시
        if (!tooltipShown) {
          // 툴팁 표시 상태 설정
          setState(() {
            _showTooltip = true;
          });
          
          // 툴팁 표시 기록 저장
          await prefs.setBool('tooltip_shown_after_first_page', true);
          
          debugPrint('노트 상세 화면에서 첫 페이지 툴팁 표시');
          
          // 10초 후에 툴팁 자동으로 숨기기 - 제거
          // Future.delayed(const Duration(seconds: 10), () {
          //   if (mounted) {
          //     setState(() {
          //       _showTooltip = false;
          //     });
          //   }
          // });
        }
      }
    } catch (e) {
      debugPrint('첫 노트 텍스트 처리 체크 중 오류 발생: $e');
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
    final currentFlashCards = _note!.flashCards;
    
    setState(() {
      _note = _note!.copyWith(
        originalText: newTitle,
        updatedAt: DateTime.now(),
        flashCards: currentFlashCards, // 현재 플래시카드 유지
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
            flashCards: currentFlashCards, // 현재 플래시카드 유지
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
            ? _pageContentService.getProcessedText(_pageManager.currentPage!.id!)?.showFullText ?? false
            : false,
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
          _useSegmentMode = true; // 기본값은 세그먼트 모드
        });
      }
    }
  }

  // ===== 플래시카드 관련 메서드 =====

  Future<void> _createFlashCard(String front, String back, {String? pinyin}) async {
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

        try {
          // 플래시카드 생성
          await _flashCardService.createFlashCard(
            front: front,
            back: finalBack,
            pinyin: finalPinyin,
            noteId: widget.noteId,
          );
        } catch (flashcardError) {
          debugPrint('플래시카드 생성 오류: $flashcardError');
          
          // 사용량 제한 오류인 경우 사용자에게 알림
          if (flashcardError.toString().contains('무료 플래시카드 사용량 한도를 초과했습니다')) {
            if (mounted) {
              // 오류 메시지를 표시하고 빠르게 함수 종료
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('무료 플래시카드 사용량 한도를 초과했습니다. 프리미엄으로 업그레이드하세요.'),
                  duration: Duration(seconds: 5),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              setState(() {
                _isCreatingFlashCard = false;
              });
              return; // 함수 종료
            }
          }
          
          // 다른 오류는 다시 던지기
          rethrow;
        }
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
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('플래시카드 생성 중 오류가 발생했습니다: $e'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingFlashCard = false;
        });
      }
    }
  }

  /// 플래시카드 화면으로 이동
  Future<void> _navigateToFlashcards() async {
    if (_note == null) return;

    try {
      // 플래시카드 화면으로 이동
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FlashCardScreen(
            noteId: _note!.id,
        ),
      ),
    );

      // 결과 처리 (Map 형태로 받음)
      if (result != null && mounted && _note != null) {
        // Map<String, dynamic> 형태로 변환
        if (result is Map) {
          final flashcardCount = result['flashcardCount'] as int? ?? 0;
          final success = result['success'] as bool? ?? false;
          final noteId = result['noteId'] as String?;
          
          debugPrint('플래시카드 화면에서 돌아옴: 카드 수 $flashcardCount개');
          
          // 성공적으로 처리되었고, 현재 노트와 일치하는 경우
          if (success && noteId == _note!.id) {
            // 노트 객체 업데이트
            final updatedNote = _note!.copyWith(flashcardCount: flashcardCount);
            
            // Firebase에 업데이트 반영
            await FirebaseFirestore.instance
                .collection('notes')
                .doc(_note!.id)
                .update({'flashcardCount': flashcardCount});
                
            // 캐시 관련 초기화 작업
            if (_pageManager.currentPage?.id != null) {
              // 현재 페이지의 ProcessedText 캐시 삭제 - 플래시카드 단어 하이라이트 갱신을 위해
              _pageContentService.removeProcessedText(_pageManager.currentPage!.id!);
            }
            
            // 노트 서비스에 캐시 업데이트
            _noteService.cacheNotes([updatedNote]);
            
            // 노트를 다시 로드하여 최신 데이터 가져오기
            await _loadNote();
            
            // 현재 페이지의 플래시카드 단어 목록을 새로 로드
            if (_pageManager.currentPageIndex >= 0 && _pageManager.currentPageIndex < _pageManager.pages.length) {
              // 플래시카드 목록 새로 로드
              final flashCardService = FlashCardService();
              final flashCards = await flashCardService.getFlashCardsForNote(_note!.id!);
              
              // 노트 객체 업데이트
        setState(() {
                _note = _note!.copyWith(flashCards: flashCards);
              });
              
              // 현재 페이지 텍스트 다시 처리하여 하이라이트 정보 갱신
              await _processTextForCurrentPage();
              
              debugPrint('플래시카드 목록 및 페이지 텍스트 새로 로드 완료: ${flashCards.length}개 카드');
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        debugPrint('플래시카드 화면 이동 중 오류: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류가 발생했습니다: $e')),
        );
      }
    }
  }

  // 현재 페이지의 플래시카드 단어를 다시 로드하는 메서드 추가
  Future<void> _loadFlashcardsForCurrentPage() async {
    try {
      if (_pageManager.currentPageIndex < 0 || _pageManager.currentPageIndex >= _pageManager.pages.length || _note == null) {
        return;
      }
      
      // 현재 노트의 모든 플래시카드를 로드
      final flashCardService = FlashCardService();
      final flashCards = await flashCardService.getFlashCardsForNote(_note!.id!);
      
      // UI 업데이트
      if (mounted) {
          setState(() {
          _note = _note!.copyWith(flashCards: flashCards);
        });
        
        // ProcessedTextWidget이 플래시카드 단어 목록 업데이트를 인식할 수 있도록 
        // 현재 페이지 다시 처리
        if (_pageManager.currentPage?.id != null) {
          await _processTextForCurrentPage();
        }
      }
      
      debugPrint('현재 페이지의 플래시카드 단어 목록 새로 로드됨: ${flashCards.length}개');
    } catch (e) {
      debugPrint('플래시카드 목록 로드 중 오류: $e');
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
    
    // 필요한 번역 데이터 확인 및 로드
    _checkAndLoadTranslationData(processedText);
  }
  
  // 번역 데이터 확인 및 필요시 로드
  Future<void> _checkAndLoadTranslationData(ProcessedText processedText) async {
    // 현재 전체 텍스트 모드
    final bool isCurrentlyFullMode = processedText.showFullText;
    // 모드 전환 후 (toggleDisplayMode 후)
    final bool willBeFullMode = !isCurrentlyFullMode;
    
    // 1. 전체 모드로 전환하는데 전체 번역이 없는 경우
    if (willBeFullMode && 
        (processedText.fullTranslatedText == null || processedText.fullTranslatedText!.isEmpty)) {
      debugPrint('전체 번역 모드로 전환했으나 번역이 없어 전체 번역 수행 시작...');
      
      // 전체 번역 수행
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      
      try {
        final translationService = TranslationService();
        final fullTranslatedText = await translationService.translateText(
          processedText.fullOriginalText,
          sourceLanguage: 'zh-CN',
          targetLanguage: 'ko'
        );
        
        // 번역 결과 업데이트
        final updatedText = processedText.copyWith(
          fullTranslatedText: fullTranslatedText,
          showFullText: true,
          showFullTextModified: true
        );
        
        // 캐시 및 UI 업데이트
        if (_pageManager.currentPage?.id != null) {
          _pageContentService.setProcessedText(_pageManager.currentPage!.id!, updatedText);
          
          // 캐시 업데이트
          await _pageContentService.updatePageCache(
            _pageManager.currentPage!.id!,
            updatedText,
            "languageLearning"
          );
          
          // 페이지 매니저 업데이트
          setState(() {});
        }
        
        debugPrint('전체 번역 완료: ${fullTranslatedText.length}자');
      } catch (e) {
        debugPrint('전체 번역 중 오류 발생: $e');
      } finally {
        // 로딩 다이얼로그 닫기
        if (context.mounted) Navigator.of(context).pop();
      }
    } 
    // 2. 세그먼트 모드로 전환하는데 세그먼트가 없는 경우
    else if (!willBeFullMode && 
             (processedText.segments == null || processedText.segments!.isEmpty)) {
      debugPrint('세그먼트 모드로 전환했으나 세그먼트가 없어 문장별 처리 시작...');
      
      // 로딩 다이얼로그 표시
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
      
      try {
        // 세그먼트 처리 (문장 분리 및 번역)
        final ocrService = EnhancedOcrService();
        final processedResult = await ocrService.processText(
          processedText.fullOriginalText, 
          "languageLearning"
        );
        
        // 세그먼트 결과 업데이트
        if (processedResult.segments != null && processedResult.segments!.isNotEmpty) {
          final updatedText = processedText.copyWith(
            segments: processedResult.segments,
            showFullText: false,
            showFullTextModified: true
          );
          
          // 캐시 및 UI 업데이트
          if (_pageManager.currentPage?.id != null) {
            _pageContentService.setProcessedText(_pageManager.currentPage!.id!, updatedText);
            
            // 캐시 업데이트
            await _pageContentService.updatePageCache(
              _pageManager.currentPage!.id!,
              updatedText,
              "languageLearning"
            );
            
            // 페이지 매니저 업데이트
            setState(() {});
          }
          
          debugPrint('세그먼트 처리 완료: ${processedResult.segments!.length}개 세그먼트');
        } else {
          debugPrint('세그먼트 처리 시도했으나 결과가 없음');
        }
      } catch (e) {
        debugPrint('세그먼트 처리 중 오류 발생: $e');
      } finally {
        // 로딩 다이얼로그 닫기
        if (context.mounted) Navigator.of(context).pop();
      }
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

  // 프로그레스 계산 메서드
  double _calculateProgress() {
    if (_pageManager.pages.isEmpty) return 0.0;
    return (_pageManager.currentPageIndex + 1) / _pageManager.pages.length;
  }

  Future<bool> _imageExists(File? imageFile, String? imageUrl) async {
    if (imageFile != null) return true;
    if (imageUrl == null) return false;
    return await _imageService.imageExists(imageUrl);
  }

  // 뒤로가기 버튼 처리
  Future<bool> _onWillPop() async {
    DebugUtils.log('WillPopScope 호출됨 - 백버튼 이벤트');
    
    // 리소스 정리는 백그라운드에서 처리
    Future.microtask(() async {
      try {
        // TTS 정리
        if (_textReaderService.isPlaying) {
          DebugUtils.log('백그라운드에서 TextReaderService 중지 중...');
          await _textReaderService.stop();
        }
        
        DebugUtils.log('백그라운드에서 TtsService 중지 중...');
        await _ttsService.stop();
        
        // 리소스 정리
        if (_pageManager.currentPage?.id != null) {
          _pageContentService.removeProcessedText(_pageManager.currentPage!.id!);
        }
        
        DebugUtils.log('백그라운드 리소스 정리 완료');
      } catch (e) {
        DebugUtils.error('백그라운드 리소스 정리 중 오류: $e');
      }
    });
    
    // 버그 해결: 기본 동작 방지하고 직접 네비게이션 처리
    if (mounted) {
      DebugUtils.log('홈 화면으로 이동 시작 (WillPopScope)');
      
      // 직접 HomeScreen으로 이동 (pushAndRemoveUntil에 슬라이드 애니메이션 적용)
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => HomeScreen(
            showTooltip: false,
            onCloseTooltip: () {}, // 빈 콜백 함수 제공
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(-1.0, 0.0); // 왼쪽에서 오른쪽으로 슬라이드
            const end = Offset.zero;
            const curve = Curves.easeInOut;
            
            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            var offsetAnimation = animation.drive(tween);
            
            return SlideTransition(
              position: offsetAnimation,
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 300),
        ),
        (route) => false // 모든 이전 경로 제거
      );
      return false; // WillPopScope 기본 동작 중지
    }
    
    return false;
  }

  // ===== UI 빌드 메서드 =====

  @override
  Widget build(BuildContext context) {
    // 상태바 아이콘 색상 설정은 initState로 이동하였으므로 여기서 제거
    
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: _isLoading || _error != null
            ? null // 로딩 중이거나 오류 상태에서는 앱바 없음
            : PikaAppBar.noteDetail(
                title: _note?.originalText ?? 'Note',
                currentPage: _pageManager.currentPageIndex + 1,
                totalPages: (_note?.isProcessingBackground ?? false) && _note?.imageCount != null
                    ? max(_note!.imageCount!, _pageManager.pages.length)
                    : _pageManager.pages.length,
                flashcardCount: _note?.flashcardCount ?? 0,
                onMorePressed: _showMoreOptions,
                onFlashcardTap: _navigateToFlashcards,
                onBackPressed: () {
                  // 홈 화면으로 직접 이동
                  DebugUtils.log('앱바 백버튼 터치됨 - 홈 화면으로 이동 시작');
                  
                  // 홈 화면으로 직접 이동 (왼쪽에서 오른쪽으로 슬라이드 애니메이션 적용)
                  if (mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) => HomeScreen(
                          showTooltip: false,
                          onCloseTooltip: () {}, // 빈 콜백 함수 제공
                        ),
                        transitionsBuilder: (context, animation, secondaryAnimation, child) {
                          const begin = Offset(-1.0, 0.0); // 왼쪽에서 오른쪽으로 슬라이드
                          const end = Offset.zero;
                          const curve = Curves.easeInOut;
                          
                          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                          var offsetAnimation = animation.drive(tween);
                          
                          return SlideTransition(
                            position: offsetAnimation,
                            child: child,
                          );
                        },
                        transitionDuration: const Duration(milliseconds: 300),
                      ),
                      (route) => false // 모든 이전 경로 제거
                    );
                  }
                  
                  // 화면 이동 후 리소스 정리 (백그라운드에서 처리)
                  Future.microtask(() async {
                    try {
                      DebugUtils.log('백그라운드에서 TTS 리소스 정리 시작');
                      
                      // TTS 관련 서비스 중지
                      if (_textReaderService.isPlaying) {
                        DebugUtils.log('TextReaderService 중지 중...');
                        await _textReaderService.stop();
                      }
                      
                      DebugUtils.log('TtsService 중지 중...');
                      await _ttsService.stop();
                      
                      // 필요한 리소스 정리
                      if (_pageManager.currentPage?.id != null) {
                        DebugUtils.log('ProcessedText 리소스 정리 중...');
                        _pageContentService.removeProcessedText(_pageManager.currentPage!.id!);
                      }
                      
                      DebugUtils.log('백그라운드 리소스 정리 완료');
                    } catch (e) {
                      DebugUtils.error('백그라운드 리소스 정리 중 오류: $e');
                    }
                  });
                },
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
                  totalPages: (_note?.isProcessingBackground ?? false) && _note?.imageCount != null
                      ? max(_note!.imageCount!, _pageManager.pages.length)
                      : _pageManager.pages.length,
                  onPageChanged: _changePage,
                  isFullTextMode: _pageManager.currentPage?.id != null 
                      ? _pageContentService.getProcessedText(_pageManager.currentPage!.id!)?.showFullText ?? false
                      : false,
                  onToggleFullTextMode: _toggleFullTextMode,
                  pageContentService: _pageContentService,
                  textReaderService: _textReaderService,
                )
              : null,
        ),
    );
  }

  // 메인 UI 구성 (로딩 및 오류 처리 이후)
  Widget _buildBody() {
    final currentImageFile = _pageManager.currentImageFile;
    final String pageNumberText = '${_pageManager.currentPageIndex + 1}/${_pageManager.pages.length}';
    
    return Stack(
      children: [
        PageView.builder(
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
                // 첫 번째 이미지 컨테이너
                _buildFirstImageContainer(),
                
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
                  Container(
                    margin: EdgeInsets.only(top: 16, left: 16, right: 16),
                    height: 200, // 높이를 200으로 고정
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        )
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: imageFile != null 
                        ? Image.file(
                            imageFile,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                          )
                        : (page?.imageUrl != null
                            ? Image.network(
                                page!.imageUrl!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              )
                            : const Center(child: Text('이미지 없음'))),
                    ),
                  ),
                
                // 페이지 내용 자리 표시자
                Expanded(
                  child: Center(
                    child: Text('페이지 ${index + 1} 로딩 중...'),
                  ),
                ),
              ],
            );
          }
        },
      ),
        
        // 툴팁 표시 (처음 텍스트 처리가 완료된 경우)
        if (_showTooltip)
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: HelpTextTooltip(
              key: const Key('note_detail_tooltip'),
              text: "첫 노트가 만들어졌어요!",
              description: "모르는 단어는 선택하여 사전 검색 하거나, 플래시카드를 만들어 복습해 볼수 있어요.",
              showTooltip: true,
              onDismiss: () {
                DebugUtils.log('📝 노트 상세 화면에서 툴팁 닫기 버튼 클릭됨!!');
                DebugUtils.log('📝 노트 상세 화면 _showTooltip 상태 변경 시작: true -> false');
                setState(() {
                  _showTooltip = false;
                });
                DebugUtils.log('📝 노트 상세 화면 _showTooltip 상태 변경 완료');
              },
              backgroundColor: ColorTokens.primaryverylight,
              borderColor: ColorTokens.primaryMedium,
              textColor: ColorTokens.textPrimary,
              tooltipPadding: const EdgeInsets.all(16),
              spacing: 4.0,
              image: Image.asset(
                'assets/images/note_help.png',
                width: double.infinity,
                fit: BoxFit.contain,
              ),
              child: Container(), // 빈 컨테이너 (툴팁만 표시)
            ),
          ),
      ],
    );
  }

  // 현재 페이지의 첫 번째 이미지 표시
  Widget _buildFirstImageContainer() {
    final currentPage = _pageManager.currentPage;
    final currentImageFile = _pageManager.currentImageFile;
    
    // 이미지가 없는 경우 컨테이너 자체를 표시하지 않음
    if (currentImageFile == null && (currentPage?.imageUrl == null || currentPage!.imageUrl!.isEmpty)) {
      return SizedBox(height: 0);
    }
    
    // 이미지 컨테이너
    return GestureDetector(
      onTap: () {
        if (currentImageFile != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FullImageScreen(
                imageFile: currentImageFile,
                title: _note?.originalText ?? '이미지',
              ),
            ),
          );
        } else if (currentPage?.imageUrl != null) {
          _imageService.getImageFile(currentPage!.imageUrl).then((file) {
            if (file != null && mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => FullImageScreen(
                    imageFile: file,
                    title: _note?.originalText ?? '이미지',
                  ),
                ),
              );
            }
          });
        }
      },
      child: Container(
        margin: const EdgeInsets.only(
          top: 16,
          left: 16,
          right: 16,
          bottom: 0,
        ),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 2),
            )
          ],
        ),
        height: 200, // 내부 컨테이너 높이도 200으로 고정
        width: MediaQuery.of(context).size.width,
        child: Stack(
          children: [
            if (currentImageFile != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  currentImageFile,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint('이미지 로드 오류: $error');
                    return Center(
                      child: Image.asset(
                        'assets/images/image_empty.png',
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    );
                  },
                ),
              )
            else if (currentPage?.imageUrl != null)
              FutureBuilder<File?>(
                future: _imageService.getImageFile(currentPage!.imageUrl),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  } else if (snapshot.hasData && snapshot.data != null) {
                    // 이미지 파일을 찾은 경우, 페이지 매니저에도 업데이트
                    if (currentPage.id != null) {
                      // 이미지 파일과 URL 업데이트 (기존 NotePageManager 메서드 활용)
                      _pageManager.updateCurrentPageImage(
                        snapshot.data!, 
                        currentPage.imageUrl!
                      );
                    }
                    
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (context, error, stackTrace) {
                          debugPrint('이미지 로드 오류: $error');
                          return Center(
                            child: Image.asset(
                              'assets/images/image_empty.png',
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          );
                        },
                      ),
                    );
                  } else {
                    return Center(
                      child: Image.asset(
                        'assets/images/image_empty.png',
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    );
                  }
                },
              ),
              
            // 이미지 전체보기 버튼 추가
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    if (currentImageFile != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FullImageScreen(
                            imageFile: currentImageFile,
                            title: _note?.originalText ?? '이미지',
                          ),
                        ),
                      );
                    } else if (currentPage?.imageUrl != null) {
                      _imageService.getImageFile(currentPage!.imageUrl).then((file) {
                        if (file != null && mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => FullImageScreen(
                                imageFile: file,
                                title: _note?.originalText ?? '이미지',
                              ),
                            ),
                          );
                        }
                      });
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(6.0),
                    child: Icon(
                      Icons.fullscreen,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
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
    
    // 캐시에서 ProcessedText 가져오기
    final processedText = currentPage.id != null
        ? _pageContentService.getProcessedText(currentPage.id!)
        : null;
    
    // 세그먼트/전체 모드 확인
    final bool isFullTextMode = processedText?.showFullText ?? false;
    
    // 패딩 설정 - 전체 모드는 좌우 패딩 줄이기, 세그먼트 모드는 기본 패딩 유지
    final EdgeInsets contentPadding = const EdgeInsets.symmetric(horizontal: SpacingTokens.md + SpacingTokens.sm); // 24.0 (통일된 패딩 값)
    
    // 페이지가 준비 중인 경우 - 백그라운드 처리를 체크하기 위한 로직 추가
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
                const Icon(Icons.error_outline, color: ColorTokens.error, size: 48),
                SizedBox(height: SpacingTokens.md),
                Text(
                  '페이지 처리 중 오류가 발생했습니다.',
                  style: TypographyTokens.body1,
                ),
                SizedBox(height: SpacingTokens.sm),
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
        (() async {
          try {
            // 서버에서 페이지 정보 가져오기
            final pageDoc = await FirebaseFirestore.instance
              .collection('pages')
              .doc(currentPage.id!)
              .get();
            
            if (!pageDoc.exists) {
              debugPrint('페이지를 찾을 수 없음: ${currentPage.id!}');
              return;
            }
            
            if (!mounted) return;
            
            final serverPage = page_model.Page.fromFirestore(pageDoc);
            
            // 페이지가 이미 처리 완료되었으나 로컬 상태가 업데이트되지 않은 경우
            if (serverPage.originalText.isNotEmpty && serverPage.originalText != 'processing') {
              debugPrint('서버에서 처리 완료된 페이지 발견: ${currentPage.id}, 로컬 상태 업데이트');
              
              // 페이지 매니저 내 페이지 목록 업데이트
              final updatedPages = _pageManager.pages.map((p) {
                return p.id == currentPage.id ? serverPage : p;
              }).toList();
              _pageManager.setPages(updatedPages);
              
              // 텍스트 다시 처리
              _processTextForCurrentPage();
              setState(() {}); // UI 갱신
            }
          } catch (e) {
            debugPrint('페이지 정보 갱신 중 오류 발생: $e');
          }
        })();
      }
      
      debugPrint('페이지 준비 중 화면 표시 (이전 방문: $wasVisitedBefore)');
      
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: ColorTokens.primary),
            SizedBox(height: SpacingTokens.lg),
            Text(
              '페이지 준비 중...',
              style: TypographyTokens.body1.copyWith(
                fontWeight: FontWeight.bold,
                color: ColorTokens.textSecondary,
              ),
            ),
            SizedBox(height: SpacingTokens.sm),
            Text(
              '이미지 인식 및 번역을 진행하고 있습니다.',
              style: TypographyTokens.body2.copyWith(
                color: ColorTokens.textGrey,
              ),
            ),
            SizedBox(height: SpacingTokens.sm),
            TextButton(
              onPressed: () => _forceRefreshPage(),
              child: Text('새로고침', style: TypographyTokens.button),
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
    
    // 텍스트/이미지 세그먼트가 있는 경우
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      padding: contentPadding, // 여기에 패딩 적용
      child: PageContentWidget(
        key: ValueKey('processed_${currentPage.id}'),
        page: currentPage,
        imageFile: currentImageFile,
        flashCards: _note?.flashCards,
        useSegmentMode: _useSegmentMode,
        isLoadingImage: false,
        noteId: widget.noteId,
        onCreateFlashCard: (front, back, {pinyin}) async {
          await _createFlashCard(front, back, pinyin: pinyin);
        },
        onDeleteSegment: _handleDeleteSegment,
      ),
    );
  }
}
