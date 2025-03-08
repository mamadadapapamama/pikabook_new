import 'package:flutter/material.dart';
import '../models/text_segment.dart';

/// 텍스트 세그먼트 위젯
/// 원문, 핀인, 번역을 함께 표시합니다.
class TextSegmentWidget extends StatelessWidget {
  /// 텍스트 세그먼트 데이터
  final TextSegment segment;

  /// TTS 버튼 클릭 시 콜백
  final VoidCallback? onTts;

  /// 사전 검색 시 콜백
  final Function(String)? onDictionaryLookup;

  /// 플래시카드 생성 시 콜백
  final Function(String, String, {String? pinyin})? onCreateFlashCard;

  /// 핀인 표시 여부
  final bool showPinyin;

  const TextSegmentWidget({
    Key? key,
    required this.segment,
    this.onTts,
    this.onDictionaryLookup,
    this.onCreateFlashCard,
    this.showPinyin = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 원문 텍스트
            _buildOriginalText(context),

            // 핀인 (있는 경우)
            if (showPinyin && segment.pinyin != null) _buildPinyin(context),

            const SizedBox(height: 8),

            // 번역 텍스트
            _buildTranslatedText(context),
          ],
        ),
      ),
    );
  }

  /// 원문 텍스트 위젯
  Widget _buildOriginalText(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SelectableText(
            segment.originalText,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            onSelectionChanged: (selection, cause) {
              if (selection.baseOffset != selection.extentOffset) {
                // 텍스트 선택 시 처리
              }
            },
          ),
        ),
        if (onTts != null)
          IconButton(
            icon: const Icon(Icons.volume_up),
            onPressed: onTts,
            tooltip: '읽기',
          ),
      ],
    );
  }

  /// 핀인 위젯
  Widget _buildPinyin(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        segment.pinyin!,
        style: TextStyle(
          fontSize: 14,
          fontStyle: FontStyle.italic,
          color: Colors.blue.shade700,
        ),
      ),
    );
  }

  /// 번역 텍스트 위젯
  Widget _buildTranslatedText(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: SelectableText(
        segment.translatedText ?? '번역 없음',
        style: TextStyle(
          fontSize: 16,
          color: Colors.grey.shade800,
        ),
      ),
    );
  }
}
