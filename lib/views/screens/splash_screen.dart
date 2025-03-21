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
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage('assets/images/splash_background.jpg'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withOpacity(0.5),
              BlendMode.darken,
            ),
          ),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: _fadeInAnimation.value,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(flex: 2),
                    
                    // 앱 로고
                    Hero(
                      tag: 'app_logo',
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Image.asset(
                          'assets/images/logo_bird.png',
                          errorBuilder: (context, error, stackTrace) {
                            debugPrint('SplashScreen 로고 로드 실패: $error');
                            return Container(
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                color: ColorTokens.primary,
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: const Icon(
                                Icons.auto_stories,
                                size: 80,
                                color: Colors.white,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // 앱 이름
                    Text(
                      'Pikabook',
                      style: TypographyTokens.headline1.copyWith(
                        color: Colors.white,
                        fontSize: 48,
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // 앱 설명
                    Text(
                      '원서 공부,\n스마트하게',
                      textAlign: TextAlign.center,
                      style: TypographyTokens.subtitle1.copyWith(
                        color: Colors.white,
                        fontSize: 24,
                      ),
                    ),
                    
                    const Spacer(flex: 2),
                    
                    // 로딩 인디케이터
                    Container(
                      margin: const EdgeInsets.only(bottom: 40),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              3,
                              (index) => Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: index == 0 ? Colors.white : Colors.white.withOpacity(0.5),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            '앱을 준비하는 중입니다...',
                            style: TypographyTokens.body2.copyWith(
                              color: Colors.white.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
