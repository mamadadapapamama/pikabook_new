import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../services/initialization_service.dart';
import '../../../theme/tokens/color_tokens.dart';
import '../../../theme/tokens/typography_tokens.dart';
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

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  String? _errorMessage;
  late AnimationController _animationController;
  late Animation<double> _fadeInAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    
    // 애니메이션 초기화
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );

    _fadeInAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.7, curve: Curves.easeIn),
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    
    _slideAnimation = Tween<double>(begin: 30, end: 0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
      ),
    );

    // 애니메이션 시작
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 배경 이미지
          Positioned.fill(
            child: Image.asset(
              'assets/images/splash_background.png',
              fit: BoxFit.cover,
            ),
          ),
          // 그라데이션 오버레이
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.0),
                    Colors.black.withOpacity(0.3),
                    Colors.black.withOpacity(0.0),
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Opacity(
                    opacity: _fadeInAnimation.value,
                    child: Transform.translate(
                      offset: Offset(0, _slideAnimation.value),
                      child: Transform.scale(
                        scale: _scaleAnimation.value,
                        child: Center(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const SizedBox(height: 20),
                                
                                // 앱 로고
                                Hero(
                                  tag: 'app_logo',
                                  child: Container(
                                    width: 140,
                                    height: 140,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(30),
                                      child: Image.asset(
                                        'assets/images/logo_bird.png',
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 40),

                                // 앱 이름
                                Text(
                                  'Pikabook',
                                  style: TypographyTokens.headline1.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // 앱 설명
                                Text(
                                  '원서 공부,\n스마트하게',
                                  textAlign: TextAlign.center,
                                  style: TypographyTokens.subtitle1.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 60),

                                // 로딩 인디케이터 또는 오류 메시지
                                if (_isLoading)
                                  const LoadingIndicator(message: '로그인 중...')
                                else if (_errorMessage != null)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    margin: const EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.red.shade200,
                                        width: 1,
                                      ),
                                    ),
                                    child: Text(
                                      _errorMessage!,
                                      textAlign: TextAlign.center,
                                      style: TypographyTokens.body2.copyWith(
                                        color: Colors.red.shade800,
                                      ),
                                    ),
                                  ),

                                const SizedBox(height: 16),

                                // Google 로그인 버튼
                                _buildLoginButton(
                                  text: 'Google 로 로그인',
                                  icon: Icons.g_mobiledata,
                                  onPressed: _handleGoogleSignIn,
                                  backgroundColor: Colors.white,
                                  textColor: const Color(0xFF031B31),
                                ),
                                const SizedBox(height: 16),

                                // Apple 로그인 버튼
                                _buildLoginButton(
                                  text: 'Apple 로 로그인',
                                  icon: Icons.apple,
                                  onPressed: _handleAppleSignIn,
                                  backgroundColor: ColorTokens.primary,
                                  textColor: Colors.white,
                                ),
                                const SizedBox(height: 40),

                                // 로그인 안내 텍스트
                                Text(
                                  '소셜 계정으로 로그인하여 모든 기기에서 데이터를 동기화하고\n백업할수 있습니다.',
                                  textAlign: TextAlign.center,
                                  style: TypographyTokens.caption.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }
              ),
            ),
          ),
        ],
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
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24),
            const SizedBox(width: 8),
            Text(
              text,
              style: TypographyTokens.button.copyWith(
                color: textColor,
              ),
            ),
          ],
        ),
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

      final user = await widget.initializationService.signInWithGoogle();
      if (user != null) {
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

      final user = await widget.initializationService.signInWithApple();
      if (user != null) {
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
