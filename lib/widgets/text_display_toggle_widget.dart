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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 텍스트 표시 모드 토글 버튼
        ToggleButtons(
          constraints: const BoxConstraints(
            minHeight: 28,
            minWidth: 40,
          ),
          isSelected: [
            currentMode == TextDisplayMode.original || currentMode == TextDisplayMode.all,
            currentMode == TextDisplayMode.pinyin || currentMode == TextDisplayMode.all,
            currentMode == TextDisplayMode.translation || currentMode == TextDisplayMode.all,
          ],
          onPressed: (index) {
            // 현재 토글 상태 확인
            List<bool> currentToggles = [
              currentMode == TextDisplayMode.original || currentMode == TextDisplayMode.all,
              currentMode == TextDisplayMode.pinyin || currentMode == TextDisplayMode.all,
              currentMode == TextDisplayMode.translation || currentMode == TextDisplayMode.all,
            ];
            
            // 토글 상태 변경
            currentToggles[index] = !currentToggles[index];
            
            // 모드 결정 로직
            if (currentToggles.every((isSelected) => isSelected)) {
              // 모두 선택된 경우
              onModeChanged(TextDisplayMode.all);
            } else if (currentToggles.every((isSelected) => !isSelected)) {
              // 모두 선택되지 않은 경우 (최소 하나는 선택되어야 함)
              currentToggles[index] = true;
              if (index == 0) {
                onModeChanged(TextDisplayMode.original);
              } else if (index == 1) {
                onModeChanged(TextDisplayMode.pinyin);
              } else {
                onModeChanged(TextDisplayMode.translation);
              }
            } else {
              // 일부만 선택된 경우
              if (currentToggles[0] && !currentToggles[1] && !currentToggles[2]) {
                onModeChanged(TextDisplayMode.original);
              } else if (!currentToggles[0] && currentToggles[1] && !currentToggles[2]) {
                onModeChanged(TextDisplayMode.pinyin);
              } else if (!currentToggles[0] && !currentToggles[1] && currentToggles[2]) {
                onModeChanged(TextDisplayMode.translation);
              } else {
                // 두 개 이상 선택된 경우 all로 처리
                onModeChanged(TextDisplayMode.all);
              }
            }
          },
          borderRadius: BorderRadius.circular(4),
          children: const [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('원문', style: TextStyle(fontSize: 12)),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('병음', style: TextStyle(fontSize: 12)),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('번역', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }
}
