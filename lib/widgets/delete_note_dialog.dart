import 'package:flutter/material.dart';

/// 노트 삭제 확인 다이얼로그
class DeleteNoteDialog extends StatelessWidget {
  final Function onConfirm;

  const DeleteNoteDialog({
    Key? key,
    required this.onConfirm,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('노트 삭제'),
      content: const Text('이 노트를 정말 삭제하시겠습니까? 이 작업은 취소할 수 없습니다.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            onConfirm();
          },
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('삭제'),
        ),
      ],
    );
  }
}