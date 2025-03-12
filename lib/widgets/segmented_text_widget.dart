import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/chinese_segmenter_service.dart';
import '../services/flashcard_service.dart' hide debugPrint;
import '../services/tts_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/note.dart';
import '../services/dictionary_service.dart';
import '../utils/context_menu_helper.dart';

class SegmentedTextWidget extends StatefulWidget {
  final String text;
  final List<SegmentedWord> segments;
  final Function(String)? onLookupDictionary;
  final Function(String)? onAddToFlashcard;

  const SegmentedTextWidget({
    Key? key,
    required this.text,
    required this.segments,
    this.onLookupDictionary,
    this.onAddToFlashcard,
  }) : super(key: key);

  @override
  State<SegmentedTextWidget> createState() => _SegmentedTextWidgetState();
}

class _SegmentedTextWidgetState extends State<SegmentedTextWidget> {
  String _selectedText = '';

  @override
  Widget build(BuildContext context) {
    // 세그멘테이션이 비활성화된 경우 단순 텍스트 표시
    if (!ChineseSegmenterService.isSegmentationEnabled) {
      return SelectableText.rich(
        TextSpan(
          text: widget.text,
          style: TextStyle(fontSize: 18, color: Colors.black),
        ),
        onSelectionChanged: (selection, cause) {
          if (selection.baseOffset != selection.extentOffset) {
            setState(() {
              _selectedText = widget.text.substring(
                selection.baseOffset,
                selection.extentOffset,
              );
            });
          }
        },
        contextMenuBuilder: (context, editableTextState) {
          // 선택된 텍스트가 없거나 중국어가 아니면 기본 메뉴 표시
          if (_selectedText.isEmpty ||
              !ContextMenuHelper.containsChineseCharacters(_selectedText)) {
            return AdaptiveTextSelectionToolbar.editableText(
              editableTextState: editableTextState,
            );
          }

          // 커스텀 메뉴 항목 생성
          return _buildCustomContextMenu(context, editableTextState);
        },
        enableInteractiveSelection: true,
        selectionControls: MaterialTextSelectionControls(),
        showCursor: true,
        cursorWidth: 2.0,
        cursorColor: Colors.blue,
      );
    }

    // 사전 초기화 (비동기 작업이지만 UI 블로킹 방지를 위해 async/await 사용하지 않음)
    final segmenterService = ChineseSegmenterService();
    segmenterService.initialize();

    // 기존 세그멘테이션 표시 로직
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          children: widget.segments.map((segment) {
            // 단어장에 있는지 확인 (초기화 전이라면 false 반환)
            final bool isInDictionary =
                segmenterService.isWordInDictionary(segment.text);
            debugPrint(
                '세그먼트 "${segment.text}" 사전 확인: ${isInDictionary ? "있음" : "없음"}');

            // 단어장에 있는 단어는 InkWell로 감싸서 탭하면 바로 뜻이 표시되도록 함
            if (isInDictionary) {
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    _showWordDetails(context, segment);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                        vertical: 2.0, horizontal: 1.0),
                    padding: const EdgeInsets.symmetric(
                        vertical: 2.0, horizontal: 4.0),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      border: Border.all(
                        color: Colors.blue.withOpacity(0.3),
                        width: 1.0,
                      ),
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    child: Text(
                      segment.text,
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.black,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.blue.withOpacity(0.5),
                        decorationThickness: 1.0,
                      ),
                    ),
                  ),
                ),
              );
            }
            // 단어장에 없는 단어는 GestureDetector로 감싸서 long press 시 컨텍스트 메뉴가 표시되도록 함
            else {
              return Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onTap: () {
                    _showWordDetails(context, segment);
                  },
                  onLongPress: () {
                    _showContextMenu(context, segment.text);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                        vertical: 2.0, horizontal: 1.0),
                    padding: const EdgeInsets.symmetric(
                        vertical: 2.0, horizontal: 4.0),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      border: Border.all(
                        color: Colors.grey.withOpacity(0.3),
                        width: 1.0,
                      ),
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    child: Text(
                      segment.text,
                      style: TextStyle(fontSize: 18, color: Colors.black),
                    ),
                  ),
                ),
              );
            }
          }).toList(),
        ),
      ],
    );
  }

  // 단어 상세 정보 표시
  void _showWordDetails(BuildContext context, SegmentedWord segment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(segment.text),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (segment.pinyin.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  '발음: ${segment.pinyin}',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
            if (segment.source != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  '출처: ${segment.source}',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            Text('의미: ${segment.meaning}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text('닫기'),
          ),
          TextButton(
            onPressed: () {
              if (widget.onAddToFlashcard != null) {
                widget.onAddToFlashcard!(segment.text);
                Navigator.of(context).pop();
                // 스낵바 제거 - 플래시카드 카운터가 증가하는 것으로 충분한 피드백 제공
              }
            },
            child: Text('플래시카드 추가'),
          ),
        ],
      ),
    );
  }

  // 컨텍스트 메뉴 표시
  void _showContextMenu(BuildContext context, String selectedText) {
    // 중국어 문자인지 확인
    bool containsChinese =
        ContextMenuHelper.containsChineseCharacters(selectedText);
    if (!containsChinese) return;

    // 단어장에 있는지 확인
    final segmenterService = ChineseSegmenterService();
    segmenterService.initialize().then((_) {
      if (segmenterService.isWordInDictionary(selectedText)) {
        // 단어장에 있는 단어는 바로 뜻 표시
        for (var segment in widget.segments) {
          if (segment.text == selectedText) {
            _showWordDetails(context, segment);
            return;
          }
        }
      }

      final RenderBox renderBox = context.findRenderObject() as RenderBox;
      final Offset position = renderBox.localToGlobal(Offset.zero);

      showMenu(
        context: context,
        position: RelativeRect.fromLTRB(
          position.dx,
          position.dy,
          position.dx + renderBox.size.width,
          position.dy + renderBox.size.height,
        ),
        items: [
          PopupMenuItem(
            child: Text('사전 검색'),
            onTap: () {
              if (widget.onLookupDictionary != null) {
                widget.onLookupDictionary!(selectedText);
              }
            },
          ),
          PopupMenuItem(
            child: Text('플래시카드 추가'),
            onTap: () {
              if (widget.onAddToFlashcard != null) {
                widget.onAddToFlashcard!(selectedText);
              }
            },
          ),
          PopupMenuItem(
            child: Text('복사'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: selectedText));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('복사되었습니다')),
              );
            },
          ),
        ],
      );
    });
  }

  // 커스텀 컨텍스트 메뉴 빌더
  Widget _buildCustomContextMenu(
      BuildContext context, EditableTextState editableTextState) {
    // 커스텀 메뉴 항목 생성
    final List<ContextMenuButtonItem> buttonItems = [];

    // 복사 버튼 추가
    buttonItems.add(
      ContextMenuButtonItem(
        onPressed: () {
          Clipboard.setData(ClipboardData(text: _selectedText));
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
          if (widget.onLookupDictionary != null) {
            widget.onLookupDictionary!(_selectedText);
          }
        },
        label: '사전 검색',
      ),
    );

    // 플래시카드 추가 버튼 생성
    buttonItems.add(
      ContextMenuButtonItem(
        onPressed: () {
          // 컨텍스트 메뉴 닫기
          editableTextState.hideToolbar();

          // 플래시카드 추가 기능 호출
          if (widget.onAddToFlashcard != null) {
            widget.onAddToFlashcard!(_selectedText);
          }
        },
        label: '플래시카드 추가',
      ),
    );

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }
}
