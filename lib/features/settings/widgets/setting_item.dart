import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

class SettingItem extends StatelessWidget {
  final String title;
  final String value;
  final VoidCallback onTap;

  const SettingItem({
    Key? key,
    required this.title,
    required this.value,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SpacingTokens.radiusXs),
        child: Container(
          width: double.infinity,
          height: SpacingTokens.buttonHeight + SpacingTokens.sm,
          padding: const EdgeInsets.symmetric(
            horizontal: SpacingTokens.md,
            vertical: SpacingTokens.sm,
          ),
          decoration: BoxDecoration(
            color: ColorTokens.surface,
            borderRadius: BorderRadius.circular(SpacingTokens.radiusXs),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TypographyTokens.captionEn.copyWith(
                      color: ColorTokens.textSecondary,
                    ),
                  ),
                  Text(
                    value,
                    style: TypographyTokens.body2,
                  ),
                ],
              ),
              SvgPicture.asset(
                'assets/images/icon_arrow_right.svg',
                width: SpacingTokens.iconSizeSmall + SpacingTokens.xs,
                height: SpacingTokens.iconSizeSmall + SpacingTokens.xs,
                colorFilter: const ColorFilter.mode(
                  ColorTokens.secondary,
                  BlendMode.srcIn,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 