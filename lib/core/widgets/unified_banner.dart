import 'package:flutter/material.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import 'pika_button.dart';

/// 통합된 배너 위젯 - 모든 앱 배너에 사용
class UnifiedBanner extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String? mainButtonText;
  final VoidCallback? onMainButtonPressed;
  final VoidCallback onDismiss;
  final Color? backgroundColor;
  final Color? borderColor;

  const UnifiedBanner({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onDismiss,
    this.mainButtonText,
    this.onMainButtonPressed,
    this.backgroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(SpacingTokens.md),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white,
        border: Border.all(
          color: borderColor ?? ColorTokens.primary, 
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(SpacingTokens.radiusXs),
        boxShadow: mainButtonText != null ? [
          BoxShadow(
            color: (borderColor ?? ColorTokens.primary).withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ] : null,
      ),
      child: Row(
        children: [
          // 아이콘
          Container(
            padding: mainButtonText != null ? EdgeInsets.all(SpacingTokens.xs) : EdgeInsets.zero,
            decoration: mainButtonText != null ? BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ) : null,
            child: Icon(
              icon,
              color: iconColor,
              size: mainButtonText != null ? 24 : SpacingTokens.iconSizeSmall,
            ),
          ),
          
          SizedBox(width: SpacingTokens.sm),
          
          // 텍스트 영역 - 유연한 크기 조정
          Expanded(
            flex: 3, // 텍스트 영역에 더 많은 공간 할당
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TypographyTokens.body1.copyWith(
                    color: ColorTokens.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                
                SizedBox(height: SpacingTokens.xsHalf),
                
                Text(
                  subtitle,
                  style: TypographyTokens.body2.copyWith(
                    color: ColorTokens.textPrimary,
                    fontSize: 13, // 🎯 더 작은 폰트 크기
                  ),
                  maxLines: 2, // 최대 2줄로 제한
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          
          SizedBox(width: SpacingTokens.xs), // 간격 줄임
          
          // 액션 버튼들
          if (mainButtonText != null && onMainButtonPressed != null) ...[
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 메인 버튼 - 텍스트 길이에 따라 자동 조정
                LayoutBuilder(
                  builder: (context, constraints) {
                    return ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: 75,  // 최소 width
                        maxWidth: 100, // 최대 width
                        minHeight: 32,
                        maxHeight: 32,
                      ),
                      child: PikaButton(
                        text: mainButtonText!,
                        variant: PikaButtonVariant.primary,
                        size: PikaButtonSize.xs,
                        padding: EdgeInsets.symmetric(
                          horizontal: SpacingTokens.xs - 1,
                          vertical: SpacingTokens.xs - 1,
                        ),
                        onPressed: onMainButtonPressed,
                      ),
                    );
                  },
                ),
            
                SizedBox(height: SpacingTokens.xs),
                
                // 닫기 버튼 (텍스트 버튼)
                SizedBox(
                  height: 20,
                  child: TextButton(
                    onPressed: onDismiss,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      '닫기',
                      style: TextStyle(
                        fontSize: 12,
                        color: ColorTokens.textSecondary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            // 메인 버튼이 없는 경우 (체험 완료 배너) - 텍스트 버튼
            SizedBox(
              height: 20,
              child: TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  '닫기',
                  style: TextStyle(
                    fontSize: 12,
                    color: ColorTokens.textSecondary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
} 