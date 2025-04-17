import 'package:flutter/material.dart';
import '../theme/tokens/color_tokens.dart';

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

  /// 모달 바텀 시트로 다이얼로그 표시
  static Future<void> show(
    BuildContext context, {
    required String currentTitle,
    required Function(String) onTitleUpdated,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: EditTitleDialog(
          currentTitle: currentTitle,
          onTitleUpdated: onTitleUpdated,
        ),
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
    final isDefaultTitle = 
        widget.currentTitle.startsWith('#') && widget.currentTitle.contains('Note');
        
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(16),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '노트 제목 변경',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              // 닫기 버튼
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
            controller: _controller,
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
                onPressed: () => _controller.clear(),
              ),
            ),
            autofocus: true,
            maxLength: 50, // 제목 길이 제한
            textInputAction: TextInputAction.done,
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                widget.onTitleUpdated(value.trim());
                Navigator.pop(context);
              }
            },
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  final newTitle = _controller.text.trim();
                  if (newTitle.isNotEmpty) {
                    widget.onTitleUpdated(newTitle);
                  }
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: ColorTokens.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('확인'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
