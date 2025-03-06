import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../models/page.dart' as page_model;
import '../services/dictionary_service.dart';
import '../services/flashcard_service.dart';

// 텍스트 표시 모드
enum TextDisplayMode { both, originalOnly, translationOnly }

class PageContentWidget extends StatefulWidget {
  final page_model.Page page;
  final File? imageFile;
  final bool isLoadingImage;
  final String noteId;
  final Function(String, String, {String? pinyin}) onCreateFlashCard;

  const PageContentWidget({
    Key? key,
    required this.page,
    required this.imageFile,
    required this.isLoadingImage,
    required this.noteId,
    required this.onCreateFlashCard,
  }) : super(key: key);

  @override
  State<PageContentWidget> createState() => _PageContentWidgetState();
}

class _PageContentWidgetState extends State<PageContentWidget> {
  TextDisplayMode _textDisplayMode = TextDisplayMode.both;
  final DictionaryService _dictionaryService = DictionaryService();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 이미지 표시
          if (widget.page.imageUrl != null) ...[
            Center(
              child: widget.isLoadingImage
                  ? Container(
                      width: double.infinity,
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('이미지 로딩 중...'),
                          ],
                        ),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: widget.imageFile != null
                          ? Image.file(
                              widget.imageFile!,
                              height: 200,
                              width: double.infinity,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: double.infinity,
                                  height: 150,
                                  color: Colors.grey[200],
                                  child: const Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.image_not_supported,
                                            size: 48, color: Colors.grey),
                                        SizedBox(height: 8),
                                        Text('이미지를 불러올 수 없습니다.'),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            )
                          : Container(
                              width: double.infinity,
                              height: 150,
                              color: Colors.grey[200],
                              child: const Center(
                                child: Text('이미지를 찾을 수 없습니다.'),
                              ),
                            ),
                    ),
            ),
            const SizedBox(height: 16),
          ],

          // 텍스트 표시 모드 토글 버튼
          _buildTextDisplayToggle(),
          const SizedBox(height: 16),

          // 원본 텍스트 표시
          if (_textDisplayMode == TextDisplayMode.both ||
              _textDisplayMode == TextDisplayMode.originalOnly) ...[
            _buildTextSection(
              title: '원문',
              text: widget.page.originalText,
              isOriginal: true,
            ),
            const SizedBox(height: 16),
          ],

          // 번역 텍스트 표시
          if (_textDisplayMode == TextDisplayMode.both ||
              _textDisplayMode == TextDisplayMode.translationOnly) ...[
            _buildTextSection(
              title: '번역',
              text: widget.page.translatedText,
              isOriginal: false,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextDisplayToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ToggleButtons(
            isSelected: [
              _textDisplayMode == TextDisplayMode.both,
              _textDisplayMode == TextDisplayMode.originalOnly,
              _textDisplayMode == TextDisplayMode.translationOnly,
            ],
            onPressed: (index) {
              setState(() {
                switch (index) {
                  case 0:
                    _textDisplayMode = TextDisplayMode.both;
                    break;
                  case 1:
                    _textDisplayMode = TextDisplayMode.originalOnly;
                    break;
                  case 2:
                    _textDisplayMode = TextDisplayMode.translationOnly;
                    break;
                }
              });
            },
            borderRadius: BorderRadius.circular(8),
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('모두 보기'),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('원문만'),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('번역만'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextSection({
    required String title,
    required String text,
    required bool isOriginal,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
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
                    // 사전 검색 버튼 추가 (중국어 텍스트인 경우에만)
                    if (isOriginal) {
                      buttonItems.add(
                        ContextMenuButtonItem(
                          label: '사전',
                          onPressed: () {
                            final selectedText = value.text.substring(
                              value.selection.start,
                              value.selection.end,
                            );
                            _showDictionarySnackbar(selectedText);
                          },
                        ),
                      );
                    }

                    buttonItems.add(
                      ContextMenuButtonItem(
                        label: '플래시카드에 추가',
                        onPressed: () {
                          final selectedText = value.text.substring(
                            value.selection.start,
                            value.selection.end,
                          );

                          // 현재 페이지의 번역 텍스트 또는 원본 텍스트 가져오기
                          String translatedText = isOriginal
                              ? widget.page.translatedText
                              : widget.page.originalText;

                          widget.onCreateFlashCard(
                              selectedText, translatedText);
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

  // 사전 스낵바 표시
  void _showDictionarySnackbar(String word) {
    final entry = _dictionaryService.lookupWord(word);

    if (entry == null) {
      // 사전에 없는 단어일 경우
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('사전에서 찾을 수 없는 단어: $word'),
          action: SnackBarAction(
            label: '플래시카드에 추가',
            onPressed: () {
              widget.onCreateFlashCard(word, '직접 의미 입력 필요');
            },
          ),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    // 사전에 있는 단어일 경우
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  entry.word,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  entry.pinyin,
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
            Text('의미: ${entry.meaning}'),
          ],
        ),
        action: SnackBarAction(
          label: '플래시카드에 추가',
          onPressed: () {
            widget.onCreateFlashCard(entry.word, entry.meaning,
                pinyin: entry.pinyin);
          },
        ),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
