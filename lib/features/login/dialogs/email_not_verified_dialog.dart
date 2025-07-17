import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../view_model/login_view_model.dart';

// 이메일 인증 필요 대화상자

Future<void> showEmailNotVerifiedDialog(BuildContext context, User user) {
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
            Icon(Icons.warning_amber, color: Colors.orange[600], size: 24),
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
              '${user.email}\n이메일 인증이 완료되지 않았습니다.',
              style: TypographyTokens.body1,
            ),
            const SizedBox(height: 16),
            Text(
              '📧 인증 메일을 확인하고 인증 링크를 클릭해주세요.\n인증 후 다시 로그인해주세요.',
              style: TypographyTokens.body2.copyWith(color: ColorTokens.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await loginViewModel.resendVerificationEmail();
                Navigator.of(dialogContext).pop();
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
            child: Text('인증 메일 재발송', style: TypographyTokens.button.copyWith(color: ColorTokens.primary)),
          ),
          ElevatedButton(
            onPressed: () async {
              // Simply close the dialog and let user go back to login selection
              Navigator.of(dialogContext).pop();
              loginViewModel.toggleEmailLogin(false); 
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: ColorTokens.primary,
              foregroundColor: Colors.white,
            ),
            child: Text('확인', style: TypographyTokens.button),
          ),
        ],
      );
    },
  );
} 