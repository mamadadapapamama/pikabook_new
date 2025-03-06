import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/tts_service.dart';

class TextSectionWidget extends StatelessWidget {
  final String title;
  final String text;
  final bool isOriginal;
  final Function(String) onDictionaryLookup;
  final Function(String, String, {String? pinyin}) onCreateFlashCard;
  final String translatedText;

  const TextSectionWidget({
    Key? key,
    required this.title,
    required this.text,
    required this.isOriginal,
    required this.onDictionaryLookup,
    required this.onCreateFlashCard,
    required this.translatedText,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final TtsService ttsService = TtsService();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                // 원문인 경우에만 TTS 버튼 표시
                if (isOriginal)
                  IconButton(
                    icon: const Icon(Icons.volume_up),
                    tooltip: '텍스트 읽기',
                    onPressed: () async {
                      // 중국어로 언어 설정
                      await ttsService.setLanguage('zh-CN');
                      // 텍스트 읽기
                      await ttsService.speak(text);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                text,
                style: const TextStyle(fontSize: 16, height: 1.5),
                contextMenuBuilder: (context, editableTextState) {
                  final TextEditingValue value =
                      editableTextState.textEditingValue;

                  // 기본 컨텍스트 메뉴 버튼 가져오기
                  final List<ContextMenuButtonItem> buttonItems = [];

                  // 복사 버튼 추가
                  buttonItems.add(
                    ContextMenuButtonItem(
                      label: '복사',
                      onPressed: () {
                        final selectedText = value.text.substring(
                          value.selection.start,
                          value.selection.end,
                        );
                        Clipboard.setData(ClipboardData(text: selectedText));
                      },
                    ),
                  );

                  if (value.selection.isValid &&
                      value.selection.start != value.selection.end) {
                    // 선택된 텍스트가 있는 경우
                    final selectedText = value.text.substring(
                      value.selection.start,
                      value.selection.end,
                    );

                    // 원문인 경우 TTS 및 사전 검색 버튼 추가
                    if (isOriginal) {
                      // TTS 버튼 추가
                      buttonItems.add(
                        ContextMenuButtonItem(
                          label: '읽기',
                          onPressed: () async {
                            await ttsService.setLanguage('zh-CN');
                            await ttsService.speak(selectedText);
                          },
                        ),
                      );

                      // 사전 검색 버튼 추가
                      buttonItems.add(
                        ContextMenuButtonItem(
                          label: '사전',
                          onPressed: () {
                            onDictionaryLookup(selectedText);
                          },
                        ),
                      );
                    }

                    // 플래시카드 추가 버튼
                    buttonItems.add(
                      ContextMenuButtonItem(
                        label: '플래시카드에 추가',
                        onPressed: () {
                          onCreateFlashCard(selectedText, translatedText);
                        },
                      ),
                    );
                  }
                  return AdaptiveTextSelectionToolbar.buttonItems(
                    anchors: editableTextState.contextMenuAnchors,
                    buttonItems: buttonItems,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
