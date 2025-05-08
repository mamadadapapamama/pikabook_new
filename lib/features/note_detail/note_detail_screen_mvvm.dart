import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../core/models/note.dart';
import '../../core/models/page.dart' as pika_page;
import 'note_detail_viewmodel.dart';
import '../../core/widgets/dot_loading_indicator.dart';
import 'page_content_widget.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import '../../core/widgets/pika_app_bar.dart';
import '../flashcard/flashcard_screen.dart';
import 'note_detail_bottom_bar.dart';
import '../../core/services/text_processing/text_reader_service.dart';
import '../../core/utils/note_tutorial.dart';
import 'package:provider/provider.dart';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/theme/tokens/ui_tokens.dart';
import '../../core/services/media/tts_service.dart';

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
      print("🚀 Navigating to NoteDetailScreenMVVM for note: ${note.id}, processing: $isProcessingBackground, totalImages: $totalImageCount");
    }
    return MaterialPageRoute(
      settings: const RouteSettings(name: '/note_detail'),
      builder: (context) => ChangeNotifierProvider(
        create: (context) => NoteDetailViewModel(
          noteId: note.id!,
          initialNote: note,
          isProcessingBackground: isProcessingBackground,
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
  @override
  void initState() {
    super.initState();
    
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
    });
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
      title: viewModel.note?.originalText ?? '노트 로딩 중...',
      currentPage: currentPageNum,
      totalPages: totalPages,
      flashcardCount: viewModel.flashCards.length,
      onMorePressed: () => _showMoreOptions(context, viewModel),
      onFlashcardTap: () => _navigateToFlashcards(context, viewModel),
      onBackPressed: () => Navigator.of(context).pop(),
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
    return Stack(
      children: [
        SafeArea(
          child: Container(
            color: Colors.white,
            padding: EdgeInsets.zero,
            child: PageView.builder(
              controller: viewModel.pageController, // 뷰모델의 컨트롤러 사용
              itemCount: viewModel.pages!.length,
              onPageChanged: viewModel.onPageChanged,
              itemBuilder: (context, index) {
                final page = viewModel.pages![index];
                
                // 특수 처리 마커가 있는지 확인
                if (page.originalText == "___PROCESSING___") {
                  return _buildProcessingPage();
                }
                
                // 페이지 콘텐츠 위젯 반환
                return _buildPageContent(context, viewModel, page);
              },
            ),
          ),
        ),
        
        // 백그라운드 처리 상태 표시기
        if (viewModel.isProcessingBackground)
          _buildProcessingStatusIndicator(context, viewModel),
      ],
    );
  }
  
  // 처리 중인 페이지 UI
  Widget _buildProcessingPage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const DotLoadingIndicator(message: '텍스트 처리를 기다리는 중...'),
          const SizedBox(height: 16),
          Text(
            '이 페이지는 아직 처리 중입니다.\n잠시 후 자동으로 업데이트됩니다.',
            textAlign: TextAlign.center,
            style: TypographyTokens.body2,
          ),
          const SizedBox(height: 24),
          // 진행 상태 표시기 추가
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 240,
              height: 8,
              child: LinearProgressIndicator(
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(ColorTokens.primary),
                // 무한 로딩 인디케이터
                value: null,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '페이지가 처리되면 바로 확인하실 수 있습니다',
            style: TypographyTokens.caption.copyWith(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  // 페이지 콘텐츠 위젯
  Widget _buildPageContent(BuildContext context, NoteDetailViewModel viewModel, pika_page.Page page) {
    return RepaintBoundary(
      child: PageContentWidget(
        key: ValueKey('page_content_${page.id}'),
        page: page,
        imageFile: viewModel.getImageFileForPage(page),
        isLoadingImage: false,
        noteId: viewModel.noteId,
        onCreateFlashCard: (front, back, {pinyin}) => 
            _handleCreateFlashCard(context, viewModel, front, back, pinyin: pinyin),
        flashCards: viewModel.flashCards,
        useSegmentMode: !viewModel.isFullTextMode,
        onDeleteSegment: (segmentIndex) => _handleDeleteSegment(context, viewModel, segmentIndex),
      ),
    );
  }
  
  // 세그먼트 삭제 처리
  void _handleDeleteSegment(BuildContext context, NoteDetailViewModel viewModel, int segmentIndex) async {
    final success = await viewModel.deleteSegment(segmentIndex);
    
    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('문장이 삭제되었습니다')),
      );
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('문장 삭제 중 오류가 발생했습니다')),
      );
    }
  }
  
  // 더보기 옵션 표시
  void _showMoreOptions(BuildContext context, NoteDetailViewModel viewModel) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildBottomSheet(context, viewModel),
    );
  }
  
  // 바텀 시트 구성
  Widget _buildBottomSheet(BuildContext context, NoteDetailViewModel viewModel) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16.0),
          topRight: Radius.circular(16.0),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: Icon(
              viewModel.note?.isFavorite == true ? Icons.star : Icons.star_border,
            ),
            title: Text(viewModel.note?.isFavorite == true ? '즐겨찾기 해제' : '즐겨찾기 추가'),
            onTap: () {
              viewModel.toggleFavorite();
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('제목 수정'),
            onTap: () {
              Navigator.pop(context);
              _showEditTitleDialog(context, viewModel);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('노트 삭제', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _confirmDeleteNote(context, viewModel);
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
  
  // 제목 수정 다이얼로그
  void _showEditTitleDialog(BuildContext context, NoteDetailViewModel viewModel) {
    final TextEditingController controller = TextEditingController(
      text: viewModel.note?.originalText,
    );
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ColorTokens.surface,
        title: const Text('제목 수정'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '새 제목을 입력하세요',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                viewModel.updateNoteTitle(newTitle);
              }
              Navigator.pop(context);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }
  
  // 노트 삭제 확인
  void _confirmDeleteNote(BuildContext context, NoteDetailViewModel viewModel) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: ColorTokens.surface,
        title: const Text('노트 삭제'),
        content: const Text('이 노트를 정말 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context); // 다이얼로그 닫기
              final success = await viewModel.deleteNote();
              if (success && context.mounted) {
                // 홈 화면으로 바로 돌아가기 (첫 번째 화면까지 모든 화면 팝)
                Navigator.of(context).popUntil((route) => route.isFirst);
                
                // 삭제 완료 메시지 표시
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('노트가 삭제되었습니다')),
                );
              } else if (context.mounted) {
                // 삭제 실패 메시지 표시
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('노트 삭제 중 오류가 발생했습니다')),
                );
              }
            },
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
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
    final success = await viewModel.createFlashCard(front, back, pinyin: pinyin);
    
    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('플래시카드가 추가되었습니다')),
      );
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('플래시카드 추가 중 오류가 발생했습니다')),
      );
    }
  }
  
  // 플래시카드 화면으로 이동
  void _navigateToFlashcards(BuildContext context, NoteDetailViewModel viewModel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FlashCardScreen(
          noteId: viewModel.noteId,
          initialFlashcards: viewModel.flashCards,
        ),
      ),
    ).then((result) {
      // 플래시카드 화면에서 돌아왔을 때 데이터 갱신
      if (result != null && result is Map && result.containsKey('flashcardCount')) {
        final int count = result['flashcardCount'] as int;
        
        if (result.containsKey('flashcards') && result['flashcards'] is List) {
          // 새로운 플래시카드 목록으로 교체
          viewModel.loadFlashcards();
          
          if (kDebugMode) {
            print("🔄 플래시카드 화면에서 돌아옴: 카운트=$count, 데이터 갱신 요청됨");
          }
        }
      } else {
        // 결과가 없어도 최신 데이터로 갱신
        viewModel.loadFlashcards();
      }
    });
  }

  // 바텀 네비게이션 바 구성 (다중 선택 모드)
  Widget _buildBottomBar(BuildContext context, NoteDetailViewModel viewModel) {
    if (viewModel.pages == null || viewModel.pages!.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // 페이지 처리 완료 콜백 설정 (한 번만 설정)
    _setupPageProcessedCallback(context, viewModel);
    
    return NoteDetailBottomBar(
      currentPage: viewModel.currentPage,
      currentPageIndex: viewModel.currentPageIndex,
      totalPages: viewModel.totalImageCount > 0 ? viewModel.totalImageCount : (viewModel.pages?.length ?? 0),
      onPageChanged: (index) {
        // 네비게이션 버튼 클릭 시 PageController를 사용하여 페이지 이동
        viewModel.navigateToPage(index);
      },
      contentManager: viewModel.getContentManager(),
      textReaderService: TextReaderService(),
      isProcessing: false,
      progressValue: (viewModel.currentPageIndex + 1) / (viewModel.totalImageCount > 0 ? viewModel.totalImageCount : (viewModel.pages?.length ?? 1)),
      onTtsPlay: () {
        if (kDebugMode) {
          print("TTS 재생/정지 토글");
        }
        // TtsService에서 현재 상태 확인
        final ttsService = viewModel.getContentManager().ttsService;
        // 재생 중이면 정지, 정지 상태면 재생
        final currentState = ttsService.state.toString();
        if (currentState.contains('playing')) {
          viewModel.stopTts();
        } else {
          viewModel.speakCurrentPageText();
        }
      },
      isMinimalUI: false,
      processedPages: viewModel.getProcessedPagesStatus(),
    );
  }
  
  // 페이지 처리 완료 콜백 설정 (스낵바 표시)
  void _setupPageProcessedCallback(BuildContext context, NoteDetailViewModel viewModel) {
    // 이미 콜백이 설정되어 있는지 검사하는 로직이 필요할 수 있음
    // 일단 매번 새로 설정하도록 구현
    
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

  // 백그라운드 처리 상태 표시기
  Widget _buildProcessingStatusIndicator(BuildContext context, NoteDetailViewModel viewModel) {
    // 처리 상태 정보
    final processedPages = viewModel.getProcessedPagesStatus();
    final totalPages = processedPages.length;
    final completedPages = processedPages.where((status) => status).length;
    final progress = totalPages > 0 ? completedPages / totalPages : 0.0;
    
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        color: Colors.black.withOpacity(0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey[700],
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '$completedPages/$totalPages',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '페이지 텍스트 처리 중...',
              style: const TextStyle(color: Colors.white, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
} 