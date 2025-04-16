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
      color: Colors.black.withOpacity(0.5),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
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
                const SizedBox(
                  width: 40, 
                  height: 40,
                  child: CircularProgressIndicator(),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 