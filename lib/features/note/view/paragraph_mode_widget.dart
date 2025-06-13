import 'package:flutter/material.dart';
import '../../../core/models/processed_text.dart';
import '../../../core/models/text_unit.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/widgets/loading_dots_widget.dart';
import '../../../core/widgets/dot_loading_indicator.dart';
import '../../../core/utils/context_menu_manager.dart';

/// 문단 모드 전용 위젯
/// LLM에서 리턴하는 다양한 블록 타입과 추가 정보를 처리합니다.
class ParagraphModeWidget extends StatefulWidget {
  final ProcessedText processedText;
  final Set<String> flashcardWords;
  final String selectedText;
  final ValueNotifier<String> selectedTextNotifier;
  final Function(String) onSelectionChanged;
  final Function(String)? onDictionaryLookup;
  final Function(String, String, {String? pinyin})? onCreateFlashCard;
  final bool showTtsButtons;
  final int? playingSegmentIndex;
  final Function(String, {int? segmentIndex})? onPlayTts;

  const ParagraphModeWidget({
    Key? key,
    required this.processedText,
    required this.flashcardWords,
    required this.selectedText,
    required this.selectedTextNotifier,
    required this.onSelectionChanged,
    this.onDictionaryLookup,
    this.onCreateFlashCard,
    this.showTtsButtons = true,
    this.playingSegmentIndex,
    this.onPlayTts,
  }) : super(key: key);

  @override
  State<ParagraphModeWidget> createState() => _ParagraphModeWidgetState();
}

class _ParagraphModeWidgetState extends State<ParagraphModeWidget> {
  // 스타일 정의
  late TextStyle _defaultOriginalTextStyle;
  late TextStyle _defaultTranslatedTextStyle;

  @override
  void initState() {
    super.initState();
    _initializeStyles();
  }

  @override
  void dispose() {
    super.dispose();
  }

  /// 스타일 초기화
  void _initializeStyles() {
    _defaultOriginalTextStyle = TypographyTokens.subtitle1Cn.copyWith(
      color: ColorTokens.textPrimary,
    );

    _defaultTranslatedTextStyle = TypographyTokens.caption.copyWith(
      color: ColorTokens.textGrey,
      height: 1.5,
    );
  }



  @override
  Widget build(BuildContext context) {
    // units가 있으면 블록 타입별로 렌더링, 없으면 로딩 표시
    if (widget.processedText.units.isNotEmpty) {
      return _buildBlockView();
    } else {
      // LLM 응답 대기 중이면 로딩 표시
      return _buildLoadingView();
    }
  }

  /// 블록 타입별 UI 렌더링
  Widget _buildBlockView() {
    final List<Widget> blockWidgets = [];

    for (int i = 0; i < widget.processedText.units.length; i++) {
      final unit = widget.processedText.units[i];
      
      // 각 블록 타입마다 한줄 띄어쓰기 (첫 번째 블록 제외)
      if (i > 0) {
        blockWidgets.add(const SizedBox(height: 16));
      }
      
      // 블록 타입별 위젯 생성
      blockWidgets.add(_buildBlockWidget(unit, i));
    }

    // 스트리밍 중이거나 준비 중일 때 로딩 점 표시
    final shouldShowLoading = widget.processedText.isStreaming || 
                             widget.processedText.streamingStatus == StreamingStatus.preparing;
    
    if (shouldShowLoading) {
      blockWidgets.add(const SizedBox(height: 16));
      blockWidgets.add(LoadingDotsWidget(
        style: _defaultTranslatedTextStyle.copyWith(
          color: ColorTokens.textGrey,
          fontSize: 16,
        ),
        usePinyinStyle: false,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blockWidgets,
    );
  }

  /// 블록 타입별 위젯 생성
  Widget _buildBlockWidget(TextUnit unit, int index) {
    switch (unit.segmentType) {
      case SegmentType.title:
      case SegmentType.question:
        return _buildBoldTextBlock(unit, index);
      
      case SegmentType.choices:
        return _buildChoicesBlock(unit, index);
      
      case SegmentType.instruction:
      case SegmentType.passage:
        return _buildBackgroundBlock(unit, index);
      
      case SegmentType.vocabulary:
      case SegmentType.answer:
      case SegmentType.dialogue:
      case SegmentType.example:
      case SegmentType.explanation:
      case SegmentType.unknown:
      default:
        return _buildNormalTextBlock(unit, index);
    }
  }

  /// Bold 텍스트 블록 (title, question)
  Widget _buildBoldTextBlock(TextUnit unit, int index) {
    final hasTranslation = unit.translatedText != null && unit.translatedText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 원문 (Bold, TTS 버튼 없음)
        ContextMenuManager.buildSelectableText(
          unit.originalText,
          style: unit.segmentType == SegmentType.title 
              ? TypographyTokens.headline3Cn.copyWith(
                  color: ColorTokens.textPrimary,
                  fontWeight: FontWeight.bold,
                )
              : _defaultOriginalTextStyle.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          isOriginal: true,
          flashcardWords: widget.flashcardWords,
          selectedText: widget.selectedText,
          selectedTextNotifier: widget.selectedTextNotifier,
          onSelectionChanged: widget.onSelectionChanged,
          onDictionaryLookup: widget.onDictionaryLookup,
          onCreateFlashCard: widget.onCreateFlashCard,
        ),

        // 번역 (일반 스타일로 통일)
        if (hasTranslation)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              unit.translatedText!,
              style: _defaultTranslatedTextStyle,
            ),
          ),
      ],
    );
  }

  /// 선택지 블록 (choices) - 한줄로 표시
  Widget _buildChoicesBlock(TextUnit unit, int index) {
    final hasTranslation = unit.translatedText != null && unit.translatedText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 원문 (한줄로 표시, TTS 버튼 없음)
        ContextMenuManager.buildSelectableText(
          unit.originalText,
          style: _defaultOriginalTextStyle,
          isOriginal: true,
          flashcardWords: widget.flashcardWords,
          selectedText: widget.selectedText,
          selectedTextNotifier: widget.selectedTextNotifier,
          onSelectionChanged: widget.onSelectionChanged,
          onDictionaryLookup: widget.onDictionaryLookup,
          onCreateFlashCard: widget.onCreateFlashCard,
        ),

        // 번역 (한줄로 표시)
        if (hasTranslation)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              unit.translatedText!,
              style: _defaultTranslatedTextStyle,
            ),
          ),
      ],
    );
  }

  /// 배경색이 있는 블록 (instruction, passage)
  Widget _buildBackgroundBlock(TextUnit unit, int index) {
    final hasTranslation = unit.translatedText != null && unit.translatedText!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: ColorTokens.secondaryVeryLight,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 원문
          ContextMenuManager.buildSelectableText(
            unit.originalText,
            style: _defaultOriginalTextStyle,
            isOriginal: true,
            flashcardWords: widget.flashcardWords,
            selectedText: widget.selectedText,
            selectedTextNotifier: widget.selectedTextNotifier,
            onSelectionChanged: widget.onSelectionChanged,
            onDictionaryLookup: widget.onDictionaryLookup,
            onCreateFlashCard: widget.onCreateFlashCard,
          ),

          // 번역
          if (hasTranslation)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                unit.translatedText!,
                style: _defaultTranslatedTextStyle,
              ),
            ),
        ],
      ),
    );
  }

  /// 일반 텍스트 블록 (나머지 타입들)
  Widget _buildNormalTextBlock(TextUnit unit, int index) {
    final hasTranslation = unit.translatedText != null && unit.translatedText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 원문 (TTS 버튼 없음)
        ContextMenuManager.buildSelectableText(
          unit.originalText,
          style: _defaultOriginalTextStyle,
          isOriginal: true,
          flashcardWords: widget.flashcardWords,
          selectedText: widget.selectedText,
          selectedTextNotifier: widget.selectedTextNotifier,
          onSelectionChanged: widget.onSelectionChanged,
          onDictionaryLookup: widget.onDictionaryLookup,
          onCreateFlashCard: widget.onCreateFlashCard,
        ),

        // 번역
        if (hasTranslation)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              unit.translatedText!,
              style: _defaultTranslatedTextStyle,
            ),
          ),
      ],
    );
  }

  /// LLM 응답 대기 중 로딩 표시
  Widget _buildLoadingView() {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 32.0),
        child: DotLoadingIndicator(message: '🧐 텍스트를 분석하고 있습니다...'),
      ),
    );
  }


} 