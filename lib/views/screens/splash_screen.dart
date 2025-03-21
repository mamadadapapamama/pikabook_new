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
  late Animation<double> _slideAnimation;
  late Animation<double> _backgroundOpacityAnimation;
  
  final List<Animation<double>> _dotsAnimations = [];

  @override
  void initState() {
    super.initState();
    debugPrint('SplashScreen initState 호출됨');

    // 애니메이션 컨트롤러 초기화
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    // 페이드인 애니메이션
    _fadeInAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeIn),
      ),
    );

    // 스케일 애니메이션
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    
    // 슬라이드 애니메이션
    _slideAnimation = Tween<double>(begin: 30, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
      ),
    );
    
    // 배경 이미지 불투명도 애니메이션
    _backgroundOpacityAnimation = Tween<double>(begin: 0.5, end: 0.3).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 1.0, curve: Curves.easeInOut),
      ),
    );
    
    // 점들의 애니메이션
    for (int i = 0; i < 3; i++) {
      final startDelay = 0.7 + (i * 0.1);
      _dotsAnimations.add(
        Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _controller,
            curve: Interval(startDelay, startDelay + 0.2, curve: Curves.easeIn),
          ),
        ),
      );
    }

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
      body: Stack(
        children: [
          // 배경 이미지
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Image.asset(
                  'assets/images/splash_background.png',
                  fit: BoxFit.cover,
                  color: Colors.black.withOpacity(_backgroundOpacityAnimation.value),
                  colorBlendMode: BlendMode.darken,
                );
              },
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
          
          // 메인 콘텐츠
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Opacity(
                    opacity: _fadeInAnimation.value,
                    child: Transform.translate(
                      offset: Offset(0, _slideAnimation.value),
                      child: Transform.scale(
                        scale: _scaleAnimation.value,
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
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(30),
                                    child: Image.asset(
                                      'assets/images/logo_bird.png',
                                      fit: BoxFit.cover,
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
                                        (index) => Opacity(
                                          opacity: _dotsAnimations[index].value,
                                          child: Container(
                                            margin: const EdgeInsets.symmetric(horizontal: 4),
                                            width: 12,
                                            height: 12,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Opacity(
                                      opacity: _dotsAnimations[2].value,
                                      child: Text(
                                        '앱을 준비하는 중입니다...',
                                        style: TypographyTokens.body2.copyWith(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
