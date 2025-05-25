import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../../../core/models/text_unit.dart';
import '../../../core/models/processed_text.dart';
import '../../../core/models/processing_status.dart';
import '../view_model/note_detail_viewmodel.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../core/models/flash_card.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/widgets/dot_loading_indicator.dart';
import '../../flashcard/flashcard_view_model.dart';
import 'page_image_widget.dart';
import 'processed_text_widget.dart';
import '../../dictionary/dictionary_result_widget.dart';

/// 노트 페이지 위젯: 이미지와 처리된 텍스트를 함께 표시
class NotePageWidget extends StatelessWidget {
  final page_model.Page page;
  final File? imageFile;
  final String noteId;
  final List<FlashCard> flashCards;
  final Function(String, String, {String? pinyin})? onCreateFlashCard;
  final Function(int)? onDeleteSegment;
  final Function(String, {int? segmentIndex})? onPlayTts;
  
  const NotePageWidget({
    Key? key,
    required this.page,
    this.imageFile,
    required this.noteId,
    this.flashCards = const [],
    this.onCreateFlashCard,
    this.onDeleteSegment,
    this.onPlayTts,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<NoteDetailViewModel>(
      builder: (context, viewModel, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            return _buildPageContent(context, constraints, viewModel);
          },
        );
      },
    );
  }
  
  Widget _buildPageContent(BuildContext context, BoxConstraints constraints, NoteDetailViewModel viewModel) {
    // 현재 페이지의 텍스트 데이터 가져오기
    final textData = viewModel.getTextViewModel(page.id);
    final processedText = textData['processedText'] as ProcessedText?;
    final isLoading = textData['isLoading'] as bool? ?? false;
    final error = textData['error'] as String?;
    final status = textData['status'] as ProcessingStatus? ?? ProcessingStatus.created;
    
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
            imageFile: imageFile,
            imageUrl: page.imageUrl,
            page: page,
            style: ImageContainerStyle.noteDetail,
            isLoading: isLoading,
            enableFullScreen: true,
          ),
          
          SizedBox(height: SpacingTokens.md),
          
          // 텍스트 로딩 상태에 따른 콘텐츠 위젯
          _buildContentBasedOnState(context, processedText, isLoading, error, status),
        ],
      ),
    );
  }
  
  // 상태에 따른 콘텐츠 위젯 반환
  Widget _buildContentBasedOnState(BuildContext context, ProcessedText? processedText, bool isLoading, String? error, ProcessingStatus status) {
    if (kDebugMode) {
      print('NotePageWidget - 상태 확인: processedText=${processedText != null ? "있음" : "없음"}, isLoading=$isLoading, error=$error, status=$status');
      if (processedText != null) {
        print('ProcessedText 내용: 원문=${processedText.fullOriginalText.length}자, 번역=${processedText.fullTranslatedText.length}자');
      }
    }
    
    if (processedText != null) {
      return _buildProcessedTextWidget(context, processedText);
    } else if (isLoading || status.isProcessing) {
      return _buildLoadingIndicator();
    } else if (error != null) {
      return _buildErrorWidget(error);
    } else {
      return _buildEmptyStateWidget();
    }
  }
  
  // 처리된 텍스트 위젯
  Widget _buildProcessedTextWidget(BuildContext context, ProcessedText processedText) {
    // FlashCardViewModel 생성 (기존 flashCards 리스트로 초기화)
    final flashCardViewModel = FlashCardViewModel(
      noteId: noteId,
      initialFlashcards: flashCards,
    );
    
    return Consumer<NoteDetailViewModel>(
      builder: (context, viewModel, child) {
        final textData = viewModel.getTextViewModel(page.id);
        final playingSegmentIndex = textData['playingSegmentIndex'] as int?;
        
        return ProcessedTextWidget(
          processedText: processedText,
          onDictionaryLookup: (word) => _handleDictionaryLookup(context, word),
          onCreateFlashCard: onCreateFlashCard,
          flashCardViewModel: flashCardViewModel,
          onDeleteSegment: onDeleteSegment,
          onPlayTts: onPlayTts,
          playingSegmentIndex: playingSegmentIndex,
          originalTextStyle: TypographyTokens.body1Cn,
          pinyinTextStyle: TypographyTokens.caption.copyWith(color: Colors.grey[600]),
          translatedTextStyle: TypographyTokens.body2.copyWith(color: Colors.grey[800]),
        );
      },
    );
  }
  
  // 로딩 인디케이터
  Widget _buildLoadingIndicator() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 32.0),
        child: DotLoadingIndicator(message: '텍스트 처리 중...'),
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
  
  // 빈 상태 위젯 - 로딩 인디케이터와 통일
  Widget _buildEmptyStateWidget() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 32.0),
        child: DotLoadingIndicator(message: '텍스트를 처리하고 있습니다'),
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
      onCreateFlashCard: onCreateFlashCard ?? (_, __, {pinyin}) {},
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
