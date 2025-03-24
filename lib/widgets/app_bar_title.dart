import 'package:flutter/material.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/color_tokens.dart';

class AppBarTitle extends StatelessWidget {
  final String title;
  
  const AppBarTitle({
    Key? key,
    required this.title,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0),
      child: Text(
        title,
        style: TypographyTokens.headline3.copyWith(
          color: ColorTokens.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
} 