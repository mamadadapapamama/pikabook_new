import 'package:flutter/material.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import 'dot_loading_indicator.dart';

/// 앱 초기화 중 표시되는 로딩 화면
///
/// 진행 상황을 표시하고, 특정 상황에서는 건너뛰기 버튼을 제공합니다.
class LoadingScreen extends StatelessWidget {
  /// 로딩 진행률 (0.0 ~ 1.0)
  final double progress;
  
  /// 주요 메시지
  final String message;
  
  /// 부가 메시지 (선택적)
  final String? subMessage;
  
  /// 건너뛰기 버튼 콜백 (null이면 버튼 표시 안 함)
  final VoidCallback? onSkip;

  const LoadingScreen({
    Key? key,
    required this.progress,
    required this.message,
    this.subMessage,
    this.onSkip,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorTokens.primary,
      body: SafeArea(
        child: Column(
          children: [
            // 헤더 영역 (로고)
            Expanded(
              flex: 3,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 로고 이미지
                    Image.asset(
                      'assets/images/pikabook_textlogo.png',
                      width: 100,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Pikabook',
                      style: TypographyTokens.subtitle1.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // 하단 로딩 영역
            Expanded(
              flex: 2,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 로딩 인디케이터
                    const DotLoadingIndicator(dotColor: Colors.white),
                    const SizedBox(height: 24),
                    
                    // 진행률 텍스트
                    Text(
                      '${(progress * 100).toInt()}% 완료',
                      style: TypographyTokens.button.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // 주요 메시지
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TypographyTokens.body1.copyWith(
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    
                    // 부가 메시지 (있을 경우)
                    if (subMessage != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subMessage!,
                        textAlign: TextAlign.center,
                        style: TypographyTokens.caption.copyWith(
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                    ],
                    
                    // 건너뛰기 버튼 (제공된 경우)
                    if (onSkip != null) ...[
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed: onSkip,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('건너뛰기'),
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
      ),
    );
  }
} 