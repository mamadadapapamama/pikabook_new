import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/chinese_segmenter_service.dart';
import '../services/flashcard_service.dart' hide debugPrint;
import '../services/tts_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/note.dart';
import '../services/dictionary_service.dart';

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
          return _buildCustomContextMenu(context, editableTextState);
        },
      );
    }

    // 기존 세그멘테이션 표시 로직
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          children: widget.segments.map((segment) {
            final bool isInDictionary =
                ChineseSegmenterService().isWordInDictionary(segment.text);

            return Material(
              color: Colors.transparent,
              child: GestureDetector(
                onTap: () {
                  _showWordDetails(context, segment);
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(
                      vertical: 2.0, horizontal: 1.0),
                  padding: const EdgeInsets.symmetric(
                      vertical: 2.0, horizontal: 4.0),
                  decoration: BoxDecoration(
                    color: isInDictionary
                        ? Colors.blue.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                    border: Border.all(
                      color: isInDictionary
                          ? Colors.blue.withOpacity(0.3)
                          : Colors.grey.withOpacity(0.3),
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

  // 커스텀 컨텍스트 메뉴 빌더
  Widget _buildCustomContextMenu(
      BuildContext context, EditableTextState editableTextState) {
    final TextEditingValue value = editableTextState.textEditingValue;
    final String selectedText = value.selection.textInside(value.text);

    if (selectedText.isEmpty) {
      return Container();
    }

    // 기본 메뉴 항목 가져오기
    final List<ContextMenuButtonItem> buttonItems = [];

    // 사전 검색 버튼 추가
    buttonItems.add(
      ContextMenuButtonItem(
        onPressed: () {
          editableTextState.hideToolbar();
          if (widget.onLookupDictionary != null) {
            widget.onLookupDictionary!(selectedText);
          }
        },
        label: '사전 찾기',
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
            widget.onAddToFlashcard!(selectedText);
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
