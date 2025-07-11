import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../../core/widgets/dot_loading_indicator.dart';
import '../../../firebase_options.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/services/authentication/auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';

class LoginScreen extends StatefulWidget {
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
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  
  // 인증 서비스
  final AuthService _authService = AuthService();
  
  // 이메일 로그인 폼 관련
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isEmailLogin = false;
  bool _isSignUp = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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
              child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // 상단 여백
                          SizedBox(
                            height: _getSafeScreenHeight(context) * 0.15, // 상단 여백 조정
                          ),
                          
                          // 새 로고 (bird) - 맨 위에 배치
                          Image.asset(
                              'assets/images/pikabook_bird.png',
                              width: SpacingTokens.iconSizeXLarge + SpacingTokens.xs,
                              height: SpacingTokens.iconSizeXLarge + SpacingTokens.xs,
                              fit: BoxFit.contain,
                          ),
                          SizedBox(height: SpacingTokens.md),
                          
                          // 원서 공부, 스마트하게 텍스트 - 중간에 배치
                          Text(
                              '책으로 하는 중국어 공부,\n스마트하게',
                              textAlign: TextAlign.center,
                              style: TypographyTokens.subtitle1.copyWith(
                                color: ColorTokens.textLight,
                                height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          
                          // 텍스트 로고 - 맨 아래에 배치
                          Image.asset(
                              'assets/images/pikabook_textlogo.png',
                              width: SpacingTokens.appLogoWidth2x,
                              height: SpacingTokens.appLogoHeight2x,
                              fit: BoxFit.contain,
                              color: ColorTokens.textLight,
                          ),
                          SizedBox(height: SpacingTokens.xl),

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

                          // 🎯 통합 로그인 버튼들 (깔끔한 3버튼 구조)
                          Column(
                              children: [
                                if (_isEmailLogin) ...[
                                  // 이메일 로그인 폼
                                  Container(
                                    width: 250,
                                    child: Column(
                                      children: [
                                        // 뒤로가기 버튼
                                        Row(
                                          children: [
                                            TextButton.icon(
                                              onPressed: () {
                                                setState(() {
                                                  _isEmailLogin = false;
                                                  _errorMessage = null;
                                                  _emailController.clear();
                                                  _passwordController.clear();
                                                });
                                              },
                                              icon: Icon(Icons.arrow_back, color: ColorTokens.textLight, size: 18),
                                              label: Text(
                                                '뒤로',
                                                style: TypographyTokens.body2.copyWith(color: ColorTokens.textLight),
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: SpacingTokens.sm),
                                        
                                        // 이메일 입력 필드
                                        TextField(
                                          controller: _emailController,
                                          keyboardType: TextInputType.emailAddress,
                                          style: TypographyTokens.body1.copyWith(color: ColorTokens.textPrimary),
                                          decoration: InputDecoration(
                                            hintText: '이메일',
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
                                          ),
                                        ),
                                        SizedBox(height: SpacingTokens.sm),
                                        
                                        // 패스워드 입력 필드
                                        TextField(
                                          controller: _passwordController,
                                          obscureText: true,
                                          style: TypographyTokens.body1.copyWith(color: ColorTokens.textPrimary),
                                          decoration: InputDecoration(
                                            hintText: '비밀번호',
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
                                          ),
                                        ),
                                        
                                        // 🎯 비밀번호 찾기 링크 (로그인 모드에서만 표시)
                                        if (!_isSignUp) ...[
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: TextButton(
                                              onPressed: _showPasswordResetDialog,
                                              child: Text(
                                                '비밀번호를 잊으셨나요?',
                                                style: TypographyTokens.body2.copyWith(
                                                  color: ColorTokens.textLight,
                                                  decoration: TextDecoration.underline,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                        
                                        SizedBox(height: SpacingTokens.sm),
                                        
                                        // 로그인/회원가입 버튼
                                        ElevatedButton(
                                          onPressed: _isLoading ? null : _handleEmailAuth,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: ColorTokens.primary,
                                            foregroundColor: ColorTokens.textLight,
                                            minimumSize: Size(250, 48),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
                                            ),
                                          ),
                                          child: Text(
                                            _isSignUp ? '회원가입' : '로그인',
                                            style: TypographyTokens.button.copyWith(color: ColorTokens.textLight),
                                          ),
                                        ),
                                        SizedBox(height: SpacingTokens.xs),
                                        
                                        // 로그인/회원가입 모드 전환
                                        TextButton(
                                          onPressed: () {
                                            setState(() {
                                              _isSignUp = !_isSignUp;
                                              _errorMessage = null;
                                            });
                                          },
                                          child: Text(
                                            _isSignUp ? '이미 계정이 있으신가요? 로그인' : '계정이 없으신가요? 회원가입',
                                            style: TypographyTokens.body2.copyWith(
                                              color: ColorTokens.textLight,
                                              decoration: TextDecoration.underline,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ] else ...[
                                  // 🎯 메인 로그인 선택 화면 (3개 버튼)
                                  Column(
                                    children: [
                                      // Apple 로그인 버튼 (맨 위로 이동)
                                      _buildLoginButton(
                                        text: 'Apple로 로그인',
                                        onPressed: _handleAppleSignIn,
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
                                      SizedBox(height: SpacingTokens.sm),

                                      // Google 로그인 버튼
                                      _buildLoginButton(
                                        text: 'Google로 로그인',
                                        onPressed: _handleGoogleSignIn,
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

                                      // 🆕 이메일 로그인 버튼 (다른 버튼들과 동일한 스타일)
                                      _buildLoginButton(
                                        text: '이메일로 로그인',
                                        onPressed: () {
                                          setState(() {
                                            _isEmailLogin = true;
                                            _errorMessage = null;
                                          });
                                        },
                                        backgroundColor: ColorTokens.surface,
                                        textColor: ColorTokens.textPrimary,
                                        leadingIcon: Padding(
                                          padding: EdgeInsets.only(right: SpacingTokens.sm),
                                          child: Icon(
                                            Icons.email_outlined,
                                            color: ColorTokens.textPrimary,
                                            size: SpacingTokens.iconSizeMedium,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                                
                                SizedBox(height: SpacingTokens.md),
                                
                                // 로그인 없이 둘러보기 버튼 추가
                                TextButton(
                                  onPressed: _isLoading ? null : _handleSkipLogin,
                                  child: Text(
                                    '로그인 없이 둘러보기',
                                    style: TypographyTokens.button.copyWith(
                                      color: ColorTokens.textLight,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                                
                                SizedBox(height: SpacingTokens.sm),
                                // 로그인 안내 메시지 추가
                                RichText(
                                  textAlign: TextAlign.center,
                                  text: TextSpan(
                                    style: TypographyTokens.body2.copyWith(
                                      color: ColorTokens.textLight,
                                    ),
                                    children: [
                                      TextSpan(text: '로그인 시 '),
                                      TextSpan(
                                        text: '개인정보 처리방침',
                                        style: TypographyTokens.body2.copyWith(
                                          color: ColorTokens.textLight,
                                          decoration: TextDecoration.underline,
                                        ),
                                        recognizer: TapGestureRecognizer()
                                          ..onTap = () {
                                            if (kDebugMode) {
                                              print('개인정보처리방침 링크 클릭됨');
                                            }
                                            launchUrl(
                                              Uri.parse('https://www.pikabook.co/privacy.html'),
                                              mode: LaunchMode.externalApplication,
                                            );
                                          },
                                      ),
                                      TextSpan(text: '과'),
                                      TextSpan(
                                        text: ' 이용약관',
                                        style: TypographyTokens.body2.copyWith(
                                          color: ColorTokens.textLight,
                                          decoration: TextDecoration.underline,
                                        ),
                                        recognizer: TapGestureRecognizer()
                                          ..onTap = () {
                                            if (kDebugMode) {
                                              print('이용약관 링크 클릭됨');
                                            }
                                            launchUrl(
                                              Uri.parse('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/'),
                                              mode: LaunchMode.externalApplication,
                                            );
                                          },
                                      ),
                                      TextSpan(text: '에 동의합니다.'),
                                    ],
                                  ),
                                ),
                              ],
                          ),
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
          padding: EdgeInsets.symmetric(vertical: SpacingTokens.sm + SpacingTokens.xsHalf, horizontal: SpacingTokens.sm),
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

  // Google 로그인 처리
  Future<void> _handleGoogleSignIn() async {
    if (_isLoading) return;
    
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      
      // Firebase가 초기화되었는지 확인
      if (Firebase.apps.isEmpty) {
        throw Exception('Firebase가 아직 초기화되지 않았습니다.');
      }
      
      // 사용자 변수
      User? user;
      
      try {
        // 직접 구현된 Google 로그인 시도
        user = await _authService.signInWithGoogle();
        
        // 성공적으로 로그인한 경우
        if (user != null) {
          // 로그인 성공 콜백 호출
          widget.onLoginSuccess(user);
        } else {
          // throw Exception('로그인이 취소되었습니다.');
          setState(() {
            _errorMessage = '로그인이 취소되었습니다. 다시 시도해 주세요.';
            _isLoading = false;
          });
        }
      } catch (e) {
        setState(() {
          _errorMessage = '로그인이 취소되었습니다. 다시 시도해 주세요.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '로그인이 취소되었습니다. 다시 시도해 주세요.';
        _isLoading = false;
      });
    }
  }
  
  // Apple 로그인 처리
  Future<void> _handleAppleSignIn() async {
    if (_isLoading) return;
    
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      
      // Firebase가 초기화되었는지 확인
      if (Firebase.apps.isEmpty) {
        throw Exception('Firebase가 아직 초기화되지 않았습니다.');
      }
      
      if (kDebugMode) {
        debugPrint('🍎 Apple Sign In 시작...');
      }
      
      // Apple 로그인 시도
      User? user = await _authService.signInWithApple();
      
      // 🎯 사용자 취소 시 조용히 처리 (null 반환)
      if (user == null) {
        if (kDebugMode) {
          debugPrint('🍎 Apple Sign In: 사용자가 취소함 - 조용히 처리');
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }
      
      // 성공적으로 로그인한 경우
      if (kDebugMode) {
        debugPrint('🍎 Apple Sign In 성공: ${user.uid}');
      }
      widget.onLoginSuccess(user);
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('🍎 Apple Sign In 실패: $e');
      }
      
      // 🎯 특정 오류에 따른 처리
      String errorMessage = '로그인 중 오류가 발생했습니다.';
      
      if (e.toString().contains('AuthorizationError Code=1001') ||
          e.toString().contains('사용자가 취소')) {
        // 사용자 취소 - 조용히 처리
        setState(() {
          _isLoading = false;
        });
        return;
      }
      
      if (e.toString().contains('AKAuthenticationError Code=-7003')) {
        errorMessage = 'Apple ID 인증에 실패했습니다.\n잠시 후 다시 시도해 주세요.';
      } else if (e.toString().contains('NSOSStatusErrorDomain Code=-54')) {
        errorMessage = '시스템 오류가 발생했습니다.\n디바이스를 재부팅하고 다시 시도해 주세요.';
      } else if (e.toString().contains('Apple ID 인증에 실패했습니다') ||
                 e.toString().contains('시스템 오류가 발생했습니다')) {
        errorMessage = e.toString().replaceAll('Exception: ', '');
      }
      
      setState(() {
        _errorMessage = errorMessage;
        _isLoading = false;
      });
    }
  }

  // 이메일 로그인/회원가입 처리
  Future<void> _handleEmailAuth() async {
    if (_isLoading) return;
    
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    
    // 입력값 검증
    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = '이메일과 비밀번호를 입력해주세요.';
      });
      return;
    }
    
    if (!email.contains('@') || !email.contains('.')) {
      setState(() {
        _errorMessage = '올바른 이메일 형식을 입력해주세요.';
      });
      return;
    }
    
    if (password.length < 6) {
      setState(() {
        _errorMessage = '비밀번호는 6자 이상이어야 합니다.';
      });
      return;
    }
    
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      
      User? user;
      
      if (_isSignUp) {
        // 회원가입
        user = await _authService.signUpWithEmail(email, password);
        
        if (user != null) {
          // 🎯 회원가입 성공 - 이메일 검증 안내
          await _showEmailVerificationDialog(user);
          return;
        }
      } else {
        // 로그인
        user = await _authService.signInWithEmail(email, password);
        
        if (user != null) {
          // 🎯 로그인 성공 - 이메일 검증 상태 확인
          if (!user.emailVerified) {
            await _showEmailNotVerifiedDialog(user);
            return;
          }
          
          widget.onLoginSuccess(user);
        }
      }
      
      if (user == null) {
        setState(() {
          _errorMessage = '로그인에 실패했습니다. 다시 시도해주세요.';
          _isLoading = false;
        });
      }
    } catch (e) {
      String errorMessage = '오류가 발생했습니다. 다시 시도해주세요.';
      
      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'user-not-found':
            errorMessage = '등록되지 않은 이메일입니다. 회원가입을 먼저 해주세요.';
            // 🎯 로그인 모드에서 에러 발생 시 회원가입 모드로 전환 제안
            if (!_isSignUp) {
              Future.delayed(Duration(milliseconds: 100), () {
                if (mounted) {
                  setState(() {
                    _isSignUp = true; // 회원가입 모드로 전환
                  });
                }
              });
            }
            break;
          case 'wrong-password':
            errorMessage = '비밀번호가 올바르지 않습니다. 비밀번호를 확인해주세요.';
            break;
          case 'email-already-in-use':
            errorMessage = '이미 가입된 이메일입니다. 로그인해주세요.';
            // 🎯 회원가입 모드에서 에러 발생 시 자동으로 로그인 모드로 전환
            if (_isSignUp) {
              Future.delayed(Duration(milliseconds: 100), () {
                if (mounted) {
                  setState(() {
                    _isSignUp = false; // 로그인 모드로 전환
                  });
                }
              });
            }
            break;
                      case 'weak-password':
              errorMessage = '비밀번호가 너무 약합니다. 6자 이상, 숫자와 문자를 포함해주세요.';
              break;
            case 'invalid-email':
              errorMessage = '올바르지 않은 이메일 형식입니다. 다시 확인해주세요.';
              break;
            case 'too-many-requests':
              errorMessage = '너무 많은 시도가 있었습니다. 5분 후 다시 시도해주세요.';
              break;
          default:
            errorMessage = e.message ?? errorMessage;
            break;
        }
      }
      
      setState(() {
        _errorMessage = errorMessage;
        _isLoading = false;
      });
    }
  }

  // 안전한 화면 높이 계산 (NaN 방지)
  double _getSafeScreenHeight(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    if (screenHeight.isNaN || screenHeight.isInfinite || screenHeight <= 0) {
      return 600.0; // 기본값
    }
    return screenHeight;
  }

  // 로그인 없이 둘러보기 처리
  Future<void> _handleSkipLogin() async {
    if (_isLoading) return;
    
    try {
      setState(() {
        _isLoading = true;
      });
      
      if (kDebugMode) {
        debugPrint('[LoginScreen] 로그인 없이 둘러보기 시작');
      }
      
      // 현재 로그인된 사용자가 있다면 로그아웃
      if (FirebaseAuth.instance.currentUser != null) {
        if (kDebugMode) {
          debugPrint('[LoginScreen] 기존 로그인 사용자 감지, 로그아웃 실행');
        }
        await FirebaseAuth.instance.signOut();
      }
      
      // App 위젯에 샘플 모드 전환 요청
      if (widget.onSkipLogin != null) {
        if (kDebugMode) {
          debugPrint('[LoginScreen] App 위젯에 샘플 모드 전환 요청 콜백 호출');
        }
        widget.onSkipLogin!(); // App 위젯의 _requestSampleModeScreen 호출
      } else {
        // 콜백이 없는 경우 (예상치 못한 상황)
        if (kDebugMode) {
          debugPrint('[LoginScreen] 경고: onSkipLogin 콜백이 null입니다.');
        }
        setState(() { _isLoading = false; }); // 로딩 해제
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[LoginScreen] 샘플 모드 진입 중 오류: $e');
      }
      setState(() {
        _errorMessage = '로그인이 취소되었습니다. 다시 시도해 주세요.';
        _isLoading = false;
      });
    }
  }

  // === 이메일 검증 관련 다이얼로그 ===

  /// 회원가입 후 이메일 검증 안내 다이얼로그
  Future<void> _showEmailVerificationDialog(User user) async {
    setState(() {
      _isLoading = false;
    });

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.mark_email_unread, color: ColorTokens.primary, size: 24),
              SizedBox(width: 8),
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
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
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
                await _resendVerificationEmail(user);
              },
              child: Text('메일 재발송', style: TypographyTokens.button.copyWith(color: ColorTokens.primary)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                // 🎯 회원가입 완료 후 바로 로그인 처리 (이메일 검증 선택사항)
                widget.onLoginSuccess(user);
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

  /// 로그인 시 이메일 미인증 안내 다이얼로그
  Future<void> _showEmailNotVerifiedDialog(User user) async {
    setState(() {
      _isLoading = false;
    });

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange[600], size: 24),
              SizedBox(width: 8),
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
              SizedBox(height: 16),
              Text(
                '📧 인증 메일을 확인하고 인증 링크를 클릭해주세요.\n인증 후 다시 로그인해주세요.',
                style: TypographyTokens.body2.copyWith(color: ColorTokens.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _resendVerificationEmail(user);
              },
              child: Text('인증 메일 재발송', style: TypographyTokens.button.copyWith(color: ColorTokens.primary)),
            ),
            ElevatedButton(
              onPressed: () async {
                // 로그아웃 후 메인 로그인 화면으로
                await FirebaseAuth.instance.signOut();
                Navigator.of(context).pop();
                setState(() {
                  _isEmailLogin = false;
                });
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

  /// 인증 메일 재발송
  Future<void> _resendVerificationEmail(User user) async {
    try {
      await _authService.resendEmailVerification();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('인증 메일을 재발송했습니다. 이메일을 확인해주세요.'),
            backgroundColor: ColorTokens.secondary,
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('인증 메일 발송에 실패했습니다. 잠시 후 다시 시도해주세요.'),
            backgroundColor: Colors.red[600],
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// 비밀번호 재설정 다이얼로그
  Future<void> _showPasswordResetDialog() async {
    final TextEditingController emailController = TextEditingController();
    String? errorMessage;

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(Icons.lock_reset, color: ColorTokens.primary, size: 24),
                  SizedBox(width: 8),
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
                  SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: '이메일 주소',
                      hintText: 'example@email.com',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email_outlined),
                      errorText: errorMessage,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text('취소', style: TypographyTokens.button.copyWith(color: ColorTokens.textSecondary)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final email = emailController.text.trim();
                    
                    if (email.isEmpty) {
                      setDialogState(() {
                        errorMessage = '이메일을 입력해주세요.';
                      });
                      return;
                    }
                    
                    if (!email.contains('@') || !email.contains('.')) {
                      setDialogState(() {
                        errorMessage = '올바른 이메일 형식을 입력해주세요.';
                      });
                      return;
                    }
                    
                    try {
                      await _authService.sendPasswordResetEmail(email);
                      Navigator.of(context).pop();
                      
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('비밀번호 재설정 메일을 발송했습니다.\n이메일을 확인해주세요.'),
                            backgroundColor: ColorTokens.secondary,
                            duration: Duration(seconds: 4),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    } catch (e) {
                      String message = '메일 발송에 실패했습니다.';
                      if (e is FirebaseAuthException) {
                        switch (e.code) {
                          case 'user-not-found':
                            message = '등록되지 않은 이메일입니다.';
                            break;
                          case 'invalid-email':
                            message = '올바르지 않은 이메일 형식입니다.';
                            break;
                        }
                      }
                      setDialogState(() {
                        errorMessage = message;
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
}
