import 'package:flutter/material.dart';

/// 일반화된 텍스트 편집 다이얼로그
/// 노트 제목, 노트스페이스 이름 등 다양한 텍스트 편집에 사용 가능
class EditTextDialog extends StatelessWidget {
  final String title;
  final String currentValue;
  final String labelText;
  final String hintText;
  final String? helperText;
  final int maxLength;
  final Function(String) onValueUpdated;

  const EditTextDialog({
    Key? key,
    required this.title,
    required this.currentValue,
    required this.labelText,
    required this.hintText,
    this.helperText,
    this.maxLength = 50,
    required this.onValueUpdated,
  }) : super(key: key);

  /// 노트 제목 편집용 팩토리 생성자
  factory EditTextDialog.forNoteTitle({
    required String currentTitle,
    required Function(String) onTitleUpdated,
  }) {
    final isDefaultTitle = currentTitle.startsWith('#') && currentTitle.contains('Note');
    
    return EditTextDialog(
      title: '노트 제목 변경',
      currentValue: currentTitle,
      labelText: '제목',
      hintText: '노트 내용을 잘 나타내는 제목을 입력하세요',
      helperText: isDefaultTitle ? '자동 생성된 제목을 더 의미 있는 제목으로 변경해보세요.' : null,
      maxLength: 50,
      onValueUpdated: onTitleUpdated,
    );
  }

  /// 노트스페이스 이름 편집용 팩토리 생성자
  factory EditTextDialog.forNoteSpace({
    required String currentName,
    required Function(String) onNameUpdated,
  }) {
    return EditTextDialog(
      title: '노트스페이스 이름 변경',
      currentValue: currentName,
      labelText: '이름',
      hintText: '새로운 노트스페이스 이름을 입력하세요',
      helperText: '노트스페이스는 노트를 분류하는 폴더입니다.',
      maxLength: 30,
      onValueUpdated: onNameUpdated,
    );
  }

  @override
  Widget build(BuildContext context) {
    final textController = TextEditingController(text: currentValue);

    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (helperText != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                helperText!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ),
          TextField(
            controller: textController,
            decoration: InputDecoration(
              labelText: labelText,
              hintText: hintText,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => textController.clear(),
              ),
            ),
            autofocus: true,
            maxLength: maxLength,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                onValueUpdated(value.trim());
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () {
            final newValue = textController.text.trim();
            if (newValue.isNotEmpty) {
              onValueUpdated(newValue);
            }
            Navigator.of(context).pop();
          },
          child: const Text('저장'),
        ),
      ],
    );
  }
}

/// 기존 코드 호환성을 위한 deprecated 클래스
@deprecated
class EditTitleDialog extends StatelessWidget {
  final String currentTitle;
  final Function(String) onTitleUpdated;

  const EditTitleDialog({
    Key? key,
    required this.currentTitle,
    required this.onTitleUpdated,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return EditTextDialog.forNoteTitle(
      currentTitle: currentTitle,
      onTitleUpdated: onTitleUpdated,
    );
  }
}
