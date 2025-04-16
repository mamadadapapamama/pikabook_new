import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/tokens/color_tokens.dart';
import 'dart:async';

/// 간단한 로딩 다이얼로그 관리 클래스
/// static 메서드를 통해 앱 전체에서 로딩 표시 관리
class LoadingDialog {
  static bool _isVisible = false;
  static String _message = '로딩 중...';
  static BuildContext? _dialogContext;
  
  /// 로딩 다이얼로그 표시
  static void show(BuildContext context, {String message = '로딩 중...'}) {
    // 이미 표시 중이면 메시지만 업데이트
    if (_isVisible) {
      updateMessage(message);
      return;
    }
    
    _isVisible = true;
    _message = message;
    
    // Dialog 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        _dialogContext = context;
        return WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            backgroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 로고 이미지
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
                // 로딩 인디케이터
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(ColorTokens.primary),
                ),
                const SizedBox(height: 16),
                // 로딩 메시지 텍스트
                StatefulBuilder(
                  builder: (context, setState) {
                    // 전역 메시지 변수 감시
                    return ValueListenableBuilder<String>(
                      valueListenable: _MessageNotifier()..value = _message,
                      builder: (context, message, child) {
                        return Text(
                          message,
                          style: const TextStyle(fontSize: 14),
                          textAlign: TextAlign.center,
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      _isVisible = false;
      _dialogContext = null;
    });
    
    debugPrint('로딩 다이얼로그 표시 완료');
  }
  
  /// 로딩 다이얼로그 메시지 업데이트
  static void updateMessage(String message) {
    _message = message;
    // 메시지 노티파이어 업데이트
    _MessageNotifier().value = message;
    debugPrint('로딩 다이얼로그 메시지 업데이트: $message');
  }
  
  /// 로딩 다이얼로그 숨기기
  static void hide() {
    if (!_isVisible) {
      debugPrint('로딩 다이얼로그가 이미 숨겨져 있음');
      return;
    }
    
    if (_dialogContext != null) {
      // 단순히 Navigator.pop 호출
      try {
        Navigator.of(_dialogContext!).pop();
        debugPrint('로딩 다이얼로그가 숨겨졌습니다');
      } catch (e) {
        debugPrint('로딩 다이얼로그 숨기기 중 오류: $e');
      }
    } else {
      debugPrint('로딩 다이얼로그 컨텍스트가 없어 숨기기 실패');
    }
    
    _isVisible = false;
    _dialogContext = null;
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