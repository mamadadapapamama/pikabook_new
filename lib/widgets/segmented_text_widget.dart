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
      return GestureDetector(
        onLongPress: () {
          // 컨텍스트 메뉴 표시 로직
          _showCustomMenu(context, widget.text);
        },
        child: SelectableText.rich(
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
          // 기본 컨텍스트 메뉴 비활성화
          contextMenuBuilder: null,
        ),
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

            return GestureDetector(
              onTap: () {
                _showWordDetails(context, segment);
              },
              onLongPress: () {
                _showCustomMenu(context, segment.text);
              },
              child: Container(
                margin:
                    const EdgeInsets.symmetric(vertical: 2.0, horizontal: 1.0),
                padding:
                    const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('플래시카드에 추가되었습니다.')),
                );
              }
            },
            child: Text('플래시카드 추가'),
          ),
        ],
      ),
    );
  }

  // 커스텀 컨텍스트 메뉴 표시 메서드
  void _showCustomMenu(BuildContext context, String text) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);

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
          child: Text('복사'),
          onTap: () {
            Clipboard.setData(
              ClipboardData(
                text: _selectedText.isNotEmpty ? _selectedText : text,
              ),
            );
          },
        ),
        PopupMenuItem(
          child: Text('사전 찾기'),
          onTap: () {
            if (_selectedText.isNotEmpty) {
              // 사전 찾기 기능 호출
              if (widget.onLookupDictionary != null) {
                widget.onLookupDictionary!(_selectedText);
              }
            }
          },
        ),
        PopupMenuItem(
          child: Text('플래시카드 추가'),
          onTap: () {
            if (_selectedText.isNotEmpty) {
              // 플래시카드 추가 기능 호출
              if (widget.onAddToFlashcard != null) {
                widget.onAddToFlashcard!(_selectedText);
              }
            }
          },
        ),
      ],
    );
  }
}
