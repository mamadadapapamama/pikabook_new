import 'package:flutter/material.dart';
import '../core/theme/tokens/color_tokens.dart';

/// 노트 진행률 표시 바 위젯
class NoteProgressBar extends StatelessWidget {
  final double progress;
  
  const NoteProgressBar({
    Key? key,
    required this.progress,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(
      value: progress.clamp(0.0, 1.0),
      backgroundColor: ColorTokens.primarylight,
      valueColor: const AlwaysStoppedAnimation<Color>(ColorTokens.primary),
      minHeight: 2,
    );
  }
}
