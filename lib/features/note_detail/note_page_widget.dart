import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import '../../core/models/page.dart' as page_model;
import '../../core/models/flash_card.dart';
import '../../core/models/processed_text.dart';
import '../../core/theme/tokens/spacing_tokens.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import '../../core/widgets/dot_loading_indicator.dart';
import '../note_detail/view_model/text_view_model.dart';
import 'page_image_widget.dart';
import 'processed_text_widget.dart';
import '../../widgets/dictionary_result_widget.dart';

/// 노트 페이지 위젯: 이미지와 처리된 텍스트를 함께 표시
class NotePageWidget extends StatelessWidget {
  final page_model.Page page;
  final File? imageFile;
  final TextViewModel textViewModel;
  final String noteId;
  final List<FlashCard> flashCards;
  final Function(String, String, {String? pinyin})? onCreateFlashCard;
  final Function(int)? onDeleteSegment;
  final Function(String, {int? segmentIndex})? onPlayTts;
  
  const NotePageWidget({
    Key? key,
    required this.page,
    this.imageFile,
    required this.textViewModel,
    required this.noteId,
    this.flashCards = const [],
    this.onCreateFlashCard,
    this.onDeleteSegment,
    this.onPlayTts,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedBuilder(
          animation: textViewModel,
          builder: (context, _) {
            return _buildPageContent(context, constraints);
          },
        );
      },
    );
  }
  
  Widget _buildPageContent(BuildContext context, BoxConstraints constraints) {
    final TextViewState state = textViewModel.state;
    
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
            isLoading: textViewModel.isLoading,
            enableFullScreen: true,
          ),
          
          SizedBox(height: SpacingTokens.md),
          
          // 텍스트 로딩 상태에 따른 콘텐츠 위젯
          _buildContentBasedOnState(context, state),
        ],
      ),
    );
  }
  
  // 상태에 따른 콘텐츠 위젯 반환
  Widget _buildContentBasedOnState(BuildContext context, TextViewState state) {
    if (state.isReady) {
      return _buildProcessedTextWidget(context);
    } else if (textViewModel.isLoading) {
      return _buildLoadingIndicator();
    } else if (state.hasError) {
      return _buildErrorWidget(state.errorMsg);
    } else {
      return _buildEmptyStateWidget();
    }
  }
  
  // 처리된 텍스트 위젯
  Widget _buildProcessedTextWidget(BuildContext context) {
    final processedText = textViewModel.processedText;
    if (processedText == null) {
      return const SizedBox.shrink();
    }
    
    return ProcessedTextWidget(
      processedText: processedText,
      onDictionaryLookup: (word) => _handleDictionaryLookup(context, word),
      onCreateFlashCard: onCreateFlashCard,
      flashCards: flashCards,
      onDeleteSegment: onDeleteSegment,
      onPlayTts: onPlayTts,
      playingSegmentIndex: textViewModel.playingSegmentIndex,
      originalTextStyle: TypographyTokens.body1Cn,
      pinyinTextStyle: TypographyTokens.caption.copyWith(color: Colors.grey[600]),
      translatedTextStyle: TypographyTokens.body2.copyWith(color: Colors.grey[800]),
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
  
  // 빈 상태 위젯
  Widget _buildEmptyStateWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.text_snippet_outlined, color: Colors.grey[400], size: 48),
            const SizedBox(height: 16),
            Text(
              '텍스트 처리 대기 중',
              style: TypographyTokens.body2.copyWith(color: Colors.grey[700]),
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
