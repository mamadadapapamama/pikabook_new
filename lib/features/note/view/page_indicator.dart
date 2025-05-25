import 'package:flutter/material.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/color_tokens.dart';

/// 페이지 번호 표시 위젯
class PageIndicator extends StatelessWidget {
  final int currentIndex;
  final int totalPages;
  
  const PageIndicator({
    Key? key,
    required this.currentIndex,
    required this.totalPages,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Text(
      '${currentIndex + 1}/${totalPages}',
      style: TypographyTokens.caption.copyWith(
        color: ColorTokens.textSecondary,
        fontSize: 12,
      ),
      textAlign: TextAlign.center,
    );
  }
}
