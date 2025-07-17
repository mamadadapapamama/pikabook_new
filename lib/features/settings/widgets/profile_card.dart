import 'package:flutter/material.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

class ProfileCard extends StatelessWidget {
  final String displayName;
  final String email;
  final String? photoUrl;

  const ProfileCard({
    Key? key,
    required this.displayName,
    required this.email,
    this.photoUrl,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SpacingTokens.sm),
      decoration: BoxDecoration(
        color: ColorTokens.surface,
        borderRadius: BorderRadius.circular(SpacingTokens.radiusXs),
      ),
      child: Row(
        children: [
          // 프로필 이미지
          CircleAvatar(
            radius: SpacingTokens.iconSizeMedium,
            backgroundColor: ColorTokens.greyLight,
            backgroundImage: photoUrl != null ? NetworkImage(photoUrl!) : null,
            child: photoUrl == null
                ? const Icon(Icons.person, 
                    size: SpacingTokens.iconSizeMedium, 
                    color: ColorTokens.greyMedium)
                : null,
          ),
          const SizedBox(width: SpacingTokens.md),
          
          // 사용자 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: TypographyTokens.buttonEn,
                ),
                const SizedBox(height: SpacingTokens.xsHalf),
                Text(
                  email,
                  style: TypographyTokens.captionEn.copyWith(
                    color: ColorTokens.textPrimary.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
} 