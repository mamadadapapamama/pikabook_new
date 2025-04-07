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
  final TextStyle? titleStyle; // 제목 텍스트 스타일 커스터마이징
  final TextStyle? descriptionStyle; // 설명 텍스트 스타일 커스터마이징

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
    this.titleStyle,
    this.descriptionStyle,
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
    // 툴팁을 표시하지 않는 경우 자식 위젯만 반환
    if (!widget.showTooltip) {
      return widget.child ?? Container();
    }
    
    // 카드형 툴팁 위젯 반환
    return AnimatedBuilder(
      animation: _bounceAnimation,
      builder: (context, child) {
        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: _getBorderColor,
              width: 1,
            ),
          ),
          color: _getBackgroundColor,
          margin: EdgeInsets.zero,
          child: Padding(
            padding: widget.tooltipPadding ?? const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더: 제목, 단계 표시, 닫기 버튼
                Row(
                  children: [
                    // 제목과 단계 표시를 포함한 영역
                    Expanded(
                      child: Row(
                        children: [
                          // 제목 (최대 폭 제한)
                          Flexible(
                            child: Text(
                              widget.text,
                              style: widget.titleStyle != null
                                  ? widget.titleStyle
                                  : TypographyTokens.body1.copyWith(
                                      color: ColorTokens.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          
                          // 단계 표시 (총 단계가 1보다 큰 경우에만 표시)
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
                    
                    // 닫기 버튼
                    InkWell(
                      onTap: () {
                        if (widget.onDismiss != null) {
                          widget.onDismiss!();
                        }
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Icon(
                          Icons.close,
                          color: ColorTokens.textPrimary,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
                
                // 이미지 (있는 경우만 표시)
                if (widget.image != null) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: widget.image!,
                    ),
                  ),
                  const SizedBox(height: 4), // 이미지 아래에 4px 간격 추가
                ],
                
                // 설명 텍스트 (있는 경우만 표시)
                if (widget.description != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    widget.description!,
                    style: widget.descriptionStyle != null 
                        ? widget.descriptionStyle
                        : TypographyTokens.body2.copyWith(
                            color: ColorTokens.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                    textAlign: TextAlign.left,
                    strutStyle: StrutStyle(forceStrutHeight: true),
                  ),
                ],
                
                // 네비게이션 버튼 (여러 단계가 있는 경우에만 표시)
                if (widget.totalSteps > 1) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // 이전 버튼 (첫 단계가 아닌 경우에만 표시)
                      if (widget.currentStep > 1)
                        TextButton(
                          onPressed: widget.onPrevStep,
                          style: TextButton.styleFrom(
                            foregroundColor: ColorTokens.textSecondary,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: Size(48, 36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: TypographyTokens.caption.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          child: Text('이전'),
                        ),
                      
                      if (widget.currentStep > 1)
                        const SizedBox(width: 8),
                      
                      // 다음 또는 완료 버튼
                      if (widget.currentStep < widget.totalSteps)
                        // 다음 버튼
                        TextButton(
                          onPressed: widget.onNextStep,
                          style: TextButton.styleFrom(
                            foregroundColor: ColorTokens.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: Size(48, 36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: TypographyTokens.caption.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          child: Text('다음'),
                        )
                      else
                        // 완료 버튼
                        TextButton(
                          onPressed: widget.onDismiss,
                          style: TextButton.styleFrom(
                            foregroundColor: ColorTokens.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            minimumSize: Size(48, 36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: TypographyTokens.caption.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          child: Text('완료'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
} 