import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/tokens/color_tokens.dart';
import 'dart:async';

/// 전역 로딩 다이얼로그 상태 관리 클래스
class LoadingDialog {
  static bool _isShowing = false;
  static String _message = '로딩 중...';
  static BuildContext? _dialogContext;
  static Timer? _dismissTimer;
  static final _messageStreamController = StreamController<String>.broadcast();
  
  /// 로딩 다이얼로그 표시
  static Future<void> show(BuildContext context, {String message = '로딩 중...'}) async {
    // 이미 표시 중이면 메시지만 업데이트
    if (_isShowing) {
      updateMessage(message);
      debugPrint('로딩 다이얼로그가 이미 표시 중입니다. 메시지 업데이트: $message');
      return;
    }
    
    _isShowing = true;
    _message = message;
    _messageStreamController.add(message);
    
    // 안전 장치: 최대 15초 후 자동으로 닫힘
    _dismissTimer?.cancel();
    _dismissTimer = Timer(const Duration(seconds: 15), () {
      hide();
      debugPrint('로딩 다이얼로그 자동 타임아웃 (15초)');
    });
    
    try {
      // BuildContext 유효성 확인
      if (!context.mounted) {
        debugPrint('컨텍스트가 유효하지 않아 로딩 다이얼로그 표시 불가');
        _isShowing = false;
        return;
      }
      
      // 모달 다이얼로그 표시
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          _dialogContext = dialogContext;
          return _LoadingOverlay(
            messageStream: _messageStreamController.stream,
            initialMessage: _message,
          );
        },
      ).then((_) {
        // 다이얼로그가 닫히면 상태 초기화
        _isShowing = false;
        _dialogContext = null;
        debugPrint('로딩 다이얼로그가 닫혔습니다');
      });
    } catch (e) {
      debugPrint('로딩 다이얼로그 표시 중 오류: $e');
      _isShowing = false;
    }
    
    debugPrint('로딩 다이얼로그 표시 요청: $message');
  }
  
  /// 로딩 다이얼로그 메시지 업데이트
  static void updateMessage(String message) {
    _message = message;
    _messageStreamController.add(message);
    debugPrint('로딩 다이얼로그 메시지 업데이트: $message');
  }
  
  /// 로딩 다이얼로그 숨기기
  static void hide() {
    debugPrint('로딩 다이얼로그 숨김 요청');
    
    // 타이머 취소
    _dismissTimer?.cancel();
    _dismissTimer = null;
    
    // 이미 닫혀있으면 무시
    if (!_isShowing) {
      debugPrint('로딩 다이얼로그가 이미 닫혀있습니다');
      return;
    }
    
    // 다이얼로그 컨텍스트가 있을 때만 닫기 시도
    if (_dialogContext != null && _dialogContext!.mounted) {
      try {
        Navigator.of(_dialogContext!).pop();
        debugPrint('로딩 다이얼로그가 숨겨졌습니다');
      } catch (e) {
        debugPrint('다이얼로그 닫기 중 오류: $e');
      }
    } else {
      debugPrint('다이얼로그 컨텍스트가 유효하지 않아 숨기기 실패');
    }
    
    // 상태 초기화
    _isShowing = false;
    _dialogContext = null;
  }
  
  /// 로딩 다이얼로그가 현재 표시 중인지 확인
  static bool get isShowing => _isShowing;
  
  /// 현재 표시 중인 메시지 가져오기
  static String get message => _message;
  
  /// 리소스 정리 (앱 종료 시 호출)
  static void dispose() {
    _dismissTimer?.cancel();
    _messageStreamController.close();
  }
}

/// 로딩 오버레이 위젯
class _LoadingOverlay extends StatefulWidget {
  final Stream<String> messageStream;
  final String initialMessage;
  
  const _LoadingOverlay({
    required this.messageStream,
    required this.initialMessage,
  });
  
  @override
  _LoadingOverlayState createState() => _LoadingOverlayState();
}

class _LoadingOverlayState extends State<_LoadingOverlay> with SingleTickerProviderStateMixin {
  late String _message;
  late AnimationController _controller;
  StreamSubscription? _messageSubscription;
  
  @override
  void initState() {
    super.initState();
    _message = widget.initialMessage;
    
    // 메시지 스트림 구독
    _messageSubscription = widget.messageStream.listen((newMessage) {
      if (mounted) {
        setState(() {
          _message = newMessage;
        });
      }
    });
    
    // 애니메이션 컨트롤러 초기화
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }
  
  @override
  void dispose() {
    _messageSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // 뒤로가기 버튼으로 닫히지 않도록 설정
      onWillPop: () async => false,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          color: Colors.black.withOpacity(0.5),
          width: double.infinity,
          height: double.infinity,
          child: Center(
            child: Container(
              width: 200,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Image.asset(
                    'assets/images/logo.png',
                    width: 60,
                    height: 60,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: ColorTokens.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.auto_stories,
                          color: Colors.white,
                          size: 30,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  _buildBouncingDots(),
                  const SizedBox(height: 20),
                  Text(
                    _message,
                    style: const TextStyle(fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  /// 로딩 애니메이션 위젯 생성
  Widget _buildBouncingDots() {
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
        controller: _controller,
        color: ColorTokens.primary,
        size: 8,
      ),
    );
  }
}

/// 바운싱 애니메이션 도트 위젯
class _BouncingDot extends StatelessWidget {
  final double delay;
  final Color color;
  final double size;
  final AnimationController controller;

  const _BouncingDot({
    required this.delay,
    required this.color,
    required this.size,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final Animation<double> animation = TweenSequence<double>([
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
    ]).animate(
      CurvedAnimation(
        parent: controller,
        curve: Interval(
          delay,  // 시작 지연
          delay + 0.7,  // 종료 (0.7 범위 내에서 애니메이션)
          curve: Curves.linear,
        ),
      ),
    );

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, animation.value),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
} 