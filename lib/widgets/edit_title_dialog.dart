import 'package:flutter/material.dart';

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
    final titleController = TextEditingController(text: currentTitle);
    final isDefaultTitle =
        currentTitle.startsWith('#') && currentTitle.contains('Note');

    return AlertDialog(
      title: const Text('노트 제목 변경'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isDefaultTitle)
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: Text(
                '자동 생성된 제목을 더 의미 있는 제목으로 변경해보세요.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ),
          TextField(
            controller: titleController,
            decoration: InputDecoration(
              labelText: '제목',
              hintText: '노트 내용을 잘 나타내는 제목을 입력하세요',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => titleController.clear(),
              ),
            ),
            autofocus: true,
            maxLength: 50, // 제목 길이 제한
            textInputAction: TextInputAction.done,
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                onTitleUpdated(value.trim());
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
            final newTitle = titleController.text.trim();
            if (newTitle.isNotEmpty) {
              onTitleUpdated(newTitle);
            }
            Navigator.of(context).pop();
          },
          child: const Text('저장'),
        ),
      ],
    );
  }
}
