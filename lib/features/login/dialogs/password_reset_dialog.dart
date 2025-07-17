import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../view_model/login_view_model.dart';

// 비밀번호 재설정 대화상자
// 이메일 주소를 입력하면 비밀번호 재설정 링크를 보내드립니다.
// 이메일을 확인해주세요.

Future<void> showPasswordResetDialog(BuildContext context) {
  final loginViewModel = Provider.of<LoginViewModel>(context, listen: false);

  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      String? errorMessage;

      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                const Icon(Icons.lock_reset, color: ColorTokens.primary, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '비밀번호 재설정',
                    style: TypographyTokens.subtitle1.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '가입하신 이메일 주소를 입력하면\n비밀번호 재설정 링크를 보내드립니다.',
                  style: TypographyTokens.body1,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: loginViewModel.emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: '이메일 주소',
                    hintText: 'example@email.com',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.email_outlined),
                    errorText: errorMessage,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text('취소', style: TypographyTokens.button.copyWith(color: ColorTokens.textSecondary)),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await loginViewModel.sendPasswordResetEmail();
                    Navigator.of(dialogContext).pop();
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('비밀번호 재설정 메일을 발송했습니다.\n이메일을 확인해주세요.'),
                        backgroundColor: ColorTokens.secondary,
                        duration: Duration(seconds: 4),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  } catch (e) {
                     setDialogState(() {
                      errorMessage = e.toString().replaceAll('Exception: ', '');
                    });
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: ColorTokens.primary,
                  foregroundColor: Colors.white,
                ),
                child: Text('재설정 메일 발송', style: TypographyTokens.button),
              ),
            ],
          );
        },
      );
    },
  );
} 