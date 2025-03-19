import 'package:flutter/material.dart';
import '../utils/text_display_mode.dart';
import '../services/page_content_service.dart';

/// 텍스트 표시 모드를 전환하는 토글 버튼 위젯. 

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

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 텍스트 표시 모드 토글 버튼
        ToggleButtons(
          constraints: const BoxConstraints(
            minHeight: 32,
            minWidth: 76,
          ),
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
          borderRadius: BorderRadius.circular(6),
          children: const [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('A', style: TextStyle(fontSize: 13)),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('B', style: TextStyle(fontSize: 13)),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('C', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
        
        // TTS 버튼 제거 (바텀 바에서 제공)
      ],
    );
  }
}
