import 'package:flutter/material.dart';
import '../services/page_content_service.dart';
import '../models/dictionary_entry.dart';

/// 사전 검색 결과를 표시하는 바텀 시트 위젯

class DictionaryResultWidget extends StatelessWidget {
  final DictionaryEntry entry;
  final Function(String, String, {String? pinyin}) onCreateFlashCard;
  final bool isExistingFlashcard;

  const DictionaryResultWidget({
    super.key,
    required this.entry,
    required this.onCreateFlashCard,
    this.isExistingFlashcard = false,
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
                  // Navigator.pop(context); // 바텀 시트를 닫지 않도록 제거
                },
                icon: const Icon(Icons.volume_up),
                label: const Text('읽기'),
              ),

              // 플래시카드 추가 버튼
              ElevatedButton.icon(
                onPressed: isExistingFlashcard
                    ? null // 이미 플래시카드에 있는 경우 비활성화
                    : () {
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
                icon: Icon(isExistingFlashcard ? Icons.check : Icons.add_card),
                label: Text(isExistingFlashcard ? '이미 추가됨' : '플래시카드 추가'),
                style: isExistingFlashcard
                    ? ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[300],
                        foregroundColor: Colors.grey[700],
                      )
                    : null,
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
    bool isExistingFlashcard = false,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DictionaryResultWidget(
          entry: entry,
          onCreateFlashCard: onCreateFlashCard,
          isExistingFlashcard: isExistingFlashcard,
        ),
      ),
    );
  }
}
