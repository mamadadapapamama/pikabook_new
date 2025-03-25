import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import '../theme/tokens/ui_tokens.dart';

/// 홈 스크린의 앱바 컴포넌트
/// 앱 로고, 노트 스페이스 이름, 설정 버튼을 포함
class HomeScreenAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String noteSpaceName;
  final VoidCallback onSettingsPressed;

  const HomeScreenAppBar({
    Key? key,
    required this.noteSpaceName,
    required this.onSettingsPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(61), // 앱바 높이 조정 (원래 높이 + 상단 패딩)
      child: Padding(
        padding: const EdgeInsets.only(top: 20.0),
        child: AppBar(
          backgroundColor: UITokens.homeBackground,
          elevation: 0,
          automaticallyImplyLeading: false,
          titleSpacing: 0,
          title: Padding(
            padding: const EdgeInsets.only(left: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 앱 로고
                Container(
                  alignment: Alignment.centerLeft,
                  child: SvgPicture.asset(
                    'assets/images/logo_pika_small.svg',
                    width: SpacingTokens.appLogoWidth,
                    height: SpacingTokens.appLogoHeight,
                    placeholderBuilder: (context) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.menu_book,
                          color: ColorTokens.primary,
                          size: SpacingTokens.iconSizeSmall,
                        ),
                        SizedBox(width: SpacingTokens.xs),
                        Text(
                          'Pikabook',
                          style: GoogleFonts.poppins(
                            fontSize: SpacingTokens.md,
                            fontWeight: FontWeight.bold,
                            color: ColorTokens.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: SpacingTokens.xs),
                // 노트 스페이스 이름
                Row(
                  children: [
                    Text(
                      noteSpaceName,
                      style: TypographyTokens.headline3.copyWith(
                        color: ColorTokens.textPrimary,
                      ),
                      textAlign: TextAlign.left,
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            // 설정 버튼
            Padding(
              padding: EdgeInsets.only(right: SpacingTokens.md),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(24),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onSettingsPressed,
                  splashColor: ColorTokens.primary.withOpacity(0.1),
                  highlightColor: ColorTokens.primary.withOpacity(0.05),
                  customBorder: const CircleBorder(),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: SizedBox(
                      width: SpacingTokens.iconSizeMedium,
                      height: SpacingTokens.iconSizeMedium,
                      child: SvgPicture.asset(
                        'assets/images/icon_profile.svg',
                        width: SpacingTokens.iconSizeMedium,
                        height: SpacingTokens.iconSizeMedium,
                        placeholderBuilder: (context) => Icon(
                          Icons.person,
                          color: ColorTokens.secondary,
                          size: SpacingTokens.iconSizeMedium,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(80);
} 