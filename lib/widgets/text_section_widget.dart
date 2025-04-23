import 'package:flutter/material.dart';
import '../core/utils/text_highlight_manager.dart';

// 아직 페이지의 텍스트 처리가 완료되지 않았을때, 원문 번역문 섹션을 처리하는 위젯.

class TextSectionWidget extends StatelessWidget {
  final String title;
  final String text;
  final bool isOriginal;
  final Function(String) onDictionaryLookup;
  final Function(String, String, {String? pinyin}) onCreateFlashCard;
  final String translatedText;
  final Set<String>? flashcardWords;

  const TextSectionWidget({
    super.key,
    required this.title,
    required this.text,
    required this.isOriginal,
    required this.onDictionaryLookup,
    required this.onCreateFlashCard,
    required this.translatedText,
    this.flashcardWords,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: isOriginal
                  ? SelectableText.rich(
                      TextSpan(
                        children: TextHighlightManager.buildHighlightedText(
                          text: text,
                          flashcardWords: flashcardWords ?? {},
                          onTap: onDictionaryLookup,
                          normalStyle: TextStyle(
                            fontSize: 18, // 원문은 큰 글자 크기
                            height: 1.8, // 줄 간격 증가
                            letterSpacing: 0.5, // 글자 간격 조정
                          ),
                        ),
                      ),
                      onSelectionChanged: (selection, cause) {
                        if (!selection.isCollapsed) {
                          try {
                            final selectedText = text.substring(
                                selection.start, selection.end);
                            if (selectedText.isNotEmpty) {
                              // 나중에 컨텍스트 메뉴를 표시해야 할 경우에 대비
                            }
                          } catch (e) {
                            debugPrint('텍스트 선택 오류: $e');
                          }
                        }
                      },
                    )
                  : Text(
                      text,
                      style: TextStyle(
                        fontSize: 16, // 번역문은 작은 글자 크기
                        height: 1.8, // 줄 간격 증가
                        letterSpacing: 0.2, // 글자 간격 조정
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
