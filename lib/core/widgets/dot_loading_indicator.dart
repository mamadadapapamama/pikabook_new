import 'package:flutter/material.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';

/// 도트 애니메이션 로딩 인디케이터 위젯 (로딩의 기본 유닛)
/// 세 개의 도트가 애니메이션되는 심플한 로딩 인디케이터입니다.

class DotLoadingIndicator extends StatefulWidget {
  final String? message;
  final Color dotColor;
  final double dotSize;
  final double spacing;
  final bool isLoginScreen;

  const DotLoadingIndicator({
    Key? key,
    this.message,
    this.dotColor = ColorTokens.primary,
    this.dotSize = 10.0,
    this.spacing = 8.0,
    this.isLoginScreen = false,
  }) : super(key: key);

  @override
  State<DotLoadingIndicator> createState() => _DotLoadingIndicatorState();
}

class _DotLoadingIndicatorState extends State<DotLoadingIndicator> with SingleTickerProviderStateMixin {
  // 단일 컨트롤러로 변경
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    
    // 단일 애니메이션 컨트롤러 사용
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 현재 테마의 밝기 확인
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    // 테마에 따른 텍스트 색상 설정
    final textColor = isDarkMode ? ColorTokens.textLight : ColorTokens.textPrimary;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // CustomPaint를 사용하여 도트 애니메이션 직접 그리기
          CustomPaint(
            size: Size(
              widget.dotSize * 3 + widget.spacing * 2,
              widget.dotSize + (widget.isLoginScreen ? 0 : 8), // 위치 애니메이션 높이 고려
            ),
            painter: _DotsPainter(
              animation: _controller,
              dotColor: widget.dotColor,
              dotSize: widget.dotSize,
              spacing: widget.spacing,
              isLoginScreen: widget.isLoginScreen,
            ),
          ),
          
          if (widget.message != null) ...[
            const SizedBox(height: 16),
            if (kReleaseMode || widget.message == null || widget.message!.isEmpty)
              const SizedBox.shrink()
            else
              Text(
                widget.message!,
                textAlign: TextAlign.center,
                style: TypographyTokens.body2.copyWith(
                  color: textColor,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 도트를 직접 그리는 CustomPainter
class _DotsPainter extends CustomPainter {
  final Animation<double> animation;
  final Color dotColor;
  final double dotSize;
  final double spacing;
  final bool isLoginScreen;

  final Paint _paint;

  _DotsPainter({
    required this.animation,
    required this.dotColor,
    required this.dotSize,
    required this.spacing,
    required this.isLoginScreen,
  }) : _paint = Paint()..color = dotColor,
       super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.height / 2;
    final totalWidth = dotSize * 3 + spacing * 2;
    final startX = (size.width - totalWidth) / 2;

    for (int i = 0; i < 3; i++) {
      final double offsetPercent = i * 0.2; // 0.0, 0.2, 0.4 오프셋
      final double value = (animation.value + offsetPercent) % 1.0;

      final double x = startX + i * (dotSize + spacing);
      double y = center;
      double currentOpacity = 1.0;

      if (isLoginScreen) {
        // 투명도 애니메이션 (0.3 ~ 1.0)
        currentOpacity = 0.3 + 0.7 * (sin(value * 2 * pi) * 0.5 + 0.5);
      } else {
        // 위치 애니메이션 (위로 최대 8)
        y = center - (8.0 * (sin(value * 2 * pi) * 0.5 + 0.5));
      }

      // 페인트 색상 및 투명도 설정
      _paint.color = dotColor.withOpacity(currentOpacity);

      // 원 그리기
      canvas.drawCircle(Offset(x + dotSize / 2, y), dotSize / 2, _paint);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter oldDelegate) {
    // 애니메이션이 변경될 때만 다시 그림
    return animation.value != oldDelegate.animation.value ||
           dotColor != oldDelegate.dotColor ||
           dotSize != oldDelegate.dotSize ||
           spacing != oldDelegate.spacing ||
           isLoginScreen != oldDelegate.isLoginScreen;
  }
} 