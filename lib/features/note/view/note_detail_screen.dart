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
import '../../../core/widgets/pika_button.dart';
import '../view_model/note_detail_viewmodel.dart';
import '../../flashcard/flashcard_view_model.dart';
import 'note_page_widget.dart';
import '../../../core/widgets/pika_app_bar.dart';
import '../../flashcard/flashcard_screen.dart';
import 'note_detail_bottom_bar.dart';
import '../../../core/services/tts/tts_service.dart';
import '../../../core/services/media/image_service.dart';
import '../../../core/services/authentication/auth_service.dart';
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

  // Service 인스턴스들 - ImageService 제거
  
  @override
  void initState() {
    super.initState();
    
    // 초기화
    _initializeServices();
    
    // 화면 렌더링 완료 후 튜토리얼 체크
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // 튜토리얼 표시 확인 (노트 개수 업데이트 없이)
      if (kDebugMode) {
        print('노트 상세 화면: 튜토리얼 체크');
      }
      
      // 튜토리얼 표시 확인
      NoteTutorial.checkAndShowTutorial(context);
      
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

    // 최종 실패 메시지 표시 (우선순위 높음)
    if (viewModel.showFailureMessage) {
      return _buildFailureMessageWidget(context, viewModel);
    }

    // LLM 타임아웃 발생시 재시도 버튼 표시
    if (viewModel.llmTimeoutOccurred && viewModel.llmRetryAvailable) {
      return _buildLlmRetryWidget(context, viewModel);
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
  
  // LLM 재시도 위젯
  Widget _buildLlmRetryWidget(BuildContext context, NoteDetailViewModel viewModel) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.access_time,
              color: Colors.orange,
              size: 64,
            ),
            const SizedBox(height: 24),
            Text(
              'LLM 처리 시간이 초과되었습니다',
              style: TypographyTokens.headline3.copyWith(
                color: Colors.orange[800],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              '번역 및 병음 처리에 예상보다 시간이 오래 걸리고 있어요.\n다시 시도해 주세요.',
              style: TypographyTokens.body2.copyWith(
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            PikaButton(
              text: '다시 시도',
              variant: PikaButtonVariant.text,
              onPressed: viewModel.isRetryingLlm ? null : () async {
                await viewModel.retryLlmProcessing();
              },
              isLoading: viewModel.isRetryingLlm,
            ),
          ],
        ),
      ),
    );
  }

  // 최종 실패 메시지 위젯
  Widget _buildFailureMessageWidget(BuildContext context, NoteDetailViewModel viewModel) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 64,
            ),
            const SizedBox(height: 24),
            Text(
              '처리 실패',
              style: TypographyTokens.headline3.copyWith(
                color: Colors.red[800],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              viewModel.userFriendlyError ?? '처리 중 문제가 발생했습니다. 잠시 후 다시 시도해주세요.',
              style: TypographyTokens.body2.copyWith(
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            PikaButton(
              text: '확인',
              variant: PikaButtonVariant.text,
              onPressed: () async {
                await viewModel.dismissFailureMessage();
              },
            ),
          ],
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
  
  // TTS 재생 처리 - 상태 업데이트만 담당 (실제 재생은 ProcessedTextWidget에서 처리)
  Future<void> _handlePlayTts(String text, {int? segmentIndex}) async {
    // ProcessedTextWidget에서 이미 TTS 재생을 처리하므로
    // 여기서는 추가적인 상태 업데이트만 필요한 경우에 사용
    if (kDebugMode) {
      print('TTS 재생 상태 업데이트: $text (세그먼트: $segmentIndex)');
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
        
        // 노트 정보 새로고침 (플래시카드 카운터 업데이트)
        await viewModel.loadNote();
        
        if (kDebugMode) {
          print("✅ 새 플래시카드 추가 완료: ${newFlashCard.front}");
          print("✅ 현재 플래시카드 목록 크기: ${_flashcards.length}개");
          print("✅ 노트 플래시카드 카운터 업데이트 완료");
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
    // 플래시카드 화면으로 이동하여 결과 받아오기 (TTS는 항상 활성화, 내부에서 샘플/일반 모드 구분)
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FlashCardScreen(
          noteId: viewModel.noteId,
          isTtsEnabled: true, // TTS 항상 활성화 (내부에서 샘플/일반 모드 구분)
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
    
    // 페이지 처리 상태 가져오기
    final processedPages = viewModel.getProcessedPagesStatus();
    final processingPages = viewModel.getProcessingPagesStatus();
    
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
      processingPages: processingPages,
    );
  }
} 