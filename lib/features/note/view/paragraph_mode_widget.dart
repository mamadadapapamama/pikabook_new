import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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

  const ParagraphModeWidget({
    Key? key,
    required this.processedText,
    required this.flashcardWords,
    required this.selectedText,
    required this.selectedTextNotifier,
    required this.onSelectionChanged,
    this.onDictionaryLookup,
    this.onCreateFlashCard,
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

  /// 스타일 초기화
  void _initializeStyles() {
    _defaultOriginalTextStyle = TypographyTokens.subtitle2Cn.copyWith(
      color: ColorTokens.black,
      fontWeight: FontWeight.w200,
    );

    _defaultTranslatedTextStyle = TypographyTokens.caption.copyWith(
      color: ColorTokens.textDarkGrey,
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
    final units = widget.processedText.units;

    if (kDebugMode) {
      debugPrint('🔍 ParagraphModeWidget: ${units.length}개 유닛 렌더링');
      for (int i = 0; i < units.length && i < 5; i++) {
        final unit = units[i];
        final preview = unit.originalText.length > 20 
            ? '${unit.originalText.substring(0, 20)}...' 
            : unit.originalText;
        debugPrint('  유닛 $i: segmentType=${unit.segmentType.name}, text="$preview"');
      }
    }

    for (int i = 0; i < units.length; i++) {
      final unit = units[i];
      
      // 배경색이 필요한 블록인지 확인 (타입 추론 포함)
      final inferredType = _inferSegmentType(unit);
      if (_needsBackground(inferredType)) {
        // 연속된 배경 블록들을 그룹화
        final groupedUnits = _getConsecutiveBackgroundUnits(units, i);
        
        // 각 블록 그룹마다 한줄 띄어쓰기 (첫 번째 블록 제외)
        if (blockWidgets.isNotEmpty) {
          blockWidgets.add(const SizedBox(height: 16));
        }
        
        // 그룹화된 배경 블록 생성
        blockWidgets.add(_buildGroupedBackgroundBlock(groupedUnits));
        
        // 인덱스를 그룹 크기만큼 건너뛰기
        i = i + groupedUnits.length - 1;
      } else {
        // 일반 블록 처리
        if (blockWidgets.isNotEmpty) {
          blockWidgets.add(const SizedBox(height: 16));
        }
        blockWidgets.add(_buildBlockWidget(unit));
      }
    }

    // 스트리밍 중이거나 준비 중일 때 로딩 점 표시
    final shouldShowLoading = widget.processedText.isStreaming || 
                             widget.processedText.streamingStatus == StreamingStatus.preparing;
    
    if (shouldShowLoading) {
      blockWidgets.add(const SizedBox(height: 16));
      blockWidgets.add(LoadingDotsWidget(
        style: _defaultTranslatedTextStyle.copyWith(
          color: ColorTokens.textDarkGrey,
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

  /// 배경색이 필요한 블록 타입인지 확인
  bool _needsBackground(SegmentType segmentType) {
    return segmentType == SegmentType.instruction ||
           segmentType == SegmentType.passage ||
           segmentType == SegmentType.title;
  }

  /// segmentType이 unknown인 경우 텍스트 내용으로 타입 추론
  SegmentType _inferSegmentType(TextUnit unit) {
    if (unit.segmentType != SegmentType.unknown) {
      return unit.segmentType;
    }

    final text = unit.originalText.trim();
    
    // 제목 패턴 감지
    if (text.length <= 15 && !text.contains('。') && !text.contains('？') && !text.contains('！')) {
      if (kDebugMode) {
        debugPrint('🔍 제목으로 추론: "$text"');
      }
      return SegmentType.title;
    }
    
    // 지시사항 패턴 감지
    if (text.contains('请') || text.contains('阅读') || text.contains('听') || text.contains('看') || 
        text.contains('根据') || text.contains('按照') || text.contains('完成')) {
      if (kDebugMode) {
        debugPrint('🔍 지시사항으로 추론: "$text"');
      }
      return SegmentType.instruction;
    }
    
    // 본문 패턴 감지 (긴 텍스트)
    if (text.length > 30) {
      if (kDebugMode) {
        debugPrint('🔍 본문으로 추론: "$text"');
      }
      return SegmentType.passage;
    }
    
    // 기본값은 unknown 유지
    return SegmentType.unknown;
  }

  /// 연속된 배경 블록들을 그룹화
  List<TextUnit> _getConsecutiveBackgroundUnits(List<TextUnit> units, int startIndex) {
    final List<TextUnit> groupedUnits = [];
    
    for (int i = startIndex; i < units.length; i++) {
      final inferredType = _inferSegmentType(units[i]);
      if (_needsBackground(inferredType)) {
        groupedUnits.add(units[i]);
      } else {
        break;
      }
    }
    
    return groupedUnits;
  }

  /// 그룹화된 배경 블록 생성
  Widget _buildGroupedBackgroundBlock(List<TextUnit> units) {
    return _buildBackgroundContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: units.asMap().entries.map((entry) {
          final index = entry.key;
          final unit = entry.value;
          
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 유닛 간 간격 (첫 번째 제외)
              if (index > 0) const SizedBox(height: 12),
              
              // 원문 (타입에 따라 스타일 다르게)
              _buildSelectableOriginalText(
                unit,
                style: unit.segmentType == SegmentType.title 
                    ? TypographyTokens.subtitle1Cn.copyWith(
                        color: ColorTokens.textPrimary,
                        fontWeight: FontWeight.w400,
                      )
                    : _defaultOriginalTextStyle,
              ),

              // 번역
              _buildTranslationText(unit),
            ],
          );
        }).toList(),
      ),
    );
  }

  /// 블록 타입별 위젯 생성
  Widget _buildBlockWidget(TextUnit unit) {
    switch (unit.segmentType) {
      case SegmentType.title:
      case SegmentType.question:
        return _buildBoldTextBlock(unit);
      
      case SegmentType.choices:
        return _buildChoicesBlock(unit);
      
      case SegmentType.instruction:
      case SegmentType.passage:
        return _buildBackgroundBlock(unit);
      
      case SegmentType.vocabulary:
      case SegmentType.answer:
      case SegmentType.dialogue:
      case SegmentType.example:
      case SegmentType.explanation:
      case SegmentType.unknown:
      default:
        return _buildNormalTextBlock(unit);
    }
  }

  /// Bold 텍스트 블록 (title, question)
  Widget _buildBoldTextBlock(TextUnit unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 원문 (title만 bold)
        _buildSelectableOriginalText(
          unit,
          style: unit.segmentType == SegmentType.title 
              ? TypographyTokens.subtitle1Cn.copyWith(
                  color: ColorTokens.textPrimary,
                  fontWeight: FontWeight.w400,
                )
              : _defaultOriginalTextStyle,
        ),

        // 번역
        _buildTranslationText(unit),
      ],
    );
  }

  /// 선택지 블록 (choices)
  Widget _buildChoicesBlock(TextUnit unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSelectableOriginalText(unit),
        _buildTranslationText(unit),
      ],
    );
  }

  /// 배경색이 있는 블록 (instruction, passage)
  Widget _buildBackgroundBlock(TextUnit unit) {
    return _buildBackgroundContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSelectableOriginalText(unit),
          _buildTranslationText(unit),
        ],
      ),
    );
  }

  /// 일반 텍스트 블록 (나머지 타입들)
  Widget _buildNormalTextBlock(TextUnit unit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSelectableOriginalText(unit),
        _buildTranslationText(unit),
      ],
    );
  }

  /// 공통 - 선택 가능한 원문 텍스트 생성
  Widget _buildSelectableOriginalText(TextUnit unit, {TextStyle? style}) {
    return ContextMenuManager.buildSelectableText(
      unit.originalText,
      style: style ?? _defaultOriginalTextStyle,
      isOriginal: true,
      flashcardWords: widget.flashcardWords,
      selectedText: widget.selectedText,
      selectedTextNotifier: widget.selectedTextNotifier,
      onSelectionChanged: widget.onSelectionChanged,
      onDictionaryLookup: widget.onDictionaryLookup,
      onCreateFlashCard: widget.onCreateFlashCard,
    );
  }

  /// 공통 - 번역 텍스트 생성
  Widget _buildTranslationText(TextUnit unit) {
    final hasTranslation = unit.translatedText != null && unit.translatedText!.isNotEmpty;
    
    if (!hasTranslation) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Text(
        unit.translatedText!,
        style: _defaultTranslatedTextStyle,
      ),
    );
  }

  /// 공통 - 배경 컨테이너 생성
  Widget _buildBackgroundContainer({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: ColorTokens.secondaryVeryLight,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: child,
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