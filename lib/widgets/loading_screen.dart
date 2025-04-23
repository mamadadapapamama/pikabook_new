import 'package:flutter/material.dart';
import '../core/theme/tokens/color_tokens.dart';
import '../core/theme/tokens/typography_tokens.dart';
import '../core/theme/tokens/spacing_tokens.dart';
import 'dot_loading_indicator.dart';

/// 앱 초기화 중 표시되는 로딩 화면
///
/// 진행 상황을 표시하는 단순한 화면입니다.
class LoadingScreen extends StatelessWidget {
  /// 로딩 진행률 (0.0 ~ 1.0)
  final double progress;
  
  /// 건너뛰기 버튼 콜백 (null이면 버튼 표시 안 함)
  final VoidCallback? onSkip;
  
  /// 앱 스토어 심사를 위한 최적화 여부
  final bool optimizeForAppReview;
  
  /// 로딩 상태 메시지
  final String? message;
  
  /// 오류 메시지
  final String? error;

  const LoadingScreen({
    Key? key,
    required this.progress,
    this.onSkip,
    this.optimizeForAppReview = false,
    this.message,
    this.error,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 앱 스토어 심사를 위한 최적화: 성능 향상을 위한 렌더링 최적화
    if (optimizeForAppReview) {
      // 가벼운 로딩 화면으로 처리
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
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 로고 이미지
                    Image.asset(
                      'assets/images/pikabook_textlogo.png',
                      width: 80, // 크기 최적화
                      color: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    
                    // 간소화된 로딩 인디케이터
                    const DotLoadingIndicator(dotColor: Colors.white),
                    const SizedBox(height: 16),
                    
                    // 상태 메시지
                    Text(
                      message ?? '앱을 준비하는 중이에요',
                      style: TypographyTokens.button.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    // 기본 로딩 화면 (기존 구현)
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
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 로고 이미지 (중앙에 배치)
                  Image.asset(
                    'assets/images/pikabook_textlogo.png',
                    width: 130,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 48),
                  
                  // 로딩 인디케이터
                  const DotLoadingIndicator(dotColor: Colors.white),
                  const SizedBox(height: 24),
                  
                  // 상태 메시지
                  Text(
                    error ?? message ?? '${(progress * 100).toInt()}% 준비중이에요... ',
                    style: TypographyTokens.button.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  
                  // 건너뛰기 버튼 (제공된 경우)
                  if (onSkip != null) ...[
                    const SizedBox(height: 32),
                    TextButton(
                      onPressed: onSkip,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('skip'),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward,
                            size: SpacingTokens.iconSizeSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
} 