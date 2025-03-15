import 'package:flutter/material.dart';
import '../utils/text_selection_helper.dart';

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
                  ? TextSelectionHelper.buildSelectableText(
                      text: text,
                      style: TextStyle(
                        fontSize: 18, // 원문은 큰 글자 크기
                        height: 1.8, // 줄 간격 증가
                        letterSpacing: isOriginal ? 0.5 : 0.2, // 글자 간격 조정
                      ),
                      onDictionaryLookup: onDictionaryLookup,
                      onCreateFlashCard: onCreateFlashCard,
                      translatedText: translatedText,
                      flashcardWords: flashcardWords,
                      onWordTap: (word) {
                        // 하이라이트된 단어를 탭했을 때 사전 검색 실행
                        onDictionaryLookup(word);
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
