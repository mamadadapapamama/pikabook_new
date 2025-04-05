import 'package:flutter/material.dart';
import '../../theme/tokens/color_tokens.dart';
import '../../theme/tokens/typography_tokens.dart';
import '../../theme/tokens/spacing_tokens.dart';
import '../../theme/tokens/ui_tokens.dart';

/// 툴팁 스타일 프리셋
enum HelpTextTooltipStyle {
  primary,
  success,
  warning,
  error,
  info,
}

class HelpTextTooltip extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (showTooltip)
          Positioned(
            bottom: -spacing,
            left: 0,
            right: 0,
            child: Container(
              width: tooltipWidth ?? 349,
              padding: tooltipPadding ?? const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _getBackgroundColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _getBorderColor,
                  width: 1,
                ),
                boxShadow: UITokens.mediumShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 제목과 닫기 버튼
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          text,
                          style: TypographyTokens.subtitle1.copyWith(
                            color: _getTextColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      // 닫기 버튼 (최대한 단순하게 구현)
                      IconButton(
                        onPressed: () {
                          print('닫기 버튼 클릭 - 단순 IconButton');
                          if (onDismiss != null) {
                            onDismiss!();
                          }
                        },
                        icon: const Icon(Icons.close),
                        color: ColorTokens.primary,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        splashRadius: 20,
                        tooltip: '닫기',
                      ),
                    ],
                  ),
                  
                  // 이미지
                  if (image != null) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: image!,
                    ),
                  ],
                  
                  // 설명
                  if (description != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      description!,
                      style: TypographyTokens.body2.copyWith(
                        color: _getTextColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
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