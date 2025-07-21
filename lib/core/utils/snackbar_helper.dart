import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'error_handler.dart';

/// 🎯 전역 Snackbar 헬퍼 클래스
/// 
/// Context가 없는 상황에서도 Snackbar를 표시할 수 있도록 도와주는 유틸리티
/// ErrorHandler의 Snackbar 메서드들을 활용하여 일관된 UI 제공
class SnackbarHelper {
  /// 🎯 현재 활성 context 찾기
  static BuildContext? _getCurrentContext() {
    return WidgetsBinding.instance.focusManager.primaryFocus?.context;
  }

  /// ✅ 성공 메시지 전역 표시
  static void showSuccess(String message) {
    final context = _getCurrentContext();
    if (context != null && context.mounted) {
      ErrorHandler.showSuccessSnackBar(context, message);
      
      if (kDebugMode) {
        debugPrint('📢 [SnackbarHelper] 성공 메시지 표시: $message');
      }
    } else {
      if (kDebugMode) {
        debugPrint('⚠️ [SnackbarHelper] Context를 찾을 수 없어 성공 메시지 표시 실패: $message');
      }
    }
  }

  /// ❌ 에러 메시지 전역 표시
  static void showError(String message) {
    final context = _getCurrentContext();
    if (context != null && context.mounted) {
      ErrorHandler.showErrorSnackBar(context, message);
      
      if (kDebugMode) {
        debugPrint('📢 [SnackbarHelper] 에러 메시지 표시: $message');
      }
    } else {
      if (kDebugMode) {
        debugPrint('⚠️ [SnackbarHelper] Context를 찾을 수 없어 에러 메시지 표시 실패: $message');
      }
    }
  }

  /// ℹ️ 정보 메시지 전역 표시
  static void showInfo(String message) {
    final context = _getCurrentContext();
    if (context != null && context.mounted) {
      ErrorHandler.showInfoSnackBar(context, message);
      
      if (kDebugMode) {
        debugPrint('📢 [SnackbarHelper] 정보 메시지 표시: $message');
      }
    } else {
      if (kDebugMode) {
        debugPrint('⚠️ [SnackbarHelper] Context를 찾을 수 없어 정보 메시지 표시 실패: $message');
      }
    }
  }

  /// 🎯 커스텀 Snackbar 전역 표시
  static void showCustom({
    required String message,
    Color? backgroundColor,
    Duration? duration,
    SnackBarAction? action,
  }) {
    final context = _getCurrentContext();
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          duration: duration ?? const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          action: action,
        ),
      );
      
      if (kDebugMode) {
        debugPrint('📢 [SnackbarHelper] 커스텀 메시지 표시: $message');
      }
    } else {
      if (kDebugMode) {
        debugPrint('⚠️ [SnackbarHelper] Context를 찾을 수 없어 커스텀 메시지 표시 실패: $message');
      }
    }
  }
} 