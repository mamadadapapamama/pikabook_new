import 'package:flutter/material.dart';
import 'dart:async';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/color_tokens.dart';

/// ... 애니메이션을 보여주는 위젯 (번역/병음 준비 중 표시용)
class LoadingDotsWidget extends StatefulWidget {
  final TextStyle? style;
  final Duration delay;
  final bool usePinyinStyle; // 병음 스타일 강제 사용 여부

  const LoadingDotsWidget({
    Key? key,
    this.style,
    this.delay = Duration.zero,
    this.usePinyinStyle = true, // 기본값을 true로 설정
  }) : super(key: key);

  @override
  State<LoadingDotsWidget> createState() => _LoadingDotsWidgetState();
}

class _LoadingDotsWidgetState extends State<LoadingDotsWidget>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<int> _dotCount;
  Timer? _delayTimer;
  String _displayText = '';
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimation();
    _startAnimation();
  }

  void _initializeAnimation() {
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200), // 1.2초 주기
      vsync: this,
    );

    _dotCount = StepTween(
      begin: 0,
      end: 4, // 0, 1, 2, 3 (빈 문자열, ., .., ...)
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _dotCount.addListener(() {
      if (mounted && _started) {
        setState(() {
          final count = _dotCount.value;
          _displayText = count == 0 ? '' : '.' * count;
        });
      }
    });

    // 무한 반복
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && _started) {
        _controller.reset();
        _controller.forward();
      }
    });
  }

  void _startAnimation() {
    if (widget.delay.inMilliseconds > 0) {
      _delayTimer = Timer(widget.delay, () {
        if (mounted) {
          setState(() {
            _started = true;
          });
          _controller.forward();
        }
      });
    } else {
      setState(() {
        _started = true;
      });
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _delayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 병음 스타일 강제 사용 또는 전달받은 스타일 사용
    TextStyle effectiveStyle;
    
    if (widget.usePinyinStyle) {
      // 병음 스타일로 고정 (로딩 애니메이션 일관성을 위해)
      effectiveStyle = TypographyTokens.caption.copyWith(
        color: ColorTokens.textGrey,
        height: 1.2,
      );
    } else {
      // 전달받은 스타일 사용
      effectiveStyle = widget.style ?? TypographyTokens.caption.copyWith(
        color: ColorTokens.textGrey,
        height: 1.2,
      );
    }

    return Text(
      _displayText,
      style: effectiveStyle,
    );
  }
} 