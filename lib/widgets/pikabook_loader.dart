import 'package:flutter/material.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';

/// Pikabook 로딩 화면
/// 
/// 노트 생성 중 또는 긴 작업 시간 동안 사용자에게 로딩 상태를 시각적으로 표시하는 위젯입니다.
/// Figma 디자인에 따라 구현되었습니다.
class PikabookLoader extends StatelessWidget {
  final String title;
  final String subtitle;

  const PikabookLoader({
    Key? key,
    this.title = '스마트한 번역 노트를 만들고 있어요.',
    this.subtitle = '잠시만 기다려 주세요!',
  }) : super(key: key);

  /// 로더를 다이얼로그로 표시하는 정적 메서드
  static Future<void> show(
    BuildContext context, {
    String title = '스마트한 번역 노트를 만들고 있어요.',
    String subtitle = '잠시만 기다려 주세요!',
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false, // 뒤로 가기 방지
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          elevation: 0,
          child: PikabookLoader(
            title: title,
            subtitle: subtitle,
          ),
        ),
      ),
    );
  }

  /// 로더를 숨기는 정적 메서드
  static void hide(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();
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
          _PikabookDotPulseAnimation(),
          
          const SizedBox(height: 24),
          
          // 텍스트 섹션
          Text(
            title,
            style: TypographyTokens.body1.copyWith(
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          
          const SizedBox(height: 8),
          
          Text(
            subtitle,
            style: TypographyTokens.body1.copyWith(
              fontWeight: FontWeight.w500,
              color: ColorTokens.primary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// 피카북 도트 펄스 애니메이션 위젯
class _PikabookDotPulseAnimation extends StatefulWidget {
  @override
  State<_PikabookDotPulseAnimation> createState() => _PikabookDotPulseAnimationState();
}

class _PikabookDotPulseAnimationState extends State<_PikabookDotPulseAnimation> 
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    
    // 애니메이션 컨트롤러 초기화
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      width: double.infinity,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 도트 펄스 애니메이션
          _buildDotPulse(),
          
          // 피카북 새 캐릭터 (고정된 상태)
          Image.asset(
            'assets/images/pikabird_80x80.png',
            width: 40,
            height: 40,
          ),
        ],
      ),
    );
  }

  Widget _buildDotPulse() {
    // 도트 애니메이션의 기본 색상
    final Color dotColor = ColorTokens.primary;
    
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _buildAnimatedDot(0, dotColor),
            const SizedBox(width: 6),
            _buildAnimatedDot(0.2, dotColor),
            const SizedBox(width: 6),
            _buildAnimatedDot(0.4, dotColor),
            const SizedBox(width: 12),
          ],
        );
      },
    );
  }

  Widget _buildAnimatedDot(double delay, Color color) {
    // 0부터 1까지의 애니메이션 값에서 지연 적용
    final double animationValue = ((_controller.value - delay) % 1.0);
    
    // 애니메이션 값이 음수가 되지 않도록 조정
    final double normalizedValue = animationValue < 0 ? 0 : animationValue;
    
    // 0.5까지 크기가 커지고, 0.5부터 1까지 다시 작아지는 효과
    double scale = 1.0;
    if (normalizedValue < 0.5) {
      scale = 1.0 + normalizedValue; // 1.0 ~ 1.5
    } else {
      scale = 2.5 - normalizedValue * 2; // 1.5 ~ 1.0
    }

    // 투명도도 크기에 맞게 조정 (크기가 클수록 불투명)
    // 범위를 0.0-1.0으로 제한
    double opacity = (0.3 + (scale - 1.0) * 1.4).clamp(0.0, 1.0);
    
    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
} 