// lib/views/screens/note_detail_screen.dart (리팩토링된 버전)
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart' show timeDilation;

// 모델
import '../../models/note.dart';
import '../../models/page.dart' as page_model;
import '../../models/processed_text.dart';
import '../../models/flash_card.dart';

// 새 클래스들
import '../../widgets/note_page_manager.dart';
import '../../note_detail/note_detail_image_handler.dart';
import '../../widgets/note_detail/note_detail_state.dart';
import '../../widgets/note_detail/first_image_container.dart';

// 서비스들
import '../../services/note_service.dart';
import '../../services/flashcard_service.dart' hide debugPrint;
import '../../services/tts_service.dart';
import '../../services/user_preferences_service.dart';
import '../../services/unified_cache_service.dart';
import '../../services/text_reader_service.dart';
import '../../services/screenshot_service.dart';
import '../../services/page_content_service.dart';
import '../../services/translation_service.dart';
import '../../services/enhanced_ocr_service.dart';
import '../../services/dictionary/dictionary_service.dart';
import '../../services/page_service.dart';
import '../../services/image_service.dart';
import '../../services/text_processing_service.dart';
import '../../services/favorites_service.dart';

// 기타 위젯 및 유틸리티
import '../../widgets/dot_loading_indicator.dart';
import '../../widgets/common/pika_app_bar.dart';
import '../../theme/tokens/typography_tokens.dart';
import '../../theme/tokens/color_tokens.dart';
import '../../widgets/note_detail/note_detail_bottom_bar.dart';
import '../../widgets/common/help_text_tooltip.dart';
import '../../widgets/note_segment_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/note_action_bottom_sheet.dart';
import '../../utils/debug_utils.dart';
import '../../views/screens/flashcard_screen.dart';
import '../../views/screens/full_image_screen.dart';
import 'dart:math' as math;
import '../../widgets/edit_title_dialog.dart';
import '../../note_detail/screenshot_service_helper.dart';
import '../../note_detail/tooltip_manager.dart';
import '../../note_detail/note_options_manager.dart';
import '../../widgets/page_content_widget.dart';

/// 노트 상세 화면
/// 페이지 탐색, 노트 액션, 백그라운드 처리, 이미지 로딩 등의 기능
class NoteDetailScreen extends StatefulWidget {
  final String noteId;
  final bool isProcessingBackground;
  final int? totalImageCount;
  
  // 라우트 이름 상수 추가
  static const String routeName = '/note_detail';

  const NoteDetailScreen({
    Key? key,
    required this.noteId,
    this.isProcessingBackground = false,
    this.totalImageCount,
  }) : super(key: key);

  // 라우트를 생성하는 편의 메소드 추가
  static Route<dynamic> route({
    required String noteId,
    bool isProcessingBackground = false,
    int totalImageCount = 1,
  }) {
    return MaterialPageRoute(
      settings: const RouteSettings(name: routeName),
      builder: (context) => NoteDetailScreen(
        noteId: noteId,
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
  late NotePageManager _pageManager;

  // 서비스들
  final TextProcessingService _textProcessingService = TextProcessingService();
  final TtsService _ttsService = TtsService();
  final FavoritesService _favoritesService = FavoritesService();
  final UserPreferencesService _preferencesService = UserPreferencesService();
  final NoteDetailImageHandler _imageHandler = NoteDetailImageHandler();
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
    
    // 옵저버 등록
    WidgetsBinding.instance.addObserver(this);
    
    // 상태 초기화
    _state.setLoading(true);
    _state.expectedTotalPages = widget.totalImageCount ?? 0;
    _state.setBackgroundProcessingFlag(widget.isProcessingBackground);
    
    // 매니저 및 핸들러 초기화
    _pageManager = NotePageManager(noteId: widget.noteId);
    
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
      await _imageHandler.clearImageCache();
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
    if (!mounted) return;
    
    try {
      // 1. 노트 데이터 로드
      await _loadNote();
      
      // 2. TTS 초기화 (병렬 처리)
      _initTts();
      
      // 3. 사용자 설정 로드
      await _loadUserPreferences();
      
      // 4. 백그라운드 처리 상태 확인 설정
      _setupBackgroundProcessingCheck();
      
      // 5. 스크린샷 감지 초기화
      await _initScreenshotDetection();
    } catch (e) {
      debugPrint('데이터 순차적 로드 중 오류: $e');
      if (mounted) {
        setState(() {
          _state.setError('노트 데이터 로드 중 오류가 발생했습니다.');
          _state.setLoading(false);
        });
      }
    }
  }

  // 노트 데이터 로드
  Future<void> _loadNote() async {
    if (!mounted) return;
    
    try {
        setState(() {
        _state.setLoading(true);
        _state.setError(null); // 이전 에러 초기화
      });
      
      if (widget.noteId.isEmpty) {
        setState(() {
          _state.setError('유효하지 않은 노트 ID입니다.');
          _state.setLoading(false);
        });
        return;
      }

      debugPrint('노트 로딩 시작: ${widget.noteId}');
      
      // 노트 가져오기에 타임아웃 추가
      Note? note;
      try {
        note = await Future.any([
          _noteService.getNoteById(widget.noteId),
          Future.delayed(const Duration(seconds: 10), () => null)
        ]);
        
        if (note == null) {
          throw Exception('노트 로딩 시간이 초과되었습니다.');
      }
    } catch (e) {
        debugPrint('노트 로드 중 오류 또는 타임아웃: $e');
      if (mounted) {
        setState(() {
            _state.setError('노트를 불러오는 중 오류가 발생했습니다: $e');
            _state.setLoading(false);
          });
        }
        return;
      }

      if (!mounted) return;
      
      setState(() {
        _state.updateNote(note!);
      });
      
      debugPrint('노트 로드 성공: ${note.id}, 페이지 로드 시작');
      
      // 페이지 로드에 타임아웃 적용
      try {
        bool pagesLoaded = false;
        await Future.any([
          _pageManager.loadPagesFromServer().then((_) {
            pagesLoaded = true;
          }),
          Future.delayed(const Duration(seconds: 15), () {
            if (!pagesLoaded) {
              throw Exception('페이지 로드 시간이 초과되었습니다.');
            }
          })
        ]);
        
        if (!mounted) return;
        
        if (_pageManager.pages.isEmpty) {
      setState(() {
            _state.setError('노트에 페이지가 없습니다.');
            _state.setLoading(false);
          });
          return;
        }
        
        // 첫 페이지로 이동
        _pageManager.changePage(0);
        
        // 현재 페이지 텍스트 처리
        await _processCurrentPageText();
        
        if (!mounted) return;
        
        setState(() {
          _state.setLoading(false);
          _state.setCurrentImageFile(_imageHandler.getCurrentImageFile());
        });
    } catch (e) {
        debugPrint('페이지 로드 중 오류: $e');
          if (mounted) {
        setState(() {
            _state.setError('페이지 로드 중 오류가 발생했습니다: $e');
            _state.setLoading(false);
          });
        }
      }
      
      if (note.id != null) {
        await _checkBackgroundProcessing(note.id!);
        }
      } catch (e) {
      debugPrint('노트 로드 중 오류: $e');
      if (mounted) {
        setState(() {
          _state.setError('노트 로드 중 오류가 발생했습니다: $e');
          _state.setLoading(false);
        });
      }
    }
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
        // 로딩 상태 업데이트
        if (mounted) {
          setState(() {
            _state.setProcessingText(true);
          });
        }
        
        // 페이지 내용 로드 (이미지 및 텍스트 처리 통합)
        final result = await _pageManager.loadPageContent(
          currentPage,
          textProcessingService: _textProcessingService,
          imageHandler: _imageHandler,
          note: _state.note!,
        );
        
        if (!mounted) return;
        
        // 결과 처리
        setState(() {
          // 이미지 파일 업데이트
          if (result['imageFile'] != null) {
            _state.setCurrentImageFile(result['imageFile']);
          }
          
          // 텍스트 처리 결과 업데이트
          if (result['processedText'] != null) {
            _useSegmentMode = !result['processedText'].showFullText;
            _state.markPageVisited(_pageManager.currentPageIndex);
          }
          
          // 처리 상태 업데이트
          _state.setProcessingText(false);
        });
      }
    } catch (e) {
      debugPrint('페이지 변경 중 오류: $e');
      
      // 오류 발생 시에도 로딩 상태 해제
      if (mounted) {
        setState(() {
          _state.setProcessingText(false);
        });
      }
    }
  }
  
  // 현재 페이지 텍스트 처리
  Future<void> _processCurrentPageText() async {
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
      // 페이지 내용 로드 (서비스 레이어로 위임)
      final result = await _pageManager.loadPageContent(
        currentPage,
        textProcessingService: _textProcessingService,
        imageHandler: _imageHandler,
        note: _state.note!,
      );
      
      if (!mounted) return;
      
      // 결과 처리
      setState(() {
        // 이미지 파일 업데이트
        if (result['imageFile'] != null) {
          _state.setCurrentImageFile(result['imageFile']);
        }
        
        // 텍스트 처리 결과 업데이트
        if (result['processedText'] != null) {
          _useSegmentMode = !result['processedText'].showFullText;
          _state.markPageVisited(_pageManager.currentPageIndex);
        }
      });
    } catch (e) {
      debugPrint('페이지 텍스트 처리 중 오류 발생: $e');
    } finally {
      // 처리 상태 업데이트 (마무리)
      if (mounted) {
        setState(() {
          _state.setProcessingText(false);
        });
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
          title: _state.note?.originalText ?? '로딩 중',
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
        body: _state.isEditingTitle ? 
          _buildTitleEditor() :
          _buildMainContent(),
      ),
    );
  }

  // 제목 편집 위젯
  Widget _buildTitleEditor() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: TextField(
          controller: _titleEditingController,
          autofocus: true,
          style: TypographyTokens.body1,
          onSubmitted: (value) => _updateNoteTitle(value),
          decoration: InputDecoration(
            hintText: '노트 제목',
            border: OutlineInputBorder(),
          ),
        ),
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
    
    return NoteDetailBottomBar(
      currentPage: _pageManager.currentPage,
      currentPageIndex: _pageManager.currentPageIndex,
      totalPages: totalPages,
      onPageChanged: (index) {
        _pageManager.changePage(index);
        setState(() {});
      },
      onToggleFullTextMode: () {
        setState(() {
          _useSegmentMode = !_useSegmentMode;
          // 직접 TextProcessingService 호출
          final pageId = _pageManager.currentPage?.id;
          if (pageId != null) {
            _textProcessingService.toggleDisplayModeForPage(pageId);
          }
        });
      },
      isFullTextMode: !_useSegmentMode,
      pageContentService: PageContentService(),
      textReaderService: TextReaderService(),
      onTtsPlay: () {
        // TTS 재생은 PageContentWidget에서 처리
      },
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
            _buildImageThumbnailContainer(page, imageFile),
            
            // 내용 영역 (현재 페이지일 경우만 콘텐츠 표시)
            Expanded(
              child: index == _pageManager.currentPageIndex
                ? SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: PageContentWidget(
                      key: ValueKey('page_${page.id}_${_useSegmentMode}_${DateTime.now().millisecondsSinceEpoch}'),
                      page: page,
                      imageFile: imageFile,
                      isLoadingImage: false,
                      noteId: widget.noteId,
                      onCreateFlashCard: (front, back, {String? pinyin}) => 
                        _createFlashCard(front, back, pinyin: pinyin),
                      flashCards: _state.note?.flashCards,
                      onDeleteSegment: _handleDeleteSegment,
                      useSegmentMode: _useSegmentMode,
                    ),
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
  
  // 이미지 썸네일 컨테이너 생성
  Widget _buildImageThumbnailContainer(page_model.Page? page, File? imageFile) {
    debugPrint('이미지 썸네일 빌드: pageId=${page?.id}, 이미지 파일=${imageFile != null}');
    
    // 페이지가 없는 경우 빈 컨테이너
    if (page == null) {
      return Container(
        height: 200,
        color: Colors.grey[100],
        child: const Center(child: Text('이미지 없음')),
      );
    }

    // 탭 시 전체 화면 이미지 표시 처리
    void onTapImage() {
      if (imageFile != null) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => FullImageScreen(
                                    imageFile: imageFile,
              title: _state.note?.originalText ?? '이미지',
                                  ),
                                ),
                              );
      } else if (page.imageUrl != null && page.imageUrl!.isNotEmpty) {
        _imageHandler.loadPageImage(page).then((file) {
          if (file != null && mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FullImageScreen(
                  imageFile: file,
                  title: _state.note?.originalText ?? '이미지',
                ),
              ),
            );
          }
        });
      }
    }

    // GestureDetector로 이미지 컨테이너 감싸기 (전체 화면 보기 위해)
    return GestureDetector(
      onTap: onTapImage,
        child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        height: 200,
          decoration: BoxDecoration(
          color: Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
              color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
              offset: const Offset(0, 2),
            ),
            ],
          ),
          child: Stack(
            children: [
            // 이미지 표시
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                    width: double.infinity,
                    height: double.infinity,
                child: imageFile != null
                  ? Image.file(
                      imageFile,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
                    )
                  : (page.imageUrl != null && page.imageUrl!.isNotEmpty
                      ? Image.network(
                          page.imageUrl!,
                          fit: BoxFit.cover,
                          loadingBuilder: (_, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return _buildImageLoadingIndicator();
                          },
                          errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
                        )
                      : _buildImagePlaceholder()),
              ),
            ),
            
            // 전체 화면 버튼
              Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black.withOpacity(0.3),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: onTapImage,
                  child: const Padding(
                    padding: EdgeInsets.all(6.0),
                    child: Icon(
                      Icons.fullscreen,
                      color: Colors.white,
                      size: 24,
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
  
  // 이미지 로딩 인디케이터
  Widget _buildImageLoadingIndicator() {
    return Container(
      color: Colors.grey[200],
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
  
  // 이미지 플레이스홀더
  Widget _buildImagePlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: Center(
        child: Icon(
          Icons.image,
          size: 48,
          color: Colors.grey[400],
        ),
      ),
    );
  }

  // 텍스트 표시 모드 토글
  Future<void> _toggleDisplayMode() async {
    final currentPage = _pageManager.currentPage;
    if (currentPage == null || currentPage.id == null) return;

    if (_state.isProcessingText) return;

    try {
      // TextProcessingService의 통합 메서드 사용 (id가 null이 아님이 확인됨)
      final updatedText = await _textProcessingService.toggleDisplayModeForPage(currentPage.id);
      
      if (updatedText != null && mounted) {
        setState(() {
          _useSegmentMode = !updatedText.showFullText;
        });
      }
    } catch (e) {
      debugPrint('디스플레이 모드 토글 중 오류 발생: $e');
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

  // 세그먼트 삭제
  Future<void> _handleDeleteSegment(int segmentIndex) async {
    final currentPage = _pageManager.currentPage;
    if (currentPage == null || currentPage.id == null || _state.note == null || _state.note!.id == null) {
      return;
    }
    
    // 세그먼트 매니저를 사용하여 삭제
    final segmentManager = NoteSegmentManager();
    final updatedPage = await segmentManager.deleteSegment(
      noteId: _state.note!.id!,
      page: currentPage,
      segmentIndex: segmentIndex,
    );
    
    if (updatedPage == null) {
      return;
    }
    
    // 페이지 업데이트
    setState(() {
      _pageManager.updateCurrentPage(updatedPage);
    });
    
    // 노트 캐시 업데이트
    try {
      await _noteService.getNoteWithPages(_state.note!.id!);
    } catch (e) {
      debugPrint('세그먼트 삭제 후 노트 캐시 업데이트 중 오류: $e');
    }
  }
  
  // 옵션 더보기 메뉴
  void _showMoreOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => NoteActionBottomSheet(
        onEditTitle: _showEditTitleDialog,
        onDeleteNote: _confirmDelete,
        onToggleFullTextMode: _toggleDisplayMode,
        onToggleFavorite: _toggleFavorite,
        isFullTextMode: !_useSegmentMode,
        isFavorite: _state.isFavorite,
        ),
      );
    }
    
  // 제목 편집 다이얼로그 표시
  void _showEditTitleDialog() {
    if (_state.note == null) return;
    
    setState(() {
      _titleEditingController.text = _state.note!.originalText;
      _state.isEditingTitle = true;
    });
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
  
  // 노트 제목 업데이트
  Future<void> _updateNoteTitle(String newTitle) async {
    if (newTitle.trim().isEmpty || _state.note == null || _state.note!.id == null) return;
    
    setState(() {
      _state.isEditingTitle = false;
    });
    
    try {
      // 노트 업데이트
      final updatedNote = _state.note!.copyWith(
        originalText: newTitle.trim(),
        updatedAt: DateTime.now(),
      );
      
      // Firestore 업데이트
      await _noteService.updateNote(_state.note!.id!, updatedNote);

      // 상태 업데이트
                setState(() {
        _state.updateNote(updatedNote);
      });

      if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('노트 제목이 업데이트되었습니다.'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('노트 제목 업데이트 오류: $e');
        
        if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('제목 업데이트에 실패했습니다.'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
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

  void _initializeManagers() {
    _screenshotHelper = ScreenshotServiceHelper();
    _tooltipManager = TooltipManager();
    _optionsManager = NoteOptionsManager();
  }

  Future<bool> _onWillPop() async {
    try {
      // 먼저 리소스 정리
      _ttsService.stop();
      _textReaderService.stop();
      
      // 제목 편집 중인 경우 처리
      if (_state.isEditingTitle) {
        if (_titleEditingController.text.isNotEmpty) {
          await _updateNoteTitle(_titleEditingController.text);
        }
        setState(() {
          _state.isEditingTitle = false;
        });
        return false;
      }
      
      // true를 반환하여 시스템이 pop을 처리하도록 함
      // 직접 Navigator.pop()을 호출하지 않아 assertion 에러를 방지
      return true;
    } catch (e) {
      debugPrint('뒤로가기 처리 중 오류: $e');
      return true;
    }
  }
}