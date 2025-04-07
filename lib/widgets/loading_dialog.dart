import 'package:flutter/material.dart';
import 'pikabook_loader.dart';
import 'dart:async';

/// 로딩 다이얼로그를 표시하는 유틸리티 클래스
///
/// 장시간의 작업이 진행될 때 전체 화면을 덮는 로딩 다이얼로그를 표시합니다.
/// 내부적으로 PikabookLoader를 사용하여 디자인에 맞게 구현되었습니다.
class LoadingDialog {
  static bool _isShowing = false;
  static BuildContext? _dialogContext;
  static Timer? _autoHideTimer;

  /// 로딩 다이얼로그를 표시하는 정적 메서드
  static Future<void> show(BuildContext context, {
    String message = '로딩 중...', 
    int timeoutSeconds = 20, // 타임아웃 시간(초) 추가
  }) async {
    if (!context.mounted) {
      return;
    }

    // 이미 표시 중이면 기존 다이얼로그 닫기 시도
    if (_isShowing) {
      hide(context);
      // 닫기 작업이 완료될 때까지 짧게 대기
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // 자동 닫힘 타이머 취소
    _autoHideTimer?.cancel();

    // 상태 업데이트
    _isShowing = true;
    _dialogContext = context;

    try {
      // 자동 닫힘 타이머 설정 (최종 안전장치)
      _autoHideTimer = Timer(Duration(seconds: timeoutSeconds + 2), () {
        if (_isShowing) {
          // 타이머 로그 출력 방지
          _safeDebugPrint('로딩 다이얼로그 자동 닫힘 타이머 작동!');
          hide(context);
        }
      });

      // Dialog 위젯을 사용하여 중앙에 작은 창으로 표시
      showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black54,
        builder: (BuildContext dialogContext) {
          _dialogContext = dialogContext;
          return WillPopScope(
            onWillPop: () async => false,
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: PikabookLoader(
                title: '스마트한 학습 노트를 만들고 있어요.',
                subtitle: '잠시만 기다려 주세요!',
                timeoutSeconds: timeoutSeconds, // 타임아웃 값 전달
              ),
            ),
          );
        },
      ).then((_) {
        // 다이얼로그가 닫히면 상태 업데이트
        _isShowing = false;
        _dialogContext = null;
        _autoHideTimer?.cancel();
        _safeDebugPrint('로딩 다이얼로그 닫힘 완료 (then 콜백)');
      }).catchError((e) {
        _safeDebugPrint('로딩 다이얼로그 오류: $e');
        _isShowing = false;
        _dialogContext = null;
        _autoHideTimer?.cancel();
      });
    } catch (e) {
      _safeDebugPrint('로딩 다이얼로그 표시 중 오류: $e');
      _isShowing = false;
      _dialogContext = null;
      _autoHideTimer?.cancel();
    }
  }

  /// 로딩 다이얼로그를 닫는 정적 메서드
  static void hide(BuildContext context) {
    // 타이머 취소
    _autoHideTimer?.cancel();
    
    // 다이얼로그가 표시되어 있지 않으면 아무 작업도 하지 않음
    if (!_isShowing) {
      return;
    }
    
    // 상태 업데이트 (먼저 업데이트하여 중복 호출 방지)
    _isShowing = false;
    
    // 여러 방법으로 다이얼로그 닫기 시도
    _tryCloseDialog(context);
  }
  
  /// 다양한 방법으로 다이얼로그 닫기 시도
  static void _tryCloseDialog(BuildContext context) {
    // 방법 1: 저장된 컨텍스트로 닫기 시도
    if (_dialogContext != null && _dialogContext!.mounted) {
      try {
        Navigator.of(_dialogContext!, rootNavigator: true).pop();
        _dialogContext = null;
        return;
      } catch (e) {
        // 오류 무시
      }
    }

    // 방법 2: 전달된 컨텍스트로 닫기 시도
    if (context.mounted) {
      try {
        Navigator.of(context, rootNavigator: true).pop();
        _dialogContext = null;
        return;
      } catch (e) {
        // 오류 무시
      }
    }

    // 방법 3: 지연 후 재시도
    Future.delayed(Duration(milliseconds: 200), () {
      if ((_dialogContext != null && _dialogContext!.mounted) || context.mounted) {
        try {
          final effectiveContext = (_dialogContext != null && _dialogContext!.mounted) 
              ? _dialogContext! 
              : context;
          
          if (effectiveContext.mounted) {
            Navigator.of(effectiveContext, rootNavigator: true).pop();
          }
        } catch (e) {
          // 오류 무시
        } finally {
          _dialogContext = null;
        }
      }
    });
  }

  // 안전한 디버그 출력 (UI에 표시되지 않도록)
  static void _safeDebugPrint(String message) {
    try {
      // 로그 메시지에 타이머 관련 키워드 포함 시 접두사 추가
      if (message.contains('타이머') || message.contains('시간') || 
          message.contains('ms') || message.contains('초')) {
        // 아무것도 출력하지 않음
        return;
      }
      
      // 시간 정보 없이 로그 출력
      debugPrint('[로딩다이얼로그] $message');
    } catch (e) {
      // 로깅 중 예외 발생 시 무시
    }
  }
} 