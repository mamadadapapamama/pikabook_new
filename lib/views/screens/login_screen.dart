import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../services/initialization_service.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/tokens/color_tokens.dart';
import '../../../widgets/loading_indicator.dart';

class LoginScreen extends StatefulWidget {
  final InitializationService initializationService;
  final VoidCallback onLoginSuccess;
  final VoidCallback? onSkipLogin;

  const LoginScreen({
    Key? key,
    required this.initializationService,
    required this.onLoginSuccess,
    this.onSkipLogin,
  }) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 앱 로고 또는 이미지
                  Icon(
                    Icons.menu_book,
                    size: 80,
                    color: ColorTokens.primary,
                  ),
                  const SizedBox(height: 24),

                  // 앱 이름
                  Text(
                    'PikaBook',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: ColorTokens.primary,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 앱 설명
                  const Text(
                    '중국어 학습을 위한 최고의 도구',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // 로딩 인디케이터 또는 오류 메시지
                  if (_isLoading)
                    const LoadingIndicator(message: '로그인 중...')
                  else if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.red.shade800,
                          fontSize: 14,
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Google 로그인 버튼
                  _buildLoginButton(
                    text: 'Google로 로그인',
                    icon: Icons.g_mobiledata,
                    onPressed: _handleGoogleSignIn,
                    backgroundColor: Colors.white,
                    textColor: Colors.black87,
                  ),
                  const SizedBox(height: 16),

                  // Apple 로그인 버튼
                  _buildLoginButton(
                    text: 'Apple로 로그인',
                    icon: Icons.apple,
                    onPressed: _handleAppleSignIn,
                    backgroundColor: Colors.black,
                    textColor: Colors.white,
                  ),
                  const SizedBox(height: 24),

                  // 로그인 안내 텍스트
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16.0, vertical: 8.0),
                    child: Text(
                      '소셜 계정으로 로그인하여 모든 기기에서 데이터를 동기화하고 백업할 수 있습니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginButton({
    required String text,
    required IconData icon,
    required VoidCallback onPressed,
    required Color backgroundColor,
    required Color textColor,
  }) {
    return ElevatedButton(
      onPressed: _isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: textColor,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: Colors.grey.shade300,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon),
          const SizedBox(width: 12),
          Text(
            text,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleGoogleSignIn() async {
    _setLoading(true);
    try {
      // Firebase 초기화 확인
      if (!Firebase.apps.isNotEmpty) {
        throw Exception('Firebase가 초기화되지 않았습니다.');
      }

      final userCredential =
          await widget.initializationService.signInWithGoogle();
      if (userCredential != null) {
        widget.onLoginSuccess();
      } else {
        _setError('Google 로그인에 실패했습니다.');
      }
    } catch (e) {
      _setError('Google 로그인 중 오류가 발생했습니다: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _handleAppleSignIn() async {
    _setLoading(true);
    try {
      // Firebase 초기화 확인
      if (!Firebase.apps.isNotEmpty) {
        throw Exception('Firebase가 초기화되지 않았습니다.');
      }

      final userCredential =
          await widget.initializationService.signInWithApple();
      if (userCredential != null) {
        widget.onLoginSuccess();
      } else {
        _setError('Apple 로그인에 실패했습니다.');
      }
    } catch (e) {
      _setError('Apple 로그인 중 오류가 발생했습니다: $e');
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool isLoading) {
    if (mounted) {
      setState(() {
        _isLoading = isLoading;
        if (isLoading) {
          _errorMessage = null;
        }
      });
    }
  }

  void _setError(String message) {
    if (mounted) {
      setState(() {
        _errorMessage = message;
      });
    }
  }
}
