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
              child: isOriginal
                  ? GestureDetector(
                      onLongPress: () {
                        // 전체 텍스트 선택 시 메뉴 표시
                        _showCustomMenu(context, text, ttsService);
                      },
                      child: SelectableText(
                        text,
                        style: TextStyle(
                          fontSize: isOriginal ? 18 : 16, // 원문은 더 큰 글자 크기
                          height: 1.8, // 줄 간격 증가
                          letterSpacing: isOriginal ? 0.5 : 0.2, // 글자 간격 조정
                        ),
                        onSelectionChanged: (selection, cause) {
                          if (selection.baseOffset != selection.extentOffset) {
                            // 텍스트가 선택되면 커스텀 메뉴 표시
                            final String selectedText = text.substring(
                              selection.baseOffset,
                              selection.extentOffset,
                            );

                            // 선택 완료 후 메뉴 표시 (약간의 딜레이 추가)
                            if (cause == SelectionChangedCause.longPress) {
                              Future.delayed(const Duration(milliseconds: 200),
                                  () {
                                _showCustomMenu(
                                    context, selectedText, ttsService);
                              });
                            }
                          }
                        },
                        contextMenuBuilder: null, // 기본 컨텍스트 메뉴 비활성화
                      ),
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

  /// 커스텀 메뉴 표시
  void _showCustomMenu(
      BuildContext context, String selectedText, TtsService ttsService) {
    if (selectedText.isEmpty) return;

    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          child: const Text('복사'),
          onTap: () {
            Clipboard.setData(ClipboardData(text: selectedText));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('텍스트가 복사되었습니다')),
            );
          },
        ),
        PopupMenuItem(
          child: const Text('읽기'),
          onTap: () async {
            await ttsService.setLanguage('zh-CN');
            await ttsService.speak(selectedText);
          },
        ),
        PopupMenuItem(
          child: const Text('사전 검색'),
          onTap: () {
            onDictionaryLookup(selectedText);
          },
        ),
        PopupMenuItem(
          child: const Text('플래시카드 추가'),
          onTap: () {
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
      ],
    );
  }
}
