import 'package:flutter/material.dart';
import '../../core/models/processed_text.dart';

/// 전체 텍스트 표시를 위한 위젯
class FullTextView extends StatelessWidget {
  final ProcessedText processedText;
  final Widget Function(String, {TextStyle? style, bool isOriginal}) buildSelectableText;
  final TextStyle? originalTextStyle;
  final TextStyle? translatedTextStyle;

  const FullTextView({
    Key? key,
    required this.processedText,
    required this.buildSelectableText,
    this.originalTextStyle,
    this.translatedTextStyle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 원본 텍스트 표시
        if (processedText.fullOriginalText.isNotEmpty)
          Container(
            width: double.infinity,
            child: buildSelectableText(
              processedText.fullOriginalText,
              style: originalTextStyle,
            ),
          ),

        // 번역 텍스트 표시
        if (processedText.showTranslation &&
            processedText.fullTranslatedText != null &&
            processedText.fullTranslatedText!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
            child: Container(
              width: double.infinity,
              child: Text(
                processedText.fullTranslatedText!,
                style: translatedTextStyle,
              ),
            ),
          ),
      ],
    );
  }
} 