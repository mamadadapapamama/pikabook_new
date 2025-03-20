import 'package:flutter/material.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';

class NoteActionBottomSheet extends StatelessWidget {
  final VoidCallback onEditTitle;
  final VoidCallback onDeleteNote;
  final VoidCallback onToggleFullTextMode;
  final VoidCallback onToggleFavorite;
  final bool isFullTextMode;
  final bool isFavorite;

  const NoteActionBottomSheet({
    Key? key,
    required this.onEditTitle,
    required this.onDeleteNote,
    required this.onToggleFullTextMode,
    required this.onToggleFavorite,
    required this.isFullTextMode,
    required this.isFavorite,
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
            child: Text(
              '노트 옵션',
              style: TypographyTokens.subtitle2.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          // 즐겨찾기 추가/제거
          ListTile(
            leading: Icon(
              isFavorite ? Icons.favorite : Icons.favorite_border, 
              color: isFavorite ? Colors.red : Colors.grey,
            ),
            title: Text(
              isFavorite ? '즐겨찾기 해제' : '즐겨찾기 추가',
              style: TypographyTokens.body1,
            ),
            onTap: () {
              Navigator.pop(context);
              onToggleFavorite();
            },
          ),
          
          // 노트 제목 변경
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.blue),
            title: Text('노트 제목 변경', style: TypographyTokens.body1),
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
                Text(
                  '텍스트 모드',
                  style: TypographyTokens.caption.copyWith(
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
            title: Text('문장별 구분', style: TypographyTokens.body1),
            trailing: !isFullTextMode ? const Icon(Icons.check, color: ColorTokens.success) : null,
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
            title: Text('원문 전체', style: TypographyTokens.body1),
            trailing: isFullTextMode ? const Icon(Icons.check, color: ColorTokens.success) : null,
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
            title: Text('노트 삭제', style: TypographyTokens.body1),
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
