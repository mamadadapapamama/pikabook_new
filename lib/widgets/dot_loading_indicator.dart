import 'package:flutter/material.dart';
import '../theme/tokens/color_tokens.dart';

/// 도트 애니메이션 로딩 인디케이터 위젯
/// 
/// 세 개의 도트가 애니메이션되는 심플한 로딩 인디케이터입니다.
/// 텍스트 작업 중일 때 사용되는 더 심플한 로딩 표시를 위해 설계되었습니다.
class DotLoadingIndicator extends StatefulWidget {
  final String? message;
  final Color dotColor;
  final double dotSize;
  final double spacing;

  const DotLoadingIndicator({
    Key? key,
    this.message,
    this.dotColor = const Color(0xFFFE6A15),
    this.dotSize = 10.0,
    this.spacing = 5.0,
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
    
    _animation1 = Tween<double>(begin: 0.0, end: 8.0).animate(
      CurvedAnimation(parent: _controller1, curve: Curves.easeInOut),
    );
    
    _animation2 = Tween<double>(begin: 0.0, end: 8.0).animate(
      CurvedAnimation(parent: _controller2, curve: Curves.easeInOut),
    );
    
    _animation3 = Tween<double>(begin: 0.0, end: 8.0).animate(
      CurvedAnimation(parent: _controller3, curve: Curves.easeInOut),
    );
    
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 첫 번째 도트
              AnimatedBuilder(
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
              AnimatedBuilder(
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
              AnimatedBuilder(
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
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
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
} 