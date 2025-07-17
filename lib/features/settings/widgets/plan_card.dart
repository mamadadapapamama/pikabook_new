import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/widgets/pika_button.dart';
import '../settings_view_model.dart';
import 'package:provider/provider.dart';
import '../../../core/widgets/upgrade_modal.dart';


class PlanCard extends StatelessWidget {
  const PlanCard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final viewModel = Provider.of<SettingsViewModel>(context);

    return GestureDetector(
      onTap: viewModel.isPlanLoaded ? () async => await viewModel.refreshPlanInfo() : null,
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
            if (viewModel.isPlanLoaded)
              _buildPlanDetails(context, viewModel)
            else
              _buildLoadingSkeleton(),
            
            if (viewModel.isPlanLoaded && viewModel.ctaButton.text.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.md),
              PikaButton(
                text: viewModel.ctaButton.text,
                variant: viewModel.ctaButton.variant,
                size: PikaButtonSize.small,
                onPressed: viewModel.ctaButton.isEnabled 
                    ? () => viewModel.handleCTAAction(context) 
                    : null,
                isFullWidth: true,
              ),
              
              if (viewModel.ctaSubtext.isNotEmpty) ...[
                const SizedBox(height: SpacingTokens.xs),
                Center(
                  child: Text(
                    viewModel.ctaSubtext,
                    style: TypographyTokens.caption.copyWith(
                      color: ColorTokens.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlanDetails(BuildContext context, SettingsViewModel viewModel) {
    String? subtitleText;
    if (viewModel.planStatusText == '활성' || viewModel.planStatusText == '결제 문제') {
      subtitleText = viewModel.nextPaymentDateText;
    } else if (viewModel.planStatusText == '취소 예정' || viewModel.planStatusText == '종료됨') {
      subtitleText = viewModel.freeTransitionDateText;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Plan Title
            Expanded(
              child: Text(
                viewModel.planTitle, 
                style: TypographyTokens.subtitle1.copyWith(fontWeight: FontWeight.bold)
              )
            ),
            // Status Badge OR Usage Button
            if (viewModel.shouldShowUsageButton)
              PikaButton(
                text: '사용량 조회',
                variant: PikaButtonVariant.primary,
                size: PikaButtonSize.xs,
                onPressed: () {
                  // TODO: Implement usage detail view
                },
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: SpacingTokens.sm, vertical: SpacingTokens.xsHalf),
                decoration: BoxDecoration(
                  color: viewModel.planStatusText == '활성' ? ColorTokens.success.withOpacity(0.1) : ColorTokens.greyMedium.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(SpacingTokens.xsHalf),
                ),
                child: Text(
                  viewModel.planStatusText,
                  style: TypographyTokens.caption.copyWith(
                    color: viewModel.planStatusText == '활성' ? ColorTokens.success : ColorTokens.textSecondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        // Subtitle (Next payment date etc.)
        if (subtitleText != null) ...[
          const SizedBox(height: SpacingTokens.xsHalf),
          Text(subtitleText, style: TypographyTokens.body2.copyWith(color: ColorTokens.textSecondary)),
        ],
        const SizedBox(height: SpacingTokens.md),
        const Divider(color: ColorTokens.greyLight, height: 1),
      ],
    );
  }

  Widget _buildLoadingSkeleton() {
    return Container(
      width: 80,
      height: 20,
      decoration: BoxDecoration(
        color: ColorTokens.greyLight,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
} 