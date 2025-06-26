import 'package:flutter/material.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';

enum PikaButtonVariant {
  primary,
  outline,
  text,
  warning,
  floating,
}

enum PikaButtonSize {
  xs,
  small,
  medium,
  large,
}

class PikaButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final PikaButtonVariant variant;
  final PikaButtonSize size;
  final Widget? leadingIcon;
  final Widget? trailingIcon;
  final bool isLoading;
  final bool isFullWidth;
  final EdgeInsets? padding;
  final double? width;

  const PikaButton({
    Key? key,
    required this.text,
    this.onPressed,
    this.variant = PikaButtonVariant.primary,
    this.size = PikaButtonSize.medium,
    this.leadingIcon,
    this.trailingIcon,
    this.isLoading = false,
    this.isFullWidth = false,
    this.padding,
    this.width,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (variant == PikaButtonVariant.floating) {
      final Color backgroundColor = onPressed == null 
          ? ColorTokens.greyMedium
          : ColorTokens.primary;
      
      final Color foregroundColor = onPressed == null
          ? ColorTokens.textGrey
          : Colors.white;
          
      return FloatingActionButton.extended(
        onPressed: isLoading ? null : onPressed,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        icon: leadingIcon ?? const Icon(Icons.add),
        label: Text(text),
        elevation: onPressed == null ? 0 : 6,
        disabledElevation: 0,
      );
    }
    
    final style = _getButtonStyle();
    final padding = this.padding ?? _getButtonPadding();
    final width = isFullWidth ? double.infinity : this.width;

    return SizedBox(
      width: width,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: style,
        child: Padding(
          padding: padding,
          child: _buildButtonContent(),
        ),
      ),
    );
  }

  Widget _buildButtonContent() {
    final List<Widget> children = [];
    
    if (leadingIcon != null) {
      children.add(leadingIcon!);
      children.add(SizedBox(width: SpacingTokens.xs));
    }
    
    children.add(
      isLoading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _getLoadingColor(),
                ),
              ),
            )
          : Text(
              text,
              style: _getTextStyle(),
            ),
    );
    
    if (trailingIcon != null) {
      children.add(SizedBox(width: SpacingTokens.xs));
      children.add(trailingIcon!);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: children,
    );
  }
  
  Color _getLoadingColor() {
    return variant == PikaButtonVariant.primary || variant == PikaButtonVariant.floating
        ? Colors.white
        : ColorTokens.primary;
  }

  EdgeInsets _getButtonPadding() {
    switch (size) {
      case PikaButtonSize.xs:
        return EdgeInsets.symmetric(
          horizontal: SpacingTokens.xs,
          vertical: SpacingTokens.xs,
        );
      case PikaButtonSize.small:
        return EdgeInsets.symmetric(
          horizontal: SpacingTokens.sm,
          vertical: SpacingTokens.sm,
        );
      case PikaButtonSize.large:
        return EdgeInsets.symmetric(
          horizontal: SpacingTokens.lg,
          vertical: SpacingTokens.sm,
        );
      default:
        return EdgeInsets.symmetric(
          horizontal: SpacingTokens.md,
          vertical: SpacingTokens.sm,
        );
    }
  }

  ButtonStyle _getButtonStyle() {
    switch (variant) {
      case PikaButtonVariant.primary:
        return ElevatedButton.styleFrom(
          backgroundColor: ColorTokens.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          disabledBackgroundColor: ColorTokens.greyMedium,
          disabledForegroundColor: ColorTokens.textGrey,
        );
      
      
      
      case PikaButtonVariant.outline:
        return ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: ColorTokens.primary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: ColorTokens.primary),
          ),
          disabledBackgroundColor: ColorTokens.greyLight,
          disabledForegroundColor: ColorTokens.textGrey,
        ).copyWith(
          side: MaterialStateProperty.resolveWith<BorderSide?>((states) {
            if (states.contains(MaterialState.disabled)) {
              return BorderSide(color: ColorTokens.greyMedium);
            }
            return BorderSide(color: ColorTokens.primary);
          }),
        );
      
      case PikaButtonVariant.text:
        return ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: ColorTokens.primary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        );
        
      case PikaButtonVariant.warning:
        return ElevatedButton.styleFrom(
          backgroundColor: Colors.red[100],
          foregroundColor: Colors.red[800],
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        );
        
      default: // PikaButtonVariant.floating
        return ElevatedButton.styleFrom(); // floating은 build에서 별도 처리
    }
  }

  TextStyle _getTextStyle() {
    final baseStyle = TypographyTokens.button;
    Color textColor;
    
    // disabled 상태일 때는 disabled 색상 사용
    if (onPressed == null) {
      switch (variant) {
        case PikaButtonVariant.primary:
        case PikaButtonVariant.floating:
        case PikaButtonVariant.outline:
        case PikaButtonVariant.text:
          textColor = ColorTokens.textGrey;
          break;
        case PikaButtonVariant.warning:
          textColor = ColorTokens.textGrey;
          break;
      }
    } else {
      // enabled 상태일 때 기존 로직
      switch (variant) {
        case PikaButtonVariant.primary:
        case PikaButtonVariant.floating:
          textColor = Colors.white;
          break;
        case PikaButtonVariant.warning:
          textColor = Colors.red[800] ?? Colors.red;
          break;
        default:
          textColor = ColorTokens.textPrimary;
      }
    }
    
    switch (size) {
      case PikaButtonSize.xs:
        return baseStyle.copyWith(fontSize: 12, color: textColor);
      case PikaButtonSize.small:
        return baseStyle.copyWith(fontSize: 14, color: textColor);
      case PikaButtonSize.large:
        return baseStyle.copyWith(fontSize: 18, color: textColor);
      default:
        return baseStyle.copyWith(fontSize: 16, color: textColor);
    }
  }
}