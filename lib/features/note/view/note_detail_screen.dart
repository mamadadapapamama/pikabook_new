import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../../../core/models/note.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/ui_tokens.dart';
import '../../../core/widgets/dot_loading_indicator.dart';
import '../../../core/widgets/pika_button.dart';
import '../../../core/widgets/pika_app_bar.dart';
import '../view_model/note_detail_viewmodel.dart';
import '../../flashcard/flashcard_view_model.dart';
import '../../flashcard/flashcard_screen.dart';
import 'note_detail_bottom_bar.dart';
import 'note_page_widget.dart';
import '../../../core/services/tts/tts_service.dart';
import '../../../core/utils/note_tutorial.dart';
import '../../flashcard/flashcard_service.dart';
import '../../../core/services/authentication/user_preferences_service.dart';
import '../../../core/models/flash_card.dart';

/// MVVM 패턴을 적용한 노트 상세 화면
class NoteDetailScreenMVVM extends StatefulWidget {
  final String noteId;
  final Note? initialNote;

  const NoteDetailScreenMVVM({
    super.key,
    required this.noteId,
    this.initialNote,
  });

  // 라우트 생성 메서드
  static Route<dynamic> route({
    required Note note, 
    bool isProcessingBackground = false,
  }) {
    if (kDebugMode) {
      print("🚀 Navigating to NoteDetailScreenMVVM for note: ${note.id}");
    }
    return MaterialPageRoute(
      settings: const RouteSettings(name: '/note_detail'),
      builder: (context) => ChangeNotifierProvider(
        create: (context) => NoteDetailViewModel(
          noteId: note.id,
          initialNote: note,
        ),
        child: NoteDetailScreenMVVM(
          noteId: note.id,
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
  late UserPreferencesService _userPreferencesService;
  List<FlashCard> _flashcards = [];
  bool _useSegmentMode = false; // 세그먼트 모드 여부
  
  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadUserPreferences(); // 사용자 설정 로드
    
    // 화면 렌더링 완료 후 튜토리얼 체크
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 튜토리얼 표시 확인
      if (kDebugMode) {
        print('노트 상세 화면: 튜토리얼 체크');
      }
      
      NoteTutorial.checkAndShowTutorial(context);
      
      // 플래시카드 로드
      await _loadFlashcards();
    });
  }
  
  /// 서비스 초기화
  Future<void> _initializeServices() async {
    try {
      _flashCardService = FlashCardService();
      _ttsService = TTSService();
      _userPreferencesService = UserPreferencesService();
      await _ttsService.init();
    } catch (e) {
      if (kDebugMode) {
        print('서비스 초기화 중 오류: $e');
      }
    }
  }
  
  /// 사용자 설정 로드
  Future<void> _loadUserPreferences() async {
    try {
      final userPrefs = await _userPreferencesService.getPreferences();
      setState(() {
        _useSegmentMode = userPrefs.useSegmentMode;
      });
    } catch (e) {
      if (kDebugMode) {
        print('사용자 설정 로드 중 오류: $e');
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
  
  @override
  Widget build(BuildContext context) {
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
    final totalPages = viewModel.totalPages;
    
    return PikaAppBar.noteDetail(
      title: viewModel.note?.title ?? '노트 로딩 중...',
      currentPage: currentPageNum,
      totalPages: totalPages,
      flashcardCount: _flashcards.length, // 로컬 상태 사용
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

    // 페이지 뷰 구성
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
        imageFile: null,
        noteId: viewModel.noteId,
        onCreateFlashCard: (front, back, {pinyin}) => 
            _handleCreateFlashCard(context, viewModel, front, back, pinyin: pinyin),
        flashCards: _flashcards,
        onPlayTts: (text, {segmentIndex}) => _handlePlayTts(text, segmentIndex: segmentIndex),
      ),
    );
  }
  
  // TTS 재생 처리
  Future<void> _handlePlayTts(String text, {int? segmentIndex}) async {
    if (kDebugMode) {
      print('TTS 재생 상태 업데이트: $text (세그먼트: $segmentIndex)');
    }
  }
  
  // 더보기 옵션 표시
  void _showMoreOptions(BuildContext context, NoteDetailViewModel viewModel) {
    final note = viewModel.note;
    if (note == null) return;
    
    viewModel.noteOptionsManager.showMoreOptions(
      context, 
      note,
      onTitleEditing: () {
        // 제목 수정 후 새로고침
        setState(() {});
      },
      onNoteDeleted: () {
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
      final newFlashCard = await _flashCardService.createFlashCard(
        front: front,
        back: back,
        noteId: viewModel.noteId,
        pinyin: pinyin,
      );
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('플래시카드가 추가되었습니다')),
        );
        
        setState(() {
          _flashcards.add(newFlashCard);
        });
        
        if (kDebugMode) {
          print("✅ 새 플래시카드 추가 완료: ${newFlashCard.front}");
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
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FlashCardScreen(
          noteId: viewModel.noteId,
          isTtsEnabled: true,
        ),
      ),
    );
    
    if (result != null && result is Map<String, dynamic>) {
      if (result.containsKey('flashcards') && result['flashcards'] is List) {
        List<dynamic> cards = result['flashcards'] as List<dynamic>;
        List<FlashCard> flashcards = cards.map((card) {
          if (card is FlashCard) {
            return card;
          } else if (card is Map<String, dynamic>) {
            return FlashCard.fromJson(card);
          }
          return FlashCard(
            id: '',
            front: '',
            back: '',
            pinyin: '',
            createdAt: DateTime.now(),
          );
        }).toList();
        
        flashcards = flashcards.where((card) => card.front.isNotEmpty).toList();
        
        setState(() {
          _flashcards = flashcards;
        });
      }
    }
  }

  // 바텀 네비게이션 바 구성
  Widget _buildBottomBar(BuildContext context, NoteDetailViewModel viewModel) {
    if (viewModel.pages == null || viewModel.pages!.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // 현재 페이지의 TTS 텍스트 가져오기 (세그먼트 모드에서만)
    final currentProcessedText = viewModel.currentProcessedText;
    final ttsText = _useSegmentMode ? (currentProcessedText?.fullOriginalText ?? '') : '';
    
    return NoteDetailBottomBar(
      currentPage: viewModel.currentPage,
      currentPageIndex: viewModel.currentPageIndex,
      totalPages: viewModel.totalPages,
      onPageChanged: (index) {
        viewModel.navigateToPage(index);
      },
      ttsText: ttsText,
      isProcessing: false,
      progressValue: (viewModel.currentPageIndex + 1) / (viewModel.pages?.length ?? 1),
      onTtsPlay: _useSegmentMode ? () {
        if (_ttsService.state == TtsState.playing) {
          _ttsService.stop();
        } else {
          if (ttsText.isNotEmpty) {
            _ttsService.speak(ttsText);
          }
        }
      } : null,
      useSegmentMode: _useSegmentMode,
      processedPages: [], // 간소화된 ViewModel에서는 빈 리스트
      processingPages: [], // 간소화된 ViewModel에서는 빈 리스트
    );
  }
} 