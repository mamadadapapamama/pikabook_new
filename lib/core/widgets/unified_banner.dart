import 'package:flutter/material.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import 'pika_button.dart';

/// 통합된 배너 위젯 - 모든 앱 배너에 사용
class UnifiedBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? mainButtonText;
  final VoidCallback? onMainButtonPressed;
  final VoidCallback onDismiss;
  final Color? backgroundColor;
  final Color? borderColor;

  const UnifiedBanner({
    super.key,
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
      margin: EdgeInsets.symmetric(horizontal: SpacingTokens.md, vertical: SpacingTokens.xs),
      padding: EdgeInsets.all(SpacingTokens.md),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white,
        border: Border.all(
          color: borderColor ?? ColorTokens.primary, 
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // 텍스트 영역 - 확장된 공간
          Expanded(
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
                
                SizedBox(height: SpacingTokens.xs),
                
                Text(
                  subtitle,
                  style: TypographyTokens.body2.copyWith(
                    color: ColorTokens.textSecondary,
                    fontSize: 13,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          
          SizedBox(width: SpacingTokens.sm),
          
          // 액션 버튼들
            Column(
              mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
              children: [
              // 메인 버튼 (있는 경우)
              if (mainButtonText != null && onMainButtonPressed != null) ...[
                PikaButton(
                    text: mainButtonText!,
                    variant: PikaButtonVariant.primary,
                    size: PikaButtonSize.xs,
                    padding: EdgeInsets.symmetric(
                    horizontal: SpacingTokens.xs,
                    vertical: SpacingTokens.xs,
                    ),
                    onPressed: onMainButtonPressed,
                  ),
                SizedBox(height: SpacingTokens.xs),
              ],
                
              // 닫기 버튼 - 더 큰 터치 영역
              Container(
                height: 32,
                  child: TextButton(
                    onPressed: onDismiss,
                    style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: SpacingTokens.xs,
                      vertical: SpacingTokens.xs,
                    ),
                    minimumSize: Size(48, 32), // 최소 터치 영역 보장
                    tapTargetSize: MaterialTapTargetSize.padded,
                    ),
                    child: Text(
                      '닫기',
                    style: TypographyTokens.caption.copyWith(
                        color: ColorTokens.textSecondary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
} 