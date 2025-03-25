import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/ui_tokens.dart';

// 설정 버튼 (homescreen app bar 에서 사용)

class AppBarMenuButton extends StatelessWidget {
  const AppBarMenuButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 16.0),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.pushNamed(context, '/settings');
          },
          splashColor: ColorTokens.primary.withOpacity(0.1),
          highlightColor: ColorTokens.primary.withOpacity(0.05),
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              Icons.settings_outlined,
              color: ColorTokens.textSecondary,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
} 