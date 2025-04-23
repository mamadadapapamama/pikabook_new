import 'package:flutter/material.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';

/// 도트 애니메이션 로딩 인디케이터 위젯 (로딩의 기본 유닛)
/// 세 개의 도트가 애니메이션되는 심플한 로딩 인디케이터입니다.

class DotLoadingIndicator extends StatefulWidget {
  final String? message;
  final Color dotColor;
  final double dotSize;
  final double spacing;
  final bool isLoginScreen;

  const DotLoadingIndicator({
    Key? key,
    this.message,
    this.dotColor = ColorTokens.primary,
    this.dotSize = 10.0,  
    this.spacing = 8.0,  
    this.isLoginScreen = false,
  }) : super(key: key);

  @override
  State<DotLoadingIndicator> createState() => _DotLoadingIndicatorState();
}

class _DotLoadingIndicatorState extends State<DotLoadingIndicator> with TickerProviderStateMixin {
  late AnimationController _controller1;
  late AnimationController _controller2;
  late AnimationController _controller3;
  
  late Animation<double> _animation1;
  late Animation<double> _animation2;
  late Animation<double> _animation3;

  @override
  void initState() {
    super.initState();
    
    _controller1 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    
    _controller2 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    
    _controller3 = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    
    // 로그인 화면에서는 다른 애니메이션 효과 적용
    if (widget.isLoginScreen) {
      _animation1 = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _controller1, curve: Curves.easeInOut),
      );
      
      _animation2 = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _controller2, curve: Curves.easeInOut),
      );
      
      _animation3 = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _controller3, curve: Curves.easeInOut),
      );
    } else {
      _animation1 = Tween<double>(begin: 0.0, end: 8.0).animate(
        CurvedAnimation(parent: _controller1, curve: Curves.easeInOut),
      );
      
      _animation2 = Tween<double>(begin: 0.0, end: 8.0).animate(
        CurvedAnimation(parent: _controller2, curve: Curves.easeInOut),
      );
      
      _animation3 = Tween<double>(begin: 0.0, end: 8.0).animate(
        CurvedAnimation(parent: _controller3, curve: Curves.easeInOut),
      );
    }
    
    // 두 번째 도트 애니메이션 지연
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) {
        _controller2.repeat(reverse: true);
      }
    });
    
    // 세 번째 도트 애니메이션 지연
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _controller3.repeat(reverse: true);
      }
    });
  }

  @override
  void dispose() {
    _controller1.dispose();
    _controller2.dispose();
    _controller3.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 현재 테마의 밝기 확인
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    // 테마에 따른 텍스트 색상 설정
    final textColor = isDarkMode ? ColorTokens.textLight : ColorTokens.textPrimary;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 첫 번째 도트
              widget.isLoginScreen 
                ? _buildLoginDot(_animation1)
                : AnimatedBuilder(
                    animation: _animation1,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, -_animation1.value),
                        child: _buildDot(),
                      );
                    },
                  ),
              SizedBox(width: widget.spacing),
              // 두 번째 도트
              widget.isLoginScreen 
                ? _buildLoginDot(_animation2)
                : AnimatedBuilder(
                    animation: _animation2,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, -_animation2.value),
                        child: _buildDot(),
                      );
                    },
                  ),
              SizedBox(width: widget.spacing),
              // 세 번째 도트
              widget.isLoginScreen 
                ? _buildLoginDot(_animation3)
                : AnimatedBuilder(
                    animation: _animation3,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, -_animation3.value),
                        child: _buildDot(),
                      );
                    },
                  ),
            ],
          ),
          if (widget.message != null) ...[
            const SizedBox(height: 16),
            Text(
              widget.message!,
              textAlign: TextAlign.center,
              style: TypographyTokens.body2.copyWith(
                color: textColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDot() {
    return Container(
      width: widget.dotSize,
      height: widget.dotSize,
      decoration: BoxDecoration(
        color: widget.dotColor,
        shape: BoxShape.circle,
      ),
    );
  }

  // 로그인 화면용 도트 빌더 - 투명도 애니메이션
  Widget _buildLoginDot(Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Container(
          width: widget.dotSize,
          height: widget.dotSize,
          decoration: BoxDecoration(
            color: widget.dotColor.withOpacity(animation.value),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
} 