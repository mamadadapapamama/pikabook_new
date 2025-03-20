import 'package:flutter/material.dart';
import '../../theme/tokens/color_tokens.dart';
import '../../theme/tokens/typography_tokens.dart';

/// 앱 초기화 중에 표시되는 스플래시 화면
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeInAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    debugPrint('SplashScreen initState 호출됨');

    // 애니메이션 컨트롤러 초기화
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000), // 애니메이션 시간 단축
      vsync: this,
    );

    // 페이드인 애니메이션
    _fadeInAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
      ),
    );

    // 스케일 애니메이션
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    // 애니메이션 즉시 시작
    _controller.forward();
    debugPrint('SplashScreen 애니메이션 시작됨');
  }

  @override
  void dispose() {
    debugPrint('SplashScreen dispose 호출됨');
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('SplashScreen build 호출됨');
    return Scaffold(
      backgroundColor: ColorTokens.background, // 즉시 배경색 표시
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              ColorTokens.primary.withOpacity(0.1),
              ColorTokens.background,
            ],
          ),
        ),
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeInAnimation.value,
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 앱 로고 또는 아이콘
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: ColorTokens.primary.withOpacity(0.2),
                              blurRadius: 15,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Image.asset(
                            'assets/images/app_logo.png',
                            width: 80,
                            height: 80,
                            errorBuilder: (context, error, stackTrace) {
                              debugPrint('SplashScreen 로고 로드 실패: $error');
                              return Icon(
                                Icons.menu_book,
                                size: 60,
                                color: ColorTokens.primary,
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 앱 이름
                      Text(
                        'Pikabook',
                        style: TypographyTokens.headline1.copyWith(
                          color: ColorTokens.primary,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // 앱 설명
                      Text(
                        '언어 학습을 위한 최고의 도구',
                        style: TypographyTokens.subtitle2.copyWith(
                          color: ColorTokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // 로딩 인디케이터
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(
                            ColorTokens.primary,
                          ),
                          strokeWidth: 3,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 로딩 메시지
                      Text(
                        '앱을 준비하는 중입니다...',
                        style: TypographyTokens.caption.copyWith(
                          color: ColorTokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
