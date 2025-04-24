import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' hide debugPrint;
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
import 'package:provider/provider.dart';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/theme/tokens/ui_tokens.dart';
import 'dart:async';
import '../../widgets/note_action_bottom_sheet.dart';

/// MVVM 패턴을 적용한 노트 상세 화면
class NoteDetailScreenMVVM extends StatelessWidget {
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
            final isProcessed = viewModel.processedPageStatus[page.id] ?? false;
            
            // 페이지 처리 상태에 따라 다른 위젯 반환
            if (!isProcessed && page.originalText == "___PROCESSING___") {
              // 처리 중이고 마커가 있는 경우 로딩 위젯 표시
              return _ProcessingPageWidget(
                pageId: page.id,
                pageIndex: index,
                viewModel: viewModel,
              );
            } else {
              // 처리 완료되었거나, 마커가 없는 경우 (오류 또는 초기 상태) 페이지 콘텐츠 표시
              return _buildPageContent(context, viewModel, page);
            }
          },
        ),
      ),
    );
  }
  
  // 페이지 콘텐츠 위젯 (복원)
  Widget _buildPageContent(BuildContext context, NoteDetailViewModel viewModel, pika_page.Page page) {
    return RepaintBoundary(
      child: PageContentWidget(
        key: ValueKey('page_content_${page.id}'),
        page: page,
        imageFile: viewModel.getImageFileForPage(page),
        isLoadingImage: false, // 필요시 ViewModel에서 관리
        noteId: viewModel.noteId,
        onCreateFlashCard: (front, back, {pinyin}) => 
            _handleCreateFlashCard(context, viewModel, front, back, pinyin: pinyin),
        flashCards: viewModel.flashCards,
        useSegmentMode: !viewModel.isFullTextMode,
        onDeleteSegment: (segmentIndex) => _handleDeleteSegment(context, viewModel, segmentIndex),
      ),
    );
  }
  
  // 세그먼트 삭제 처리 (복원)
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
  
  // 더보기 옵션 표시 (NoteActionBottomSheet 사용하도록 수정)
  void _showMoreOptions(BuildContext context, NoteDetailViewModel viewModel) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NoteActionBottomSheet(
        onEditTitle: () => _showEditTitleDialog(context, viewModel),
        onDeleteNote: () => _confirmDeleteNote(context, viewModel),
        onToggleFavorite: viewModel.toggleFavorite,
        onToggleFullTextMode: viewModel.toggleFullTextMode, // FullTextMode 토글 추가
        isFavorite: viewModel.note?.isFavorite ?? false,
        isFullTextMode: viewModel.isFullTextMode, // FullTextMode 상태 전달
      ),
    );
  }

  // 바텀 시트 구성 (_buildBottomSheet) 제거 (NoteActionBottomSheet 사용)
  
  // 제목 수정 다이얼로그 (복원, NoteActionBottomSheet에서 호출됨)
  void _showEditTitleDialog(BuildContext context, NoteDetailViewModel viewModel) {
    final TextEditingController controller = TextEditingController(
      text: viewModel.note?.originalText,
    );
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
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
  
  // 노트 삭제 확인 (복원, NoteActionBottomSheet에서 호출됨)
  void _confirmDeleteNote(BuildContext context, NoteDetailViewModel viewModel) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('노트 삭제'),
        content: const Text('정말로 이 노트를 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.'),
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
  
  // 플래시카드 생성 처리 (복원)
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
  
  // 플래시카드 화면으로 이동 (복원)
  void _navigateToFlashcards(BuildContext context, NoteDetailViewModel viewModel) {
    if (viewModel.flashCards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장된 플래시카드가 없습니다. 먼저 플래시카드를 추가해주세요.')),
      );
      return;
    }
    
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

  // 바텀 네비게이션 바 구성 (NoteDetailBottomBar 위젯 사용)
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
      onToggleFullTextMode: viewModel.toggleFullTextMode,
      isFullTextMode: viewModel.isFullTextMode,
      contentManager: viewModel.getContentManager(),
      textReaderService: TextReaderService(), // 직접 생성 또는 의존성 주입 필요
      isProcessing: viewModel.isProcessingBackground, // ViewModel 상태 사용
      progressValue: (viewModel.currentPageIndex + 1) / (viewModel.totalImageCount > 0 ? viewModel.totalImageCount : (viewModel.pages?.length ?? 1)),
      onTtsPlay: () {
        if (kDebugMode) {
          print("TTS 재생 시작");
        }
        viewModel.speakCurrentPageText();
      },
      isMinimalUI: false, // 필요에 따라 조정
      processedPages: viewModel.getProcessedPagesStatus(),
    );
  }
  
  // 페이지 처리 완료 콜백 설정 (스낵바 표시) (복원)
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
}

/// 처리 중인 페이지를 위한 스테이트풀 위젯
class _ProcessingPageWidget extends StatefulWidget {
  final String? pageId;
  final int pageIndex;
  final NoteDetailViewModel viewModel;
  
  const _ProcessingPageWidget({
    Key? key,
    this.pageId,
    required this.pageIndex,
    required this.viewModel,
  }) : super(key: key);
  
  @override
  _ProcessingPageWidgetState createState() => _ProcessingPageWidgetState();
}

class _ProcessingPageWidgetState extends State<_ProcessingPageWidget> {
  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint('페이지 ${widget.pageIndex} 처리 위젯 초기화');
    }
  }
  
  @override
  void dispose() {
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    // ViewModel의 public getter 사용 (다음 단계에서 추가 예정)
    final isProcessed = widget.viewModel.processedPageStatus[widget.pageId] ?? false;
    
    if (!isProcessed) {
      return _buildLoadingUI();
    } else {
      // 이론적으로 처리 완료 시 이 위젯은 더 이상 표시되지 않아야 함.
      // PageView.builder에서 처리된 페이지에 대해 다른 위젯을 반환하도록 해야 함.
      // 안전 장치로 로딩 UI를 계속 표시하거나 빈 컨테이너 반환
      return Container(); // 처리 완료 시 빈 컨테이너 반환
    }
  }
  
  // 로딩 UI
  Widget _buildLoadingUI() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const DotLoadingIndicator(message: '텍스트 처리를 기다리는 중...'),
          const SizedBox(height: 16),
          Text(
            '이 페이지는 백그라운드에서 처리 중입니다.\n완료되면 자동으로 업데이트됩니다.',
            textAlign: TextAlign.center,
            style: TypographyTokens.body2,
          ),
          const SizedBox(height: 24),
          // 이미지 파일이 있으면 보여주기
          if (widget.pageId != null)
            FutureBuilder<Widget>(
              future: _loadImageWidget(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done && 
                    snapshot.hasData) {
                  return snapshot.data!;
                }
                return const SizedBox.shrink();
              },
            ),
        ],
      ),
    );
  }
  
  // 이미지 위젯 로드
  Future<Widget> _loadImageWidget() async {
    try {
      final imageFile = widget.viewModel.getImageFileForPage(
        widget.viewModel.pages?[widget.pageIndex]
      );
      
      if (imageFile != null && await imageFile.exists()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            imageFile,
            height: 200,
            fit: BoxFit.contain,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('이미지 로드 중 오류: $e');
      }
    }
    
    return const SizedBox.shrink();
  }
}

// 로컬 debugPrint 함수 사용
void debugPrint(String message) {
  if (kDebugMode) {
    print(message);
  }
} 