import 'package:flutter/material.dart';
import '../../theme/tokens/color_tokens.dart';
import '../../theme/tokens/typography_tokens.dart';
import '../../theme/tokens/spacing_tokens.dart';

class HelpTextTooltip extends StatelessWidget {
  final String text;
  final Widget child;
  final bool showTooltip;
  final VoidCallback? onDismiss;
  final EdgeInsets? tooltipPadding;
  final double? tooltipWidth;
  final double? tooltipHeight;
  final double? arrowSize;
  final Color? backgroundColor;
  final Color? textColor;

  const HelpTextTooltip({
    Key? key,
    required this.text,
    required this.child,
    required this.showTooltip,
    this.onDismiss,
    this.tooltipPadding,
    this.tooltipWidth,
    this.tooltipHeight,
    this.arrowSize,
    this.backgroundColor,
    this.textColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (showTooltip)
          Positioned(
            top: -8, // 위젯 바로 위에 위치
            left: 0,
            right: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 툴팁 내용
                Container(
                  width: tooltipWidth ?? double.infinity,
                  padding: tooltipPadding ?? const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: backgroundColor ?? ColorTokens.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 닫기 버튼
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          GestureDetector(
                            onTap: onDismiss,
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: textColor ?? Colors.white,
                            ),
                          ),
                        ],
                      ),
                      // 툴팁 텍스트
                      Text(
                        text,
                        style: TypographyTokens.body2.copyWith(
                          color: textColor ?? Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                // 화살표
                Center(
                  child: CustomPaint(
                    size: Size(arrowSize ?? 16, arrowSize ?? 8),
                    painter: TrianglePainter(
                      color: backgroundColor ?? ColorTokens.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// 삼각형 화살표를 그리는 CustomPainter
class TrianglePainter extends CustomPainter {
  final Color color;

  TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
} 