import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../view_model/login_view_model.dart';

Future<void> showEmailVerificationDialog(BuildContext context, User user, Function(User) onLoginSuccess) {
  final loginViewModel = Provider.of<LoginViewModel>(context, listen: false);

  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            const Icon(Icons.mark_email_unread, color: ColorTokens.primary, size: 24),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '이메일 인증 필요',
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
              '🎉 회원가입이 완료되었습니다!',
              style: TypographyTokens.body1,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ColorTokens.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: ColorTokens.primary.withOpacity(0.3)),
              ),
              child: Text(
                '인증 메일을 ${user.email}로 발송했습니다. 이메일 인증을 완료하시고 피카북을 사용해 주세요.',
                style: TypographyTokens.body2.copyWith(color: ColorTokens.textPrimary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await loginViewModel.resendVerificationEmail();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('인증 메일을 재발송했습니다. 이메일을 확인해주세요.'),
                    backgroundColor: ColorTokens.secondary,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('인증 메일 발송에 실패했습니다: ${e.toString()}'),
                    backgroundColor: ColorTokens.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: Text('메일 재발송', style: TypographyTokens.button.copyWith(color: ColorTokens.primary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onLoginSuccess(user);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: ColorTokens.primary,
              foregroundColor: Colors.white,
            ),
            child: Text('피카북 시작하기', style: TypographyTokens.button),
          ),
        ],
      );
    },
  );
} 