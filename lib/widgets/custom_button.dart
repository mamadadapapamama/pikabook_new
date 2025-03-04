import 'package:flutter/material.dart';

enum ButtonType { primary, secondary, outline, text }

class CustomButton extends StatelessWidget {
  final String text;
  final void Function()? onPressed;
  final ButtonType type;
  final IconData? icon;
  final bool isLoading;
  final bool isFullWidth;
  final double? width;
  final double height;
  final double borderRadius;

  const CustomButton({
    Key? key,
    required this.text,
    required this.onPressed,
    this.type = ButtonType.primary,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = false,
    this.width,
    this.height = 48.0,
    this.borderRadius = 8.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 버튼 타입에 따른 스타일 설정
    Color backgroundColor;
    Color textColor;
    Color borderColor;

    switch (type) {
      case ButtonType.primary:
        backgroundColor = theme.primaryColor;
        textColor = Colors.white;
        borderColor = Colors.transparent;
        break;
      case ButtonType.secondary:
        backgroundColor = theme.colorScheme.secondary;
        textColor = Colors.white;
        borderColor = Colors.transparent;
        break;
      case ButtonType.outline:
        backgroundColor = Colors.transparent;
        textColor = theme.primaryColor;
        borderColor = theme.primaryColor;
        break;
      case ButtonType.text:
        backgroundColor = Colors.transparent;
        textColor = theme.primaryColor;
        borderColor = Colors.transparent;
        break;
    }

    // 버튼 내용 위젯
    Widget buttonContent = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading)
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                valueColor: AlwaysStoppedAnimation<Color>(textColor),
              ),
            ),
          )
        else if (icon != null)
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: Icon(icon, color: textColor, size: 18),
          ),
        Text(
          text,
          style: theme.textTheme.labelLarge?.copyWith(
            color: textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );

    // 버튼 위젯 생성
    return SizedBox(
      width: isFullWidth ? double.infinity : width,
      height: height,
      child: type == ButtonType.text
          ? TextButton(
              onPressed: isLoading ? null : onPressed,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(borderRadius),
                ),
              ),
              child: buttonContent,
            )
          : ElevatedButton(
              onPressed: isLoading ? null : onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: backgroundColor,
                foregroundColor: textColor,
                elevation: type == ButtonType.outline ? 0 : 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(borderRadius),
                  side: BorderSide(color: borderColor),
                ),
              ),
              child: buttonContent,
            ),
    );
  }
}
