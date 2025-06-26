import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import 'pika_button.dart';

/// 프리미엄 구독 만료 시 표시되는 앱 배너
class PremiumExpiredBanner extends StatelessWidget {
  final VoidCallback onUpgrade;
  final VoidCallback onDismiss;

  const PremiumExpiredBanner({
    super.key,
    required this.onUpgrade,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.all(SpacingTokens.md),
      padding: EdgeInsets.all(SpacingTokens.md),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: ColorTokens.secondary, // dark green outline
          width: 1.0,
        ),
        borderRadius: BorderRadius.circular(SpacingTokens.radiusXs),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 경고 아이콘
          Icon(
            Icons.info_outline,
            color: ColorTokens.secondary,
            size: SpacingTokens.iconSizeMedium,
          ),
          
          SizedBox(width: SpacingTokens.sm),
          
          // 텍스트 영역
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '프리미엄 구독이 만료되었습니다',
                  style: TypographyTokens.subtitle2.copyWith(
                    color: ColorTokens.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                
                SizedBox(height: SpacingTokens.xsHalf),
                
                Text(
                  '무료 플랜으로 전환되어 일부 기능이 제한됩니다',
                  style: TypographyTokens.body2.copyWith(
                    color: ColorTokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          
          SizedBox(width: SpacingTokens.sm),
          
          // 액션 버튼들
          Column(
            children: [
              // 업그레이드 버튼
              SizedBox(
                width: 80,
                height: 32,
                child: PikaButton(
                  text: '업그레이드',
                  variant: PikaButtonVariant.primary,
                  onPressed: onUpgrade,
                ),
              ),
              
              SizedBox(height: SpacingTokens.xs),
              
              // 닫기 버튼
              GestureDetector(
                onTap: onDismiss,
                child: Container(
                  padding: EdgeInsets.all(SpacingTokens.xs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '닫기',
                        style: TypographyTokens.caption.copyWith(
                          color: ColorTokens.textSecondary,
                        ),
                      ),
                      SizedBox(width: SpacingTokens.xsHalf),
                      Icon(
                        Icons.close,
                        size: 16,
                        color: ColorTokens.textSecondary,
                      ),
                    ],
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