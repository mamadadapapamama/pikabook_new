// lib/views/screens/note_detail_screen.dart (리팩토링된 버전)
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart' show timeDilation;
import 'package:cloud_firestore/cloud_firestore.dart';

// 모델
import '../../models/note.dart';
import '../../models/page.dart' as page_model;
import '../../models/processed_text.dart';
import '../../models/flash_card.dart';

// 매니저
import '../../managers/page_manager.dart';
import '../../managers/content_manager.dart';
import '../../widgets/note_detail/note_detail_state.dart';
import '../../widgets/page_image_widget.dart';

// 서비스들
import '../../services/content/note_service.dart';
import '../../services/content/flashcard_service.dart' hide debugPrint;
import '../../services/media/tts_service.dart';
import '../../services/authentication/user_preferences_service.dart';
import '../../services/storage/unified_cache_service.dart';
import '../../services/text_processing/text_reader_service.dart';
import '../../services/media/screenshot_service.dart';
import '../../services/text_processing/translation_service.dart';
import '../../services/text_processing/enhanced_ocr_service.dart';
import '../../services/dictionary/external_cn_dictionary_service.dart';
import '../../services/content/page_service.dart';
import '../../services/media/image_service.dart';
import '../../services/text_processing/text_processing_service.dart';
import '../../services/content/favorites_service.dart';

// 기타 위젯 및 유틸리티
import '../../widgets/dot_loading_indicator.dart';
import '../../widgets/common/pika_app_bar.dart';
import '../../theme/tokens/typography_tokens.dart';
import '../../theme/tokens/color_tokens.dart';
import '../../widgets/note_detail/note_detail_bottom_bar.dart';
import '../../widgets/common/help_text_tooltip.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/note_action_bottom_sheet.dart';
import '../../utils/debug_utils.dart';
import '../../views/screens/flashcard_screen.dart';
import '../../views/screens/full_image_screen.dart';
import 'dart:math' as math;
import '../../widgets/edit_title_dialog.dart';
import '../../utils/screenshot_service_helper.dart';
import '../../utils/tooltip_manager.dart';
import '../../managers/note_options_manager.dart';
import '../../widgets/page_content_widget.dart';

/// 노트 상세 화면
/// 페이지 탐색, 노트 액션, 백그라운드 처리, 이미지 로딩 등의 기능
class NoteDetailScreen extends StatefulWidget {
  final String noteId;
  final Note? note;
  final bool isProcessingBackground;
  final int totalImageCount;
  
  // 라우트 이름 상수 추가
  static const String routeName = '/note_detail';

  const NoteDetailScreen({
    Key? key,
    required this.noteId,
    this.note,
    this.isProcessingBackground = false,
    this.totalImageCount = 0,
  }) : super(key: key);

  // 라우트를 생성하는 편의 메소드 추가
  static Route<dynamic> route({
    required Note note,
    bool isProcessingBackground = false,
    int totalImageCount = 0,
  }) {
    return MaterialPageRoute(
      settings: const RouteSettings(name: routeName),
      builder: (context) => NoteDetailScreen(
        noteId: note.id!,
        note: note,
        isProcessingBackground: isProcessingBackground,
        totalImageCount: totalImageCount,
      ),
    );
  }

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> with WidgetsBindingObserver {
  // 페이지 상태 및 관리 객체
  final _state = NoteDetailState();
  late PageManager _pageManager;
  final ContentManager _contentManager = ContentManager();

  // 서비스들
  final TextProcessingService _textProcessingService = TextProcessingService();
  final TtsService _ttsService = TtsService();
  final FavoritesService _favoritesService = FavoritesService();
  final UserPreferencesService _preferencesService = UserPreferencesService();
  final ImageService _imageService = ImageService();
  late PageContentWidget _pageContentWidget;
  
  // 화면 설정 및 상태
  bool _useSegmentMode = true;        // 세그먼트 모드 사용 여부
  bool _isFirstLoad = true;           // 첫 로드 여부
  bool _isScreenshotDetectionEnabled = false; // 스크린샷 감지 기능 활성화 여부

  // 핵심 서비스 인스턴스 (필요한 것만 유지)
  final NoteService _noteService = NoteService();
  final PageService _pageService = PageService();
  final FlashCardService _flashCardService = FlashCardService();
  final TextReaderService _textReaderService = TextReaderService();
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  final ScreenshotService _screenshotService = ScreenshotService();
  
  // UI 컨트롤러
  late PageController _pageController;
  TextEditingController _titleEditingController = TextEditingController();

  // 기타 변수
  ThemeData? _theme;
  Timer? _screenshotWarningTimer;
  bool _isShowingScreenshotWarning = false;

  // 새로운 매니저 인스턴스
  late ScreenshotServiceHelper _screenshotHelper;
  late TooltipManager _tooltipManager;
  late NoteOptionsManager _optionsManager;

  @override
  void initState() {
    super.initState();
    debugPrint('🔍 NoteDetailScreen.initState: noteId=${widget.noteId}, 노트=${widget.note?.originalText}');
    
    try {
      // 옵저버 등록
      WidgetsBinding.instance.addObserver(this);
      
      // 상태 초기화
      _state.setLoading(true);
      _state.expectedTotalPages = widget.totalImageCount;
      _state.setBackgroundProcessingFlag(widget.isProcessingBackground);
      _state.note = widget.note; // 전달받은 노트 객체를 바로 상태에 설정
      
      // 매니저 및 핸들러 초기화
      _pageManager = PageManager(
        noteId: widget.noteId,
        initialNote: widget.note,
      );
      
      // 컨트롤러 초기화
      _pageController = PageController();
      
      // 새로운 매니저 인스턴스 초기화
      _initializeManagers();
      
      // 상태표시줄 설정 및 데이터 로드
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _setupStatusBar();
        // 이미 mounted 체크가 되어있는 내부에서 비동기 작업 시작
        _loadDataSequentially();
      });
      
      debugPrint('✅ NoteDetailScreen initState 완료');
    } catch (e, stackTrace) {
      debugPrint('❌ NoteDetailScreen initState 중 오류 발생: $e');
      debugPrint('스택 트레이스: $stackTrace');
    }
  }
  
  void _setupStatusBar() {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.dark,
      ),
    );
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _theme = Theme.of(context);
    
    if (mounted && _state.note != null) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    try {
      // 타이머 관련 리소스 정리
    _screenshotWarningTimer?.cancel();
      _state.cancelBackgroundTimer();
      
      // 서비스 정리
    _ttsService.stop();
      _textReaderService.stop();
      _screenshotService.stopDetection();
      
      // PageController 정리 - 에러 방지를 위해 try-catch로 감싸기
      try {
        if (_pageController.hasClients) {
    _pageController.dispose();
        }
      } catch (e) {
        debugPrint('PageController 정리 중 오류: $e');
      }
      
      // Animation 관련 설정 초기화
      timeDilation = 1.0;
    } catch (e) {
      debugPrint('리소스 정리 중 오류: $e');
    } finally {
      // 옵저버 해제
      WidgetsBinding.instance.removeObserver(this);
    super.dispose();
    }
  }
  
  // 리소스 정리 메서드
  Future<void> _cleanupResources() async {
    try {
      await _imageService.clearImageCache();
      await _cancelAllPendingTasks();
    } catch (e) {
      debugPrint('리소스 정리 중 오류: $e');
    }
  }
  
  // 진행 중인 모든 작업을 취소
  Future<void> _cancelAllPendingTasks() async {
    try {
      if (widget.noteId.isNotEmpty) {
        _ttsService.stop();
        _textReaderService.stop();
        
        final prefs = await SharedPreferences.getInstance();
        final key = 'processing_note_${widget.noteId}';
        await prefs.setBool(key, false);
      }
    } catch (e) {
      debugPrint('백그라운드 작업 취소 중 오류: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _screenshotService.startDetection();
    } else if (state == AppLifecycleState.paused) {
      _screenshotService.stopDetection();
    }
  }

  // 스크린샷 감지 초기화
  Future<void> _initScreenshotDetection() async {
    await _screenshotHelper.initialize((timestamp) {
      if (mounted) {
        _screenshotHelper.showSnackBarWarning(context);
      }
    });
    
    await _screenshotHelper.startDetection();
  }

  // 데이터 순차적 로드 (안정성 개선)
  Future<void> _loadDataSequentially() async {
    debugPrint('🔄 _loadDataSequentially 시작');
    
    if (!mounted) {
      debugPrint('❌ _loadDataSequentially: 위젯이 더 이상 마운트되지 않음');
      return;
    }
    
    try {
      // 1. 노트 데이터 로드
      debugPrint('📝 노트 데이터 로드 시작');
      await _loadNote();
      if (!mounted) return;
      debugPrint('✅ 노트 데이터 로드 완료');
      
      // 2. TTS 초기화 (병렬 처리)
      debugPrint('🔊 TTS 초기화 시작');
      _initTts();
      if (!mounted) return;
      debugPrint('✅ TTS 초기화 완료');
      
      // 3. 사용자 설정 로드
      debugPrint('⚙️ 사용자 설정 로드 시작');
      await _loadUserPreferences();
      if (!mounted) return;
      debugPrint('✅ 사용자 설정 로드 완료');
      
      // 4. 백그라운드 처리 상태 확인 설정
      debugPrint('🔄 백그라운드 처리 상태 확인 설정 시작');
      _setupBackgroundProcessingCheck();
      if (!mounted) return;
      debugPrint('✅ 백그라운드 처리 상태 확인 설정 완료');
      
      // 5. 스크린샷 감지 초기화
      debugPrint('📸 스크린샷 감지 초기화 시작');
      await _initScreenshotDetection();
      if (!mounted) return;
      debugPrint('✅ 스크린샷 감지 초기화 완료');
      
      debugPrint('🎉 _loadDataSequentially 전체 완료');
    } catch (e, stackTrace) {
      debugPrint('❌ 데이터 순차적 로드 중 오류: $e');
      debugPrint('스택 트레이스: $stackTrace');
      if (mounted) {
        setState(() {
          _state.setError('노트 데이터 로드 중 오류가 발생했습니다: $e');
          _state.setLoading(false);
        });
      }
    }
  }

  // 노트 로드 함수 - 선택적으로 초기 데이터 사용
  Future<void> _loadNote() async {
    debugPrint('📄 _loadNote 메서드 시작: noteId=${widget.noteId}');
    
    if (!mounted) {
      debugPrint('❌ _loadNote: 위젯이 더 이상 마운트되지 않음');
      return;
    }
    
    try {
      setState(() {
        _state.setLoading(true);
        _state.setError(null); // 이전 에러 초기화
      });
      
      // 이미 완전한 노트 객체가 있는 경우 바로 사용
      if (widget.note != null && 
          widget.note!.id != null && 
          widget.note!.id!.isNotEmpty) {
        debugPrint('🔍 전달받은 노트 데이터를 사용합니다: ${widget.note!.id}, 페이지 수: ${widget.note!.pages?.length ?? 0}');
        
        // 노트 객체로 상태 업데이트  
        setState(() {
          _state.updateNote(widget.note!);
          _titleEditingController.text = widget.note!.originalText ?? '';
          _state.setLoading(false);
        });
        
        // 페이지 로딩은 생략 - 이미 노트 객체가 있기 때문
        return;
      }
      
      // 노트 ID로 데이터 로드
      debugPrint('📝 서버에서 노트 데이터 로드: ${widget.noteId}');
      await _loadPages(); // 기존 페이지 로드 로직 사용
      
    } catch (e, stackTrace) {
      debugPrint('❌ 노트 로드 중 오류: $e');
      debugPrint('스택 트레이스: $stackTrace');
      if (mounted) {
        setState(() {
          _state.setError('노트 로드 중 오류가 발생했습니다: $e');
          _state.setLoading(false);
        });
      }
    }
  }
  
  // 페이지 로드 로직을 별도 메서드로 분리
  Future<void> _loadPages() async {
    try {
      debugPrint('⏱️ 페이지 로드 타임아웃 설정 (5초)');
      
      // UI 차단 없이 페이지 로드 시작
      final pageLoadFuture = _pageManager.loadPagesFromServer(forceReload: true);
      
      // 타임아웃 설정
      final pageLoadResult = await Future.any([
        pageLoadFuture,
        Future.delayed(const Duration(seconds: 5), () {
          debugPrint('⚠️ 페이지 로드 타임아웃');
          throw Exception('페이지 로드 시간이 초과되었습니다.');
        })
      ]);
      
      if (!mounted) {
        debugPrint('❌ 페이지 로드 후 위젯이 마운트되지 않음');
        return;
      }
      
      if (_pageManager.pages.isEmpty) {
        debugPrint('⚠️ 페이지가 없음');
        setState(() {
          _state.setError('노트에 페이지가 없습니다.');
          _state.setLoading(false);
        });
        return;
      }
      
      debugPrint('✅ 페이지 로드 성공: ${_pageManager.pages.length}개 페이지');
      
      // 첫 페이지로 이동 - UI 업데이트만 즉시 처리
      debugPrint('🔄 첫 페이지로 이동');
      _pageManager.changePage(0);
      
      // 로딩 상태 해제 - 텍스트 처리 전에 UI 표시
      setState(() {
        _state.setLoading(false);
        _state.setCurrentImageFile(_imageService.getCurrentImageFile());
      });
      
      // 페이지 텍스트 처리는 별도 작업으로 비동기 실행
      _processPageTextAfterLoading();
      
      debugPrint('🎉 페이지 로드 메인 로직 완료, UI 표시 중');
    } catch (e) {
      debugPrint('❌ 페이지 로드 중 오류: $e');
      if (mounted) {
        setState(() {
          _state.setError('페이지 로드 중 오류가 발생했습니다: $e');
          _state.setLoading(false);
        });
      }
    }
  }

  // 페이지 로드 이후 텍스트 처리를 위한 별도 메서드
  void _processPageTextAfterLoading() {
    // UI 스레드 차단 방지를 위해 microtask 사용
    Future.microtask(() async {
      try {
        debugPrint('📝 백그라운드에서 페이지 텍스트 처리 시작');
        await _processCurrentPageText();
        
        // 처리 완료 후 백그라운드 처리 상태 확인
        if (_state.note?.id != null && mounted) {
          await _checkBackgroundProcessing(_state.note!.id!);
        }
        
        debugPrint('✅ 백그라운드 페이지 텍스트 처리 완료');
      } catch (e) {
        debugPrint('⚠️ 백그라운드 텍스트 처리 중 오류 (무시됨): $e');
      }
    });
  }

  // 백그라운드 처리 상태 확인
  Future<void> _checkBackgroundProcessing(String noteId) async {
        try {
          final noteDoc = await FirebaseFirestore.instance
              .collection('notes')
          .doc(noteId)
              .get();
          
      if (noteDoc.exists && mounted) {
            final data = noteDoc.data();
        final isProcessingBackground = data?['isProcessingBackground'] as bool? ?? false;
        final processingCompleted = data?['processingCompleted'] as bool? ?? false;
    
    setState(() {
          _state.setBackgroundProcessingFlag(isProcessingBackground && !processingCompleted);
        });
      }
    } catch (e) {
      debugPrint('백그라운드 처리 상태 확인 중 오류: $e');
    }
  }
  
  // 페이지 변경 처리
  Future<void> _changePage(int index) async {
    if (index < 0 || index >= _pageManager.pages.length) return;
    
    try {
      // 페이지 매니저에 인덱스 변경 알림
      _pageManager.changePage(index);
      
      // PageController 애니메이션
      if (_pageController.hasClients && _pageController.page?.round() != index) {
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
    
      // 이전에 방문한 페이지가 아닌 경우에만 방문 기록 추가
      if (!_state.isPageVisited(index)) {
        _state.markPageVisited(index);
      }
    
      // UI 업데이트
      if (mounted) {
        setState(() {});
      }
  
      // 페이지 내용 로드 (이미지 및 텍스트 처리) - 서비스 레이어로 위임
      final currentPage = _pageManager.currentPage;
      if (currentPage != null && _state.note != null) {
        // 이미 처리 중인 경우 중복 처리 방지
        if (_state.isProcessingText) {
          debugPrint('⚠️ 이미 텍스트 처리 중입니다. 중복 처리 방지');
          return;
        }
        
        // 로딩 상태 업데이트
        if (mounted) {
          setState(() {
            _state.setProcessingText(true);
          });
        }
        
        try {
          // 타임아웃과 에러 처리 개선
          final result = await Future.any([
            _contentManager.processPageText(
              page: currentPage,
              imageFile: _imageService.getCurrentImageFile(),
              recursionDepth: 0, // 초기 호출은 recursionDepth 0
            ),
            Future.delayed(const Duration(seconds: 10), () {
              debugPrint('⚠️ 페이지 텍스트 처리 타임아웃 발생');
              return null;
            }),
          ]);
          
          if (!mounted) return;
          
          // 결과 처리
          setState(() {
            // 이미지 파일 업데이트 (null 체크 추가)
            final currentImageFile = _imageService.getCurrentImageFile();
            if (currentImageFile != null && currentImageFile.existsSync()) {
              _state.setCurrentImageFile(currentImageFile);
            }
            
            // 텍스트 처리 결과 업데이트
            if (result != null) {
              _useSegmentMode = !result.showFullText;
              _state.markPageVisited(_pageManager.currentPageIndex);
            }
            
            // 처리 상태 업데이트
            _state.setProcessingText(false);
          });
        } catch (e) {
          debugPrint('❌ 페이지 변경 중 텍스트 처리 오류: $e');
          
          // 오류 발생 시에도 로딩 상태 해제
          if (mounted) {
            setState(() {
              _state.setProcessingText(false);
            });
          }
        }
      }
    } catch (e) {
      debugPrint('❌ 페이지 변경 처리 중 오류: $e');
      
      // 오류 발생 시에도 로딩 상태 해제
      if (mounted) {
        setState(() {
          _state.setProcessingText(false);
        });
      }
    }
  }

  // 현재 페이지 텍스트 처리
  Future<void> _processCurrentPageText({bool isRetry = false}) async {
    final currentPage = _pageManager.currentPage;
    if (currentPage == null || _state.note == null) {
      debugPrint('텍스트 처리: 현재 페이지 또는 노트 정보가 없습니다');
      return;
    }
    
    if (!mounted) return;

    // 처리 상태 업데이트
    setState(() {
      _state.setProcessingText(true);
    });

    try {
      // 타임아웃 추가 및 에러 처리 강화
      final result = await Future.any([
        _contentManager.processPageText(
          page: currentPage,
          imageFile: _imageService.getCurrentImageFile(),
          recursionDepth: isRetry ? 1 : 0, // 재시도 시 recursionDepth 증가
        ),
        Future.delayed(const Duration(seconds: 15), () {
          debugPrint('⚠️ 페이지 텍스트 처리 타임아웃');
          return null;
        }),
      ]);
    
      if (!mounted) return;
    
      // 결과가 null이 아닌 경우에만 상태 업데이트
      if (result != null) {
        setState(() {
          // 이미지 파일 업데이트 (null 체크 추가)
          final currentImageFile = _imageService.getCurrentImageFile();
          if (currentImageFile != null && currentImageFile.existsSync()) {
            _state.setCurrentImageFile(currentImageFile);
          }
          
          _useSegmentMode = !result.showFullText;
          _state.markPageVisited(_pageManager.currentPageIndex);
          
          // 텍스트 처리 완료 표시
          _state.setProcessingText(false);
        });
      } else {
        setState(() {
          _state.setProcessingText(false);
          // 실패한 경우에도 페이지 방문 표시는 유지
          _state.markPageVisited(_pageManager.currentPageIndex);
        });
      }
    } catch (e) {
      debugPrint('❌ 텍스트 처리 중 오류: $e');
      
      // 첫 번째 시도에서 실패한 경우에만 한 번 더 시도
      if (!isRetry) {
        debugPrint('🔄 텍스트 처리 재시도 중...');
        // 잠시 딜레이 후 재시도
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          _processCurrentPageText(isRetry: true);
        }
      } else {
        if (mounted) {
          setState(() {
            _state.setProcessingText(false);
          });
        }
      }
    }
  }

  // TTS 초기화
  void _initTts() {
    _ttsService.init();
  }

  // 사용자 기본 설정 로드
  Future<void> _loadUserPreferences() async {
    try {
      if (!mounted) return;

    final currentPage = _pageManager.currentPage;
      if (currentPage == null || currentPage.id == null) return;

      // TextProcessingService를 통해 사용자 설정 로드 및 적용 (id가 null이 아님이 확인됨)
      final useSegmentMode = await _textProcessingService.loadAndApplyUserPreferences(currentPage.id);

      if (mounted) {
    setState(() {
          _useSegmentMode = useSegmentMode;
              });
            }

      debugPrint('노트 뷰 모드 로드됨: 세그먼트 모드 사용: $_useSegmentMode');
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

  // 백그라운드 처리 확인 설정
  Future<void> _setupBackgroundProcessingCheck() async {
    // 처리 상태 주기적으로 확인
    _state.backgroundCheckTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkBackgroundProcessing(widget.noteId)
    );
  }
  
      // 플래시카드 화면으로 이동
  void _navigateToFlashcards() {
    if (_state.note?.id != null) {
      Navigator.push(
          context,
      MaterialPageRoute(
        builder: (context) => FlashCardScreen(
            noteId: _state.note!.id!,
        ),
      ),
    );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        // 앱바
        appBar: PikaAppBar.noteDetail(
          title: _state.note?.originalText ?? '',
          currentPage: _pageManager.currentPageIndex + 1,
          totalPages: _pageManager.pages.length,
          flashcardCount: _state.note?.flashcardCount ?? 0,
          onMorePressed: () => _optionsManager.showMoreOptions(
            context,
            _state.note,
            onTitleEditing: () {
              // 제목 편집 후 처리
              setState(() {});
            },
            onFavoriteToggle: (isFavorite) {
    setState(() {
                _state.toggleFavorite();
              });
            },
            onNoteDeleted: () {
              Navigator.of(context).pop(); // 화면 닫기
            },
          ),
          onFlashcardTap: _navigateToFlashcards,
          onBackPressed: () async {
            final shouldPop = await _onWillPop();
            if (shouldPop && context.mounted) {
              Navigator.of(context).pop();
            }
            },
          ),
        // 본문
        body: _buildMainContent(),
      ),
    );
  }
  
  // 메인 콘텐츠 위젯
  Widget _buildMainContent() {
    return Stack(
      children: [
        Column(
          children: [
            // 메인 콘텐츠 영역
            Expanded(
              child: Container(
                color: Colors.white,
                child: _buildBody(),
              ),
            ),
            
            // 하단 네비게이션 바
            _buildBottomBar(),
          ],
        ),
        
        // 툴팁 표시
        if (_state.showTooltip)
          _tooltipManager.buildTooltip(
            context,
            onDismiss: () {
    setState(() {
                _tooltipManager.handleTooltipDismiss();
                _state.showTooltip = false;
              });
            },
            onNextStep: () {
      setState(() {
                _tooltipManager.setTooltipStep(_tooltipManager.tooltipStep + 1);
              });
            },
            onPrevStep: () {
        setState(() {
                _tooltipManager.setTooltipStep(_tooltipManager.tooltipStep - 1);
              });
            },
          ),
      ],
    );
  }
  
  // 하단 바 구성
  Widget _buildBottomBar() {
    // null 체크와 기본값 설정으로 안전하게 처리
    final totalPages = (_state.note?.imageCount != null) 
        ? _state.note!.imageCount! 
        : _pageManager.pages.length;
    
    // PageContentService 대신 ContentManager 사용
    return NoteDetailBottomBar(
              currentPage: _pageManager.currentPage,
              currentPageIndex: _pageManager.currentPageIndex,
      totalPages: totalPages,
      onPageChanged: (index) => _changePage(index),
      onToggleFullTextMode: _toggleDisplayMode,
      isFullTextMode: !_useSegmentMode,
      contentManager: _contentManager, // PageContentService에서 ContentManager로 변경
              textReaderService: _textReaderService,
      isProcessing: _state.isProcessingText,
      );
    }

  // 메인 UI 구성
  Widget _buildBody() {
    // 로딩 중 또는 노트가 없는 경우
    if (_state.isLoading || _state.note == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
      children: [
            // 로딩 표시
            const DotLoadingIndicator(message: '노트를 불러오는 중입니다'),
            
            const SizedBox(height: 24),
            
            // 새로고침 버튼 (2초 이상 로딩이 지속되면 표시)
            if (!_state.isLoading)
              TextButton(
                onPressed: _forceRefreshPage,
                child: const Text('새로고침'),
              ),
          ],
        ),
      );
    }
    
    // 에러가 있는 경우
    if (_state.error?.isNotEmpty == true) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
              children: [
            Text(
              _state.error ?? '오류가 발생했습니다',
              style: TypographyTokens.body1.copyWith(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _forceRefreshPage,
              child: const Text('다시 시도'),
            ),
          ],
      ),
    );
  }
  
    // 페이지가 없는 경우
    if (_pageManager.pages.isEmpty) {
                                return Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
            Text(
              '페이지가 없습니다',
              style: TypographyTokens.body1,
              textAlign: TextAlign.center,
            ),
                                    ],
                                  ),
                                );
                              }
    
    // 정상적인 경우 PageView로 페이지 표시
    return PageView.builder(
        itemCount: _pageManager.pages.length,
          controller: _pageController,
        onPageChanged: (index) {
          _changePage(index);
        },
        itemBuilder: (context, index) {
        // 페이지 정보 가져오기
            final page = _pageManager.getPageAtIndex(index);
        
        // 페이지가 없으면 기본 UI 표시
        if (page == null) {
          return Center(child: Text('페이지 정보가 없습니다'));
        }
        
        // 이미지 파일 로드
            final imageFile = _pageManager.getImageFileForPage(page);
            
            return Column(
              children: [
            // 이미지 영역
            PageImageWidget(
              page: page,
              imageFile: imageFile,
              title: _state.note?.originalText ?? '노트',
              showTitle: true,
              style: ImageContainerStyle.noteDetail,
              onFullScreenTap: (file) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => FullImageScreen(
                      imageFile: file,
                      title: _state.note?.originalText ?? '이미지',
                                  ),
                                ),
                              );
                            },
            ),
            
            // 내용 영역 (현재 페이지일 경우만 콘텐츠 표시)
            Expanded(
              child: index == _pageManager.currentPageIndex
                ? SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildPageContentWidget(),
                  )
                : Center(
                            child: Text(
                      '페이지 ${index + 1}',
                      style: TypographyTokens.body1,
                    ),
                  ),
                ),
              ],
            );
      },
    );
  }
  
  // _buildPageContentWidget 메서드 수정
  Widget _buildPageContentWidget() {
    final currentPage = _pageManager.currentPage;
    if (currentPage == null) return const SizedBox.shrink();
    
    return PageContentWidget(
      key: ValueKey('page_content_${currentPage.id}'),
      page: currentPage,
      imageFile: _state.imageFile,
      isLoadingImage: _state.isProcessingText,
      noteId: widget.noteId,
      onCreateFlashCard: _createFlashCard,
      flashCards: [], // 필요한 경우 플래시카드 목록 전달
      onDeleteSegment: _deleteSegment,
      useSegmentMode: _useSegmentMode,
    );
  }
  
  // _deleteSegment 메서드 수정
  Future<void> _deleteSegment(int segmentIndex) async {
    final currentPage = _pageManager.currentPage;
    if (currentPage == null) return;
    
    setState(() {
      _state.setProcessingText(true);
    });
    
    try {
      final updatedPage = await _contentManager.deleteSegment(
        noteId: widget.noteId,
        page: currentPage,
        segmentIndex: segmentIndex,
      );
      
      if (updatedPage != null) {
        setState(() {
          _pageManager.updateCurrentPage(updatedPage);
          if (_state.note != null) {
            _state.updateNote(_state.note!);
          }
        });
        
        // 페이지 처리 후 다시 텍스트 로드
        _processCurrentPageText();
      }
    } catch (e) {
      debugPrint('세그먼트 삭제 중 오류: $e');
    } finally {
      setState(() {
        _state.setProcessingText(false);
      });
    }
  }

  // _toggleDisplayMode 메서드 수정
  Future<void> _toggleDisplayMode() async {
    final currentPage = _pageManager.currentPage;
    if (currentPage?.id == null) return;
    
    try {
      final updatedText = await _contentManager.toggleDisplayModeForPage(currentPage!.id);
      
      if (mounted && updatedText != null) {
        setState(() {
          _useSegmentMode = !updatedText.showFullText;
        });
      }
    } catch (e) {
      debugPrint('디스플레이 모드 토글 실패: $e');
    }
  }

  // 플래시카드 생성
  Future<void> _createFlashCard(String front, String back, {String? pinyin}) async {
    setState(() {
      _state.isCreatingFlashCard = true;
    });

        try {
          // 플래시카드 생성
          await _flashCardService.createFlashCard(
            front: front,
        back: back,
        pinyin: pinyin,
            noteId: widget.noteId,
          );
      
      // 캐시 업데이트
      await _cacheService.removeCachedNote(widget.noteId);

      // Firestore에서 노트 가져오기
      final noteDoc = await FirebaseFirestore.instance
          .collection('notes')
          .doc(widget.noteId)
          .get();

      if (noteDoc.exists && mounted) {
        final updatedNote = Note.fromFirestore(noteDoc);
        setState(() {
          _state.updateNote(updatedNote);
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
          _state.isCreatingFlashCard = false;
        });
      }
    }
  }

  // 옵션 더보기 메뉴
  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => NoteActionBottomSheet(
        onEditTitle: () => _optionsManager.showMoreOptions(
          context,
          _state.note,
          onTitleEditing: () => setState(() {}),
          onFavoriteToggle: (isFavorite) => setState(() => _state.toggleFavorite()),
          onNoteDeleted: () => Navigator.of(context).pop(),
        ),
        onDeleteNote: _confirmDelete,
        onToggleFullTextMode: _toggleDisplayMode,
        onToggleFavorite: _toggleFavorite,
        isFullTextMode: !_useSegmentMode,
        isFavorite: _state.isFavorite,
        ),
      );
    }
    
  // 즐겨찾기 토글
  Future<void> _toggleFavorite() async {
    if (_state.note == null || _state.note?.id == null) return;

    final newValue = !_state.isFavorite;
    
                setState(() {
      _state.isFavorite = newValue;
    });
    
    try {
      // id가 null이 아님을 확인했으므로 안전하게 사용
      await _favoritesService.toggleFavorite(_state.note!.id!, newValue);
    } catch (e) {
      if (mounted) {
      setState(() {
          _state.isFavorite = !newValue; // 실패 시 원래 값으로 되돌림
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('즐겨찾기 설정 중 오류가 발생했습니다: $e'))
        );
      }
    }
  }
  
  // 노트 삭제 확인
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
            style: TextButton.styleFrom(foregroundColor: ColorTokens.primary),
                        ),
                      ],
      ),
    );
  }

  // 노트 삭제
  Future<void> _deleteNote() async {
    if (_state.note == null || _state.note?.id == null) return;

                setState(() {
      _state.setLoading(true);
    });

    try {
      // 페이지 삭제
      await _pageService.deleteAllPagesForNote(_state.note!.id!);

      // 노트 삭제
      await _noteService.deleteNote(_state.note!.id!);
        
        if (mounted) {
        Navigator.of(context).pop(); // 삭제 후 이전 화면으로 돌아가기
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state.setLoading(false);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('노트 삭제 중 오류가 발생했습니다: $e'))
        );
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

  // 매니저 인스턴스 초기화
  void _initializeManagers() {
    try {
      _screenshotHelper = ScreenshotServiceHelper();
      _tooltipManager = TooltipManager();
      _optionsManager = NoteOptionsManager();
      
      debugPrint('✅ 모든 매니저 초기화 완료');
    } catch (e, stackTrace) {
      debugPrint('❌ 매니저 초기화 중 오류 발생: $e');
      debugPrint('스택 트레이스: $stackTrace');
    }
  }

  Future<bool> _onWillPop() async {
    try {
      // 먼저 리소스 정리
      _ttsService.stop();
      _textReaderService.stop();
      
      // true를 반환하여 시스템이 pop을 처리하도록 함
      // 직접 Navigator.pop()을 호출하지 않아 assertion 에러를 방지
      return true;
    } catch (e) {
      debugPrint('뒤로가기 처리 중 오류: $e');
      return true;
    }
  }
}