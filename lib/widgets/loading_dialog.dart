import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../theme/tokens/color_tokens.dart';
import 'dart:async';

/// 매우 단순화된 로딩 다이얼로그 관리자
class LoadingDialog {
  static bool _isVisible = false;
  static String _message = '로딩 중...';
  static OverlayEntry? _overlayEntry;
  static BuildContext? _dialogContext;
  
  /// 로딩 다이얼로그 표시
  static void show(BuildContext context, {String message = '로딩 중...'}) {
    try {
      if (_isVisible) {
        updateMessage(message);
        return;
      }
      
      _isVisible = true;
      _message = message;
      
      try {
        // Navigator를 통한 다이얼로그 표시 방식으로 변경
        Future.microtask(() {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext dialogContext) {
              _dialogContext = dialogContext;
              return WillPopScope(
                onWillPop: () async => false,
                child: Dialog(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  child: Container(
                    width: 200,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 로딩 이미지
                        Image.asset(
                          'assets/images/pikabook_loader.gif',
                          width: 60,
                          height: 60,
                          errorBuilder: (context, error, stackTrace) {
                            // 이미지 로드 실패 시 CircularProgressIndicator 표시
                            return const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(ColorTokens.primary),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        // 메시지 텍스트
                        _MessageText(initialMessage: message),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        });
        
        debugPrint('로딩 다이얼로그 표시 완료: $message');
      } catch (e) {
        _isVisible = false;
        debugPrint('로딩 다이얼로그 표시 중 오류: $e');
      }
    } catch (e) {
      _isVisible = false;
      debugPrint('로딩 다이얼로그 초기화 중 오류: $e');
    }
  }
  
  /// 로딩 다이얼로그 메시지 업데이트
static void updateMessage(String message) {
  if (!kDebugMode) return; // 릴리즈 모드에서는 아무 동작도 하지 않음

  try {
    _message = message;
    // 별도의 microtask로 실행하여 UI 업데이트 안정성 개선
    Future.microtask(() {
      _MessageNotifier().value = message;
    });
    debugPrint('로딩 다이얼로그 메시지 업데이트: $message');
  } catch (e) {
    debugPrint('로딩 다이얼로그 메시지 업데이트 중 오류: $e');
  }
}  
  /// 로딩 다이얼로그 숨기기
  static void hide() {
    try {
      if (!_isVisible) {
        return;
      }
      
      // 다이얼로그 컨텍스트가 있으면 Navigator.pop으로 닫기
      if (_dialogContext != null) {
        try {
          Navigator.of(_dialogContext!, rootNavigator: true).pop();
          _dialogContext = null;
        } catch (e) {
          debugPrint('Navigator.pop으로 다이얼로그 닫기 실패: $e');
        }
      }
      // 기존 OverlayEntry 방식의 cleanup도 유지
      else if (_overlayEntry != null) {
        try {
          _overlayEntry!.remove();
        } catch (e) {
          debugPrint('로딩 다이얼로그 제거 중 오류: $e');
        } finally {
          _overlayEntry = null;
        }
      }
      
      _isVisible = false;
      debugPrint('로딩 다이얼로그 숨김 완료');
    } catch (e) {
      // 오류가 발생해도 상태 초기화
      _isVisible = false;
      _overlayEntry = null;
      _dialogContext = null;
      debugPrint('로딩 다이얼로그 숨김 중 오류: $e');
    }
  }
  
  /// 로딩 다이얼로그 표시 여부 확인
  static bool isShowing() {
    return _isVisible;
  }
}

/// 메시지 업데이트를 위한 내부 ValueNotifier
class _MessageNotifier extends ValueNotifier<String> {
  static final _MessageNotifier _instance = _MessageNotifier._internal('');
  
  factory _MessageNotifier() {
    return _instance;
  }
  
  _MessageNotifier._internal(String value) : super(value);
}

/// 메시지 텍스트 위젯 (상태 변경에 반응)
class _MessageText extends StatefulWidget {
  final String initialMessage;
  
  const _MessageText({required this.initialMessage});
  
  @override
  State<_MessageText> createState() => _MessageTextState();
}

class _MessageTextState extends State<_MessageText> {
  late String _message;
  
  @override
  void initState() {
    super.initState();
    _message = widget.initialMessage;
    
    // 메시지 변경을 감지하기 위한 리스너 추가
    _MessageNotifier().addListener(_updateMessage);
  }
  
  @override
  void dispose() {
    _MessageNotifier().removeListener(_updateMessage);
    super.dispose();
  }
  
  void _updateMessage() {
    if (mounted) {
      setState(() {
        _message = _MessageNotifier().value;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Text(
      _message,
      style: const TextStyle(fontSize: 14),
      textAlign: TextAlign.center,
    );
  }
} 