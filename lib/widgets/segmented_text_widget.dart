import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/chinese_segmenter_service.dart';
import '../services/flashcard_service.dart' hide debugPrint;
import '../services/tts_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/note.dart';

class SegmentedTextWidget extends StatefulWidget {
  final String text;
  final String? noteId;
  final Function()? onFlashCardAdded;

  const SegmentedTextWidget({
    Key? key,
    required this.text,
    this.noteId,
    this.onFlashCardAdded,
  }) : super(key: key);

  @override
  _SegmentedTextWidgetState createState() => _SegmentedTextWidgetState();
}

class _SegmentedTextWidgetState extends State<SegmentedTextWidget> {
  final ChineseSegmenterService _segmenterService = ChineseSegmenterService();
  final TtsService _ttsService = TtsService();
  final FlashCardService _flashCardService = FlashCardService();

  List<SegmentedWord> _segments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _processText();
  }

  @override
  void didUpdateWidget(SegmentedTextWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _processText();
    }
  }

  Future<void> _processText() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final segments = await _segmenterService.processText(widget.text);

      if (mounted) {
        setState(() {
          _segments = segments;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('텍스트 처리 오류: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_segments.isEmpty) {
      return Text(
        widget.text,
        style: const TextStyle(fontSize: 18),
      );
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: _segments.map((segment) {
        return GestureDetector(
          onTap: () => _showWordDetails(context, segment),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              segment.word,
              style: const TextStyle(fontSize: 18),
            ),
          ),
        );
      }).toList(),
    );
  }

  void _showWordDetails(BuildContext context, SegmentedWord segment) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    segment.word,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    segment.pinyin,
                    style: const TextStyle(
                      fontSize: 16,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.volume_up),
                    onPressed: () => _ttsService.speak(segment.word),
                    tooltip: '발음 듣기',
                  ),
                  IconButton(
                    icon: const Icon(Icons.content_copy),
                    onPressed: () => _copyToClipboard(context, segment.word),
                    tooltip: '복사',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '의미: ${segment.meaning}',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              if (widget.noteId != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.flash_on),
                    label: const Text('플래시카드 추가'),
                    onPressed: () => _addToFlashcard(context, segment),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('클립보드에 복사되었습니다')),
    );
    Navigator.pop(context);
  }

  Future<void> _addToFlashcard(
      BuildContext context, SegmentedWord segment) async {
    if (widget.noteId == null) return;

    try {
      await _flashCardService.createFlashCard(
        front: segment.word,
        back: segment.meaning,
        pinyin: segment.pinyin,
        noteId: widget.noteId!,
      );

      if (widget.onFlashCardAdded != null) {
        widget.onFlashCardAdded!();
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('플래시카드가 추가되었습니다')),
        );
      }
    } catch (e) {
      debugPrint('플래시카드 추가 오류: $e');
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('플래시카드 추가 실패: $e')),
        );
      }
    }
  }
}
