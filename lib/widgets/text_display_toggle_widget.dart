import 'package:flutter/material.dart';
import '../utils/text_display_mode.dart';
import '../services/page_content_service.dart';

/// 텍스트 표시 모드를 전환하는 토글 버튼 위젯
class TextDisplayToggleWidget extends StatelessWidget {
  final TextDisplayMode currentMode;
  final Function(TextDisplayMode) onModeChanged;
  final String originalText;

  const TextDisplayToggleWidget({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
    required this.originalText,
  });

  @override
  Widget build(BuildContext context) {
    final pageContentService = PageContentService();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 텍스트 표시 모드 토글 버튼
          ToggleButtons(
            isSelected: [
              currentMode == TextDisplayMode.both,
              currentMode == TextDisplayMode.originalOnly,
              currentMode == TextDisplayMode.translationOnly,
            ],
            onPressed: (index) {
              switch (index) {
                case 0:
                  onModeChanged(TextDisplayMode.both);
                  break;
                case 1:
                  onModeChanged(TextDisplayMode.originalOnly);
                  break;
                case 2:
                  onModeChanged(TextDisplayMode.translationOnly);
                  break;
              }
            },
            borderRadius: BorderRadius.circular(8),
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('모두 보기'),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('원문만'),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('번역만'),
              ),
            ],
          ),

          // TTS 버튼 (원문 읽기)
          IconButton(
            icon: const Icon(Icons.volume_up),
            tooltip: '원문 읽기',
            onPressed: () => pageContentService.speakText(originalText),
          ),
        ],
      ),
    );
  }
}
