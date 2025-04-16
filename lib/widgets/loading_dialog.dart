import 'dart:ui';
import 'package:flutter/material.dart';

/// 로딩 다이얼로그 클래스
/// 앱 전체에서 로딩 표시에 사용됨
class LoadingDialog {
  static OverlayEntry? _overlayEntry;
  static bool _isVisible = false;
  
  /// 로딩 다이얼로그 표시
  static void show(BuildContext context, {String message = '로딩 중...'}) {
    debugPrint('로딩 다이얼로그 표시 요청: $message');
    
    // 이미 표시 중이면 무시
    if (_isVisible) {
      debugPrint('로딩 다이얼로그가 이미 표시 중입니다');
      return;
    }
    
    // 오버레이 항목 생성
    _overlayEntry = OverlayEntry(
      builder: (context) => _LoadingOverlay(message: message),
    );
    
    // 오버레이에 추가
    if (_overlayEntry != null) {
      Overlay.of(context).insert(_overlayEntry!);
      _isVisible = true;
      debugPrint('로딩 다이얼로그가 표시되었습니다');
    }
  }
  
  /// 로딩 다이얼로그 숨기기
  static void hide() {
    debugPrint('로딩 다이얼로그 숨김 요청');
    
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
      _isVisible = false;
      debugPrint('로딩 다이얼로그가 숨겨졌습니다');
    }
  }
  
  /// 로딩 다이얼로그 표시 여부 확인
  static bool isShowing() {
    return _isVisible;
  }
}

/// 로딩 오버레이 위젯
class _LoadingOverlay extends StatelessWidget {
  final String message;
  
  const _LoadingOverlay({required this.message});
  
  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x59000000), // rgba(0, 0, 0, 0.35)
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        child: Center(
          child: Container(
            width: 300,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 피카북 로더 애니메이션
                SizedBox(
                  height: 40,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildLoader(),
                      const SizedBox(width: 12),
                      _buildPikabirdLogo(),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  '스마트 노트를 만들고 있어요.',
                  style: const TextStyle(
                    fontFamily: 'Noto Sans KR',
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF226357),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  /// 로딩 애니메이션 위젯 생성
  Widget _buildLoader() {
    return SizedBox(
      width: 70,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          3,
          (index) => _buildBouncingDot(index * 0.3),
        ),
      ),
    );
  }
  
  /// 바운싱 애니메이션 도트 생성
  Widget _buildBouncingDot(double delay) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: _BouncingDot(
        delay: delay,
        color: const Color(0xFFFE975B),
        size: 8,
      ),
    );
  }
  
  /// 피카버드 로고 생성
  Widget _buildPikabirdLogo() {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      child: Stack(
        children: [
          // 새 모양 윤곽
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              color: Color(0xFFFE6A15),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
                bottomLeft: Radius.circular(15),
                bottomRight: Radius.circular(5),
              ),
            ),
          ),
          // 주황 노랑 그라데이션 배경
          Positioned(
            top: 3,
            left: 3,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Color(0xFFFFD53C),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(4),
                ),
              ),
            ),
          ),
          // 눈
          Positioned(
            top: 10,
            left: 15,
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 바운싱 애니메이션 도트 위젯
class _BouncingDot extends StatefulWidget {
  final double delay;
  final Color color;
  final double size;

  const _BouncingDot({
    required this.delay,
    required this.color,
    required this.size,
  });

  @override
  _BouncingDotState createState() => _BouncingDotState();
}

class _BouncingDotState extends State<_BouncingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _animation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: -10)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -10, end: 0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_controller);

    Future.delayed(Duration(milliseconds: (widget.delay * 1000).toInt()), () {
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
        return Transform.translate(
          offset: Offset(0, _animation.value),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
} 