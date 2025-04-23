import 'package:flutter/material.dart';
import '../core/utils/text_display_mode.dart';

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
    // 병음 토글 버튼만 표시
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: _shouldShowPinyin() ? Colors.blue : Colors.grey.shade200,
        foregroundColor: _shouldShowPinyin() ? Colors.white : Colors.black87,
        minimumSize: const Size(40, 30),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      onPressed: () => _togglePinyin(),
      child: const Text('병음', style: TextStyle(fontSize: 12)),
    );
  }
  
  // 병음 표시 여부 확인
  bool _shouldShowPinyin() {
    return currentMode == TextDisplayMode.all;
  }
  
  // 병음 토글
  void _togglePinyin() {
    TextDisplayMode newMode;
    
    if (_shouldShowPinyin()) {
      // 병음 끄기
      newMode = TextDisplayMode.nopinyin;
    } else {
      // 병음 켜기
      newMode = TextDisplayMode.all;
    }
    
    // 모드 변경 콜백 호출
    onModeChanged(newMode);
  }
}
