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
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                text,
                style: TextStyle(
                  fontSize: isOriginal ? 18 : 16, // 원문은 더 큰 글자 크기
                  height: 1.8, // 줄 간격 증가
                  letterSpacing: isOriginal ? 0.5 : 0.2, // 글자 간격 조정
                ),
                contextMenuBuilder: isOriginal
                    ? (context, editableTextState) {
                        final TextEditingValue value =
                            editableTextState.textEditingValue;
                        final selectedText =
                            value.selection.textInside(value.text);

                        // 기본 컨텍스트 메뉴 버튼 가져오기
                        final List<ContextMenuButtonItem> buttonItems = [];

                        // 복사 버튼 추가
                        buttonItems.add(
                          ContextMenuButtonItem(
                            label: '복사',
                            onPressed: () {
                              Clipboard.setData(
                                  ClipboardData(text: selectedText));
                              editableTextState.hideToolbar();
                            },
                          ),
                        );

                        // TTS 버튼 추가
                        buttonItems.add(
                          ContextMenuButtonItem(
                            label: '읽기',
                            onPressed: () async {
                              editableTextState.hideToolbar();
                              await ttsService.setLanguage('zh-CN');
                              await ttsService.speak(selectedText);
                            },
                          ),
                        );

                        // 사전 검색 버튼 추가
                        buttonItems.add(
                          ContextMenuButtonItem(
                            label: '사전 검색',
                            onPressed: () {
                              editableTextState.hideToolbar();
                              onDictionaryLookup(selectedText);
                            },
                          ),
                        );

                        // 플래시카드 추가 버튼 (원문 -> 번역)
                        buttonItems.add(
                          ContextMenuButtonItem(
                            label: '플래시카드 추가',
                            onPressed: () {
                              editableTextState.hideToolbar();
                              onCreateFlashCard(selectedText, translatedText);

                              // 추가 완료 메시지 표시
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('플래시카드가 추가되었습니다.'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        );

                        return AdaptiveTextSelectionToolbar.buttonItems(
                          anchors: editableTextState.contextMenuAnchors,
                          buttonItems: buttonItems,
                        );
                      }
                    : null, // 번역문에는 context menu 없음
              ),
            ),
          ],
        ),
      ),
    );
  }
}
