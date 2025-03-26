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
  
  // 애니메이션 컨트롤러 및 애니메이션 변수
  late AnimationController _animationController;
  late Animation<double> _logoFadeAnimation;
  late Animation<double> _textFadeAnimation;
  late Animation<double> _birdFadeAnimation;
  late Animation<double> _buttonsFadeAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimation();
    
    // Firebase 초기화가 완료되지 않은 경우, 백그라운드에서 초기화 진행
    if (widget.isInitializing) {
      _startBackgroundInitialization();
    }
  }

  void _setupAnimation() {
    // 애니메이션 컨트롤러 설정 (전체 애니메이션 지속 시간: 2.4초)
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    // 로고 페이드인 애니메이션 (0~0.25)
    _logoFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.25, curve: Curves.easeIn),
      ),
    );
    
    // 텍스트 페이드인 애니메이션 (0.25~0.5)
    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.25, 0.5, curve: Curves.easeIn),
      ),
    );
    
    // 새 로고 페이드인 애니메이션 (0.5~0.75)
    _birdFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.5, 0.75, curve: Curves.easeIn),
      ),
    );
    
    // 버튼 페이드인 애니메이션 (0.75~1.0)
    _buttonsFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.75, 1.0, curve: Curves.easeIn),
      ),
    );

    // 애니메이션 시작
    _animationController.forward();
  }

  // 백그라운드에서 Firebase 초기화 작업 시작
  void _startBackgroundInitialization() {
    debugPrint('백그라운드에서 Firebase 초기화 시작');
    
    // 초기화 작업 시작
    widget.initializationService.retryInitialization(
      options: DefaultFirebaseOptions.currentPlatform,
    ).then((_) {
      debugPrint('백그라운드 Firebase 초기화 완료');
      
      // 초기화 완료 후 로그인 화면 갱신
      if (mounted) {
        setState(() {
          // 화면 갱신
        });
      }
    }).catchError((error) {
      debugPrint('백그라운드 Firebase 초기화 실패: $error');
      
      // 초기화 실패 시 오류 메시지 표시
      if (mounted) {
        setState(() {
          _errorMessage = '앱 초기화 실패: $error';
        });
      }
    });
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
                  return Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 상단 여백
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.15, // 상단 여백 조정
                          ),
                          
                          // 새 로고 (bird) - 맨 위에 배치
                          Opacity(
                            opacity: _birdFadeAnimation.value,
                            child: Image.asset(
                              'assets/images/pikabook_bird.png',
                              width: 60,
                              height: 60,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // 원서 공부, 스마트하게 텍스트 - 중간에 배치
                          Opacity(
                            opacity: _textFadeAnimation.value,
                            child: const Text(
                              '원서 공부,\n스마트하게',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Noto Sans KR',
                                fontSize: 20,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          // 텍스트 로고 - 맨 아래에 배치
                          Opacity(
                            opacity: _logoFadeAnimation.value,
                            child: Image.asset(
                              'assets/images/pikabook_textlogo.png',
                              width: 160,
                              height: 27.42,
                              fit: BoxFit.contain,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 60),

                          // 로딩 인디케이터 또는 오류 메시지
                          if (_isLoading)
                            const DotLoadingIndicator(
                              dotColor: Colors.white,
                            )
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

                          // 소셜 로그인 버튼들 (애니메이션 적용)
                          Opacity(
                            opacity: _buttonsFadeAnimation.value,
                            child: Column(
                              children: [
                                // Facebook 로그인 버튼
                                _buildLoginButton(
                                  text: 'Facebook으로 로그인',
                                  onPressed: () {
                                    // Facebook 로그인 기능 추가
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Facebook 로그인은 아직 지원되지 않습니다.')),
                                    );
                                  },
                                  backgroundColor: Colors.white,
                                  textColor: const Color(0xFF031B31),
                                  leadingIcon: Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: Icon(Icons.facebook, color: const Color(0xFF1877F2), size: 24),
                                  ),
                                ),
                                const SizedBox(height: 8),

                                // Google 로그인 버튼
                                _buildLoginButton(
                                  text: 'Google로 로그인',
                                  onPressed: _handleGoogleSignIn,
                                  backgroundColor: Colors.white,
                                  textColor: const Color(0xFF031B31),
                                  leadingIcon: Padding(
                                    padding: const EdgeInsets.only(right: 8.0),
                                    child: Image.asset(
                                      'assets/images/google.png',
                                      width: 24,
                                      height: 24,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Icon(Icons.g_translate, color: const Color(0xFF031B31));
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),

                                // Apple 로그인 버튼
                                _buildLoginButton(
                                  text: 'Apple로 로그인',
                                  onPressed: _handleAppleSignIn,
                                  backgroundColor: Colors.white,
                                  textColor: Colors.black,
                                  leadingIcon: Padding(
                                    padding: const EdgeInsets.only(right: 8.0, bottom: 4.0),
                                    child: Image.asset(
                                      'assets/images/apple.png',
                                      width: 24,
                                      height: 24,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Icon(Icons.apple, color: Colors.black);
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 40),
                        ],
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
      width: 250, // 버튼 너비 209px에서 250px로 증가
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8), // 패딩 2px 추가
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
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF031B31),
                height: 1.5,
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
