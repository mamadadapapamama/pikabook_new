import 'package:flutter/material.dart';
import 'dart:ui';

/// 로딩 다이얼로그를 표시하는 유틸리티 클래스
///
/// 장시간의 작업이 진행될 때 전체 화면을 덮는 로딩 다이얼로그를 표시합니다.
/// 내부적으로 PikabookLoader를 사용하여 디자인에 맞게 구현되었습니다.
class LoadingDialog {
  static OverlayEntry? _overlayEntry;
  
  /// 로딩 다이얼로그를 표시하는 정적 메서드
  static void show(BuildContext context, {String message = '로딩 중...'}) {
    // 이미 표시 중이면 닫고 다시 열기
    hide(context);
    
    _overlayEntry = OverlayEntry(
      builder: (context) => _LoadingOverlay(message: message),
    );
    
    if (_overlayEntry != null && context.mounted) {
      try {
        Overlay.of(context).insert(_overlayEntry!);
      } catch (e) {
        debugPrint('로딩 다이얼로그 표시 중 오류: $e');
      }
    }
  }
  
  /// 로딩 다이얼로그를 닫는 정적 메서드
  static void hide(BuildContext context) {
    if (_overlayEntry != null) {
      try {
        _overlayEntry!.remove();
        _overlayEntry = null;
      } catch (e) {
        debugPrint('로딩 다이얼로그 닫기 중 오류: $e');
      }
    }
  }
}

/// 로딩 오버레이 위젯
class _LoadingOverlay extends StatelessWidget {
  final String message;
  
  const _LoadingOverlay({required this.message});
  
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.7),
      child: Center(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 15,
                  spreadRadius: 2,
                )
              ]
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    strokeWidth: 4.0,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
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
} 