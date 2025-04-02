import 'package:flutter/material.dart';
import 'pikabook_loader.dart';

/// 로딩 다이얼로그를 표시하는 위젯
///
/// 장시간의 작업이 진행될 때 전체 화면을 덮는 로딩 다이얼로그를 표시합니다.
/// 사용자의 다른 액션을 차단하고 작업 진행 상황을 알리는 메시지를 표시할 수 있습니다.
/// 
/// 주로 데이터 저장, 네트워크 요청 등 사용자가 대기해야 하는 작업에 사용합니다.
/// 화면의 일부분만 로딩 표시가 필요한 경우 LoadingIndicator를 사용하세요.
/// 
/// 내부적으로 PikabookLoader를 사용하여 Figma 디자인에 맞게 구현되었습니다.
class LoadingDialog {
  static bool _isShowing = false;

  /// 로딩 다이얼로그를 표시하는 정적 메서드
  static void show(BuildContext context, {String message = '로딩 중...'}) {
    if (!context.mounted) {
      debugPrint('로딩 다이얼로그 표시 실패: context가 더 이상 유효하지 않습니다.');
      return;
    }

    // 이미 표시 중이면 다시 표시하지 않음
    if (_isShowing) {
      debugPrint('로딩 다이얼로그가 이미 표시 중입니다.');
      // 이전 다이얼로그를 닫고 새 메시지로 다시 표시
      try {
        hide(context);
      } catch (e) {
        debugPrint('이전 로딩 다이얼로그 닫기 실패: $e');
      }
    }

    try {
      // 상태 업데이트
      _isShowing = true;

      // PikabookLoader를 사용하여 표시
      PikabookLoader.show(
        context,
        title: '스마트한 번역 노트를 만들고 있어요.',
        subtitle: message,
      ).then((_) {
        // 다이얼로그가 닫힐 때 상태 초기화
        _isShowing = false;
        debugPrint('로딩 다이얼로그 닫힘 (자동)');
      }).catchError((e) {
        // 오류 발생 시 상태 초기화
        _isShowing = false;
        debugPrint('로딩 다이얼로그 표시 중 오류: $e');
      });
    } catch (e) {
      // 오류 발생 시 상태 초기화
      _isShowing = false;
      debugPrint('로딩 다이얼로그 표시 중 오류 발생: $e');
    }
  }

  /// 로딩 다이얼로그를 닫는 정적 메서드
  static void hide(BuildContext context) {
    // 컨텍스트 유효성 검사
    if (!context.mounted) {
      debugPrint('로딩 다이얼로그 닫기 실패: context가 더 이상 유효하지 않습니다.');
      _isShowing = false; // 어쨌든 상태 초기화
      return;
    }

    // 다이얼로그가 표시되어 있지 않으면 아무 작업도 하지 않음
    if (!_isShowing) {
      debugPrint('로딩 다이얼로그가 표시되어 있지 않아 닫기 작업 무시');
      return;
    }

    try {
      // 먼저 상태 업데이트
      _isShowing = false;
      
      // PikabookLoader를 사용하여 닫기
      Navigator.of(context, rootNavigator: true).popUntil((route) {
        // 최상위 다이얼로그만 닫도록 처리
        final isDialog = route.settings.name == null && route is RawDialogRoute;
        if (isDialog) {
          // Dialog 발견, 닫기
          debugPrint('로딩 다이얼로그 발견 및 닫기 시도');
          return false; // 이 라우트는 닫고 계속 진행
        }
        return true; // 더 이상 라우트를 닫지 않음
      });
      
      debugPrint('로딩 다이얼로그 닫기 성공');
    } catch (e) {
      debugPrint('로딩 다이얼로그 닫기 실패: $e');
    } finally {
      // 확실하게 상태 초기화 (성공 여부와 관계없이)
      _isShowing = false;
    }
  }

  /// 로딩 다이얼로그의 메시지를 업데이트하는 정적 메서드
  static void updateMessage(BuildContext context, String message) {
    // 메시지 업데이트를 위해 다이얼로그를 닫고 다시 표시
    if (_isShowing) {
      hide(context);
      // 약간의 지연을 주어 다이얼로그가 확실히 닫히도록 함
      Future.delayed(const Duration(milliseconds: 100), () {
        show(context, message: message);
      });
    } else {
      // 표시되지 않은 경우 바로 표시
      show(context, message: message);
    }
  }
}
