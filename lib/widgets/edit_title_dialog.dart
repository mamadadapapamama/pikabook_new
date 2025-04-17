import 'package:flutter/material.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';

/// 노트 제목 편집 다이얼로그 위젯
class EditTitleDialog extends StatefulWidget {
  /// 현재 제목
  final String currentTitle;

  /// 제목 업데이트 콜백
  final Function(String) onTitleUpdated;

  /// 생성자
  const EditTitleDialog({
    super.key,
    required this.currentTitle,
    required this.onTitleUpdated,
  });

  /// 다이얼로그로 제목 변경 UI 표시
  static Future<void> show(
    BuildContext context, {
    required String currentTitle,
    required Function(String) onTitleUpdated,
  }) {
    final TextEditingController controller = TextEditingController(text: currentTitle);
    final bool isDefaultTitle = 
        currentTitle.startsWith('#') && currentTitle.contains('Note');
    
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('노트 제목 변경'),
        backgroundColor: Colors.white,
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
              controller: controller,
              decoration: InputDecoration(
                labelText: '제목',
                hintText: '노트 내용을 잘 나타내는 제목을 입력하세요',
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: ColorTokens.primary),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: ColorTokens.primary, width: 2.0),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => controller.clear(),
                ),
              ),
              autofocus: true,
              maxLength: 50, // 제목 길이 제한
              textInputAction: TextInputAction.done,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '취소',
              style: TextStyle(
                color: ColorTokens.textTertiary,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                onTitleUpdated(newTitle);
              }
              Navigator.pop(context);
            },
            child: Text(
              '저장',
              style: TextStyle(
                color: ColorTokens.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  State<EditTitleDialog> createState() => _EditTitleDialogState();
}

class _EditTitleDialogState extends State<EditTitleDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 다이얼로그로 대체되었으므로 더 이상 필요하지 않음
    return const SizedBox.shrink();
  }
}
