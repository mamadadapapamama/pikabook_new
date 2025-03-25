import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../services/initialization_service.dart';
import '../../../theme/tokens/color_tokens.dart';
import '../../../theme/tokens/typography_tokens.dart';
import '../../../widgets/dot_loading_indicator.dart';
import '../../../firebase_options.dart';

class LoginScreen extends StatefulWidget {
  final InitializationService initializationService;
  final VoidCallback onLoginSuccess;
  final VoidCallback? onSkipLogin;
  final bool isInitializing;

  const LoginScreen({
    Key? key,
    required this.initializationService,
    required this.onLoginSuccess,
    this.onSkipLogin,
    this.isInitializing = false,
  }) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  String? _errorMessage;
  late AnimationController _animationController;
  late Animation<double> _fadeInAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimation();
  }

  void _setupAnimation() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeInAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeIn,
      ),
    );

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
                    Colors.black.withOpacity(0.4),
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
                      offset: Offset(0, 0),
                      child: Transform.scale(
                        scale: 1.0,
                        child: Center(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const SizedBox(height: 20),
        

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
                                  const DotLoadingIndicator(message: '로그인 중...')
                                else if (_errorMessage != null)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    margin: const EdgeInsets.symmetric(vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(8),
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
                                  onPressed: _handleGoogleSignIn,
                                  backgroundColor: Colors.white,
                                  textColor: const Color(0xFF031B31),
                                  leadingIcon: Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: Image.asset(
                                      'assets/images/social_icons/google_2x.png',
                                      width: 24,
                                      height: 24,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Icon(Icons.g_translate, color: const Color(0xFF031B31));
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Apple 로그인 버튼
                                _buildLoginButton(
                                  text: 'Apple 로 로그인',
                                  onPressed: _handleAppleSignIn,
                                  backgroundColor: Colors.white,
                                  textColor: Colors.black,
                                  leadingIcon: Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: Image.asset(
                                      'assets/images/social_icons/apple.png',
                                      width: 24,
                                      height: 24,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Icon(Icons.apple, color: Colors.black);
                                      },
                                    ),
                                  ),
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
    required VoidCallback onPressed,
    required Color backgroundColor,
    required Color textColor,
    required Widget leadingIcon,
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
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            leadingIcon,
            Text(
              text,
              style: TypographyTokens.button.copyWith(
                color: textColor,
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 구글 로그인 처리
  Future<void> _handleGoogleSignIn() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final user = await widget.initializationService.signInWithGoogle();

      if (user != null && mounted) {
        debugPrint('Google 로그인 성공: ${user.email}');
        widget.onLoginSuccess();
      }
    } catch (e) {
      debugPrint('Google 로그인 오류: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '로그인 실패: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 애플 로그인 처리
  Future<void> _handleAppleSignIn() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final user = await widget.initializationService.signInWithApple();

      if (user != null && mounted) {
        debugPrint('Apple 로그인 성공: ${user.email}');
        widget.onLoginSuccess();
      }
    } catch (e) {
      debugPrint('Apple 로그인 오류: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '로그인 실패: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}
