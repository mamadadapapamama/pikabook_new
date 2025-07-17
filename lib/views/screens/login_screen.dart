import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';

import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../../core/widgets/dot_loading_indicator.dart';
import '../../features/login/view_model/login_view_model.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';
import '../../features/login/dialogs/password_reset_dialog.dart';
import '../../features/login/dialogs/email_verification_dialog.dart';
import '../../features/login/dialogs/email_not_verified_dialog.dart';


class LoginScreen extends StatelessWidget {
  final Function(User) onLoginSuccess;
  final VoidCallback? onSkipLogin;
  final bool isInitializing;

  const LoginScreen({
    Key? key,
    required this.onLoginSuccess,
    this.onSkipLogin,
    this.isInitializing = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LoginViewModel(),
      child: Consumer<LoginViewModel>(
        builder: (context, viewModel, child) {
    return Scaffold(
      body: Stack(
        children: [
                // Background
          Positioned.fill(
            child: Image.asset(
              'assets/images/splash_background.png',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    ColorTokens.black.withOpacity(0.0),
                    ColorTokens.black.withOpacity(0.3),
                    ColorTokens.black.withOpacity(0.0),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: SpacingTokens.xxl - SpacingTokens.sm),
              child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                            if (!viewModel.isEmailLogin)
                              const _LoginHeader(),
                            SizedBox(height: SpacingTokens.xl),
                            _buildLoadingAndError(context, viewModel),
                          SizedBox(height: SpacingTokens.md),
                            viewModel.isEmailLogin
                                ? _buildEmailForm(context, viewModel)
                                : _buildSocialLogins(context, viewModel),
                            SizedBox(height: SpacingTokens.md),
                            _buildSkipLoginButton(context, viewModel),
                            SizedBox(height: SpacingTokens.sm),
                            const _LegalInfoWidget(),
                            SizedBox(height: SpacingTokens.xl + SpacingTokens.sm),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingAndError(BuildContext context, LoginViewModel viewModel) {
    if (viewModel.isLoading) {
      return const DotLoadingIndicator(dotColor: ColorTokens.textLight);
    }
    if (viewModel.errorMessage != null) {
      return Container(
                              padding: EdgeInsets.all(SpacingTokens.sm + SpacingTokens.xs),
                              margin: EdgeInsets.symmetric(vertical: SpacingTokens.sm),
                              decoration: BoxDecoration(
                                color: ColorTokens.errorLight,
                                borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
                                border: Border.all(
                                  color: ColorTokens.error.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Text(
          viewModel.errorMessage!,
                                textAlign: TextAlign.center,
          style: TypographyTokens.body2.copyWith(color: ColorTokens.error),
                                ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildSocialLogins(BuildContext context, LoginViewModel viewModel) {
    return Column(
      children: [
        _buildLoginButton(
          text: 'Apple로 로그인',
          onPressed: () async {
            final user = await viewModel.handleSocialSignIn(SocialLoginType.apple);
            if (user != null) onLoginSuccess(user);
          },
          assetPath: 'assets/images/apple.png',
          icon: Icons.apple,
        ),
        SizedBox(height: SpacingTokens.sm),
        _buildLoginButton(
          text: 'Google로 로그인',
          onPressed: () async {
            final user = await viewModel.handleSocialSignIn(SocialLoginType.google);
            if (user != null) onLoginSuccess(user);
          },
          assetPath: 'assets/images/google.png',
          icon: Icons.g_translate,
        ),
        SizedBox(height: SpacingTokens.sm),
        _buildLoginButton(
          text: '이메일로 로그인',
          onPressed: () => viewModel.toggleEmailLogin(true),
          icon: Icons.email_outlined,
        ),
      ],
    );
  }

  Widget _buildEmailForm(BuildContext context, LoginViewModel viewModel) {
    return Container(
                                    width: 250,
                                    child: Column(
                                      children: [
                                        Row(
                                          children: [
                                            TextButton.icon(
                onPressed: () => viewModel.toggleEmailLogin(false),
                                              icon: Icon(Icons.arrow_back, color: ColorTokens.textLight, size: 18),
                label: Text('뒤로', style: TypographyTokens.body2.copyWith(color: ColorTokens.textLight)),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: SpacingTokens.sm),
                                        TextField(
            controller: viewModel.emailController,
                                          keyboardType: TextInputType.emailAddress,
                                          style: TypographyTokens.body1.copyWith(color: ColorTokens.textPrimary),
            decoration: _inputDecoration('이메일'),
                                        ),
                                        SizedBox(height: SpacingTokens.sm),
                                        TextField(
            controller: viewModel.passwordController,
                                          obscureText: true,
                                          style: TypographyTokens.body1.copyWith(color: ColorTokens.textPrimary),
            decoration: _inputDecoration('비밀번호'),
          ),
          if (!viewModel.isSignUp)
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: TextButton(
                onPressed: () => showPasswordResetDialog(context),
                                              child: Text(
                                                '비밀번호를 잊으셨나요?',
                                                style: TypographyTokens.body2.copyWith(
                                                  color: ColorTokens.textLight,
                                                  decoration: TextDecoration.underline,
                                                ),
                                              ),
                                            ),
                                          ),
                                        SizedBox(height: SpacingTokens.sm),
                                        ElevatedButton(
            onPressed: viewModel.isLoading ? null : () async {
              final user = await viewModel.handleEmailAuth();
              if (user != null) {
                if (viewModel.isSignUp) {
                  await showEmailVerificationDialog(context, user, onLoginSuccess);
                } else {
                  if (!user.emailVerified) {
                    await showEmailNotVerifiedDialog(context, user);
                  } else {
                    onLoginSuccess(user);
                  }
                }
              }
            },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: ColorTokens.primary,
                                            foregroundColor: ColorTokens.textLight,
              minimumSize: const Size(250, 48),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
                                            ),
                                          ),
                                          child: Text(
              viewModel.isSignUp ? '회원가입' : '로그인',
                                            style: TypographyTokens.button.copyWith(color: ColorTokens.textLight),
                                          ),
                                        ),
                                        SizedBox(height: SpacingTokens.xs),
                                        TextButton(
            onPressed: viewModel.toggleSignUp,
                                          child: Text(
              viewModel.isSignUp ? '이미 계정이 있으신가요? 로그인' : '계정이 없으신가요? 회원가입',
                                            style: TypographyTokens.body2.copyWith(
                                              color: ColorTokens.textLight,
                                              decoration: TextDecoration.underline,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
    );
  }

  Widget _buildSkipLoginButton(BuildContext context, LoginViewModel viewModel) {
    return TextButton(
      onPressed: viewModel.isLoading ? null : onSkipLogin,
                                  child: Text(
                                    '로그인 없이 둘러보기',
                                    style: TypographyTokens.button.copyWith(
                                      color: ColorTokens.textLight,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
    );
  }

  InputDecoration _inputDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TypographyTokens.body1.copyWith(color: ColorTokens.textSecondary),
      filled: true,
      fillColor: ColorTokens.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
        borderSide: BorderSide.none,
                                        ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: SpacingTokens.sm,
        vertical: SpacingTokens.sm,
      ),
    );
  }

  Widget _buildLoginButton({
    required String text,
    required VoidCallback onPressed,
    IconData? icon,
    String? assetPath,
  }) {
    return Container(
      width: 250,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: ColorTokens.surface,
          foregroundColor: ColorTokens.textPrimary,
          elevation: 0,
          padding: EdgeInsets.symmetric(vertical: SpacingTokens.sm + SpacingTokens.xsHalf, horizontal: SpacingTokens.sm),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (assetPath != null)
              Padding(
                padding: EdgeInsets.only(right: SpacingTokens.sm),
                child: Image.asset(
                  assetPath,
                  width: SpacingTokens.iconSizeMedium,
                  height: SpacingTokens.iconSizeMedium,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(icon, color: ColorTokens.black);
                  },
                ),
              )
            else if (icon != null)
              Padding(
                padding: EdgeInsets.only(right: SpacingTokens.sm),
                child: Icon(
                  icon,
                  color: ColorTokens.textPrimary,
                  size: SpacingTokens.iconSizeMedium,
                ),
              ),
            Text(
              text,
              style: TypographyTokens.buttonEn.copyWith(color: ColorTokens.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginHeader extends StatelessWidget {
  const _LoginHeader({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
            children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.15),
        Image.asset(
          'assets/images/pikabook_bird.png',
          width: SpacingTokens.iconSizeXLarge + SpacingTokens.xs,
          height: SpacingTokens.iconSizeXLarge + SpacingTokens.xs,
          fit: BoxFit.contain,
        ),
        SizedBox(height: SpacingTokens.md),
              Text(
          '책으로 하는 중국어 공부,\n스마트하게',
          textAlign: TextAlign.center,
          style: TypographyTokens.subtitle1.copyWith(
            color: ColorTokens.textLight,
            height: 1.4,
            ),
        ),
        const SizedBox(height: 12),
        Image.asset(
          'assets/images/pikabook_textlogo.png',
          width: SpacingTokens.appLogoWidth2x,
          height: SpacingTokens.appLogoHeight2x,
          fit: BoxFit.contain,
          color: ColorTokens.textLight,
              ),
            ],
    );
  }
}

class _LegalInfoWidget extends StatelessWidget {
  const _LegalInfoWidget({Key? key}) : super(key: key);

  void _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }

  @override
  Widget build(BuildContext context) {
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: TypographyTokens.body2.copyWith(color: ColorTokens.textLight),
                children: [
          const TextSpan(text: '로그인 시 '),
          TextSpan(
            text: '개인정보 처리방침',
            style: const TextStyle(decoration: TextDecoration.underline),
            recognizer: TapGestureRecognizer()
              ..onTap = () => _launchURL('https://www.pikabook.co/privacy.html'),
          ),
          const TextSpan(text: '과 '),
          TextSpan(
            text: '이용약관',
            style: const TextStyle(decoration: TextDecoration.underline),
            recognizer: TapGestureRecognizer()
              ..onTap = () => _launchURL('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/'),
          ),
          const TextSpan(text: '에 동의합니다.'),
        ],
      ),
    );
  }
}

// NOTE: The dialog implementations have been temporarily replaced with placeholders.
// They will be restored and moved to separate files in the next steps.
