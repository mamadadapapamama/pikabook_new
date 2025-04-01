import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../services/initialization_service.dart';
import '../../../theme/tokens/color_tokens.dart';
import '../../../theme/tokens/typography_tokens.dart';
import '../../../theme/tokens/spacing_tokens.dart';
import '../../../widgets/dot_loading_indicator.dart';
import '../../../firebase_options.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginScreen extends StatefulWidget {
  final InitializationService? initializationService;
  final Function(User) onLoginSuccess;
  final VoidCallback? onSkipLogin;
  final bool isInitializing;

  const LoginScreen({
    Key? key,
    this.initializationService,
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
    debugPrint('백그라운드에서 Firebase 초기화 상태 확인 시작');
    
    // 초기화 작업 시작 (Firebase 초기화 자체를 시도하지 않음)
    widget.initializationService?.retryInitialization().then((_) {
      debugPrint('백그라운드 Firebase 초기화 상태 확인 완료');
      
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
                              width: SpacingTokens.iconSizeXLarge + SpacingTokens.xs,
                              height: SpacingTokens.iconSizeXLarge + SpacingTokens.xs,
                              fit: BoxFit.contain,
                            ),
                          ),
                          SizedBox(height: SpacingTokens.md),
                          
                          // 원서 공부, 스마트하게 텍스트 - 중간에 배치
                          Opacity(
                            opacity: _textFadeAnimation.value,
                            child: Text(
                              '원서 공부,\n스마트하게',
                              textAlign: TextAlign.center,
                              style: TypographyTokens.subtitle1.copyWith(
                                color: ColorTokens.textLight,
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
                              width: SpacingTokens.appLogoWidth,
                              height: SpacingTokens.appLogoHeight,
                              fit: BoxFit.contain,
                              color: ColorTokens.textLight,
                            ),
                          ),
                          SizedBox(height: SpacingTokens.xxl + SpacingTokens.xs),

                          // 로딩 인디케이터 또는 오류 메시지
                          if (_isLoading)
                            const DotLoadingIndicator(
                              dotColor: ColorTokens.textLight,
                            )
                          else if (_errorMessage != null)
                            Container(
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
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: TypographyTokens.body2.copyWith(
                                  color: ColorTokens.error,
                                ),
                              ),
                            ),

                          SizedBox(height: SpacingTokens.md),

                          // 소셜 로그인 버튼들 (애니메이션 적용)
                          Opacity(
                            opacity: _buttonsFadeAnimation.value,
                            child: Column(
                              children: [
                                // Google 로그인 버튼
                                _buildLoginButton(
                                  text: 'Google로 로그인',
                                  onPressed: _handleGoogleLogin,
                                  backgroundColor: ColorTokens.surface,
                                  textColor: ColorTokens.textPrimary,
                                  leadingIcon: Padding(
                                    padding: EdgeInsets.only(right: SpacingTokens.sm),
                                    child: Image.asset(
                                      'assets/images/google.png',
                                      width: SpacingTokens.iconSizeMedium,
                                      height: SpacingTokens.iconSizeMedium,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Icon(Icons.g_translate, color: ColorTokens.textPrimary);
                                      },
                                    ),
                                  ),
                                ),
                                SizedBox(height: SpacingTokens.sm),

                                // Apple 로그인 버튼
                                _buildLoginButton(
                                  text: 'Apple로 로그인',
                                  onPressed: _handleAppleLogin,
                                  backgroundColor: ColorTokens.surface,
                                  textColor: ColorTokens.black,
                                  leadingIcon: Padding(
                                    padding: EdgeInsets.only(right: SpacingTokens.sm, bottom: SpacingTokens.xs),
                                    child: Image.asset(
                                      'assets/images/apple.png',
                                      width: SpacingTokens.iconSizeMedium,
                                      height: SpacingTokens.iconSizeMedium,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Icon(Icons.apple, color: ColorTokens.black);
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: SpacingTokens.xl + SpacingTokens.sm),
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
      width: 250,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          elevation: 0,
          padding: EdgeInsets.symmetric(vertical: SpacingTokens.sm + SpacingTokens.xs/2, horizontal: SpacingTokens.sm),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            leadingIcon,
            Text(
              text,
              style: TypographyTokens.buttonEn.copyWith(
                color: ColorTokens.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 로그인 처리
  Future<void> _handleGoogleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 초기화 서비스가 제공되지 않은 경우 Firebase Auth 직접 사용
      User? user;
      UserCredential? userCredential;

      if (widget.initializationService != null) {
        // 기존 초기화 서비스 사용
        userCredential = await widget.initializationService!.signInWithGoogle();
        user = userCredential?.user;
      } else {
        // Firebase Auth 직접 사용
        final googleSignIn = GoogleSignIn();
        final googleUser = await googleSignIn.signIn();
        if (googleUser == null) {
          setState(() {
            _isLoading = false;
          });
          return; // 로그인 취소
        }

        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
        user = userCredential.user;
      }

      if (user != null) {
        // 로그인 성공
        widget.onLoginSuccess(user); // User 객체 전달
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = '로그인에 실패했습니다';
        });
      }
    } catch (e) {
      debugPrint('Google 로그인 오류: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Google 로그인 중 오류가 발생했습니다: $e';
      });
    }
  }

  // Apple 로그인 처리
  Future<void> _handleAppleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 초기화 서비스가 제공되지 않은 경우 Firebase Auth 직접 사용
      User? user;
      UserCredential? userCredential;

      if (widget.initializationService != null) {
        // 기존 초기화 서비스 사용
        userCredential = await widget.initializationService!.signInWithApple();
        user = userCredential?.user;
      } else {
        // Apple 로그인 직접 구현
        // 노트: Apple 로그인은 더 복잡한 구현이 필요합니다 (nonce 생성 등)
        // 간단히 하기 위해 코드 샘플은 생략합니다
        // 필요시 initializationService.dart의 signInWithApple 코드를 참조하세요
        
        // 임시 에러 메시지
        setState(() {
          _isLoading = false;
          _errorMessage = 'Apple 로그인이 현재 지원되지 않습니다';
        });
        return;
      }

      if (user != null) {
        // 로그인 성공
        widget.onLoginSuccess(user); // User 객체 전달
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = '로그인에 실패했습니다';
        });
      }
    } catch (e) {
      debugPrint('Apple 로그인 오류: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Apple 로그인 중 오류가 발생했습니다: $e';
      });
    }
  }
}
