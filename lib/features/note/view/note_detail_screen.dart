import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../../../core/models/note.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../core/models/flash_card.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/widgets/dot_loading_indicator.dart';
import '../view_model/note_detail_viewmodel.dart';
import '../../flashcard/flashcard_view_model.dart';
import 'note_page_widget.dart';
import '../../../core/widgets/pika_app_bar.dart';
import '../../flashcard/flashcard_screen.dart';
import 'note_detail_bottom_bar.dart';
import '../../../core/services/tts/tts_service.dart';
import '../../../core/services/tts/tts_playback_service.dart';
import '../../../core/services/media/image_service.dart';
import '../../../core/utils/note_tutorial.dart';
import '../../../core/theme/tokens/ui_tokens.dart';
import '../../flashcard/flashcard_service.dart';

/// MVVM 패턴을 적용한 노트 상세 화면
class NoteDetailScreenMVVM extends StatefulWidget {
  final String noteId;
  final Note? initialNote;

  const NoteDetailScreenMVVM({
    Key? key,
    required this.noteId,
    this.initialNote,
  }) : super(key: key);

  // 라우트 생성 메서드
  static Route<dynamic> route({
    required Note note, 
    bool isProcessingBackground = false,
    int totalImageCount = 0,
  }) {
    if (kDebugMode) {
      print("🚀 Navigating to NoteDetailScreenMVVM for note: ${note.id}, totalImages: $totalImageCount");
    }
    return MaterialPageRoute(
      settings: const RouteSettings(name: '/note_detail'),
      builder: (context) => ChangeNotifierProvider(
        create: (context) => NoteDetailViewModel(
          noteId: note.id!,
          initialNote: note,
          totalImageCount: totalImageCount,
        ),
        child: NoteDetailScreenMVVM(
          noteId: note.id!,
          initialNote: note,
        ),
      ),
    );
  }
  
  @override
  State<NoteDetailScreenMVVM> createState() => _NoteDetailScreenMVVMState();
}

class _NoteDetailScreenMVVMState extends State<NoteDetailScreenMVVM> {
  late FlashCardService _flashCardService;
  late TTSService _ttsService;
  List<FlashCard> _flashcards = [];
  bool _isPageCallbackSet = false; // 페이지 콜백 설정 여부 플래그

  // Service 인스턴스들 - ImageService 제거
  
  @override
  void initState() {
    super.initState();
    
    // 초기화
    _initializeServices();
    
    // 화면 렌더링 완료 후 튜토리얼 체크
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 노트 개수를 먼저 업데이트한 후 튜토리얼 체크
      if (kDebugMode) {
        if (kDebugMode) print('노트 상세 화면: 노트 개수 업데이트 후 튜토리얼 체크');
      }
      
      // 노트 개수 즉시 업데이트 (노트 상세 화면에 들어왔으므로 최소 1개)
      await NoteTutorial.updateNoteCount(1);
      
      // 잠시 딜레이를 주어 SharedPreferences에 반영될 시간 부여
      await Future.delayed(const Duration(milliseconds: 100));
      
      // 튜토리얼 표시 확인
      NoteTutorial.checkAndShowTutorial(context);
      
      // 페이지 처리 상태 표시 콜백 설정
      final viewModel = Provider.of<NoteDetailViewModel>(context, listen: false);
      viewModel.setPageProcessedCallback(_showPageProcessedMessage);
      
      // 플래시카드 로드
      await _loadFlashcards();
    });
  }
  
  /// 서비스 초기화
  Future<void> _initializeServices() async {
    try {
      // 서비스 인스턴스 생성
      _flashCardService = FlashCardService();
      _ttsService = TTSService();
      
      // TTS 서비스 초기화
      await _ttsService.init();
    } catch (e) {
      if (kDebugMode) {
        print('서비스 초기화 실패: $e');
      }
    }
  }
  
  /// 플래시카드 로드
  Future<void> _loadFlashcards() async {
    try {
      final cards = await _flashCardService.getFlashCardsForNote(widget.noteId);
      setState(() {
        _flashcards = cards;
      });
    } catch (e) {
      if (kDebugMode) {
        print('플래시카드 로드 실패: $e');
      }
    }
  }
  
  // 페이지 처리 완료 시 스낵바로 알림
  void _showPageProcessedMessage(int pageIndex) {
    if (!mounted) return;
    
    final viewModel = Provider.of<NoteDetailViewModel>(context, listen: false);
    final pageNumber = pageIndex + 1;
    final totalPages = viewModel.pages?.length ?? 0;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$pageNumber/$totalPages 페이지 처리가 완료되었습니다.'),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: '확인',
          onPressed: () {
            // 현재 다른 페이지를 보고 있는 경우, 처리 완료된 페이지로 이동
            if (viewModel.currentPageIndex != pageIndex) {
              viewModel.pageController.animateToPage(
                pageIndex,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ViewModel에 접근
    final viewModel = Provider.of<NoteDetailViewModel>(context);
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(context, viewModel),
      body: _buildBody(context, viewModel),
      bottomNavigationBar: _buildBottomBar(context, viewModel),
    );
  }
  
  // 앱바 구성
  PreferredSizeWidget _buildAppBar(BuildContext context, NoteDetailViewModel viewModel) {
    final currentPageNum = viewModel.currentPageIndex + 1;
    final totalPages = viewModel.pages?.length ?? 0;
    
    return PikaAppBar.noteDetail(
      title: viewModel.note?.title ?? '노트 로딩 중...',
      currentPage: currentPageNum,
      totalPages: totalPages,
      flashcardCount: viewModel.flashcardCount,
      onMorePressed: () => _showMoreOptions(context, viewModel),
      onFlashcardTap: () => _navigateToFlashcards(context, viewModel),
      onBackPressed: () => Navigator.of(context).pop({'needsRefresh': false}),
      backgroundColor: UITokens.screenBackground, 
      noteId: viewModel.noteId,
    );
  }
  
  // 바디 구성
  Widget _buildBody(BuildContext context, NoteDetailViewModel viewModel) {
    if (viewModel.isLoading) {
      return const Center(child: DotLoadingIndicator(message: '페이지 로딩 중...'));
    }

    if (viewModel.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            '오류 발생: ${viewModel.error}',
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (viewModel.pages == null || viewModel.pages!.isEmpty) {
      return Center(
        child: Text(
          '표시할 페이지가 없습니다.',
          style: TypographyTokens.body1,
        ),
      );
    }

    // 페이지 뷰 구성 - PageController 연결
    return SafeArea(
      child: Container(
        color: Colors.white,
        padding: EdgeInsets.zero,
        child: PageView.builder(
          controller: viewModel.pageController, // 뷰모델의 컨트롤러 사용
          itemCount: viewModel.pages!.length,
          onPageChanged: viewModel.onPageChanged,
          itemBuilder: (context, index) {
            final page = viewModel.pages![index];
            
            // 페이지 콘텐츠 위젯 반환 (NotePageWidget에서 자체적으로 처리 상태 관리)
            return _buildPageContent(context, viewModel, page);
          },
        ),
      ),
    );
  }
  
  // 페이지 콘텐츠 위젯
  Widget _buildPageContent(BuildContext context, NoteDetailViewModel viewModel, page_model.Page page) {
    return RepaintBoundary(
      child: NotePageWidget(
        key: ValueKey('page_content_${page.id}'),
        page: page,
        imageFile: null, // PageImageWidget이 직접 이미지를 처리하도록 null 전달
        noteId: viewModel.noteId,
        // 콜백 함수들만 전달
        onCreateFlashCard: (front, back, {pinyin}) => 
            _handleCreateFlashCard(context, viewModel, front, back, pinyin: pinyin),
        flashCards: _flashcards,
        onPlayTts: (text, {segmentIndex}) => _handlePlayTts(text, segmentIndex: segmentIndex),
      ),
    );
  }
  
  // TTS 재생 처리
  Future<void> _handlePlayTts(String text, {int? segmentIndex}) async {
    try {
      await _ttsService.speak(text);
    } catch (e) {
      if (kDebugMode) {
        print('TTS 재생 실패: $e');
      }
    }
  }
  
  // 더보기 옵션 표시
  void _showMoreOptions(BuildContext context, NoteDetailViewModel viewModel) {
    final note = viewModel.note;
    if (note == null) return;
    
    // 노트 옵션 매니저를 통해 옵션 표시
    viewModel.noteOptionsManager.showMoreOptions(
      context, 
      note,
      onTitleEditing: () {
        // 노트 제목 업데이트 후 새로고침
        viewModel.loadNote();
      },
      onNoteDeleted: () {
        // 노트 삭제 후 이전 화면으로 이동 (새로고침 필요)
        Navigator.of(context).pop({'needsRefresh': true});
      }
    );
  }
  
  // 플래시카드 생성 처리
  void _handleCreateFlashCard(
    BuildContext context, 
    NoteDetailViewModel viewModel,
    String front, 
    String back, 
    {String? pinyin}
  ) async {
    try {
      // 직접 FlashCardService 사용하여 플래시카드 생성
      final newFlashCard = await _flashCardService.createFlashCard(
        front: front,
        back: back,
        noteId: viewModel.noteId,
        pinyin: pinyin,
      );
      
      // 성공 메시지 표시
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('플래시카드가 추가되었습니다')),
        );
        
        // 플래시카드 목록 업데이트
        setState(() {
          _flashcards.add(newFlashCard);
        });
        
        if (kDebugMode) {
          print("✅ 새 플래시카드 추가 완료: ${newFlashCard.front}");
          print("✅ 현재 플래시카드 목록 크기: ${_flashcards.length}개");
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("❌ 플래시카드 생성 중 오류: $e");
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('플래시카드 추가 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }
  
  // 플래시카드 화면으로 이동
  void _navigateToFlashcards(BuildContext context, NoteDetailViewModel viewModel) async {
    // 플래시카드 화면으로 이동하여 결과 받아오기
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FlashCardScreen(
          noteId: viewModel.noteId,
        ),
      ),
    );
    
    // 플래시카드 화면에서 돌아왔을 때 결과 처리
    if (result != null && result is Map<String, dynamic>) {
      // 플래시카드 목록이 있으면 화면 갱신하여 하이라이트 효과 적용
      if (result.containsKey('flashcards') && result['flashcards'] is List) {
        List<dynamic> cards = result['flashcards'] as List<dynamic>;
        List<FlashCard> flashcards = cards.map((card) {
          if (card is FlashCard) {
            return card;
          } else if (card is Map<String, dynamic>) {
            return FlashCard.fromJson(card);
          }
          // 타입이 잘못된 경우 빈 카드 반환
          return FlashCard(
            id: '',
            front: '',
            back: '',
            pinyin: '',
            createdAt: DateTime.now(),
          );
        }).toList();
        
        // 비어있지 않은 플래시카드만 필터링
        flashcards = flashcards.where((card) => card.front.isNotEmpty).toList();
        
        if (kDebugMode) {
          print('플래시카드 목록 업데이트: ${flashcards.length}개');
        }
        
        // 플래시카드 목록 업데이트
        setState(() {
          _flashcards = flashcards;
        });
      }
    }
  }

  // 바텀 네비게이션 바 구성 (다중 선택 모드)
  Widget _buildBottomBar(BuildContext context, NoteDetailViewModel viewModel) {
    if (viewModel.pages == null || viewModel.pages!.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // 페이지 처리 완료 콜백 설정 (한 번만 설정)
    _setupPageProcessedCallback(context, viewModel);
    
    // 페이지 처리 상태 가져오기
    final processedPages = viewModel.getProcessedPagesStatus();
    
    // 현재 페이지의 TTS 텍스트 가져오기
    final currentProcessedText = viewModel.currentProcessedText;
    final ttsText = currentProcessedText?.fullOriginalText ?? '';
    
    return NoteDetailBottomBar(
      currentPage: viewModel.currentPage,
      currentPageIndex: viewModel.currentPageIndex,
      totalPages: viewModel.pages?.length ?? 0,
      onPageChanged: (index) {
        // 네비게이션 버튼 클릭 시 PageController를 사용하여 페이지 이동
        viewModel.navigateToPage(index);
      },
      // TTS 관련 데이터만 전달
      ttsText: ttsText,
      isProcessing: false,
      progressValue: (viewModel.currentPageIndex + 1) / (viewModel.pages?.length ?? 1),
      onTtsPlay: () {
        // TTS 재생/정지 토글 (Service 직접 사용)
        if (_ttsService.state == TtsState.playing) {
          _ttsService.stop();
        } else {
          // 현재 페이지 텍스트 읽기
          if (ttsText.isNotEmpty) {
            _ttsService.speak(ttsText);
          }
        }
      },
      processedPages: processedPages,
    );
  }
  
  // 페이지 처리 완료 콜백 설정 (스낵바 표시)
  void _setupPageProcessedCallback(BuildContext context, NoteDetailViewModel viewModel) {
    // 이미 콜백이 설정되어 있는지 검사하는 로직이 필요할 수 있음
    // 일단 매번 새로 설정하도록 구현
    
    if (_isPageCallbackSet) return;
    
    _isPageCallbackSet = true;
    
    viewModel.setPageProcessedCallback((pageIndex) {
      // 현재 화면이 살아있는지 확인
      if (context.mounted) {
        // 페이지 번호는 1부터 시작하도록 표시
        final pageNum = pageIndex + 1;
        
        // 스낵바로 페이지 처리 완료 메시지 표시
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$pageNum번째 페이지가 처리 완료되었습니다.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }
} 