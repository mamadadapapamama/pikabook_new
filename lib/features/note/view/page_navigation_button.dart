import 'package:flutter/material.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';

/// 페이지 네비게이션 버튼 위젯
class PageNavigationButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isDisabled;
  final bool isProcessing; // 처리 중 상태 추가
  
  const PageNavigationButton({
    Key? key,
    required this.icon,
    this.onTap,
    this.isDisabled = false,
    this.isProcessing = false, // 기본값은 false
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    // 상태에 따른 색상 설정
    Color bgColor;
    Color iconColor;
    
    if (isProcessing) {
      // 처리 중 상태
      bgColor = ColorTokens.primary.withOpacity(0.1);
      iconColor = ColorTokens.primary;
    } else if (isDisabled) {
      // 비활성화 상태 (처리되지 않은 페이지)
      bgColor = Colors.transparent;
      iconColor = ColorTokens.greyMedium;
    } else if (onTap != null) {
      // 활성화 상태 (처리 완료된 페이지)
      bgColor = ColorTokens.surface;
      iconColor = ColorTokens.secondary;
    } else {
      // 기본 상태
      bgColor = Colors.transparent;
      iconColor = ColorTokens.greyMedium;
    }
    
    return GestureDetector(
      onTap: (isDisabled || isProcessing) ? () {} : onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bgColor,
          border: isProcessing 
            ? Border.all(color: ColorTokens.primary.withOpacity(0.3), width: 1)
            : null,
        ),
        child: Center(
          child: isProcessing 
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(ColorTokens.primary),
                ),
              )
            : Icon(
                icon, 
                color: iconColor,
                size: SpacingTokens.iconSizeMedium,
              ),
        ),
      ),
    );
  }
}
