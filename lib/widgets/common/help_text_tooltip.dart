import 'package:flutter/material.dart';
import '../../theme/tokens/color_tokens.dart';
import '../../theme/tokens/typography_tokens.dart';
import '../../theme/tokens/spacing_tokens.dart';

/// 툴팁 스타일 프리셋
enum HelpTextTooltipStyle {
  primary,
  success,
  warning,
  error,
  info,
}

class HelpTextTooltip extends StatefulWidget {
  final String text;
  final String? description;
  final Widget? image;
  final Widget child;
  final bool showTooltip;
  final VoidCallback? onDismiss;
  final EdgeInsets? tooltipPadding;
  final double? tooltipWidth;
  final double? tooltipHeight;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? textColor;
  final double spacing; // 버튼과 툴팁 사이의 간격
  final HelpTextTooltipStyle style; // 추가된 스타일 프리셋

  const HelpTextTooltip({
    Key? key,
    required this.text,
    this.description,
    this.image,
    required this.child,
    required this.showTooltip,
    this.onDismiss,
    this.tooltipPadding,
    this.tooltipWidth,
    this.tooltipHeight,
    this.backgroundColor,
    this.borderColor,
    this.textColor,
    this.spacing = 4.0, // 기본값 4px
    this.style = HelpTextTooltipStyle.primary, // 기본 스타일
  }) : super(key: key);

  // 스타일 프리셋에 따른 배경색 반환
  Color get _getBackgroundColor {
    if (backgroundColor != null) return backgroundColor!;
    
    switch (style) {
      case HelpTextTooltipStyle.primary:
        return ColorTokens.primaryverylight;
      case HelpTextTooltipStyle.success:
        return ColorTokens.successLight;
      case HelpTextTooltipStyle.warning:
        return ColorTokens.warningLight;
      case HelpTextTooltipStyle.error:
        return ColorTokens.errorLight;
      case HelpTextTooltipStyle.info:
        return ColorTokens.primaryverylight;
    }
  }
  
  // 스타일 프리셋에 따른 테두리색 반환
  Color get _getBorderColor {
    if (borderColor != null) return borderColor!;
    
    switch (style) {
      case HelpTextTooltipStyle.primary:
        return ColorTokens.primaryMedium;
      case HelpTextTooltipStyle.success:
        return ColorTokens.success;
      case HelpTextTooltipStyle.warning:
        return ColorTokens.warning;
      case HelpTextTooltipStyle.error:
        return ColorTokens.error;
      case HelpTextTooltipStyle.info:
        return ColorTokens.primaryMedium;
    }
  }
  
  // 스타일 프리셋에 따른 텍스트색 반환
  Color get _getTextColor {
    if (textColor != null) return textColor!;
    return ColorTokens.textPrimary;
  }

  @override
  State<HelpTextTooltip> createState() => _HelpTextTooltipState();
}

class _HelpTextTooltipState extends State<HelpTextTooltip> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: const Offset(0, -0.05),
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    // 애니메이션 반복
    _animationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (widget.showTooltip)
          Positioned(
            bottom: -widget.spacing, // 버튼과의 간격
            left: 0,
            right: 0,
            child: SlideTransition(
              position: _offsetAnimation,
              child: Container(
                width: widget.tooltipWidth ?? double.infinity,
                padding: widget.tooltipPadding ?? const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget._getBackgroundColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: widget._getBorderColor,
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 이미지가 있는 경우 먼저 표시
                    if (widget.image != null) ...[
                      Center(child: widget.image!),
                      const SizedBox(height: 8),
                    ],
                    // 툴팁 제목과 닫기 버튼을 포함하는 Row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            widget.text,
                            style: TypographyTokens.body1.copyWith(
                              color: widget._getTextColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        // 닫기 버튼
                        GestureDetector(
                          onTap: () {
                            debugPrint('HelpTextTooltip: 닫기 버튼 클릭됨');
                            if (widget.onDismiss != null) {
                              widget.onDismiss!();
                            }
                          },
                          behavior: HitTestBehavior.opaque, // 투명 영역까지 탭 감지
                          child: Container(
                            padding: const EdgeInsets.all(8), // 탭 영역 확장
                            margin: const EdgeInsets.only(top: -4, right: -4), // 위치 조정
                            child: Icon(
                              Icons.close,
                              size: 20, // 약간 더 큰 사이즈
                              color: widget._getTextColor.withOpacity(0.8), // 더 선명한 색상
                            ),
                          ),
                        ),
                      ],
                    ),
                    // 설명이 있는 경우 추가
                    if (widget.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.description!,
                        style: TypographyTokens.body2.copyWith(
                          color: widget._getTextColor,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// 아래쪽을 향하는 삼각형 화살표를 그리는 CustomPainter
class TrianglePainter extends CustomPainter {
  final Color color;

  TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// 위쪽을 향하는 삼각형 화살표를 그리는 CustomPainter
class UpwardTrianglePainter extends CustomPainter {
  final Color color;

  UpwardTrianglePainter({required this.color});

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