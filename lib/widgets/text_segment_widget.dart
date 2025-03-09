import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
          child: GestureDetector(
            onLongPress: () {
              // 현재 선택된 텍스트 가져오기
              final TextSelection selection = TextSelection.fromPosition(
                const TextPosition(offset: 0),
              );

              // 선택된 텍스트가 없으면 전체 텍스트 사용
              final String selectedText =
                  selection.textInside(segment.originalText).isNotEmpty
                      ? selection.textInside(segment.originalText)
                      : segment.originalText;

              // 커스텀 메뉴 표시
              _showCustomMenu(context, selectedText);
            },
            child: SelectableText(
              segment.originalText,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              onSelectionChanged: (selection, cause) {
                if (selection.baseOffset != selection.extentOffset) {
                  // 텍스트가 선택되면 커스텀 메뉴 표시
                  final String selectedText = segment.originalText.substring(
                    selection.baseOffset,
                    selection.extentOffset,
                  );

                  // 선택 완료 후 메뉴 표시 (약간의 딜레이 추가)
                  if (cause == SelectionChangedCause.longPress) {
                    Future.delayed(const Duration(milliseconds: 200), () {
                      _showCustomMenu(context, selectedText);
                    });
                  }
                }
              },
              contextMenuBuilder: null, // 기본 컨텍스트 메뉴 비활성화
            ),
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

  /// 커스텀 메뉴 표시
  void _showCustomMenu(BuildContext context, String selectedText) {
    if (selectedText.isEmpty) return;

    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          child: const Text('복사'),
          onTap: () {
            Clipboard.setData(ClipboardData(text: selectedText));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('텍스트가 복사되었습니다')),
            );
          },
        ),
        PopupMenuItem(
          child: const Text('사전 검색'),
          onTap: () {
            if (onDictionaryLookup != null) {
              onDictionaryLookup!(selectedText);
            }
          },
        ),
        PopupMenuItem(
          child: const Text('플래시카드 추가'),
          onTap: () {
            // 원문에서 선택한 경우, 번역을 의미로 사용
            final String word = selectedText;
            final String meaning = segment.translatedText ?? '직접 의미 입력 필요';

            // 플래시카드 바로 추가
            if (onCreateFlashCard != null) {
              onCreateFlashCard!(
                word,
                meaning,
                pinyin: segment.pinyin,
              );

              // 추가 완료 메시지 표시
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('플래시카드가 추가되었습니다.'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
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
      child: Text(
        segment.translatedText ?? '번역 없음',
        style: TextStyle(
          fontSize: 16,
          color: Colors.grey.shade800,
        ),
      ),
    );
  }
}
