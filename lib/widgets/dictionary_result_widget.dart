import 'package:flutter/material.dart';
import '../features/note_detail/managers/segment_manager.dart';
import '../core/models/dictionary.dart';
import '../core/theme/tokens/color_tokens.dart';
import '../core/theme/tokens/typography_tokens.dart';
import '../core/theme/tokens/spacing_tokens.dart';
import '../core/theme/tokens/ui_tokens.dart';
import '../core/widgets/pika_button.dart';
import '../core/widgets/tts_button.dart';
import '../core/services/media/tts_service.dart';

/// 사전 검색 결과를 표시하는 바텀 시트 위젯

class DictionaryResultWidget extends StatefulWidget {
  final DictionaryEntry entry;
  final Function(String, String, {String? pinyin}) onCreateFlashCard;
  final bool isExistingFlashcard;

  const DictionaryResultWidget({
    super.key,
    required this.entry,
    required this.onCreateFlashCard,
    this.isExistingFlashcard = false,
  });

  @override
  State<DictionaryResultWidget> createState() => _DictionaryResultWidgetState();
}

class _DictionaryResultWidgetState extends State<DictionaryResultWidget> {
  final TtsService _ttsService = TtsService();
  bool _isSpeaking = false;
  bool _ttsEnabled = true;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      await _ttsService.init();
      final isAvailable = await _ttsService.isTtsAvailable();
      if (mounted) {
        setState(() {
          _ttsEnabled = isAvailable;
        });
      }
    } catch (e) {
      debugPrint('TTS 초기화 오류: $e');
    }
  }

  @override
  void dispose() {
    _ttsService.dispose();
    super.dispose();
  }

  Future<void> _speakText(String text) async {
    if (_isSpeaking) {
      await _stopSpeaking();
      return;
    }

    if (!_ttsEnabled) return;

    setState(() {
      _isSpeaking = true;
    });

    try {
      await _ttsService.setLanguage('zh-CN');
      await _ttsService.speak(text);
    } catch (e) {
      debugPrint('TTS 실행 오류: $e');
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('음성 재생 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  Future<void> _stopSpeaking() async {
    if (!_isSpeaking) return;

    try {
      await _ttsService.stop();
    } catch (e) {
      debugPrint('TTS 중지 오류: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(SpacingTokens.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 단어와 TTS 버튼
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.entry.word,
                  style: TypographyTokens.headline2Cn.copyWith(
                    color: ColorTokens.textPrimary,
                  ),
                ),
              ),
              TtsButton(
                text: widget.entry.word,
                size: TtsButton.sizeMedium,
                tooltip: !_ttsEnabled ? '무료 TTS 사용량을 모두 사용했습니다.' : null,
                iconColor: ColorTokens.secondary,
                activeBackgroundColor: ColorTokens.primary.withOpacity(0.2),
                onPlayStart: () => _speakText(widget.entry.word),
                onPlayEnd: _stopSpeaking,
              ),
            ],
          ),
          
          // 핀인
          if (widget.entry.pinyin.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: SpacingTokens.sm),
              child: Text(
                widget.entry.pinyin,
                style: TypographyTokens.caption.copyWith(
                  color: ColorTokens.textGrey,
                  fontFamily: TypographyTokens.poppins,
                ),
              ),
            ),
          
          // 의미
          if (widget.entry.meaning.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: SpacingTokens.sm),
              child: Text(
                widget.entry.meaning,
                style: TypographyTokens.body1.copyWith(
                  color: ColorTokens.secondary,
                ),
              ),
            ),
          
          SizedBox(height: SpacingTokens.lg),
          
          // 플래시카드 추가 버튼
          PikaButton(
            text: widget.isExistingFlashcard ? '플래시카드로 설정됨' : '플래시카드 추가',
            variant: widget.isExistingFlashcard ? PikaButtonVariant.primary : PikaButtonVariant.primary,
            leadingIcon: !widget.isExistingFlashcard 
              ? Image.asset(
                  'assets/images/icon_flashcard_dic.png',
                  width: 24,
                  height: 24,
                )
              : null,
            onPressed: widget.isExistingFlashcard
                ? null
                : () {
                    widget.onCreateFlashCard(
                      widget.entry.word,
                      widget.entry.meaning,
                      pinyin: widget.entry.pinyin,
                    );
                    Navigator.pop(context);

                    // 추가 완료 메시지
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('플래시카드에 추가되었습니다'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
            isFullWidth: true,
          ),
        ],
      ),
    );
  }

  /// 사전 결과 바텀 시트 표시 헬퍼 메서드
  static void showDictionaryBottomSheet({
    required BuildContext context,
    required DictionaryEntry entry,
    required Function(String, String, {String? pinyin}) onCreateFlashCard,
    bool isExistingFlashcard = false,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: ColorTokens.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SpacingTokens.lg),
          ),
        ),
        child: DictionaryResultWidget(
          entry: entry,
          onCreateFlashCard: onCreateFlashCard,
          isExistingFlashcard: isExistingFlashcard,
        ),
      ),
    );
  }
}
