import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show timeDilation;
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import 'dart:async';
import 'dot_loading_indicator.dart';

/// Pikabook 로딩 화면
/// 로딩 상태를 시각적으로 표시하는 위젯입니다.
class PikabookLoader extends StatelessWidget {
  final String message;
  final String? subtitle;

  const PikabookLoader({
    Key? key,
    this.message = '스마트 노트를 만들고 있어요...',
    this.subtitle,
  }) : super(key: key);

  // 로더 상태 관리를 위한 정적 변수들
  static bool _isVisible = false;
  static BuildContext? _dialogContext;
  static Timer? _timeoutTimer;
  
  // 메시지 상태 관리를 위한 ValueNotifier
  static final ValueNotifier<String> _messageNotifier = ValueNotifier<String>('스마트 노트를 만들고 있어요...');

  /// 로더를 다이얼로그로 표시하는 정적 메서드
  static Future<void> show(
    BuildContext context, {
    String message = '스마트 노트를 만들고 있어요...',
    int timeoutSeconds = 10,
  }) async {
    // 디버그 타이머 비활성화
    timeDilation = 1.0;
    
    // 이미 실행 중인 타이머가 있다면 취소
    _cancelExistingTimer();
    
    // 이미 표시 중이면 메시지만 업데이트
    if (_isVisible) {
      updateMessage(message);
      return;
    }
    
    _isVisible = true;
    _messageNotifier.value = message;
    
    if (!context.mounted) return;
    
    // 다이얼로그 표시
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black54,
        builder: (context) {
          _dialogContext = context;
          return PopScope(
            canPop: false,
            child: Material(
              type: MaterialType.transparency,
              child: Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: const EdgeInsets.all(24),
                elevation: 0,
                child: _LoaderWithMessage(),
              ),
            ),
          );
        },
      ).then((_) {
        _isVisible = false;
        _cancelExistingTimer();
        timeDilation = 1.0;  // 디버그 타이머 비활성화
      }).catchError((e) {
        _isVisible = false;
        _cancelExistingTimer();
        timeDilation = 1.0;  // 디버그 타이머 비활성화
      });
      
      // 타이머 시작
      if (timeoutSeconds > 0 && context.mounted) {
        _startTimer(timeoutSeconds, context);
      }
    } catch (e) {
      _isVisible = false;
      debugPrint('로딩 다이얼로그 표시 중 오류: $e');
    }
  }
  
  /// 기존 타이머 취소
  static void _cancelExistingTimer() {
    if (_timeoutTimer != null) {
      try {
        _timeoutTimer!.cancel();
        _timeoutTimer = null;
      } catch (e) {
        // 오류 무시
      }
    }
  }
  
  /// 타이머 시작
  static void _startTimer(int seconds, BuildContext context) {
    _cancelExistingTimer();
    _timeoutTimer = Timer(Duration(seconds: seconds), () {
      if (context.mounted) {
        hide(context);
      }
    });
  }
  
  /// 메시지 업데이트 메서드
  static void updateMessage(String message) {
    _messageNotifier.value = message;
  }

  /// 로더를 숨기는 정적 메서드
  static void hide(BuildContext context) {
    if (!_isVisible) return;
    
    _isVisible = false;
    _cancelExistingTimer();
    
    // 디버그 타이머 비활성화
    timeDilation = 1.0;
    
    // 다이얼로그 닫기
    if (_dialogContext != null && _dialogContext!.mounted) {
      try {
        Navigator.of(_dialogContext!, rootNavigator: true).pop();
        _dialogContext = null;
      } catch (e) {
        // 오류 발생 시 지연 후 다시 시도
        Future.delayed(const Duration(milliseconds: 100), () {
          try {
            if (_dialogContext != null && _dialogContext!.mounted) {
              Navigator.of(_dialogContext!, rootNavigator: true).pop();
              _dialogContext = null;
            }
          } catch (_) {}
        });
      }
    }
  }
  
  /// 로딩 다이얼로그 표시 여부 확인
  static bool isShowing() {
    return _isVisible;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      width: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 애니메이션 로더
          const DotLoadingIndicator(
            dotColor: ColorTokens.primary,
            dotSize: 10.0,
            spacing: 8.0,
          ),
          
          const SizedBox(height: 24),
          
          // 메인 메시지
          Text(
            message,
            style: TypographyTokens.body1Bold,
            textAlign: TextAlign.center,
          ),
          
          // 서브타이틀이 있으면 표시
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: TypographyTokens.body1.copyWith(
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// 메시지 상태를 관리하는 내부 위젯
class _LoaderWithMessage extends StatefulWidget {
  @override
  State<_LoaderWithMessage> createState() => _LoaderWithMessageState();
}

class _LoaderWithMessageState extends State<_LoaderWithMessage> {
  @override
  void initState() {
    super.initState();
    PikabookLoader._messageNotifier.addListener(_onMessageChanged);
  }

  @override
  void dispose() {
    PikabookLoader._messageNotifier.removeListener(_onMessageChanged);
    super.dispose();
  }

  void _onMessageChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return PikabookLoader(
      message: PikabookLoader._messageNotifier.value,
    );
  }
} 