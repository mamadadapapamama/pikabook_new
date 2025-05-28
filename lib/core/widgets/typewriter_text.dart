import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

/// 타이프라이터 효과를 제공하는 텍스트 위젯
class TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration duration;
  final Duration delay;
  final VoidCallback? onComplete;
  final bool autoStart;

  const TypewriterText({
    Key? key,
    required this.text,
    this.style,
    this.duration = const Duration(milliseconds: 50),
    this.delay = Duration.zero,
    this.onComplete,
    this.autoStart = true,
  }) : super(key: key);

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<int> _characterCount;
  Timer? _delayTimer;
  String _displayText = '';

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      debugPrint('🎬 TypewriterText initState: "${widget.text.length > 30 ? widget.text.substring(0, 30) + "..." : widget.text}"');
      debugPrint('   autoStart: ${widget.autoStart}, delay: ${widget.delay.inMilliseconds}ms');
    }
    _initializeAnimation();
    
    if (widget.autoStart) {
      _startAnimation();
    }
  }

  void _initializeAnimation() {
    _controller = AnimationController(
      duration: Duration(
        milliseconds: widget.text.length * widget.duration.inMilliseconds,
      ),
      vsync: this,
    );

    _characterCount = StepTween(
      begin: 0,
      end: widget.text.length,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _characterCount.addListener(() {
      if (mounted) {
        setState(() {
          _displayText = widget.text.substring(0, _characterCount.value);
        });
      }
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && widget.onComplete != null) {
        widget.onComplete!();
      }
    });
  }

  void _startAnimation() {
    if (kDebugMode) {
      debugPrint('▶️ TypewriterText _startAnimation 시작');
      debugPrint('   delay: ${widget.delay.inMilliseconds}ms, text length: ${widget.text.length}');
    }
    
    if (widget.delay.inMilliseconds > 0) {
      _delayTimer = Timer(widget.delay, () {
        if (mounted) {
          if (kDebugMode) {
            debugPrint('⏰ TypewriterText delay 완료, 애니메이션 시작');
          }
          _controller.forward();
        }
      });
    } else {
      if (kDebugMode) {
        debugPrint('🚀 TypewriterText 즉시 애니메이션 시작');
      }
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(TypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (oldWidget.text != widget.text) {
      _controller.reset();
      _displayText = '';
      _initializeAnimation();
      
      if (widget.autoStart) {
        _startAnimation();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _delayTimer?.cancel();
    super.dispose();
  }

  /// 애니메이션 시작
  void start() {
    _startAnimation();
  }

  /// 애니메이션 중지
  void stop() {
    _controller.stop();
    _delayTimer?.cancel();
  }

  /// 애니메이션 리셋
  void reset() {
    _controller.reset();
    setState(() {
      _displayText = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayText,
      style: widget.style,
    );
  }
}

/// 스트리밍 텍스트를 위한 특별한 타이프라이터 위젯
class StreamingTypewriterText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration characterDelay;
  final bool isComplete;
  final VoidCallback? onComplete;

  const StreamingTypewriterText({
    Key? key,
    required this.text,
    this.style,
    this.characterDelay = const Duration(milliseconds: 30),
    this.isComplete = false,
    this.onComplete,
  }) : super(key: key);

  @override
  State<StreamingTypewriterText> createState() => _StreamingTypewriterTextState();
}

class _StreamingTypewriterTextState extends State<StreamingTypewriterText> {
  String _displayText = '';
  Timer? _timer;
  int _currentIndex = 0;
  String _previousText = '';

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  @override
  void didUpdateWidget(StreamingTypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (oldWidget.text != widget.text) {
      _previousText = oldWidget.text;
      _startTyping();
    }
  }

  void _startTyping() {
    _timer?.cancel();
    
    // 이전 텍스트보다 긴 부분만 타이핑
    final startIndex = _previousText.length;
    _currentIndex = startIndex;
    
    if (startIndex < widget.text.length) {
      _timer = Timer.periodic(widget.characterDelay, (timer) {
        if (_currentIndex < widget.text.length) {
          setState(() {
            _displayText = widget.text.substring(0, _currentIndex + 1);
            _currentIndex++;
          });
        } else {
          timer.cancel();
          if (widget.isComplete && widget.onComplete != null) {
            widget.onComplete!();
          }
        }
      });
    } else {
      // 이미 모든 텍스트가 표시된 경우
      setState(() {
        _displayText = widget.text;
      });
      if (widget.isComplete && widget.onComplete != null) {
        widget.onComplete!();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayText,
      style: widget.style,
    );
  }
}

/// 페이드인 효과와 함께 나타나는 텍스트
class FadeInText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration duration;
  final Duration delay;
  final VoidCallback? onComplete;

  const FadeInText({
    Key? key,
    required this.text,
    this.style,
    this.duration = const Duration(milliseconds: 500),
    this.delay = Duration.zero,
    this.onComplete,
  }) : super(key: key);

  @override
  State<FadeInText> createState() => _FadeInTextState();
}

class _FadeInTextState extends State<FadeInText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );

    _opacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed && widget.onComplete != null) {
        widget.onComplete!();
      }
    });

    _startAnimation();
  }

  void _startAnimation() {
    if (widget.delay.inMilliseconds > 0) {
      _delayTimer = Timer(widget.delay, () {
        if (mounted) {
          _controller.forward();
        }
      });
    } else {
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
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Text(
            widget.text,
            style: widget.style,
          ),
        );
      },
    );
  }
} 