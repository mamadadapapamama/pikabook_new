import 'package:flutter/material.dart';

class NoteActionBottomSheet extends StatelessWidget {
  final VoidCallback onEditTitle;
  final VoidCallback onDeleteNote;
  final VoidCallback onToggleFullTextMode;
  final bool isFullTextMode;

  const NoteActionBottomSheet({
    Key? key,
    required this.onEditTitle,
    required this.onDeleteNote,
    required this.onToggleFullTextMode,
    required this.isFullTextMode,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 상단 타이틀
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: const Text(
              '노트 옵션',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          // 노트 제목 변경
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.blue),
            title: const Text('노트 제목 변경'),
            onTap: () {
              Navigator.pop(context);
              onEditTitle();
            },
          ),
          
          // 구분선
          const Divider(height: 1),
          
          // 텍스트 모드 그룹 타이틀
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.format_align_left, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                const Text(
                  '텍스트 모드',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          
          // 문장별 구분 모드
          ListTile(
            leading: const SizedBox(width: 24),
            title: const Text('문장별 구분'),
            trailing: !isFullTextMode ? const Icon(Icons.check, color: Colors.green) : null,
            onTap: () {
              Navigator.pop(context);
              if (isFullTextMode) {
                onToggleFullTextMode();
              }
            },
          ),
          
          // 원문 전체 모드
          ListTile(
            leading: const SizedBox(width: 24),
            title: const Text('원문 전체'),
            trailing: isFullTextMode ? const Icon(Icons.check, color: Colors.green) : null,
            onTap: () {
              Navigator.pop(context);
              if (!isFullTextMode) {
                onToggleFullTextMode();
              }
            },
          ),
          
          // 구분선
          const Divider(height: 1),
          
          // 노트 삭제
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('노트 삭제'),
            onTap: () {
              Navigator.pop(context);
              onDeleteNote();
            },
          ),
        ],
      ),
    );
  }
}
