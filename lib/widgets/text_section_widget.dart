import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/tts_service.dart';
import '../services/language_detection_service.dart';
import '../utils/context_menu_helper.dart';

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
                  ? SelectableText(
                      text,
                      style: TextStyle(
                        fontSize: 18, // 원문은 큰 글자 크기
                        height: 1.8, // 줄 간격 증가
                        letterSpacing: isOriginal ? 0.5 : 0.2, // 글자 간격 조정
                      ),
                      contextMenuBuilder: (context, editableTextState) {
                        final String selectedText = editableTextState
                            .textEditingValue.selection
                            .textInside(
                                editableTextState.textEditingValue.text);

                        debugPrint(
                            '==== TextSectionWidget.contextMenuBuilder 호출됨 ====');
                        debugPrint('선택된 텍스트 = "$selectedText"');
                        debugPrint(
                            '플래시카드 단어 수: ${flashcardWords?.length ?? 0}');

                        // ContextMenuHelper 사용하여 컨텍스트 메뉴 생성
                        return ContextMenuHelper.buildCustomContextMenu(
                          context: context,
                          editableTextState: editableTextState,
                          selectedText: selectedText,
                          flashcardWords: flashcardWords,
                          onLookupDictionary: (text) =>
                              onDictionaryLookup(text),
                          onAddToFlashcard: (text) =>
                              onCreateFlashCard(text, translatedText),
                        );
                      },
                      enableInteractiveSelection: true,
                      selectionControls: MaterialTextSelectionControls(),
                      showCursor: true,
                      cursorWidth: 2.0,
                      cursorColor: Colors.blue,
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
