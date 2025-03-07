import 'package:flutter/material.dart';
import '../models/processed_text.dart';
import '../models/text_segment.dart';
import 'text_segment_widget.dart';

/// 처리된 텍스트 표시 위젯
/// 전체 텍스트와 세그먼트별 표시를 전환할 수 있습니다.
class ProcessedTextWidget extends StatefulWidget {
  /// 처리된 텍스트 데이터
  final ProcessedText processedText;

  /// TTS 버튼 클릭 시 콜백
  final Function(String)? onTts;

  /// 사전 검색 시 콜백
  final Function(String)? onDictionaryLookup;

  /// 플래시카드 생성 시 콜백
  final Function(String, String)? onCreateFlashCard;

  const ProcessedTextWidget({
    Key? key,
    required this.processedText,
    this.onTts,
    this.onDictionaryLookup,
    this.onCreateFlashCard,
  }) : super(key: key);

  @override
  State<ProcessedTextWidget> createState() => _ProcessedTextWidgetState();
}

class _ProcessedTextWidgetState extends State<ProcessedTextWidget> {
  /// 현재 표시 모드 (전체 텍스트 또는 세그먼트별)
  late bool _showFullText;

  @override
  void initState() {
    super.initState();
    _showFullText = widget.processedText.showFullText;
  }

  @override
  void didUpdateWidget(ProcessedTextWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.processedText != widget.processedText) {
      _showFullText = widget.processedText.showFullText;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 표시 모드 전환 버튼
        _buildDisplayModeToggle(context),

        const SizedBox(height: 16),

        // 텍스트 표시
        _showFullText
            ? _buildFullTextView(context)
            : _buildSegmentedView(context),
      ],
    );
  }

  /// 표시 모드 전환 버튼
  Widget _buildDisplayModeToggle(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          _showFullText ? '전체 텍스트 모드' : '문장별 모드',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          value: _showFullText,
          onChanged: (value) {
            setState(() {
              _showFullText = value;
            });
          },
          activeColor: Theme.of(context).primaryColor,
        ),
      ],
    );
  }

  /// 전체 텍스트 표시
  Widget _buildFullTextView(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 원문 텍스트
        Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '원문',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (widget.onTts != null)
                      IconButton(
                        icon: const Icon(Icons.volume_up),
                        onPressed: () => widget.onTts
                            ?.call(widget.processedText.fullOriginalText),
                        tooltip: '읽기',
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  widget.processedText.fullOriginalText,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ),

        // 번역 텍스트
        if (widget.processedText.fullTranslatedText != null)
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '번역',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    widget.processedText.fullTranslatedText!,
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 세그먼트별 표시
  Widget _buildSegmentedView(BuildContext context) {
    // 세그먼트가 없는 경우
    if (widget.processedText.segments == null ||
        widget.processedText.segments!.isEmpty) {
      debugPrint('세그먼트 데이터가 없습니다.');
      return const Center(
        child: Text('문장별 데이터가 없습니다. 전체 텍스트 모드를 사용해주세요.'),
      );
    }

    debugPrint('세그먼트 표시: ${widget.processedText.segments!.length}개');

    // 세그먼트 위젯 목록 생성
    final segmentWidgets =
        widget.processedText.segments!.asMap().entries.map((entry) {
      final index = entry.key;
      final segment = entry.value;
      debugPrint(
          '세그먼트 $index: ${segment.originalText.substring(0, segment.originalText.length > 10 ? 10 : segment.originalText.length)}...');

      return TextSegmentWidget(
        segment: segment,
        onTts: widget.onTts != null
            ? () => widget.onTts?.call(segment.originalText)
            : null,
        onDictionaryLookup: widget.onDictionaryLookup,
        onCreateFlashCard: widget.onCreateFlashCard,
      );
    }).toList();

    // 세그먼트 목록 표시
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '문장별 표시 (${widget.processedText.segments!.length}개)',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 16),
        // 세그먼트 위젯 목록을 ListView로 표시
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: segmentWidgets.length,
          itemBuilder: (context, index) => segmentWidgets[index],
        ),
      ],
    );
  }
}
