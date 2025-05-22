import 'package:flutter/material.dart';
import '../core/theme/tokens/color_tokens.dart';
import '../core/theme/tokens/spacing_tokens.dart';

/// 페이지 네비게이션 버튼 위젯
class PageNavigationButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool isDisabled;
  
  const PageNavigationButton({
    Key? key,
    required this.icon,
    this.onTap,
    this.isDisabled = false,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    // 상태에 따른 색상 설정
    final Color bgColor = isDisabled 
      ? ColorTokens.greyLight  // 비활성화 상태 배경색
      : (onTap != null ? ColorTokens.surface : Colors.transparent);
      
    final Color iconColor = isDisabled 
      ? ColorTokens.greyMedium  // 비활성화 상태 아이콘 색상
      : (onTap != null ? ColorTokens.secondary : ColorTokens.greyMedium);
    
    return GestureDetector(
      onTap: isDisabled ? () {} : onTap,  // 비활성화 상태에서는 onTap을 실행하지 않음
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bgColor,
        ),
        child: Center(
          child: Icon(
            icon, 
            color: iconColor,
            size: SpacingTokens.iconSizeMedium,
          ),
        ),
      ),
    );
  }
}
