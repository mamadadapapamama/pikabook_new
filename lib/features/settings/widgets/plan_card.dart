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
            
            // CTA 버튼은 무료 플랜일 때만 표시되도록 수정
            if (viewModel.isPlanLoaded && viewModel.planType == 'free') ...[
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
            ]
            // 프리미엄/체험중일 때는 App Store 관리 버튼 표시
            else if (viewModel.isPlanLoaded && viewModel.planType == 'premium') ...[
               const SizedBox(height: SpacingTokens.md),
               PikaButton(
                text: 'App Store에서 관리',
                variant: PikaButtonVariant.outline,
                size: PikaButtonSize.small,
                onPressed: () => viewModel.handleCTAAction(context),
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
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildPlanDetails(BuildContext context, SettingsViewModel viewModel) {
    String? dateInfoText = viewModel.nextPaymentDateText ?? viewModel.freeTransitionDateText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Plan Title (with remaining days)
            Expanded(
              child: Text(
                viewModel.planTitle, 
                style: TypographyTokens.subtitle1.copyWith(fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              )
            ),
            const SizedBox(width: SpacingTokens.sm),
            // Usage Button (always visible)
            PikaButton(
              text: '사용량 조회',
              variant: PikaButtonVariant.primary,
              size: PikaButtonSize.xs,
              onPressed: () {
                // TODO: Implement usage detail view
              },
            )
          ],
        ),
        // Subtitle (Next payment date etc.)
        if (viewModel.planType != 'free' && dateInfoText != null) ...[
          const SizedBox(height: SpacingTokens.xsHalf),
          Row(
            children: [
              Text(dateInfoText, style: TypographyTokens.body2.copyWith(color: ColorTokens.textSecondary)),
              const SizedBox(width: SpacingTokens.xs),
              InkWell(
                onTap: viewModel.isLoading ? null : viewModel.refreshPlanInfo,
                child: const Icon(Icons.refresh, size: 16, color: ColorTokens.textSecondary),
              ),
            ],
          ),
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