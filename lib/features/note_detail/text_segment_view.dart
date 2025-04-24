import 'package:flutter/material.dart';
import '../../core/models/processed_text.dart';
import '../../core/models/text_segment.dart';
import '../../core/utils/segment_utils.dart';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/widgets/tts_button.dart';

/// 세그먼트 단위 텍스트 표시를 위한 위젯
class TextSegmentView extends StatelessWidget {
  final List<TextSegment> segments;
  final ProcessedText processedText;
  final Function(int)? onDeleteSegment;
  final Widget Function(String, {TextStyle? style, bool isOriginal}) buildSelectableText;
  final TextStyle? originalTextStyle;
  final TextStyle? pinyinTextStyle;
  final TextStyle? translatedTextStyle;

  const TextSegmentView({
    Key? key,
    required this.segments,
    required this.processedText,
    required this.buildSelectableText,
    this.onDeleteSegment,
    this.originalTextStyle,
    this.pinyinTextStyle,
    this.translatedTextStyle,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 세그먼트가 없으면 빈 컨테이너 반환
    if (segments.isEmpty) {
      return const SizedBox.shrink();
    }

    // 세그먼트 목록을 위젯 목록으로 변환
    List<Widget> segmentWidgets = [];

    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];

      // 원본 텍스트가 비어있으면 건너뜀
      if (segment.originalText.isEmpty) {
        continue;
      }

      // 세그먼트 컨테이너
      Widget segmentContainer = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 원본 텍스트와 TTS 버튼을 함께 표시하는 행
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 원본 텍스트 (확장 가능하게)
              Expanded(
                child: buildSelectableText(
                  segment.originalText, 
                  style: originalTextStyle,
                  isOriginal: true,
                ),
              ),
              
              // TTS 재생 버튼 - 세그먼트 스타일로 통일
              Padding(
                padding: const EdgeInsets.only(left: 8.0, top: 2.0),
                child: TtsButton(
                  text: segment.originalText,
                  segmentIndex: i,
                  size: TtsButton.sizeMedium, // 중간 크기로 통일
                  tooltip: '무료 TTS 사용량을 모두 사용했습니다.',
                  activeBackgroundColor: ColorTokens.primary.withOpacity(0.2), // 더 뚜렷한 활성화 색상
                ),
              ),
            ],
          ),

          // 병음 표시 - 직접 processedText의 showPinyin 값 사용
          if (segment.pinyin != null && 
              segment.pinyin!.isNotEmpty && 
              processedText.showPinyin)
            Padding(
              padding: const EdgeInsets.only(top: 2.0, bottom: 4.0),
              child: Text(
                segment.pinyin!,
                style: pinyinTextStyle,
              ),
            ),

          // 번역 표시
          if (segment.translatedText != null &&
              segment.translatedText!.isNotEmpty &&
              processedText.showTranslation)
            Padding(
              padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
              child: Text(
                segment.translatedText!,
                style: translatedTextStyle,
              ),
            ),
        ],
      );
      
      // 세그먼트 컨테이너 래핑
      Widget wrappedSegmentContainer = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4.0),
        ),
        child: segmentContainer,
      );
      
      // 삭제 가능 조건: 세그먼트 모드(showFullText=false)이고 onDeleteSegment 콜백이 있을 때만
      if (onDeleteSegment != null && !processedText.showFullText) {
        final int segmentIndex = i;
        wrappedSegmentContainer = SegmentUtils.buildDismissibleSegment(
          key: ValueKey('segment_$i'),
          direction: DismissDirection.endToStart,
          onDelete: () {
            onDeleteSegment!(segmentIndex);
          },
          confirmDismiss: (direction) async {
            return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('문장 삭제'),
                content: const Text('이 문장을 삭제하시겠습니까?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('취소'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('삭제'),
                    style: TextButton.styleFrom(foregroundColor: ColorTokens.error),
                  ),
                ],
              ),
            );
          },
          child: wrappedSegmentContainer,
        );
      }

      // 구분선을 포함한 위젯 목록에 추가
      segmentWidgets.add(wrappedSegmentContainer);
      
      // 구분선 추가 (마지막 세그먼트가 아닌 경우)
      if (i < segments.length - 1) {
        segmentWidgets.add(
          const Padding(
            padding: EdgeInsets.only(top: 16.0, bottom: 16.0),
            child: Divider(height: 1, thickness: 1, color: ColorTokens.dividerLight),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: segmentWidgets,
    );
  }
} 