import 'package:flutter/material.dart';
import '../../theme/tokens/color_tokens.dart';
import '../../theme/tokens/typography_tokens.dart';
import '../../theme/tokens/spacing_tokens.dart';
import '../../theme/tokens/ui_tokens.dart';
import '../../utils/debug_utils.dart';

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
  final Widget? child;
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
  final int currentStep; // 현재 단계
  final int totalSteps; // 전체 단계
  final VoidCallback? onNextStep; // 다음 단계로 이동
  final VoidCallback? onPrevStep; // 이전 단계로 이동

  const HelpTextTooltip({
    Key? key,
    required this.text,
    this.description,
    this.image,
    this.child,
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
    this.currentStep = 1,
    this.totalSteps = 1,
    this.onNextStep,
    this.onPrevStep,
  }) : super(key: key);

  @override
  State<HelpTextTooltip> createState() => _HelpTextTooltipState();
}

class _HelpTextTooltipState extends State<HelpTextTooltip> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();
    
    // 바운스 애니메이션 컨트롤러 초기화
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),  // 속도 증가
    );
    
    // 위아래로 움직이는 바운스 애니메이션 설정
    _bounceAnimation = Tween<double>(
      begin: 0.0,
      end: 6.0,  // 움직임 범위 증가
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    // 애니메이션 반복 설정
    _animationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  // 스타일 프리셋에 따른 배경색 반환
  Color get _getBackgroundColor {
    if (widget.backgroundColor != null) return widget.backgroundColor!;
    
    switch (widget.style) {
      case HelpTextTooltipStyle.primary:
        return ColorTokens.surface;
      case HelpTextTooltipStyle.success:
        return ColorTokens.successLight;
      case HelpTextTooltipStyle.warning:
        return ColorTokens.warningLight;
      case HelpTextTooltipStyle.error:
        return ColorTokens.errorLight;
      case HelpTextTooltipStyle.info:
        return ColorTokens.surface;
    }
  }
  
  // 스타일 프리셋에 따른 테두리색 반환
  Color get _getBorderColor {
    if (widget.borderColor != null) return widget.borderColor!;
    
    switch (widget.style) {
      case HelpTextTooltipStyle.primary:
        return ColorTokens.primary;
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
    if (widget.textColor != null) return widget.textColor!;
    return ColorTokens.textPrimary;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (widget.child != null) widget.child!,
        if (widget.showTooltip)
          AnimatedBuilder(
            animation: _bounceAnimation,
            builder: (context, child) {
              return Positioned(
                bottom: widget.child != null ? -widget.spacing + _bounceAnimation.value : 0,
                left: 0,
                right: 0,
                child: Container(
                  width: widget.tooltipWidth ?? 349,
                  padding: widget.tooltipPadding ?? const EdgeInsets.all(20),
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
                      // 제목과 닫기 버튼, 단계 표시
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Text(
                                  widget.text,
                                  style: TypographyTokens.body1En.copyWith(
                                    color: ColorTokens.primary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (widget.totalSteps > 1) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: ColorTokens.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${widget.currentStep}/${widget.totalSteps}',
                                      style: TypographyTokens.caption.copyWith(
                                        color: ColorTokens.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // 닫기 버튼 (터치 영역 확장 및 시각적 피드백 개선)
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                DebugUtils.log('📣 헬프텍스트 닫기 버튼 클릭됨!! - 이벤트 발생');
                                if (widget.onDismiss != null) {
                                  DebugUtils.log('📣 헬프텍스트 onDismiss 콜백 호출 시작');
                                  widget.onDismiss!();
                                  DebugUtils.log('📣 헬프텍스트 onDismiss 콜백 호출 완료');
                                } else {
                                  DebugUtils.log('⚠️ 헬프텍스트 onDismiss 콜백이 null입니다');
                                }
                              },
                              borderRadius: BorderRadius.circular(24),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: const Icon(
                                  Icons.close,
                                  color: ColorTokens.textPrimary,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                      // 이미지
                      if (widget.image != null) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: widget.image!,
                        ),
                      ],
                      
                      // 설명
                      if (widget.description != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          widget.description!,
                          style: TypographyTokens.body2.copyWith(
                            color: ColorTokens.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                      
                      // 이전/다음 단계 버튼 (다중 단계인 경우에만)
                      if (widget.totalSteps > 1) ...[
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // 이전 버튼
                            if (widget.currentStep > 1)
                              Material(
                                color: ColorTokens.greyLight,
                                borderRadius: BorderRadius.circular(8),
                                child: InkWell(
                                  onTap: () {
                                    DebugUtils.log('📣 헬프텍스트 이전 버튼 클릭됨!!');
                                    if (widget.onPrevStep != null) {
                                      widget.onPrevStep!();
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12, 
                                      vertical: 8
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.arrow_back_ios,
                                          size: 14,
                                          color: ColorTokens.textSecondary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '이전',
                                          style: TypographyTokens.button.copyWith(
                                            color: ColorTokens.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            else
                              const SizedBox(width: 80), // 이전 버튼 없을 때 공간 유지
                              
                            // 다음 버튼
                            if (widget.currentStep < widget.totalSteps)
                              Material(
                                color: ColorTokens.primary,
                                borderRadius: BorderRadius.circular(8),
                                child: InkWell(
                                  onTap: () {
                                    DebugUtils.log('📣 헬프텍스트 다음 버튼 클릭됨!!');
                                    if (widget.onNextStep != null) {
                                      widget.onNextStep!();
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12, 
                                      vertical: 8
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '다음',
                                          style: TypographyTokens.button.copyWith(
                                            color: ColorTokens.textLight,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.arrow_forward_ios,
                                          size: 14,
                                          color: ColorTokens.textLight,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
} 