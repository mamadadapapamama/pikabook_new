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
import '../../note_detail/note_detail_page_manager.dart';
import '../../note_detail/note_detail_image_handler.dart';
import '../../note_detail/note_detail_text_processor.dart';
import '../../widgets/note_detail/note_detail_state.dart';
import '../../widgets/note_detail/first_image_container.dart';
import '../../widgets/note_detail/current_page_content.dart';

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
import '../../note_detail/note_content_manager.dart';
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
  // 핵심 서비스 인스턴스 (필요한 것만 유지)
  final NoteService _noteService = NoteService();
  final PageService _pageService = PageService();
  final FlashCardService _flashCardService = FlashCardService();
  final TtsService _ttsService = TtsService();
  final TextReaderService _textReaderService = TextReaderService();
  final UserPreferencesService _preferencesService = UserPreferencesService();
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  final ScreenshotService _screenshotService = ScreenshotService();
  
  // 새로운 매니저와 핸들러 클래스 사용
  late NoteDetailPageManager _pageManager;
  late NoteDetailImageHandler _imageHandler;
  late NoteDetailTextProcessor _textProcessor;
  
  // 상태 관리 클래스 사용
  late NoteDetailState _state;
  
  // UI 컨트롤러
  late PageController _pageController;
  TextEditingController _titleEditingController = TextEditingController();

  // 기타 변수
  bool _useSegmentMode = true;
  ThemeData? _theme;
  Timer? _screenshotWarningTimer;
  bool _isShowingScreenshotWarning = false;

  // 새로운 매니저 인스턴스
  late ScreenshotServiceHelper _screenshotHelper;
  late TooltipManager _tooltipManager;
  late NoteOptionsManager _optionsManager;
  late NoteContentManager _contentManager;

  @override
  void initState() {
    super.initState();
    
    // 옵저버 등록
    WidgetsBinding.instance.addObserver(this);
    
    // 상태 초기화
    _state = NoteDetailState();
    _state.setLoading(true);
    _state.expectedTotalPages = widget.totalImageCount ?? 0;
    _state.setBackgroundProcessingFlag(widget.isProcessingBackground);
    
    // 매니저 및 핸들러 초기화
    _pageManager = NoteDetailPageManager(noteId: widget.noteId);
    _imageHandler = NoteDetailImageHandler();
    _textProcessor = NoteDetailTextProcessor();
    
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
    timeDilation = 1.0;
    
    // 필수 리소스 정리
    _ttsService.stop();
    _textReaderService.stop();
    _screenshotService.stopDetection();
    _screenshotWarningTimer?.cancel();
    _state.cancelBackgroundTimer();
    
    // 비동기 리소스 정리
    _cleanupResources();
    
    // 옵저버 해제
    WidgetsBinding.instance.removeObserver(this);
    
    super.dispose();
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
      });
      
      if (widget.noteId.isEmpty) {
      setState(() {
          _state.setError('유효하지 않은 노트 ID입니다.');
          _state.setLoading(false);
        });
        return;
      }

      // 노트 가져오기 요청
      final note = await _noteService.getNoteById(widget.noteId);
      
      if (!mounted) return;
      
      if (note == null) {
        setState(() {
          _state.setError('노트를 찾을 수 없습니다. 삭제되었거나 접근 권한이 없습니다.');
          _state.setLoading(false);
        });
      return;
    }

    setState(() {
        _state.updateNote(note);
      });
      
      // 페이지 로드 (더 안정적으로)
      try {
        await _pageManager.loadPagesFromServer();
        
        if (!mounted) return;
        
        // 페이지가 있으면 첫 페이지 처리
        if (_pageManager.pages.isNotEmpty) {
          // 첫 페이지로 이동 (페이지 컨트롤러 인덱스 0으로 설정)
          _pageManager.changePage(0);
          
          // 현재 페이지 텍스트 처리
          await _processCurrentPageText();
        }
        
    if (!mounted) return;
    
        // 로딩 상태 업데이트
          setState(() {
          _state.setLoading(false);
          _state.setCurrentImageFile(_imageHandler.getCurrentImageFile());
        });
      } catch (e) {
        debugPrint('페이지 로드 중 오류: $e');
            if (mounted) {
              setState(() {
            _state.setLoading(false);
          });
        }
      }
      
      // 백그라운드 처리 상태 확인
      await _checkBackgroundProcessing(note.id!);
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
  
  // 현재 페이지 텍스트 처리
  Future<void> _processCurrentPageText() async {
    final currentPage = _pageManager.currentPage;
    if (currentPage == null) return;
    
    if (!mounted) return;

    setState(() {
      _state.setProcessingText(true);
    });

    try {
      debugPrint('페이지 텍스트 처리 시작: ${currentPage.id}');
      
      // 이미지 로드가 필요한 경우 로드
      if (currentPage.imageUrl != null && currentPage.imageUrl!.isNotEmpty) {
        await _imageHandler.loadPageImage(currentPage);
      }
      
      // 텍스트 처리
      final processedText = await _textProcessor.processPageText(
        page: currentPage,
        imageFile: _imageHandler.getCurrentImageFile(),
      );
      
      if (!mounted) return;
      
      if (processedText != null && currentPage.id != null) {
        try {
        // 기본 표시 설정 지정
        final updatedProcessedText = processedText.copyWith(
          showFullText: false, // 기본값: 세그먼트 모드
            showPinyin: true, // 병음 표시는 기본적으로 활성화
          showTranslation: true, // 번역은 항상 표시
        );
        
          // 업데이트된 텍스트 캐싱
          _textProcessor.setProcessedText(currentPage.id!, updatedProcessedText);
        
          debugPrint('텍스트 처리 완료: ${currentPage.id}');
          
          // 페이지가 처음 방문된 것으로 표시
          _state.markPageVisited(_pageManager.currentPageIndex);
          
        } catch (e) {
          debugPrint('페이지 텍스트 처리 중 오류 발생: ProcessedText 객체 변환 실패: $e');
          // 캐시 삭제 및 다시 로드 시도
          _textProcessor.removeProcessedText(currentPage.id!);
        }
      }
    } catch (e) {
      debugPrint('페이지 텍스트 처리 중 오류 발생: $e');
    } finally {
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

  // 페이지 변경 처리
  void _changePage(int index) {
    // 범위 검사
    if (index < 0 || index >= _pageManager.pages.length) {
        return;
      }
    
    // 페이지 매니저를 통한 페이지 변경
    _pageManager.changePage(index);
    
    // PageController 애니메이션
    if (index != _pageManager.currentPageIndex) {
      try {
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } catch (e) {
        // 페이지 애니메이션 오류는 무시
      }
    }
    
    // 이전에 방문한 페이지가 아닌 경우에만 방문 기록 추가
    if (!_state.isPageVisited(index)) {
      _state.markPageVisited(index);
    }
    
    // 페이지 텍스트 처리
    _processCurrentPageText();
    
    setState(() {});
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
          _contentManager.toggleFullTextMode(_useSegmentMode);
        });
      },
      isFullTextMode: !_useSegmentMode,
      pageContentService: PageContentService(),
      textReaderService: TextReaderService(),
      showPinyin: true,
      showTranslation: true,
      onTogglePinyin: () {
        // 병음 토글은 PageContentWidget에서 처리
      },
      onToggleTranslation: () {
        // 번역 토글은 PageContentWidget에서 처리
      },
      onTtsPlay: () {
        // TTS 재생은 PageContentWidget에서 처리
      },
      isProcessing: _state.isProcessingText,
    );
  }
  
  // 메인 UI 구성
  Widget _buildBody() {
    final currentPage = _pageManager.currentPage;
    final isFirstPageProcessing = currentPage == null || 
                                  currentPage.originalText == '___PROCESSING___' || 
                                  ((currentPage.originalText.isEmpty || currentPage.originalText == 'processing') && 
                                   !_state.isPageVisited(_pageManager.currentPageIndex));

    // 초기 로딩 또는 첫 페이지 처리 중일 때 로딩 UI 표시 (조건 통합)
    if (_state.isLoading || _state.note == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 피카북 캐릭터 이미지
            Image.asset(
              'assets/images/pikabook_bird.png',
              width: 40,
              height: 40,
            ),
            const SizedBox(height: 16), // 이미지와 인디케이터 사이 간격
            
            // 메시지 없이 로딩 아이콘만 표시
            const DotLoadingIndicator(),
            
            const SizedBox(height: 16),
            
            // Figma 디자인의 텍스트와 동일하게 수정
            Text(
              '스마트 노트를 만들고 있어요.',
              style: TypographyTokens.subtitle2.copyWith(
                fontWeight: FontWeight.w700,
                color: ColorTokens.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '글자 인식과 번역을 하고 있어요.\n잠시만 기다려 주세요!',
              style: TypographyTokens.body1.copyWith(
                color: ColorTokens.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            // 새로고침 버튼 표시 (선택적)
            if (!_state.isLoading)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: TextButton(
                  onPressed: () => _forceRefreshPage(),
                  child: Text('새로고침', style: TypographyTokens.button),
                ),
              ),
          ],
        ),
      );
    }
    
    // 텍스트 처리 중인 경우 (별도 로딩 표시)
    if (_state.isProcessingText) {
      return Center(
        child: DotLoadingIndicator(message: '텍스트 처리 중이에요!'),
      );
    }
    
    // 페이지가 있는 경우, PageView로 페이지 표시
    return PageView.builder(
      itemCount: _pageManager.pages.length,
      controller: _pageController,
      onPageChanged: (index) {
        if (!_state.isPageVisited(index)) {
          _state.markPageVisited(index);
        }
        _changePage(index);
      },
      itemBuilder: (context, index) {
        final page = _pageManager.getPageAtIndex(index);
        final imageFile = _pageManager.getImageFileForPage(page);
        
        // 공통 이미지 썸네일 컨테이너 사용
        Widget imageThumbnail = _buildImageThumbnailContainer(page, imageFile);
        
        if (index == _pageManager.currentPageIndex) {
          // 현재 페이지: 이미지 + 텍스트 콘텐츠
          return Column(
            children: [
              imageThumbnail, // 공통 썸네일 위젯
              
              // 텍스트 콘텐츠 (스크롤 가능)
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: PageContentWidget(
                    key: ValueKey('page_${page?.id}_${_useSegmentMode}'),
                    page: page!,
                    imageFile: imageFile,
                    flashCards: _state.note?.flashCards,
                    useSegmentMode: _useSegmentMode,
                    isLoadingImage: false,
                    noteId: widget.noteId,
                    onCreateFlashCard: (front, back, {pinyin}) async {
                      await _createFlashCard(front, back, pinyin: pinyin);
                    },
                    onDeleteSegment: _handleDeleteSegment,
                  ),
                ),
              ),
            ],
          );
        } else {
          // 다른 페이지는 단순히 이미지만 표시
          return Container(
            color: Colors.white,
            child: imageThumbnail,
          );
        }
      },
    );
  }
  
  // 이미지 컨테이너 구성
  Widget _buildImageContainer() {
    final currentPage = _pageManager.currentPage;
    final currentImageFile = _pageManager.currentImageFile;
    
    // 이미지가 없는 경우 컨테이너 자체를 표시하지 않음
    if (currentImageFile == null && (currentPage?.imageUrl == null || currentPage!.imageUrl!.isEmpty)) {
      return SizedBox(height: 0);
    }
    
    return FirstImageContainer(
      currentPage: currentPage,
      currentImageFile: currentImageFile,
      noteTitle: _state.note?.originalText ?? '노트',
      onFullScreenTap: (imageFile) {
                              Navigator.push(
      context,
      MaterialPageRoute(
                                  builder: (context) => FullImageScreen(
                                    imageFile: imageFile,
              title: _state.note?.originalText ?? '이미지',
        ),
      ),
    );
                            },
    );
  }

  // 현재 페이지 콘텐츠 구성
  Widget _buildCurrentPageContent() {
    final currentPage = _pageManager.currentPage;
    
    // 현재 페이지가 null인 경우 로딩 표시
    if (currentPage == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const DotLoadingIndicator(),
            const SizedBox(height: 16),
            Text(
              '페이지를 준비하고 있어요...',
              style: TypographyTokens.body1Bold,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    // 처리 중인 페이지인 경우 로딩 표시
    if (currentPage.originalText == '___PROCESSING___' || 
        ((currentPage.originalText.isEmpty || currentPage.originalText == 'processing') && 
         !_state.isPageVisited(_pageManager.currentPageIndex))) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const DotLoadingIndicator(),
            const SizedBox(height: 16),
            Text(
              '페이지를 처리하고 있어요...',
              style: TypographyTokens.body1Bold,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '잠시만 기다려주세요.',
              style: TypographyTokens.body2,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    // 이전에 방문했고 텍스트가 비어있는 경우 빈 페이지 메시지
    if (currentPage.originalText.isEmpty && _state.isPageVisited(_pageManager.currentPageIndex)) {
      return Center(
        child: Text(
          '이 페이지에는 텍스트가 없습니다.',
          style: TypographyTokens.body1Bold,
          textAlign: TextAlign.center,
        ),
      );
    }
    
    // 일반적인 경우 콘텐츠 표시 - PageContentWidget을 사용하여 단어 선택 및 사전 검색, 플래시카드 기능 제공
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: PageContentWidget(
        key: ValueKey('processed_${currentPage.id}_${_useSegmentMode}'),
        page: currentPage,
        imageFile: _pageManager.getImageFileForPage(currentPage),
        flashCards: _state.note?.flashCards,
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

  // 전체텍스트/세그먼트 모드 전환
  void _toggleFullTextMode() {
    final currentPage = _pageManager.currentPage;
    if (currentPage == null || currentPage.id == null) {
      return;
    }
    
    // 캐시된 processedText 가져오기
    final processedText = _textProcessor.getProcessedText(currentPage.id!);
    if (processedText == null) {
      return;
    }
    
    // 모드 전환
        setState(() {
      final updatedText = _textProcessor.toggleDisplayMode(currentPage.id!, processedText);
      _useSegmentMode = !updatedText.showFullText;
    });
    
    // 필요한 번역 데이터 확인 및 로드
      if (mounted) {
      _textProcessor.checkAndLoadTranslationData(context, processedText, currentPage.id!).then((updatedText) {
        if (updatedText != null) {
          setState(() {
            _useSegmentMode = !updatedText.showFullText;
          });
        }
      });
    }
  }
  
  // 병음 표시 전환
  void _togglePinyin() {
    final currentPage = _pageManager.currentPage;
    if (currentPage == null || currentPage.id == null) {
        return;
      }
      
    // 캐시된 processedText 가져오기
    final processedText = _textProcessor.getProcessedText(currentPage.id!);
    if (processedText == null) {
      return;
    }
    
    // 병음 표시 전환
          setState(() {
      _textProcessor.togglePinyin(currentPage.id!, processedText);
    });
  }
  
  // 번역 표시 전환
  void _toggleTranslation() {
    final currentPage = _pageManager.currentPage;
    if (currentPage == null || currentPage.id == null) {
      return;
    }
    
    // 캐시된 processedText 가져오기
    final processedText = _textProcessor.getProcessedText(currentPage.id!);
    if (processedText == null) {
      return;
    }
    
    // 번역 표시 전환
    setState(() {
      _textProcessor.toggleTranslation(currentPage.id!, processedText);
    });
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
        onToggleFullTextMode: _toggleFullTextMode,
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
      await _noteService.toggleFavorite(_state.note!.id!, newValue);
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

  // 이미지 썸네일 컨테이너 생성
  Widget _buildImageThumbnailContainer(page_model.Page? page, File? imageFile) {
    if (page == null) {
      return Container(
        height: 200,
        color: Colors.grey[200],
        child: const Center(child: Text('이미지 없음')),
      );
    }

    return Container(
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
                onTap: () => _showFullImage(page, imageFile),
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
  
  // 전체 화면 이미지 표시
  void _showFullImage(page_model.Page page, File? imageFile) {
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

  void _initializeManagers() {
    _screenshotHelper = ScreenshotServiceHelper();
    _tooltipManager = TooltipManager();
    _optionsManager = NoteOptionsManager();
    _contentManager = NoteContentManager(
      _pageManager,
      _textProcessor,
      _imageHandler,
      _state,
    );
  }

  Future<bool> _onWillPop() async {
    try {
      // TTS 및 리소스 정리
      await _cleanupResources();
      
      // 제목 편집 중인 경우 저장
      if (_state.isEditingTitle) {
        if (_titleEditingController.text.isNotEmpty) {
          await _updateNoteTitle(_titleEditingController.text);
        }
        setState(() {
          _state.isEditingTitle = false;
        });
        return false;
      }
      
      // 동기적으로 Navigator.pop 호출
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      
      return false;
    } catch (e) {
      debugPrint('뒤로가기 처리 중 오류: $e');
      return true;
    }
  }
}