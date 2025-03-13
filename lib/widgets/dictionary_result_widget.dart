import 'package:flutter/material.dart';
import '../services/dictionary_service.dart';
import '../services/page_content_service.dart';

/// 사전 검색 결과를 표시하는 바텀 시트 위젯
class DictionaryResultWidget extends StatelessWidget {
  final DictionaryEntry entry;
  final Function(String, String, {String? pinyin}) onCreateFlashCard;

  const DictionaryResultWidget({
    super.key,
    required this.entry,
    required this.onCreateFlashCard,
  });

  @override
  Widget build(BuildContext context) {
    final pageContentService = PageContentService();

    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 단어 제목
          Text(
            entry.word,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          // 발음 정보
          if (entry.pinyin.isNotEmpty)
            Text(
              '발음: ${entry.pinyin}',
              style: const TextStyle(
                fontSize: 16,
                fontStyle: FontStyle.italic,
              ),
            ),

          const SizedBox(height: 8),

          // 의미 정보
          Text(
            '의미: ${entry.meaning}',
            style: const TextStyle(fontSize: 16),
          ),

          const SizedBox(height: 16),

          // 버튼 영역
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // TTS 버튼
              ElevatedButton.icon(
                onPressed: () {
                  pageContentService.speakText(entry.word);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.volume_up),
                label: const Text('읽기'),
              ),

              // 플래시카드 추가 버튼
              ElevatedButton.icon(
                onPressed: () {
                  onCreateFlashCard(
                    entry.word,
                    entry.meaning,
                    pinyin: entry.pinyin,
                  );
                  Navigator.pop(context);

                  // 추가 완료 메시지
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('플래시카드에 추가되었습니다'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.add_card),
                label: const Text('플래시카드 추가'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 사전 결과 바텀 시트 표시 헬퍼 메서드
  static void showDictionaryBottomSheet({
    required BuildContext context,
    required DictionaryEntry entry,
    required Function(String, String, {String? pinyin}) onCreateFlashCard,
  }) {
    // 간단한 스낵바로 먼저 표시 (디버깅용)
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('사전 검색 결과: ${entry.word} - ${entry.meaning}'),
        duration: const Duration(seconds: 1),
      ),
    );

    // Bottom Sheet 표시
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return DictionaryResultWidget(
          entry: entry,
          onCreateFlashCard: onCreateFlashCard,
        );
      },
    );
  }
}
