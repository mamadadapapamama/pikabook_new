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
  static BuildContext? _dialogContext;

  /// 로딩 다이얼로그를 표시하는 정적 메서드
  static void show(BuildContext context, {String message = '로딩 중...'}) {
    if (!context.mounted) {
      debugPrint('로딩 다이얼로그 표시 실패: context가 더 이상 유효하지 않습니다.');
      return;
    }

    // 이미 표시 중이면 기존 다이얼로그 닫기 시도 
    if (_isShowing) {
      debugPrint('로딩 다이얼로그가 이미 표시 중입니다. 기존 다이얼로그 닫기 시도');
      hide(context);
    }

    try {
      // 상태 업데이트
      _isShowing = true;
      _dialogContext = null;

      // 전달된 context 저장 (PikabookLoader에서 새 context 생성하기 때문)
      _dialogContext = context;

      // PikabookLoader를 사용하여 표시
      PikabookLoader.show(
        context,
        title: '스마트한 번역 노트를 만들고 있어요.',
        subtitle: '잠시만 기다려 주세요!',
      ).then((_) {
        // 다이얼로그가 닫힐 때 상태 초기화
        _isShowing = false;
        _dialogContext = null;
        debugPrint('로딩 다이얼로그 닫힘 (자동)');
      }).catchError((e) {
        // 오류 발생 시 상태 초기화
        _isShowing = false;
        _dialogContext = null;
        debugPrint('로딩 다이얼로그 표시 중 오류: $e');
      });
    } catch (e) {
      // 오류 발생 시 상태 초기화
      _isShowing = false;
      _dialogContext = null;
      debugPrint('로딩 다이얼로그 표시 중 오류 발생: $e');
    }
  }

  /// 로딩 다이얼로그를 닫는 정적 메서드
  static void hide(BuildContext context) {
    // 다이얼로그가 표시되어 있지 않으면 아무 작업도 하지 않음
    if (!_isShowing) {
      debugPrint('로딩 다이얼로그가 표시되어 있지 않아 닫기 작업 무시');
      return;
    }

    try {
      // 먼저 상태 업데이트
      _isShowing = false;
      
      // 저장된 다이얼로그 컨텍스트가 있으면 사용, 없으면 전달된 컨텍스트 사용
      BuildContext effectiveContext = _dialogContext ?? context;
      
      // 컨텍스트 유효성 검사
      if (!effectiveContext.mounted) {
        debugPrint('로딩 다이얼로그 닫기 실패: context가 더 이상 유효하지 않습니다.');
        // 상태 초기화 후 종료
        _dialogContext = null;
        return;
      }
      
      // 즉시 닫기 시도
      try {
        final navigator = Navigator.of(effectiveContext, rootNavigator: true);
        if (navigator.canPop()) {
          navigator.pop();
          debugPrint('로딩 다이얼로그 닫기 성공');
        }
      } catch (e) {
        debugPrint('로딩 다이얼로그 닫기 실패: $e');
      }
      
      // 추가 안전장치: addPostFrameCallback으로 한 번 더 시도
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          // 컨텍스트가 여전히 유효한지 확인
          if (effectiveContext.mounted) {
            final navigator = Navigator.of(effectiveContext, rootNavigator: true);
            if (navigator.canPop()) {
              navigator.pop();
              debugPrint('로딩 다이얼로그 닫기 성공 (addPostFrameCallback)');
            }
          }
        } catch (e) {
          debugPrint('로딩 다이얼로그 닫기 실패 (addPostFrameCallback): $e');
        } finally {
          // 상태 초기화
          _dialogContext = null;
        }
      });
    } catch (e) {
      debugPrint('로딩 다이얼로그 닫기 실패: $e');
    } finally {
      // 확실하게 상태 초기화 (성공 여부와 관계없이)
      _isShowing = false;
      _dialogContext = null;
    }
  }

  /// 로딩 다이얼로그의 메시지를 업데이트하는 정적 메서드
  static void updateMessage(BuildContext context, String message) {
    // 메시지 업데이트를 위해 다이얼로그를 닫고 다시 표시
    if (_isShowing) {
      hide(context);
      // 약간의 지연을 주어 다이얼로그가 확실히 닫히도록 함
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          show(context, message: message);
        }
      });
    } else {
      // 표시되지 않은 경우 바로 표시
      show(context, message: message);
    }
  }
}
