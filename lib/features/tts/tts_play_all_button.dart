import 'package:flutter/material.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import 'tts_button.dart';

/// 전체 텍스트 TTS 재생 버튼 위젯
class TtsPlayAllButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPlayStart;
  
  const TtsPlayAllButton({
    Key? key,
    required this.text,
    this.onPlayStart,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // TtsButton 위젯 사용
        TtsButton(
          text: text,
          size: TtsButton.sizeSmall,
          iconColor: ColorTokens.secondary,
          activeBackgroundColor: ColorTokens.secondaryLight,
          useCircularShape: true,
          onPlayStart: onPlayStart,
          tooltip: '본문 전체 듣기',
        ),
        const SizedBox(width: 4),
        Text(
          '본문 전체 듣기',
          style: TypographyTokens.caption.copyWith(
            color: ColorTokens.secondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
} 