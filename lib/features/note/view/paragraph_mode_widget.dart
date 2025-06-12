import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/models/processed_text.dart';
import '../../../core/models/text_unit.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/services/tts/tts_service.dart';
import '../../../core/services/common/plan_service.dart';
import '../../../core/services/common/usage_limit_service.dart';
import '../../../core/widgets/upgrade_modal.dart';
import '../../tts/slow_tts_button.dart';
import '../../../core/widgets/loading_dots_widget.dart';
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
  late final TTSService _ttsService;
  
  // 스타일 정의
  late TextStyle _defaultOriginalTextStyle;
  late TextStyle _defaultTranslatedTextStyle;

  @override
  void initState() {
    super.initState();
    _ttsService = TTSService();
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

    _defaultTranslatedTextStyle = TypographyTokens.body2.copyWith(
      color: ColorTokens.textSecondary,
      height: 1.5,
    );
  }

  /// TTS 재생 토글
  Future<void> _toggleTts(String text, int segmentIndex) async {
    try {
      // 플랜 체크 먼저 수행
      final planService = PlanService();
      final planType = await planService.getCurrentPlanType();
      
      // 무료 플랜인 경우 업그레이드 모달 표시
      if (planType == PlanService.PLAN_FREE) {
        if (mounted) {
          await UpgradePromptHelper.showTtsUpgradePrompt(context);
        }
        return;
      }
      
      // 프리미엄 플랜이지만 TTS 제한에 도달한 경우 체크
      final usageService = UsageLimitService();
      final limitStatus = await usageService.checkInitialLimitStatus();
      
      if (limitStatus['ttsLimitReached'] == true) {
        if (mounted) {
          await UpgradePromptHelper.showTtsUpgradePrompt(context);
        }
        return;
      }

      // 현재 재생 중인 세그먼트와 같으면 중지
      if (widget.playingSegmentIndex == segmentIndex && _ttsService.state == TtsState.playing) {
        await _ttsService.stop();
        if (widget.onPlayTts != null) {
          widget.onPlayTts!('', segmentIndex: null);
        }
      } else {
        // 새로운 세그먼트 재생
        await _ttsService.speakSegment(text, segmentIndex);
        if (widget.onPlayTts != null) {
          widget.onPlayTts!(text, segmentIndex: segmentIndex);
        }
      }
    } catch (e) {
      debugPrint('TTS 재생 중 오류: $e');
    }
  }

  /// TTS 버튼 위젯 생성
  Widget _buildTtsButton(String text, int segmentIndex, bool isPlaying) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isPlaying 
            ? ColorTokens.primary.withOpacity(0.2)
            : Colors.transparent,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(
          isPlaying ? Icons.stop : Icons.volume_up,
          color: ColorTokens.textSecondary,
          size: 16,
        ),
        onPressed: () => _toggleTts(text, segmentIndex),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 32,
        ),
        splashRadius: 16,
      ),
    );
  }

  /// 느린 TTS 버튼 위젯 생성
  Widget _buildSlowTtsButton(String text, int segmentIndex, bool isPlaying) {
    return SlowTtsButton(
      text: text,
      segmentIndex: segmentIndex,
      size: 24.0,
      isEnabled: true,
      useCircularShape: true,
      iconColor: ColorTokens.textSecondary,
      activeBackgroundColor: ColorTokens.primary.withOpacity(0.2),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      debugPrint('🎨 [문단모드] ParagraphModeWidget build 시작');
      debugPrint('   유닛 개수: ${widget.processedText.units.length}');
      debugPrint('   스트리밍 상태: ${widget.processedText.streamingStatus}');
    }

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
    final isPlaying = widget.playingSegmentIndex == index;
    final hasTranslation = unit.translatedText != null && unit.translatedText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 원문 (Bold)
        Row(
          children: [
            Expanded(
              child: ContextMenuManager.buildSelectableText(
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
            ),
            if (widget.showTtsButtons) ...[
              _buildTtsButton(unit.originalText, index, isPlaying),
              const SizedBox(width: 4),
              _buildSlowTtsButton(unit.originalText, index, isPlaying),
            ],
          ],
        ),

        // 번역 (Bold)
        if (hasTranslation)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              unit.translatedText!,
              style: unit.segmentType == SegmentType.title 
                  ? TypographyTokens.headline3.copyWith(
                      color: ColorTokens.textSecondary,
                      fontWeight: FontWeight.bold,
                    )
                  : _defaultTranslatedTextStyle.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
            ),
          )
        else if (widget.processedText.isStreaming)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: LoadingDotsWidget(
              style: _defaultTranslatedTextStyle,
              usePinyinStyle: false,
            ),
          ),
      ],
    );
  }

  /// 선택지 블록 (choices) - 한줄로 표시
  Widget _buildChoicesBlock(TextUnit unit, int index) {
    final isPlaying = widget.playingSegmentIndex == index;
    final hasTranslation = unit.translatedText != null && unit.translatedText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 원문 (한줄로 표시)
        Row(
          children: [
            Expanded(
              child: ContextMenuManager.buildSelectableText(
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
            ),
            if (widget.showTtsButtons) ...[
              _buildTtsButton(unit.originalText, index, isPlaying),
              const SizedBox(width: 4),
              _buildSlowTtsButton(unit.originalText, index, isPlaying),
            ],
          ],
        ),

        // 번역 (한줄로 표시)
        if (hasTranslation)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              unit.translatedText!,
              style: _defaultTranslatedTextStyle,
            ),
          )
        else if (widget.processedText.isStreaming)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: LoadingDotsWidget(
              style: _defaultTranslatedTextStyle,
              usePinyinStyle: false,
            ),
          ),
      ],
    );
  }

  /// 일반 텍스트 블록 (나머지 타입들)
  Widget _buildNormalTextBlock(TextUnit unit, int index) {
    final isPlaying = widget.playingSegmentIndex == index;
    final hasTranslation = unit.translatedText != null && unit.translatedText!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 원문
        Row(
          children: [
            Expanded(
              child: ContextMenuManager.buildSelectableText(
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
            ),
            if (widget.showTtsButtons) ...[
              _buildTtsButton(unit.originalText, index, isPlaying),
              const SizedBox(width: 4),
              _buildSlowTtsButton(unit.originalText, index, isPlaying),
            ],
          ],
        ),

        // 번역
        if (hasTranslation)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              unit.translatedText!,
              style: _defaultTranslatedTextStyle,
            ),
          )
        else if (widget.processedText.isStreaming)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: LoadingDotsWidget(
              style: _defaultTranslatedTextStyle,
              usePinyinStyle: false,
            ),
          ),
      ],
    );
  }

  /// LLM 응답 대기 중 로딩 표시
  Widget _buildLoadingView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 로딩 메시지
        Text(
          '텍스트를 분석하고 있습니다...',
          style: _defaultTranslatedTextStyle.copyWith(
            color: ColorTokens.textGrey,
          ),
        ),
        const SizedBox(height: 16),
        
        // 로딩 애니메이션
        LoadingDotsWidget(
          style: _defaultTranslatedTextStyle,
          usePinyinStyle: false,
        ),
      ],
    );
  }

  /// 전체 텍스트 표시 (fallback)
  Widget _buildFullTextView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 원문 텍스트 표시
        ContextMenuManager.buildSelectableText(
          widget.processedText.fullOriginalText,
          style: _defaultOriginalTextStyle,
          isOriginal: true,
          flashcardWords: widget.flashcardWords,
          selectedText: widget.selectedText,
          selectedTextNotifier: widget.selectedTextNotifier,
          onSelectionChanged: widget.onSelectionChanged,
          onDictionaryLookup: widget.onDictionaryLookup,
          onCreateFlashCard: widget.onCreateFlashCard,
        ),
        const SizedBox(height: 16),
        
        // 번역 텍스트 표시 (스트리밍 상태 고려)
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 16),
          child: widget.processedText.fullTranslatedText != null &&
                  widget.processedText.fullTranslatedText!.isNotEmpty
              ? Text(
                  widget.processedText.fullTranslatedText!,
                  style: _defaultTranslatedTextStyle,
                )
              : widget.processedText.isStreaming
                  ? LoadingDotsWidget(
                      style: _defaultTranslatedTextStyle,
                      usePinyinStyle: false,
                    )
                  : const SizedBox.shrink(),
        ),
      ],
    );
  }
} 