import 'package:flutter/material.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

class SelectionOption {
  final String value;
  final String label;
  final String? subtitle;
  final bool isDisabled;

  SelectionOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.isDisabled = false,
  });
}

class SelectionDialog extends StatelessWidget {
  final String title;
  final List<SelectionOption> options;
  final String currentValue;
  final Function(String) onSelected;

  const SelectionDialog({
    Key? key,
    required this.title,
    required this.options,
    required this.currentValue,
    required this.onSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: ColorTokens.surface,
      title: Text(title, style: TypographyTokens.subtitle2),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: options.length,
          itemBuilder: (context, index) {
            final option = options[index];
            return RadioListTile<String>(
              title: Text(
                option.label,
                style: TypographyTokens.body2,
              ),
              subtitle: option.subtitle != null
                  ? Text(
                      option.subtitle!,
                      style: TypographyTokens.caption.copyWith(
                        color: ColorTokens.textPrimary,
                      ),
                    )
                  : null,
              value: option.value,
              groupValue: currentValue,
              activeColor: ColorTokens.primary,
              onChanged: option.isDisabled
                  ? null
                  : (value) {
                      if (value != null) {
                        onSelected(value);
                      }
                      Navigator.pop(context);
                    },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            '취소',
            style: TypographyTokens.button.copyWith(
              color: ColorTokens.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
} 