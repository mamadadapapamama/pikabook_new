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
              _buildPlanDetails(viewModel)
            else
              _buildLoadingSkeleton(),
            
            if (viewModel.isPlanLoaded && viewModel.ctaButton.text.isNotEmpty) ...[
              const SizedBox(height: SpacingTokens.md),
              PikaButton(
                text: viewModel.ctaButton.text,
                variant: viewModel.ctaButton.variant,
                size: PikaButtonSize.small,
                onPressed: viewModel.ctaButton.isEnabled 
                    ? viewModel.ctaButton.action
                    : null,
                isFullWidth: true,
              ),
              
              if (viewModel.ctaSubtext.isNotEmpty) ...[
                const SizedBox(height: SpacingTokens.xs),
                Text(
                  viewModel.ctaSubtext,
                  style: TypographyTokens.caption.copyWith(
                    color: ColorTokens.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlanDetails(SettingsViewModel viewModel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(viewModel.planTitle, style: TypographyTokens.subtitle1.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: SpacingTokens.xsHalf),
                Text(viewModel.planSubtitle, style: TypographyTokens.body2),
              ],
            ),
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
        const SizedBox(height: SpacingTokens.md),
        const Divider(color: ColorTokens.greyMedium, height: 1),
        const SizedBox(height: SpacingTokens.md),
        if (viewModel.nextPaymentDateText != null && (viewModel.planStatusText == '활성' || viewModel.planStatusText == '결제 문제'))
          _buildInfoRow(Icons.calendar_today, viewModel.nextPaymentDateText!),
        if (viewModel.freeTransitionDateText != null && (viewModel.planStatusText == '취소 예정' || viewModel.planStatusText == '종료됨'))
           _buildInfoRow(Icons.event_busy, viewModel.freeTransitionDateText!),
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

  Widget _buildInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.sm),
      child: Row(
        children: [
          Icon(icon, size: 16, color: ColorTokens.textSecondary),
          const SizedBox(width: SpacingTokens.sm),
          Text(text, style: TypographyTokens.body2),
        ],
      ),
    );
  }
} 