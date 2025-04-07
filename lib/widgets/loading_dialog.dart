import 'package:flutter/material.dart';
import 'pikabook_loader.dart';

/// 로딩 다이얼로그를 표시하는 유틸리티 클래스
///
/// 장시간의 작업이 진행될 때 전체 화면을 덮는 로딩 다이얼로그를 표시합니다.
/// 내부적으로 PikabookLoader를 사용하여 디자인에 맞게 구현되었습니다.
class LoadingDialog {
  static bool _isShowing = false;
  static BuildContext? _dialogContext;

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
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // 상태 업데이트
    _isShowing = true;
    _dialogContext = context;

    try {
      // 즉시 배경을 보여주기 위해 애니메이션 없이 즉시 표시
      await showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black54,
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) {
          _dialogContext = context;
          return WillPopScope(
            onWillPop: () async => false,
            child: SafeArea(
              child: Material(
                type: MaterialType.transparency,
                child: PikabookLoader(
                  title: '스마트한 학습 노트를 만들고 있어요.',
                  subtitle: '잠시만 기다려 주세요!',
                  timeoutSeconds: timeoutSeconds, // 타임아웃 값 전달
                ),
              ),
            ),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: Tween<double>(begin: 0.0, end: 1.0).animate(animation),
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutQuint,
                ),
              ),
              child: child,
            ),
          );
        },
      );
    } catch (e) {
      // 오류 발생 시에도 상태는 업데이트
      _isShowing = true;
      _dialogContext = context;
    }
  }

  /// 로딩 다이얼로그를 닫는 정적 메서드
  static void hide(BuildContext context) {
    // 다이얼로그가 표시되어 있지 않으면 아무 작업도 하지 않음
    if (!_isShowing) {
      return;
    }
    
    // 상태 업데이트 (먼저 업데이트하여 중복 호출 방지)
    _isShowing = false;
    
    try {
      // PikabookLoader의 hide 메서드를 사용하여 닫기
      PikabookLoader.hide(context);
    } catch (e) {
      // 오류 발생 시 직접 Navigator를 통해 닫기 시도
      try {
        // 저장된 다이얼로그 컨텍스트가 있으면 사용, 없으면 전달된 컨텍스트 사용
        BuildContext effectiveContext = _dialogContext ?? context;
        
        // 컨텍스트 유효성 검사 및 닫기 시도
        if (effectiveContext.mounted) {
          Navigator.of(effectiveContext, rootNavigator: true).pop();
        }
      } catch (navError) {
        // 오류 무시
      }
    } finally {
      // 어떤 경우든 상태 초기화
      _dialogContext = null;
    }
  }
} 