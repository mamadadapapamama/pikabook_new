import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show timeDilation;
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import 'dart:async';

/// Pikabook 로딩 화면
/// 
/// 노트 생성 중 또는 긴 작업 시간 동안 사용자에게 로딩 상태를 시각적으로 표시하는 위젯입니다.
/// Figma 디자인에 따라 구현되었습니다.
class PikabookLoader extends StatelessWidget {
  final String message;
  final int timeoutSeconds;

  const PikabookLoader({
    Key? key,
    this.message = '스마트한 학습 노트를 만들고 있어요.\n잠시만 기다려 주세요! 조금 시간이 걸릴수 있어요.',
    this.timeoutSeconds = 20,
  }) : super(key: key);

  /// 로더를 다이얼로그로 표시하는 정적 메서드
  static Future<void> show(
    BuildContext context, {
    String message = '스마트한 학습 노트를 만들고 있어요.\n잠시만 기다려 주세요! 조금 시간이 걸릴수 있어요.',
    int timeoutSeconds = 20, // 타임아웃 시간 (초 단위)
  }) async {
    // 디버그 타이머 방지
    timeDilation = 1.0;
    
    if (!context.mounted) return;
    
    // 기존 로더가 있으면 먼저 제거 (중복 방지)
    hide(context);
    
    // 타임아웃 설정 - 지정된 시간 후 자동으로 닫힘
    Timer? timeoutTimer;
    if (timeoutSeconds > 0) {
      timeoutTimer = Timer(Duration(seconds: timeoutSeconds), () {
        if (context.mounted) hide(context);
      });
    }
    
    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.transparent, // 배경 투명하게 설정
        useSafeArea: true,
        builder: (context) => WillPopScope(
          onWillPop: () async => false, // 뒤로 가기 방지
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              color: Colors.transparent,
              child: Center(
                child: PikabookLoader(
                  message: message,
                  timeoutSeconds: timeoutSeconds,
                ),
              ),
            ),
          ),
        ),
      ).then((_) {
        timeoutTimer?.cancel();
      });
    } catch (e) {
      debugPrint('로더 표시 중 오류: $e');
      timeoutTimer?.cancel();
    }
  }

  /// 로더를 숨기는 정적 메서드
  static void hide(BuildContext context) {
    if (!context.mounted) return;
    
    try {
      // 안전하게 다이얼로그 닫기
      Navigator.of(context, rootNavigator: true).pop();
    } catch (e) {
      debugPrint('로더 숨기기 중 오류: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      width: 300, // Figma 디자인과 동일한 너비
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 로더 애니메이션
          _LoaderWithBird(),
          
          const SizedBox(height: 24),
          
          // 텍스트 섹션
          Text(
            message,
            style: TypographyTokens.body1.copyWith(
              height: 1.4,
              color: ColorTokens.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// 피카북 새와 애니메이션 도트를 함께 표시하는 로더
class _LoaderWithBird extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 도트 애니메이션
          _AnimatedDotLoader(),
          
          const SizedBox(width: 12),
          
          // 피카북 새 캐릭터 (고정된 상태)
          Image.asset(
            'assets/images/pikabook_bird.png',
            width: 40,
            height: 40,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: ColorTokens.primary.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome,
                  color: ColorTokens.primary,
                  size: 24,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 애니메이션 도트 로더
class _AnimatedDotLoader extends StatefulWidget {
  @override
  State<_AnimatedDotLoader> createState() => _AnimatedDotLoaderState();
}

class _AnimatedDotLoaderState extends State<_AnimatedDotLoader> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    
    // 디버그 타이머 방지
    timeDilation = 1.0;
    
    // 애니메이션 컨트롤러 초기화
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    
    // 다음 프레임에서 애니메이션 시작 (안정성 향상)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.repeat();
      }
    });
  }
  
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildAnimatedDot(0),
            const SizedBox(width: 6),
            _buildAnimatedDot(0.2),
            const SizedBox(width: 6),
            _buildAnimatedDot(0.4),
          ],
        );
      }
    );
  }
  
  Widget _buildAnimatedDot(double delay) {
    // 애니메이션 값 계산 (0-1 범위)
    final double t = ((_controller.value - delay) % 1.0).clamp(0.0, 1.0);
    
    // 사인 곡선을 사용하여 더 부드러운 애니메이션 생성
    // 0에서 π까지의 사인 곡선값은 0에서 1로 증가한 후 다시 0으로 감소
    final double scale = 1.0 + 0.5 * sin(t * 3.14);
    
    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: 0.3 + 0.7 * scale / 1.5,
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: ColorTokens.primary,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

// 사인 함수 구현 (Math 패키지 없이 사용하기 위함)
double sin(double x) {
  // 테일러 급수를 사용한 사인 근사값 (충분히 정확)
  double result = 0;
  double term = x;
  
  // 첫 5개 항만 사용 (충분히 정확한 결과)
  result += term;
  
  term = term * x * x / 6;
  result -= term;
  
  term = term * x * x / 20;
  result += term;
  
  term = term * x * x / 42;
  result -= term;
  
  term = term * x * x / 72;
  result += term;
  
  return result;
} 