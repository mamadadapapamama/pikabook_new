import 'package:flutter/material.dart';

/// 로딩 다이얼로그를 표시하는 위젯
class LoadingDialog extends StatefulWidget {
  final String message;

  const LoadingDialog({
    Key? key,
    required this.message,
  }) : super(key: key);

  /// 로딩 다이얼로그를 표시하는 정적 메서드
  static BuildContext? _dialogContext;
  static _LoadingDialogState? _dialogState;
  static bool _isShowing = false;

  static void show(BuildContext context, {required String message}) {
    // 이미 다이얼로그가 표시되어 있으면 메시지만 업데이트
    if (_dialogContext != null && _dialogState != null && _isShowing) {
      _dialogState!.updateMessage(message);
      return;
    }

    // 기존 다이얼로그가 있으면 닫기
    if (_dialogContext != null) {
      try {
        Navigator.of(_dialogContext!, rootNavigator: true).pop();
      } catch (e) {
        debugPrint('기존 다이얼로그 닫기 실패: $e');
      }
      _dialogContext = null;
      _dialogState = null;
      _isShowing = false;
    }

    // 새 다이얼로그 표시
    _isShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogContext) {
        _dialogContext = dialogContext;
        return LoadingDialog(message: message);
      },
    ).then((_) {
      // 다이얼로그가 닫힐 때 상태 초기화
      _isShowing = false;
      _dialogContext = null;
      _dialogState = null;
    });
  }

  /// 로딩 다이얼로그를 닫는 정적 메서드
  static void hide(BuildContext context) {
    if (_dialogContext != null && _isShowing) {
      try {
        // rootNavigator: true를 사용하여 최상위 네비게이터에서 팝업을 닫음
        Navigator.of(_dialogContext!, rootNavigator: true).pop();
      } catch (e) {
        debugPrint('다이얼로그 닫기 실패: $e');

        // 첫 번째 시도가 실패하면 제공된 컨텍스트로 시도
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (e2) {
          debugPrint('대체 컨텍스트로 다이얼로그 닫기 실패: $e2');
        }
      }

      // 상태 초기화
      _dialogContext = null;
      _dialogState = null;
      _isShowing = false;
    }
  }

  @override
  State<LoadingDialog> createState() => _LoadingDialogState();
}

class _LoadingDialogState extends State<LoadingDialog> {
  late String _message;

  @override
  void initState() {
    super.initState();
    _message = widget.message;
    LoadingDialog._dialogState = this;
  }

  @override
  void dispose() {
    // 이 상태 객체가 현재 다이얼로그 상태인 경우에만 초기화
    if (LoadingDialog._dialogState == this) {
      LoadingDialog._dialogState = null;
    }
    super.dispose();
  }

  void updateMessage(String message) {
    if (mounted) {
      setState(() {
        _message = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // 뒤로 가기 방지
      child: AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  strokeWidth: 5,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).primaryColor,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
