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
  final DictionaryService _dictionaryService = DictionaryService();

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
              color: segment.isInDictionary
                  ? Colors.blue.shade50
                  : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: segment.isInDictionary
                    ? Colors.blue.shade200
                    : Colors.grey.shade400,
                width: segment.isInDictionary ? 1.0 : 1.0,
                style: segment.isInDictionary
                    ? BorderStyle.solid
                    : BorderStyle.none,
              ),
            ),
            child: Text(
              segment.word,
              style: TextStyle(
                fontSize: 18,
                color: segment.isInDictionary ? Colors.black87 : Colors.black54,
                fontWeight: segment.isInDictionary
                    ? FontWeight.normal
                    : FontWeight.normal,
              ),
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
              if (segment.source != null) ...[
                const SizedBox(height: 4),
                Text(
                  '출처: ${segment.source}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
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
              if (segment.meaning == '사전에 없는 단어' ||
                  segment.meaning.isEmpty ||
                  segment.source == 'external') ...[
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  '외부 사전에서 검색:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildExternalDictButton(
                      context,
                      segment.word,
                      'Google',
                      ExternalDictType.google,
                      Icons.g_translate,
                    ),
                    _buildExternalDictButton(
                      context,
                      segment.word,
                      'Naver',
                      ExternalDictType.naver,
                      Icons.language,
                    ),
                    _buildExternalDictButton(
                      context,
                      segment.word,
                      'Baidu',
                      ExternalDictType.baidu,
                      Icons.search,
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildExternalDictButton(
    BuildContext context,
    String word,
    String label,
    ExternalDictType type,
    IconData icon,
  ) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onPressed: () async {
        Navigator.pop(context);
        final success =
            await _dictionaryService.openExternalDictionary(word, type: type);
        if (!success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$label 사전을 열 수 없습니다.')),
          );
        }
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
