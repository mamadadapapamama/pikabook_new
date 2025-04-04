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

class _HelpTextTooltipState extends State<HelpTextTooltip> {
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
            child: Container(
              width: widget.tooltipWidth ?? 349,
              padding: widget.tooltipPadding ?? const EdgeInsets.all(20),
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
                  // 제목과 닫기 버튼을 포함하는 Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          widget.text,
                          style: TypographyTokens.subtitle1.copyWith(
                            color: widget._getTextColor,
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
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
                          padding: const EdgeInsets.all(8), // 탭 영역을 더 넓게 확장
                          decoration: BoxDecoration(
                            color: ColorTokens.greyLight.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(
                            Icons.close,
                            size: 20,
                            color: ColorTokens.textPrimary, // 더 명확한 색상으로 변경
                          ),
                        ),
                      ),
                    ],
                  ),

                  // 이미지가 있는 경우 표시
                  if (widget.image != null) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: double.infinity,
                        child: widget.image!,
                      ),
                    ),
                  ],
                  
                  // 설명이 있는 경우 추가
                  if (widget.description != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      widget.description!,
                      style: TypographyTokens.body2.copyWith(
                        color: widget._getTextColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
} 