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

  static void show(BuildContext context, {required String message}) {
    // 이미 다이얼로그가 표시되어 있으면 메시지만 업데이트
    if (_dialogContext != null && _dialogState != null) {
      _dialogState!.updateMessage(message);
      return;
    }

    // 기존 다이얼로그가 있으면 닫기
    if (_dialogContext != null) {
      try {
        Navigator.of(_dialogContext!).pop();
      } catch (e) {
        // 무시
      }
      _dialogContext = null;
      _dialogState = null;
    }

    // 새 다이얼로그 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        _dialogContext = dialogContext;
        return LoadingDialog(message: message);
      },
    );
  }

  /// 로딩 다이얼로그를 닫는 정적 메서드
  static void hide(BuildContext context) {
    if (_dialogContext != null) {
      Navigator.of(_dialogContext!).pop();
      _dialogContext = null;
      _dialogState = null;
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
