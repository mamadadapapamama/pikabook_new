import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../../../core/models/processed_text.dart';
import '../../../core/models/processing_status.dart';
import '../view_model/note_detail_viewmodel.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../core/models/flash_card.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/widgets/dot_loading_indicator.dart';
import '../../../core/widgets/typewriter_text.dart';
import '../../flashcard/flashcard_view_model.dart';
import 'page_image_widget.dart';
import 'processed_text_widget.dart';
import '../../dictionary/dictionary_result_widget.dart';

/// 노트 페이지 위젯: 이미지와 처리된 텍스트를 함께 표시
class NotePageWidget extends StatefulWidget {
  final page_model.Page page;
  final File? imageFile;
  final String noteId;
  final List<FlashCard> flashCards;
  final Function(String, String, {String? pinyin})? onCreateFlashCard;
  final Function(String, {int? segmentIndex})? onPlayTts;
  
  const NotePageWidget({
    Key? key,
    required this.page,
    this.imageFile,
    required this.noteId,
    this.flashCards = const [],
    this.onCreateFlashCard,
    this.onPlayTts,
  }) : super(key: key);

  @override
  State<NotePageWidget> createState() => _NotePageWidgetState();
}

class _NotePageWidgetState extends State<NotePageWidget> {
  bool _hasTriedLoading = false;

  @override
  void initState() {
    super.initState();
    // 초기 로딩 시도
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryLoadTextIfNeeded();
    });
  }

  @override
  void didUpdateWidget(NotePageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 페이지가 변경되면 로딩 상태 리셋
    if (oldWidget.page.id != widget.page.id) {
      _hasTriedLoading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tryLoadTextIfNeeded();
      });
    }
  }

  void _tryLoadTextIfNeeded() {
    if (!mounted || _hasTriedLoading) return;
    
    final viewModel = Provider.of<NoteDetailViewModel>(context, listen: false);
    final textViewModel = viewModel.getTextViewModel(widget.page.id);
    final processedText = textViewModel['processedText'] as ProcessedText?;
    final isLoading = textViewModel['isLoading'] as bool? ?? false;
    
    // ProcessedText가 없고 로딩 중이 아닐 때만 로드 시도
    if (processedText == null && !isLoading && !viewModel.isLoading) {
      _hasTriedLoading = true;
      viewModel.loadCurrentPageText();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Consumer를 사용하여 ViewModel에 직접 접근
    return Consumer<NoteDetailViewModel>(
      builder: (context, viewModel, child) {
        // 현재 페이지의 텍스트 데이터 미리 가져오기
        final textViewModel = viewModel.getTextViewModel(widget.page.id);
        final processedText = textViewModel['processedText'] as ProcessedText?;
        final isLoading = textViewModel['isLoading'] as bool? ?? false;
        final error = textViewModel['error'] as String?;
        
        return _buildPageContent(context, viewModel, processedText, isLoading, error);
      },
    );
  }
  
  Widget _buildPageContent(BuildContext context, NoteDetailViewModel viewModel, 
      ProcessedText? processedText, bool isLoading, String? error) {
    
    // 스크롤 가능한 컨테이너
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: SpacingTokens.lg,
        vertical: SpacingTokens.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 페이지 이미지 위젯
          PageImageWidget(
            imageFile: widget.imageFile,
            imageUrl: widget.page.imageUrl,
            page: widget.page,
            isLoading: viewModel.isLoading,
            enableFullScreen: true,
          ),
          
          SizedBox(height: SpacingTokens.md),
          
          // 텍스트 콘텐츠 위젯
          _buildTextContent(context, viewModel, processedText, isLoading, error),
        ],
      ),
    );
  }
  
  // 텍스트 콘텐츠 위젯 (상태에 따라 다른 위젯 반환)
  Widget _buildTextContent(BuildContext context, NoteDetailViewModel viewModel,
      ProcessedText? processedText, bool isLoading, String? error) {
    
    if (kDebugMode) {
      print('🎭 NotePageWidget _buildTextContent');
      print('   processedText != null: ${processedText != null}');
      print('   page.showTypewriterEffect: ${widget.page.showTypewriterEffect}');
      if (processedText != null) {
        print('   processedText.streamingStatus: ${processedText.streamingStatus}');
        print('   processedText.fullTranslatedText.length: ${processedText.fullTranslatedText?.length ?? 0}');
      }
    }
    
    // 1차 ProcessedText (원문만, 번역 없음) - 타이프라이터 효과 적용
    if (processedText != null && 
        widget.page.showTypewriterEffect && 
        (processedText.fullTranslatedText == null || processedText.fullTranslatedText!.isEmpty)) {
      return _buildTypewriterOnlyWidget(context, processedText);
    }
    
    // 2차 ProcessedText (번역 완료) - 일반 표시
    if (processedText != null) {
      return _buildProcessedTextWidget(context, processedText, viewModel);
    }
    
    // 로딩 중이거나 오류가 있는 경우
    if (isLoading) {
      return _buildLoadingIndicator();
    } else if (error != null) {
      return _buildErrorWidget(error);
    } else {
      return _buildLoadingIndicator(); // 빈 상태도 로딩 인디케이터로 통일
    }
  }
  
  // 처리된 텍스트 위젯 (번역 완료된 상태)
  Widget _buildProcessedTextWidget(BuildContext context, ProcessedText processedText, NoteDetailViewModel viewModel) {
    // FlashCardViewModel 생성 (기존 flashCards 리스트로 초기화)
    final flashCardViewModel = FlashCardViewModel(
      noteId: widget.noteId,
      initialFlashcards: widget.flashCards,
    );
    
    return ProcessedTextWidget(
      processedText: processedText,
      onDictionaryLookup: (word) => _handleDictionaryLookup(context, word),
      onCreateFlashCard: widget.onCreateFlashCard,
      flashCardViewModel: flashCardViewModel,
      onPlayTts: widget.onPlayTts,
      playingSegmentIndex: null, // TTS 재생 인덱스는 별도 관리 필요
      showTypewriterEffect: false, // 번역 완료된 상태에서는 타이프라이터 효과 사용안함
    );
  }
  
  // 타이프라이터 효과 전용 위젯 (1차 ProcessedText용)
  Widget _buildTypewriterOnlyWidget(BuildContext context, ProcessedText processedText) {
    if (kDebugMode) {
      print('🎬 NotePageWidget _buildTypewriterOnlyWidget');
      print('   units 개수: ${processedText.units.length}');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 세그먼트별 타이프라이터 효과
        ...processedText.units.asMap().entries.map((entry) {
          final index = entry.key;
          final unit = entry.value;
          
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TypewriterText(
                text: unit.originalText,
                style: TypographyTokens.subtitle1Cn.copyWith(color: ColorTokens.textPrimary),
                duration: const Duration(milliseconds: 50),
                delay: Duration(milliseconds: index * 300), // 세그먼트별 지연
              ),
              if (index < processedText.units.length - 1) // 마지막이 아니면 구분선
                const Padding(
                  padding: EdgeInsets.only(top: 16.0, bottom: 16.0),
                  child: Divider(height: 1, thickness: 1, color: ColorTokens.dividerLight),
                ),
            ],
          );
        }).toList(),
      ],
    );
  }
  
  // 로딩 인디케이터 (처리 중 상태 공통 사용)
  Widget _buildLoadingIndicator() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 32.0),
        child: DotLoadingIndicator(message: '텍스트를 처리하고 있습니다'),
      ),
    );
  }
  
  // 오류 위젯
  Widget _buildErrorWidget(String? errorMessage) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              errorMessage ?? '텍스트 처리 중 오류가 발생했습니다.',
              style: TypographyTokens.body2.copyWith(color: Colors.red[800]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  // 사전 검색 처리
  void _handleDictionaryLookup(BuildContext context, String word) {
    if (word.isEmpty) return;
    
    if (kDebugMode) {
      print('사전 검색: $word');
    }
    
    DictionaryResultWidget.searchAndShowDictionary(
      context: context,
      word: word,
      onCreateFlashCard: widget.onCreateFlashCard ?? (_, __, {pinyin}) {},
      onEntryFound: (entry) {
        if (kDebugMode) {
          print('사전 검색 결과: ${entry.word} - ${entry.meaning}');
        }
      },
      onNotFound: () {
        if (kDebugMode) {
          print('사전 검색 결과 없음: $word');
        }
      },
    );
  }
}
