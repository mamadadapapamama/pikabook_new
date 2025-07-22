import 'package:flutter/material.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/widgets/pika_button.dart';
import '../settings_view_model.dart';
import 'package:provider/provider.dart';
import '../../../core/models/subscription_state.dart'; // Entitlement enum import

//내플랜 카드 위젯
class PlanCard extends StatelessWidget {
  const PlanCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<SettingsViewModel>(context);
    final subscriptionInfo = viewModel.subscriptionInfo;

    return GestureDetector(
      onTap: () => viewModel.refreshPlanInfo(force: true),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (viewModel.isPlanLoaded && subscriptionInfo != null)
              _buildPlanDetails(context, viewModel, subscriptionInfo)
            else
              _buildLoadingSkeleton(),
            
            if (viewModel.isPlanLoaded && subscriptionInfo != null) ...[
              const SizedBox(height: SpacingTokens.md),
              PikaButton(
                text: subscriptionInfo.ctaText,
                variant: subscriptionInfo.entitlement == Entitlement.free ? PikaButtonVariant.primary : PikaButtonVariant.outline,
                size: PikaButtonSize.small,
                onPressed: subscriptionInfo.entitlement == Entitlement.premium 
                    ? null // 🎯 프리미엄 상태일 때는 버튼 비활성화
                    : () => viewModel.handleCTAAction(context),
                isFullWidth: true,
              ),
              if (subscriptionInfo.ctaSubtext != null) ...[
                const SizedBox(height: SpacingTokens.xs),
                Center(
                  child: Text(
                    subscriptionInfo.ctaSubtext!,
                    style: TypographyTokens.caption.copyWith(
                      color: ColorTokens.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildPlanDetails(BuildContext context, SettingsViewModel viewModel, subscriptionInfo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      subscriptionInfo.planTitle, 
                      style: TypographyTokens.subtitle1.copyWith(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: SpacingTokens.xs),
                  InkWell(
                    onTap: viewModel.isLoading ? null : () => viewModel.refreshPlanInfo(force: true),
                    child: const Icon(Icons.refresh, size: 18, color: ColorTokens.textSecondary),
                  ),
                ],
              ),
            ),
            PikaButton(
              text: '사용량 조회',
              variant: PikaButtonVariant.primary,
              size: PikaButtonSize.small,
              onPressed: () => viewModel.showUsageDialog(context),
            )
          ],
        ),
        if (subscriptionInfo.dateInfoText != null) ...[
          const SizedBox(height: SpacingTokens.xsHalf),
          Text(
            subscriptionInfo.dateInfoText!, 
            style: TypographyTokens.body2.copyWith(color: ColorTokens.textSecondary)
          ),
        ]
      ],
    );
  }

  Widget _buildLoadingSkeleton() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SkeletonBox(width: 120, height: 24),
            SkeletonBox(width: 80, height: 28),
          ],
        ),
        SizedBox(height: SpacingTokens.xsHalf),
        SkeletonBox(width: 150, height: 18),
        SizedBox(height: SpacingTokens.md),
        Divider(color: ColorTokens.greyLight, height: 1),
      ],
    );
  }
}

class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  const SkeletonBox({Key? key, required this.width, required this.height}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: ColorTokens.greyLight,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
} 