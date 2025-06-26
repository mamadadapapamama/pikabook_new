import 'package:flutter/material.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import '../theme/tokens/typography_tokens.dart';

/// 사용량 한도 도달 시 표시되는 배너 위젯
class UsageLimitBanner extends StatelessWidget {
  final VoidCallback? onDismiss;
  final VoidCallback? onUpgrade;

  const UsageLimitBanner({
    super.key,
    this.onDismiss,
    this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.all(SpacingTokens.md),
      padding: EdgeInsets.all(SpacingTokens.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ColorTokens.warning,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: ColorTokens.warning.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 경고 아이콘
          Container(
            padding: EdgeInsets.all(SpacingTokens.xs),
            decoration: BoxDecoration(
              color: ColorTokens.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.warning_rounded,
              color: ColorTokens.warning,
              size: 24,
            ),
          ),
          
          SizedBox(width: SpacingTokens.md),
          
          // 텍스트 영역
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '사용량 한도에 도달했어요',
                  style: TypographyTokens.subtitle2.copyWith(
                    color: ColorTokens.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                
                SizedBox(height: SpacingTokens.xsHalf),
                
                Text(
                  '추가로 사용하시려면 업그레이드 해주세요',
                  style: TypographyTokens.body2.copyWith(
                    color: ColorTokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          
          // 업그레이드 버튼
          if (onUpgrade != null) ...[
            SizedBox(width: SpacingTokens.sm),
            TextButton(
              onPressed: onUpgrade,
              style: TextButton.styleFrom(
                backgroundColor: ColorTokens.warning,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: SpacingTokens.md,
                  vertical: SpacingTokens.xs,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                '업그레이드',
                style: TypographyTokens.body2.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          
          // 닫기 버튼
          if (onDismiss != null) ...[
            SizedBox(width: SpacingTokens.xs),
            IconButton(
              onPressed: onDismiss,
              icon: Icon(
                Icons.close,
                color: ColorTokens.textSecondary,
                size: 20,
              ),
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              padding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
    );
  }
} 