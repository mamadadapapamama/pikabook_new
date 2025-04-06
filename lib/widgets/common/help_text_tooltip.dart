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
    // 모달 형태로 변경: Stack 대신 위젯을 반환하고, 쇼툴팁이 true면 모달 다이얼로그를 표시
    if (widget.showTooltip) {
      // 포스트 프레임 콜백으로 모달 표시 (빌드 사이클 중에 showDialog 호출 방지)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          barrierDismissible: false,
          barrierColor: Colors.transparent, // 투명 배경으로 설정
          builder: (dialogContext) {
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: EdgeInsets.zero,
              child: Stack(
                children: [
                  // 모달 컨테이너
                  Positioned(
                    bottom: MediaQuery.of(context).size.height * 0.1, // 화면 하단에서 10% 위치에 배치
                    left: 16,
                    right: 16,
                    child: AnimatedBuilder(
                      animation: _bounceAnimation,
                      builder: (context, child) {
                        return Container(
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
                                  // 닫기 버튼 (확장된 터치 영역)
                                  GestureDetector(
                                    onTap: () {
                                      DebugUtils.log('📣 헬프텍스트 닫기 버튼 클릭됨!! - 이벤트 발생');
                                      // 다이얼로그가 열려있는지 확인하고 닫기
                                      if (Navigator.of(dialogContext).canPop()) {
                                        Navigator.of(dialogContext).pop();
                                      }
                                      
                                      // 약간의 지연 후 onDismiss 콜백 실행
                                      Future.delayed(Duration(milliseconds: 100), () {
                                        if (widget.onDismiss != null) {
                                          DebugUtils.log('📣 헬프텍스트 onDismiss 콜백 호출 시작 (지연 실행)');
                                          widget.onDismiss!();
                                          DebugUtils.log('📣 헬프텍스트 onDismiss 콜백 호출 완료');
                                        } else {
                                          DebugUtils.log('⚠️ 헬프텍스트 onDismiss 콜백이 null입니다');
                                        }
                                      });
                                    },
                                    child: Container(
                                      width: 40,
                                      height: 40,
                                      child: Center(
                                        child: Icon(
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
                              
                              // 다음 버튼 및 이전 버튼 (여러 단계가 있는 경우)
                              if (widget.totalSteps > 1) ...[
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (widget.currentStep > 1) // 첫 단계가 아닌 경우에만 이전 버튼 표시
                                      TextButton(
                                        onPressed: () {
                                          Navigator.of(dialogContext).pop(); // 현재 다이얼로그 닫기
                                          if (widget.onPrevStep != null) {
                                            widget.onPrevStep!();
                                          }
                                        },
                                        style: TextButton.styleFrom(
                                          foregroundColor: ColorTokens.textSecondary,
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          minimumSize: Size(10, 10),
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          textStyle: TypographyTokens.caption.copyWith(
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        child: Text('이전'),
                                      ),
                                    
                                    if (widget.currentStep > 1)
                                      const SizedBox(width: 8),
                                    
                                    if (widget.currentStep < widget.totalSteps) // 마지막 단계가 아닌 경우에만 다음 버튼 표시
                                      TextButton(
                                        onPressed: () {
                                          Navigator.of(dialogContext).pop(); // 현재 다이얼로그 닫기
                                          if (widget.onNextStep != null) {
                                            widget.onNextStep!();
                                          }
                                        },
                                        style: TextButton.styleFrom(
                                          foregroundColor: ColorTokens.primary,
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          minimumSize: Size(10, 10),
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          textStyle: TypographyTokens.caption.copyWith(
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        child: Text('다음'),
                                      )
                                    else
                                      TextButton(
                                        onPressed: () {
                                          Navigator.of(dialogContext).pop(); // 다이얼로그 닫기
                                          
                                          // 약간의 지연 후 onDismiss 콜백 실행
                                          Future.delayed(Duration(milliseconds: 100), () {
                                            if (widget.onDismiss != null) {
                                              DebugUtils.log('📣 헬프텍스트 완료 버튼 - onDismiss 콜백 호출');
                                              widget.onDismiss!();
                                            }
                                          });
                                        },
                                        style: TextButton.styleFrom(
                                          foregroundColor: ColorTokens.primary,
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          minimumSize: Size(10, 10),
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
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      });
    }
    
    // 자식 위젯만 반환하거나 빈 컨테이너 반환
    return widget.child ?? Container();
  }
} 