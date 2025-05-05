import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io'; // File 클래스 import 추가
import 'package:provider/provider.dart';
import '../../core/models/note.dart';
import '../../core/models/page.dart' as pika_page;
import '../../core/models/processed_text.dart';
import '../../core/models/text_segment.dart';
import '../../core/models/flash_card.dart'; // 실제 FlashCard 모델 사용
import '../../core/theme/tokens/typography_tokens.dart';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/widgets/pika_app_bar.dart';
import '../../core/widgets/dot_loading_indicator.dart';
import '../../features/note_detail/page_content_widget.dart';
import '../../features/note_detail/note_detail_bottom_bar.dart';
import '../../core/services/text_processing/text_reader_service.dart';
import '../../core/theme/tokens/ui_tokens.dart';
import 'sample_notes_service.dart';
import '../../features/note_detail/managers/content_manager.dart'; // ContentManager import 추가
import 'sample_flashcard_screen.dart'; // 샘플 플래시카드 화면 import 추가

// 샘플 모드용 ViewModel - 실제 ViewModel을 간소화
class SampleNoteDetailViewModel extends ChangeNotifier {
  final Note note;
  final SampleNotesService sampleNotesService;
  
  bool _isLoading = true;
  bool get isLoading => _isLoading;
  
  String? _error;
  String? get error => _error;
  
  List<pika_page.Page>? _pages;
  List<pika_page.Page>? get pages => _pages;
  
  int _currentPageIndex = 0;
  int get currentPageIndex => _currentPageIndex;
  
  pika_page.Page? get currentPage => 
      (_pages != null && _pages!.isNotEmpty) ? _pages![_currentPageIndex] : null;
  
  final PageController _pageController = PageController();
  PageController get pageController => _pageController;
  
  ProcessedText? _processedText;
  
  // 미리 정의된 샘플 플래시카드 목록
  final List<FlashCard> _sampleFlashcards = [
    FlashCard(
      id: 'sample-card-1',
      front: '学校',
      back: '학교',
      pinyin: 'xuéxiào',
      createdAt: DateTime.now(),
      sourceLanguage: 'zh-CN',
      targetLanguage: 'ko'
    ),
    FlashCard(
      id: 'sample-card-2',
      front: '老师',
      back: '선생님',
      pinyin: 'lǎoshī',
      createdAt: DateTime.now(),
      sourceLanguage: 'zh-CN',
      targetLanguage: 'ko'
    ),
    FlashCard(
      id: 'sample-card-3',
      front: '同学',
      back: '학우, 급우',
      pinyin: 'tóngxué',
      createdAt: DateTime.now(),
      sourceLanguage: 'zh-CN',
      targetLanguage: 'ko'
    ),
    FlashCard(
      id: 'sample-card-4',
      front: '认真',
      back: '성실하다',
      pinyin: 'rènzhēn',
      createdAt: DateTime.now(),
      sourceLanguage: 'zh-CN',
      targetLanguage: 'ko'
    ),
    FlashCard(
      id: 'sample-card-5',
      front: '专心',
      back: '집중하다',
      pinyin: 'zhuānxīn',
      createdAt: DateTime.now(),
      sourceLanguage: 'zh-CN',
      targetLanguage: 'ko'
    ),
  ];
  
  List<FlashCard>? get flashCards => _sampleFlashcards;
  
  SampleNoteDetailViewModel({
    required this.note,
    required this.sampleNotesService,
  }) {
    _initialize();
  }
  
  Future<void> _initialize() async {
    try {
      _isLoading = true;
      notifyListeners();
      
      // 노트의 페이지 설정
      _pages = note.pages;
      
      // 프로세스된 텍스트 로드 (첫 페이지)
      if (_pages != null && _pages!.isNotEmpty) {
        final pageId = _pages![0].id;
        if (pageId != null) {
          _processedText = sampleNotesService.getProcessedTextForPage(pageId);
        }
      }
      
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = '데이터 로드 중 오류 발생: $e';
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // 페이지 변경 처리
  void onPageChanged(int index) {
    _currentPageIndex = index;
    notifyListeners();
  }
  
  // 페이지 이동
  void navigateToPage(int index) {
    if (_pages == null || index < 0 || index >= _pages!.length) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
  
  // ViewModel에서 ContentManager 대신 사용할 수 있는 메서드
  Future<ProcessedText?> getProcessedText(String pageId) async {
    return sampleNotesService.getProcessedTextForPage(pageId);
  }
  
  // 더미 메서드들
  List<bool> getProcessedPagesStatus() {
    // 모든 페이지가 처리 완료된 것으로 표시
    List<bool> result = [];
    if (_pages != null) {
      for (int i = 0; i < _pages!.length; i++) {
        result.add(true);
      }
    }
    return result;
  }
  
  // 더미 메서드 - 실제로는 아무 것도 하지 않음
  Future<bool> createFlashCard(String front, String back, {String? pinyin}) async {
    return true; // 항상 성공한 것처럼 처리
  }
  
  // 더미 메서드 - 실제로는 아무 것도 하지 않음
  Future<bool> deleteSegment(int segmentIndex) async {
    return true; // 항상 성공한 것처럼 처리
  }
  
  // 더미 메서드 - 항상 null 반환
  File? getImageFileForPage(pika_page.Page page) {
    return null;
  }
  
  // 더미 메서드 - 실제로는 아무 것도 하지 않음
  void speakCurrentPageText() {
    // 샘플 모드에서는 구현하지 않음
  }
  
  // 더미 메서드 - ContentManager 대용
  dynamic getContentManager() {
    return ContentManager(); // ContentManager 인스턴스 반환
  }
  
  // 콜백 설정 더미 메서드
  void setPageProcessedCallback(Function(int) callback) {
    // 샘플 모드에서는 구현하지 않음
  }
  
  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}

/// 샘플 노트 상세 화면 - 실제 노트 상세 화면과 유사한 UI
class SampleNoteDetailScreen extends StatelessWidget {
  final Note note;
  final SampleNotesService sampleNotesService;

  const SampleNoteDetailScreen({
    Key? key,
    required this.note,
    required this.sampleNotesService,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // ChangeNotifierProvider 사용하여 ViewModel 제공
    return ChangeNotifierProvider(
      create: (context) => SampleNoteDetailViewModel(
        note: note,
        sampleNotesService: sampleNotesService,
      ),
      child: _SampleNoteDetailScreenContent(),
    );
  }
}

/// 샘플 노트 상세 화면의 내용 위젯
class _SampleNoteDetailScreenContent extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // ViewModel에 접근
    final viewModel = Provider.of<SampleNoteDetailViewModel>(context);
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(context, viewModel),
      body: _buildBody(context, viewModel),
      bottomNavigationBar: _buildBottomBar(context, viewModel),
    );
  }
  
  // 앱바 구성
  PreferredSizeWidget _buildAppBar(BuildContext context, SampleNoteDetailViewModel viewModel) {
    final currentPageNum = viewModel.currentPageIndex + 1;
    final totalPages = viewModel.pages?.length ?? 0;
    final bool isSampleNote = viewModel.note.id != null && viewModel.note.id!.startsWith('sample-');
    final bool isAnimalNote = viewModel.note.id == 'sample-animal-book';
    
    return PikaAppBar.noteDetail(
      title: viewModel.note.originalText,
      currentPage: currentPageNum,
      totalPages: totalPages,
      // 동물 노트인 경우 flashcardCount를 0으로 설정
      flashcardCount: isAnimalNote ? 0 : (viewModel.flashCards?.length ?? 0),
      onMorePressed: () {
        // 샘플 모드에서는 더보기 버튼을 비활성화
      },
      onFlashcardTap: () {
        // 동물 노트인 경우 메시지 표시 후 반환
        if (isAnimalNote) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이 노트에는 플래시카드가 없습니다.')),
          );
          return;
        }
        
        // 플래시카드 화면으로 이동
        if (viewModel.flashCards != null && viewModel.flashCards!.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SampleFlashCardScreen(
                flashcards: viewModel.flashCards!,
                noteTitle: viewModel.note.translatedText,
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이 노트에는 플래시카드가 없습니다.')),
          );
        }
      },
      onBackPressed: () => Navigator.of(context).pop(),
      backgroundColor: UITokens.screenBackground,
      // 샘플 모드 정보 추가
      noteId: isSampleNote ? null : viewModel.note.id,
      flashcards: isAnimalNote ? null : (isSampleNote ? viewModel.flashCards : null),
      sampleNoteTitle: isSampleNote ? viewModel.note.translatedText : null,
    );
  }
  
  // 바디 구성
  Widget _buildBody(BuildContext context, SampleNoteDetailViewModel viewModel) {
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
          controller: viewModel.pageController,
          itemCount: viewModel.pages!.length,
          onPageChanged: viewModel.onPageChanged,
          itemBuilder: (context, index) {
            final page = viewModel.pages![index];
            
            // 페이지 콘텐츠 위젯 반환
            return _buildPageContent(context, viewModel, page);
          },
        ),
      ),
    );
  }
  
  // 페이지 콘텐츠 위젯
  Widget _buildPageContent(BuildContext context, SampleNoteDetailViewModel viewModel, pika_page.Page page) {
    return RepaintBoundary(
      child: FutureBuilder<ProcessedText?>(
        future: viewModel.getProcessedText(page.id!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: DotLoadingIndicator(message: '콘텐츠 로딩 중...'));
          }
          
          if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
            return Center(
              child: Text(
                '콘텐츠를 불러올 수 없습니다.',
                style: TypographyTokens.body1,
              ),
            );
          }
          
          final processedText = snapshot.data!;
          
          return PageContentWidget(
            key: ValueKey('page_content_${page.id}'),
            page: page,
            imageFile: null,
            isLoadingImage: false,
            noteId: page.noteId ?? viewModel.note.id ?? '',
            onCreateFlashCard: (front, back, {pinyin}) => 
                _handleLoginRequired(context),
            flashCards: viewModel.flashCards,
            useSegmentMode: true,
            onDeleteSegment: (segmentIndex) => _handleLoginRequired(context),
          );
        },
      ),
    );
  }

  // 바텀 네비게이션 바 구성
  Widget _buildBottomBar(BuildContext context, SampleNoteDetailViewModel viewModel) {
    if (viewModel.pages == null || viewModel.pages!.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return NoteDetailBottomBar(
      currentPage: viewModel.currentPage,
      currentPageIndex: viewModel.currentPageIndex,
      totalPages: viewModel.pages?.length ?? 0,
      onPageChanged: (index) {
        viewModel.navigateToPage(index);
      },
      contentManager: viewModel.getContentManager(),
      textReaderService: TextReaderService(),
      isProcessing: false,
      progressValue: (viewModel.currentPageIndex + 1) / (viewModel.pages?.length ?? 1),
      onTtsPlay: () {
        // 샘플 모드에서는 로그인 요구 다이얼로그 표시
        _showLoginRequiredDialog(context);
      },
      isMinimalUI: false,
      processedPages: viewModel.getProcessedPagesStatus(),
    );
  }
  
  // 더보기 옵션 표시
  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildBottomSheet(context),
    );
  }
  
  // 바텀 시트 구성
  Widget _buildBottomSheet(BuildContext context) {
    // 플래시카드 화면으로 이동하는 메서드
    void _navigateToFlashcards(BuildContext context, SampleNoteDetailViewModel viewModel) {
      if (viewModel.flashCards != null && viewModel.flashCards!.isNotEmpty) {
        Navigator.pop(context); // 바텀 시트 닫기
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SampleFlashCardScreen(
              flashcards: viewModel.flashCards!,
              noteTitle: viewModel.note.translatedText,
            ),
          ),
        );
      } else {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이 노트에는 플래시카드가 없습니다.')),
        );
      }
    }

    // Provider에서 ViewModel 가져오기
    final viewModel = Provider.of<SampleNoteDetailViewModel>(context, listen: false);

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
          // 플래시카드 보기 버튼 추가
          ListTile(
            leading: const Icon(Icons.style),
            title: const Text('플래시카드 보기'),
            onTap: () => _navigateToFlashcards(context, viewModel),
          ),
          ListTile(
            leading: const Icon(Icons.star_border),
            title: const Text('즐겨찾기에 추가'),
            onTap: () {
              Navigator.pop(context);
              _showLoginRequiredDialog(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('제목 수정'),
            onTap: () {
              Navigator.pop(context);
              _showLoginRequiredDialog(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('노트 삭제', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _showLoginRequiredDialog(context);
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
  
  // 로그인 필요 다이얼로그 표시
  void _showLoginRequiredDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            '로그인이 필요한 서비스입니다',
            style: TypographyTokens.subtitle2,
          ),
          content: Text(
            '노트 저장과 맞춤 학습을 위해 로그인이 필요합니다.',
            style: TypographyTokens.body2,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // 다이얼로그 닫기
              },
              child: Text(
                '취소',
                style: TypographyTokens.button.copyWith(
                  color: ColorTokens.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // 다이얼로그 닫기
                Navigator.of(context).pop(); // 노트 상세 화면 닫기
                // 로그인 화면으로 이동 로직이 필요하다면 추가
              },
              child: Text(
                '로그인',
                style: TypographyTokens.button.copyWith(
                  color: ColorTokens.primary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
  
  // 로그인 필요 처리
  void _handleLoginRequired(BuildContext context) {
    _showLoginRequiredDialog(context);
    return null;
  }
} 