import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/chinese_segmenter_service.dart';
import '../services/dictionary_service.dart';

class SegmentedTextWidget extends StatefulWidget {
  final String text;
  final List<String> segments;
  final Set<String> flashcardWords;
  final Function(String)? onLookupDictionary;
  final Function(String)? onAddToFlashcard;

  const SegmentedTextWidget({
    Key? key,
    required this.text,
    required this.segments,
    required this.flashcardWords,
    this.onLookupDictionary,
    this.onAddToFlashcard,
  }) : super(key: key);

  @override
  State<SegmentedTextWidget> createState() => _SegmentedTextWidgetState();
}

class _SegmentedTextWidgetState extends State<SegmentedTextWidget> {
  String _selectedText = '';
  late ChineseSegmenterService _segmenterService;

  @override
  void initState() {
    super.initState();
    _segmenterService = ChineseSegmenterService();
    _segmenterService.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      children: widget.segments.map((segment) {
        bool isInFlashcard = widget.flashcardWords.contains(segment);
        bool isInDictionary = _segmenterService.isWordInDictionary(segment);

        return GestureDetector(
          onTap: () {
            if (isInFlashcard || isInDictionary) {
              widget.onLookupDictionary?.call(segment);
            }
          },
          onLongPress: () {
            if (!isInFlashcard) {
              _showContextMenu(context, segment);
            }
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 2.0),
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 6.0),
            decoration: BoxDecoration(
              color:
                  isInFlashcard ? Colors.yellow.shade200 : Colors.transparent,
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: Text(
              segment,
              style: TextStyle(
                fontSize: 18,
                fontWeight: isInFlashcard ? FontWeight.bold : FontWeight.normal,
                decoration: isInFlashcard
                    ? TextDecoration.none
                    : TextDecoration.underline,
                decorationColor: Colors.blue.withOpacity(0.5),
                decorationThickness: 1.0,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ✅ 컨텍스트 메뉴 표시
  void _showContextMenu(BuildContext context, String selectedText) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final Offset position = overlay.localToGlobal(Offset.zero);

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        PopupMenuItem(
          child: const Text('사전 검색'),
          onTap: () => widget.onLookupDictionary?.call(selectedText),
        ),
        PopupMenuItem(
          child: const Text('플래시카드 추가'),
          onTap: () {
            widget.onAddToFlashcard?.call(selectedText);
            setState(() {
              widget.flashcardWords.add(selectedText);
            });
          },
        ),
        PopupMenuItem(
          child: const Text('복사'),
          onTap: () {
            Clipboard.setData(ClipboardData(text: selectedText));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('복사되었습니다')),
            );
          },
        ),
      ],
    );
  }
}
