import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/tts_service.dart';
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
    Key? key,
    required this.title,
    required this.text,
    required this.isOriginal,
    required this.onDictionaryLookup,
    required this.onCreateFlashCard,
    required this.translatedText,
    this.flashcardWords,
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
                  ? SelectableText(
                      text,
                      style: TextStyle(
                        fontSize: isOriginal ? 18 : 16, // 원문은 더 큰 글자 크기
                        height: 1.8, // 줄 간격 증가
                        letterSpacing: isOriginal ? 0.5 : 0.2, // 글자 간격 조정
                      ),
                      contextMenuBuilder: (context, editableTextState) {
                        final String selectedText = editableTextState
                            .textEditingValue.selection
                            .textInside(
                                editableTextState.textEditingValue.text);

                        debugPrint('contextMenuBuilder 호출됨: 선택된 텍스트 = "$selectedText"');
                        
                        // 선택된 텍스트가 없으면 기본 메뉴 표시
                        if (selectedText.isEmpty) {
                          return AdaptiveTextSelectionToolbar.editableText(
                            editableTextState: editableTextState,
                          );
                        }

                        // 이미 플래시카드에 추가된 단어인지 확인
                        bool isAlreadyInFlashcard =
                            flashcardWords?.contains(selectedText) ?? false;
                        
                        debugPrint('플래시카드에 포함된 단어: $isAlreadyInFlashcard');

                        // 플래시카드에 이미 추가된 단어인 경우, 해당 단어의 뜻을 바로 표시하고 컨텍스트 메뉴는 표시하지 않음
                        if (isAlreadyInFlashcard) {
                          // 단어 상세 정보를 바로 표시
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            onDictionaryLookup(selectedText);
                          });
                          return const SizedBox.shrink();
                        }

                        // 중국어 문자가 포함된 경우에만 사전 검색 및 플래시카드 추가 메뉴 항목 표시
                        bool containsChinese = ContextMenuHelper.containsChineseCharacters(selectedText);
                        
                        if (!containsChinese) {
                          // 중국어가 아닌 경우 기본 메뉴 표시
                          return AdaptiveTextSelectionToolbar.editableText(
                            editableTextState: editableTextState,
                          );
                        }

                        // 커스텀 메뉴 항목 생성
                        final List<ContextMenuButtonItem> buttonItems = [];

                        // 복사 버튼 추가
                        buttonItems.add(
                          ContextMenuButtonItem(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: selectedText));
                              editableTextState.hideToolbar();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('복사되었습니다')),
                              );
                            },
                            label: '복사',
                          ),
                        );

                        // 전체 선택 버튼 추가
                        buttonItems.add(
                          ContextMenuButtonItem(
                            onPressed: () {
                              editableTextState.selectAll(SelectionChangedCause.toolbar);
                            },
                            label: '전체 선택',
                          ),
                        );

                        // 사전 검색 버튼 추가
                        buttonItems.add(
                          ContextMenuButtonItem(
                            onPressed: () {
                              editableTextState.hideToolbar();
                              onDictionaryLookup(selectedText);
                            },
                            label: '사전 검색',
                          ),
                        );

                        // 플래시카드 추가 버튼 생성 (이미 추가된 경우에는 표시하지 않음)
                        if (!isAlreadyInFlashcard) {
                          buttonItems.add(
                            ContextMenuButtonItem(
                              onPressed: () {
                                editableTextState.hideToolbar();
                                onCreateFlashCard(selectedText, translatedText);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('플래시카드가 추가되었습니다.'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              label: '플래시카드 추가',
                            ),
                          );
                        }

                        // 읽기 버튼 추가
                        buttonItems.add(
                          ContextMenuButtonItem(
                            onPressed: () {
                              editableTextState.hideToolbar();
                              ttsService.setLanguage('zh-CN');
                              ttsService.speak(selectedText);
                            },
                            label: '읽기',
                          ),
                        );

                        return AdaptiveTextSelectionToolbar.buttonItems(
                          anchors: editableTextState.contextMenuAnchors,
                          buttonItems: buttonItems,
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
