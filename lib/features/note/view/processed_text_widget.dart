import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../../core/models/processed_text.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/services/tts/tts_service.dart';
import '../../flashcard/flashcard_view_model.dart';
import '../../../core/widgets/typewriter_text.dart';

/// ProcessedTextWidget은 처리된 텍스트(중국어 원문, 병음, 번역)를 표시하는 위젯입니다.

class ProcessedTextWidget extends StatefulWidget {
  final ProcessedText processedText;
  final Function(String)? onDictionaryLookup;
  final Function(String, String, {String? pinyin})? onCreateFlashCard;
  final FlashCardViewModel? flashCardViewModel;
  final Function(String, {int? segmentIndex})? onPlayTts;
  final int? playingSegmentIndex;
  final TextStyle? originalTextStyle;
  final TextStyle? pinyinTextStyle;
  final TextStyle? translatedTextStyle;
  final bool showTtsButtons;
  final bool showTypewriterEffect; // 타이프라이터 효과 여부

  const ProcessedTextWidget({
    Key? key,
    required this.processedText,
    this.onDictionaryLookup,
    this.onCreateFlashCard,
    this.flashCardViewModel,
    this.onPlayTts,
    this.playingSegmentIndex,
    this.originalTextStyle,
    this.pinyinTextStyle,
    this.translatedTextStyle,
    this.showTtsButtons = true,
    this.showTypewriterEffect = false,
  }) : super(key: key);

  @override
  State<ProcessedTextWidget> createState() => _ProcessedTextWidgetState();
}

class _ProcessedTextWidgetState extends State<ProcessedTextWidget> {
  String _selectedText = '';

  // 선택된 텍스트 상태 관리를 위한 ValueNotifier
  final ValueNotifier<String> _selectedTextNotifier = ValueNotifier<String>('');

  // TTS 서비스
  final TTSService _ttsService = TTSService();
  
  // 기본 스타일 정의 (내부에서 관리)
  TextStyle get _defaultOriginalTextStyle => widget.originalTextStyle ?? TypographyTokens.subtitle1Cn.copyWith (color:ColorTokens.textPrimary);
  TextStyle get _defaultPinyinTextStyle => widget.pinyinTextStyle ?? TypographyTokens.caption.copyWith(color: Colors.grey[800]);
  TextStyle get _defaultTranslatedTextStyle => widget.translatedTextStyle ?? TypographyTokens.body2.copyWith(color: ColorTokens.textSecondary);
  
  @override
  void initState() {
    super.initState();
    _initTts();
  }

  /// TTS 초기화
  Future<void> _initTts() async {
    try {
      await _ttsService.init();
      
      // TTS 상태 변경 리스너 설정
      _ttsService.setOnPlayingStateChanged((segmentIndex) {
        if (mounted) {
          setState(() {
            // 상태 업데이트는 widget.playingSegmentIndex를 통해 부모에서 관리
          });
        }
      });
      
      // TTS 재생 완료 리스너 설정
      _ttsService.setOnPlayingCompleted(() {
        if (mounted) {
          setState(() {
            // 재생 완료 시 상태 리셋
          });
        }
      });
    } catch (e) {
      debugPrint('TTS 초기화 실패: $e');
    }
  }

  @override
  void dispose() {
    _selectedTextNotifier.dispose(); // ValueNotifier 정리
    super.dispose();
  }

  @override
  void didUpdateWidget(ProcessedTextWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ProcessedText 변경 감지
    if (oldWidget.processedText != widget.processedText) {
      debugPrint('처리된 텍스트 변경 감지: didUpdateWidget');
      
      // 선택된 텍스트 초기화
      setState(() {
        _selectedText = '';
        _selectedTextNotifier.value = '';
      });
    }
    
    // 표시 설정 변경 감지 - 개별 속성 확인
    if (oldWidget.processedText.displayMode != widget.processedText.displayMode) {
      debugPrint('표시 모드 변경 감지: ${oldWidget.processedText.displayMode} -> ${widget.processedText.displayMode}');
      setState(() {});
    }
  }

  /// 선택된 텍스트 변경 핸들러
  void _handleSelectionChanged(String text) {
    if (mounted) {
      setState(() {
        _selectedText = text;
      });
    }
  }

  /// TTS 재생 토글
  Future<void> _toggleTts(String text, int segmentIndex) async {
    try {
      // 현재 재생 중인 세그먼트인지 확인
      final bool isCurrentlyPlaying = widget.playingSegmentIndex == segmentIndex;
      
      if (isCurrentlyPlaying) {
        // 재생 중이면 중지
        await _ttsService.stop();
        if (widget.onPlayTts != null) {
          widget.onPlayTts!('', segmentIndex: null);
        }
      } else {
        // 재생 시작
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

  /// **전체 텍스트 표시** → **문단별 텍스트 표시**
  Widget _buildFullTextView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 원문 텍스트 표시
        SelectableText(
          widget.processedText.fullOriginalText,
          style: _defaultOriginalTextStyle,
        ),
        const SizedBox(height: 16),
        
        // 번역 텍스트 표시 - 래퍼 제거하고 직접 표시
        if (widget.processedText.fullTranslatedText != null &&
            widget.processedText.fullTranslatedText!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            child: Text(
              widget.processedText.fullTranslatedText!,
              style: _defaultTranslatedTextStyle,
            ),
          ),
      ],
    );
  }

  /// 세그먼트 단위 표시 (타이프라이터 효과 지원)
  Widget _buildSegmentView() {
    final List<Widget> unitWidgets = [];

    for (int i = 0; i < widget.processedText.units.length; i++) {
      final unit = widget.processedText.units[i];
      final isPlaying = widget.playingSegmentIndex == i;
      final hasTranslation = unit.translatedText != null && unit.translatedText!.isNotEmpty;

      // 세그먼트 컨테이너
      Widget segmentContainer = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 원문 표시 (타이프라이터 효과 또는 일반 텍스트)
          Row(
            children: [
              Expanded(
                child: widget.showTypewriterEffect
                    ? TypewriterText(
                        text: unit.originalText,
                        style: _defaultOriginalTextStyle,
                        duration: const Duration(milliseconds: 50),
                        delay: Duration(milliseconds: i * 300), // 세그먼트별 지연
                      )
                    : SelectableText(
                        unit.originalText,
                        style: _defaultOriginalTextStyle,
                        onSelectionChanged: (selection, cause) {
                          final selectedText = unit.originalText.substring(
                            selection.start,
                            selection.end,
                          );
                          _handleSelectionChanged(selectedText);
                        },
                      ),
              ),
              if (widget.showTtsButtons) _buildTtsButton(unit.originalText, i, isPlaying),
            ],
          ),

          // 병음 표시 (번역이 있는 경우에만)
          if (widget.processedText.displayMode == TextDisplayMode.full &&
              unit.pinyin != null &&
              unit.pinyin!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Text(
                unit.pinyin!,
                style: _defaultPinyinTextStyle,
              ),
            ),

          // 번역 표시 (번역이 있는 경우에만)
          if (hasTranslation)
            Padding(
              padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
              child: Text(
                unit.translatedText!,
                style: _defaultTranslatedTextStyle,
              ),
            ),
        ],
      );
      
      unitWidgets.add(segmentContainer);
      
      // 구분선 추가 (마지막 유닛이 아닌 경우)
      if (i < widget.processedText.units.length - 1) {
        unitWidgets.add(
          const Padding(
            padding: EdgeInsets.only(top: 16.0, bottom: 16.0),
            child: Divider(height: 1, thickness: 1, color: ColorTokens.dividerLight),
          ),
        );
      }
    }

    // 세그먼트 위젯이 없으면 전체 텍스트 표시
    if (unitWidgets.isEmpty) {
      return _buildFullTextView();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: unitWidgets,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 문장별 모드인지 문단별 모드인지에 따라 다른 렌더링
    final bool isParagraphMode = widget.processedText.mode == TextProcessingMode.paragraph;

    // 로딩 확인용
    if (kDebugMode) {
      print('[${DateTime.now()}] ProcessedTextWidget build 호출');
      print('ProcessedTextWidget 모드: ${widget.processedText.mode}, 표시 모드: ${widget.processedText.displayMode}');
      print('문단 모드: $isParagraphMode, 유닛 개수: ${widget.processedText.units.length}');
    }
    
    // 번역 텍스트 체크 로그 추가
    if (widget.processedText.fullTranslatedText != null && widget.processedText.fullTranslatedText!.isNotEmpty) {
      final sample = widget.processedText.fullTranslatedText!.length > 50 
          ? widget.processedText.fullTranslatedText!.substring(0, 50) + '...' 
          : widget.processedText.fullTranslatedText!;
      debugPrint('ProcessedTextWidget: 번역 텍스트 있음 (${widget.processedText.fullTranslatedText!.length}자)');
      debugPrint('ProcessedTextWidget: 번역 텍스트 샘플 - "$sample"');
    } else {
      debugPrint('ProcessedTextWidget: 번역 텍스트 없음 (null 또는 빈 문자열)');
    }
    
    // 세그먼트별 번역 체크
    if (widget.processedText.units != null && widget.processedText.units.isNotEmpty) {
      int untranslatedUnits = 0;
      for (final unit in widget.processedText.units) {
        if (unit.translatedText == null || unit.translatedText!.isEmpty || unit.translatedText == unit.originalText) {
          untranslatedUnits++;
        }
      }
      debugPrint('ProcessedTextWidget: 유닛 ${widget.processedText.units.length}개 중 $untranslatedUnits개 번역 누락');
    }

    // 문장 바깥 탭 시 선택 취소를 위한 GestureDetector 추가
    return GestureDetector(
      onTap: () {
        // 문장 바깥을 탭하면 선택 취소
        setState(() {
          _selectedText = '';
        });
      },
      behavior: HitTestBehavior.translucent,
      child: Container(
        color: ColorTokens.surface, // 배경색을 흰색으로 설정
        padding: const EdgeInsets.only(top: 8.0), // 첫 번째 세그먼트를 위한 상단 패딩 추가
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 모드에 따라 다른 위젯 표시 (키 추가)
            // 모드나 설정이 변경될 때 항상 새 위젯을 생성하도록 고유 키 사용
            KeyedSubtree(
              key: ValueKey('processed_text_${widget.processedText.mode}_'
                  '${widget.processedText.displayMode}_'
                  '${widget.processedText.hashCode}'),
              child: widget.processedText.units != null &&
                  widget.processedText.mode == TextProcessingMode.segment
                  ? _buildSegmentView() // 문장별 표시
                  : _buildFullTextView(), // 문단별 표시
            ),
          ],
        ),
      ),
    );
  }
}
