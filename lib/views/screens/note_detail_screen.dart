// lib/views/screens/note_detail_screen.dart (리팩토링된 버전)
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';

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
import '../../widgets/note_detail_bottom_bar.dart';
import '../../widgets/common/help_text_tooltip.dart';
import '../../widgets/note_segment_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/scheduler.dart';
import '../../widgets/note_action_bottom_sheet.dart';
import '../../utils/debug_utils.dart';
import '../../views/screens/flashcard_screen.dart';
import '../../views/screens/full_image_screen.dart';
import 'dart:math' as math;

/// 노트 상세 화면
/// 페이지 탐색, 노트 액션, 백그라운드 처리, 이미지 로딩 등의 기능
class NoteDetailScreen extends StatefulWidget {
  final String noteId;
  final bool isProcessingBackground;
  final int totalImageCount;
  
  // 라우트 이름 상수 추가
  static const String routeName = '/note_detail';

  const NoteDetailScreen({
    Key? key,
    required this.noteId,
    this.isProcessingBackground = false,
    this.totalImageCount = 1,
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

  @override
  void initState() {
    super.initState();
    
    // 옵저버 등록
    WidgetsBinding.instance.addObserver(this);
    
    // 상태 초기화
    _state = NoteDetailState();
    _state.setLoading(true);
    _state.expectedTotalPages = widget.totalImageCount;
    _state.setBackgroundProcessingFlag(widget.isProcessingBackground);
    
    // 매니저 및 핸들러 초기화
    _pageManager = NoteDetailPageManager(noteId: widget.noteId);
    _imageHandler = NoteDetailImageHandler();
    _textProcessor = NoteDetailTextProcessor();
    
    // 컨트롤러 초기화
    _pageController = PageController();
    
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
    await _screenshotService.initialize(() {
      if (mounted) {
        _showScreenshotWarning();
      }
    });
    
    await _screenshotService.startDetection();
  }

  // 스크린샷 경고 메시지 표시
  void _showScreenshotWarning() {
    if (_isShowingScreenshotWarning) return;
    
    setState(() {
      _isShowingScreenshotWarning = true;
    });
    
    ScaffoldMessenger.of(context).clearSnackBars();
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
  
  // TTS 재생
  void _onTtsPlay() {
    if (_pageManager.currentPage == null) return;
    
    // 현재 페이지의 원본 텍스트 재생
    final originalText = _pageManager.currentPage!.originalText;
    if (originalText.isNotEmpty && originalText != '___PROCESSING___') {
      _ttsService.speak(originalText);
    }
  }
  
  // 플래시카드 화면으로 이동
  Future<void> _navigateToFlashcards() async {
    if (_state.note == null || _state.note?.id == null) return;

    try {
      // 플래시카드 화면으로 이동
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FlashCardScreen(
            noteId: _state.note!.id!,
        ),
      ),
    );

      // 결과 처리
      if (result != null && mounted && _state.note != null) {
        if (result is Map) {
          final flashcardCount = result['flashcardCount'] as int? ?? 0;
          final success = result['success'] as bool? ?? false;
          final noteId = result['noteId'] as String?;
          
          if (success && noteId == _state.note!.id) {
            // 노트 객체 업데이트
            final updatedNote = _state.note!.copyWith(flashcardCount: flashcardCount);
            
            // Firebase에 업데이트 반영
            await FirebaseFirestore.instance
                .collection('notes')
                .doc(_state.note!.id)
                .update({'flashcardCount': flashcardCount});
                
            // 캐시 관련 초기화 작업
            if (_pageManager.currentPage?.id != null) {
              _textProcessor.removeProcessedText(_pageManager.currentPage!.id!);
            }
            
            // 노트 서비스에 캐시 업데이트
            _noteService.cacheNotes([updatedNote]);
            
            // 노트를 다시 로드하여 최신 데이터 가져오기
            await _loadNote();
            
            // 현재 페이지의 플래시카드 단어 목록을 새로 로드
            if (_pageManager.currentPageIndex >= 0 && _pageManager.currentPageIndex < _pageManager.pages.length) {
              // 플래시카드 목록 새로 로드
              final flashcards = await _flashCardService.getFlashCardsForNote(_state.note!.id!);
              
              // 노트 객체 업데이트
        setState(() {
                _state.updateNote(_state.note!.copyWith(flashCards: flashcards));
              });
              
              // 현재 페이지 텍스트 다시 처리
              await _processCurrentPageText();
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
          onMorePressed: _showMoreOptions,
          onFlashcardTap: _navigateToFlashcards,
          onBackPressed: () async {
            await _onWillPop();
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
          _buildTooltip(),
      ],
    );
  }
  
  // 하단 바 구성
  Widget _buildBottomBar() {
    final currentPageIndex = _pageManager.currentPageIndex;
    final totalPages = _state.note?.imageCount != null && _state.note!.imageCount! > 0
        ? _state.note!.imageCount!
        : (_state.expectedTotalPages > 0 
            ? math.max(_pageManager.pages.length, _state.expectedTotalPages)
            : _pageManager.pages.length);
    
    return NoteDetailBottomBar(
      currentPage: _pageManager.currentPage,
      currentPageIndex: currentPageIndex,
      totalPages: totalPages,
      onPageChanged: _changePage,
      onToggleFullTextMode: _toggleFullTextMode,
      isFullTextMode: !_useSegmentMode,
      pageContentService: PageContentService(),
      textReaderService: _textReaderService,
      showPinyin: true,
      showTranslation: true,
      isProcessing: _state.isProcessingText,
      onTogglePinyin: _togglePinyin,
      onToggleTranslation: _toggleTranslation,
      onTtsPlay: _onTtsPlay,
    );
  }
  
  // 메인 UI 구성
  Widget _buildBody() {
    // 로딩 중인 경우
    if (_state.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const DotLoadingIndicator(
              dotColor: ColorTokens.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '노트를 불러오고 있어요...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
          ],
      ),
    );
  }
  
    // 오류가 있는 경우
    if (_state.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              _state.error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('돌아가기'),
            ),
          ],
        ),
      );
    }
    
    // 노트가 없거나 페이지가 없는 경우
    if (_state.note == null || _pageManager.pages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const DotLoadingIndicator(
              dotColor: ColorTokens.primary,
            ),
            const SizedBox(height: 16),
            Text(
              '페이지를 준비하고 있어요...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    // 페이지 뷰 구성
    return PageView.builder(
        itemCount: _pageManager.pages.length,
          controller: _pageController,
        onPageChanged: (index) {
            // 이전에 방문하지 않은 페이지라면 방문 기록에 추가
        _state.markPageVisited(index);
            
        // 페이지 변경 처리
          _changePage(index);
        },
        itemBuilder: (context, index) {
          if (index == _pageManager.currentPageIndex) {
          return _buildCurrentPageView();
        } else {
          return _buildOtherPageView(index);
        }
      },
    );
  }
  
  // 현재 페이지 뷰
  Widget _buildCurrentPageView() {
            return Column(
              children: [
        // 이미지 컨테이너
        _buildImageContainer(),
                
        // 페이지 내용
                Expanded(
                  child: Container(
            color: Colors.white,
                    child: _buildCurrentPageContent(),
                  ),
                ),
              ],
            );
  }
  
  // 다른 페이지 뷰 (미리보기)
  Widget _buildOtherPageView(int index) {
            final page = _pageManager.getPageAtIndex(index);
            final imageFile = _pageManager.getImageFileForPage(page);
            
            return Column(
              children: [
        // 미리보기 이미지
                if (imageFile != null || page?.imageUrl != null)
                  Container(
                    margin: EdgeInsets.only(top: 16, left: 16, right: 16),
            height: 200,
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
        
        // 미리보기 내용
        Expanded(
          child: Center(
            child: Text('페이지 ${index + 1} 로딩 중...'),
          ),
        ),
      ],
    );
  }
  
  // 툴팁 구성
  Widget _buildTooltip() {
    return Positioned(
      bottom: 80,
      left: 16,
      right: 16,
      child: Material(
        elevation: 0,
        color: Colors.transparent,
        child: HelpTextTooltip(
          key: const Key('note_detail_tooltip'),
          text: _state.tooltipStep == 1 
            ? "첫 노트가 만들어졌어요!" 
            : _state.tooltipStep == 2
              ? "다음 페이지로 이동은 스와이프나 화살표로!"
              : "불필요한 텍스트는 지워요.",
          description: _state.tooltipStep == 1
            ? "모르는 단어는 선택하여 사전 검색 하거나, 플래시카드를 만들어 복습해 볼수 있어요."
            : _state.tooltipStep == 2
              ? "노트의 빈 공간을 왼쪽으로 슬라이드하거나, 바텀 바의 화살표를 눌러 다음 장으로 넘어갈 수 있어요."
              : "잘못 인식된 문장은 왼쪽으로 슬라이드해 삭제할수 있어요.",
          showTooltip: _state.showTooltip,
          onDismiss: _handleTooltipDismiss,
          backgroundColor: ColorTokens.primaryverylight,
          borderColor: ColorTokens.primary,
          textColor: ColorTokens.textPrimary,
          tooltipPadding: const EdgeInsets.all(16),
          tooltipWidth: MediaQuery.of(context).size.width - 32,
          spacing: 8.0,
          style: HelpTextTooltipStyle.primary,
          image: Image.asset(
            _state.tooltipStep == 1 
              ? 'assets/images/note_help_1.png'
              : _state.tooltipStep == 2
                ? 'assets/images/note_help_2.png'
                : 'assets/images/note_help_3.png',
            width: double.infinity,
            fit: BoxFit.contain,
          ),
          currentStep: _state.tooltipStep,
          totalSteps: _state.totalTooltipSteps,
          onNextStep: () {
            setState(() {
              _state.setTooltipStep(_state.tooltipStep + 1);
            });
          },
          onPrevStep: () {
            setState(() {
              _state.setTooltipStep(_state.tooltipStep - 1);
            });
          },
        ),
      ),
    );
  }
  
  // 툴팁 닫기 처리
  void _handleTooltipDismiss() {
    setState(() {
      _state.showTooltip = false;
      _state.setTooltipStep(1);
    });
    
    // 툴팁 표시 상태 저장
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('note_detail_tooltip_shown', true);
    });
  }
  
  // 뒤로가기 처리
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

  // 현재 페이지 내용 구성
  Widget _buildCurrentPageContent() {
    final currentPage = _pageManager.currentPage;
    final currentImageFile = _pageManager.currentImageFile;
    
    // 페이지가 없는 경우
    if (currentPage == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const DotLoadingIndicator(),
            const SizedBox(height: 16),
            Text(
              '페이지를 준비하고 있어요...',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
      );
    }
    
    // 처리 중인 경우
    if (currentPage.originalText == '___PROCESSING___') {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const DotLoadingIndicator(),
            const SizedBox(height: 16),
            Text(
              '텍스트 처리 중이에요!',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
                  ),
                ),
              ],
        ),
      );
    }
    
    // 페이지가 준비 중인 경우
    if ((currentPage.originalText.isEmpty || currentPage.originalText == 'processing') 
        && !_state.isPageVisited(_pageManager.currentPageIndex)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
            children: [
            const DotLoadingIndicator(),
            const SizedBox(height: 16),
            Text(
              '페이지 준비 중...\n이미지 인식 및 번역을 진행하고 있습니다.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    // 텍스트 처리 중인 경우
    if (_state.isProcessingText) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
            const DotLoadingIndicator(),
            const SizedBox(height: 16),
            Text(
              '텍스트 처리 중이에요!',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
              ),
            ),
                          ],
                        ),
                      );
                    }
    
    // 현재 페이지의 처리된 텍스트 가져오기
    final processedText = currentPage.id != null
        ? _textProcessor.getProcessedText(currentPage.id!)
        : null;
    
    // CurrentPageContent 위젯 사용
    return CurrentPageContent(
      currentPage: currentPage,
      currentImageFile: currentImageFile,
      flashCards: _state.note?.flashCards,
      useSegmentMode: _useSegmentMode,
      noteId: widget.noteId,
      onCreateFlashCard: _createFlashCard,
      onDeleteSegment: _handleDeleteSegment,
      isProcessingText: _state.isProcessingText,
      wasVisitedBefore: _state.isPageVisited(_pageManager.currentPageIndex),
      processedText: processedText,
      isLoading: _state.isLoading,
      isProcessing: currentPage.originalText == 'processing',
      currentIndex: _pageManager.currentPageIndex,
      onToggleDisplayMode: _toggleFullTextMode,
      onTogglePinyin: _togglePinyin,
      onToggleTranslation: _toggleTranslation,
      onAddFlashcard: () {
        // 플래시카드 추가 구현
      },
      onDelete: () {
        // 페이지 삭제 구현
      },
      onReadText: _onTtsPlay,
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
}