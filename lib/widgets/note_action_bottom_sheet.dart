import 'package:flutter/material.dart';
import '../core/theme/tokens/color_tokens.dart';
import '../core/theme/tokens/typography_tokens.dart';

// 노트제목 변경, 노트삭제 기능
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
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 드래그 핸들
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: ColorTokens.disabled,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            // 바텀시트 타이틀 추가
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: 
                Text(
                '노트 설정',
                style: TypographyTokens.button.copyWith(
                  color: ColorTokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            
            // 노트 제목 변경
            _buildActionTile(
              context: context,
              title: '노트 제목 변경',
              trailing: Icon(
                Icons.edit,
                color: ColorTokens.primary
              ),
              onTap: () {
                Navigator.pop(context);
                onEditTitle();
              },
            ),
            
            // 구분선
            Divider(color: ColorTokens.divider, height: 1),
            
            // 노트 삭제
            _buildActionTile(
              context: context,
              title: '노트 삭제',
              trailing: Icon(
                Icons.delete_outline,
                color: ColorTokens.error
              ),
              onTap: () {
                Navigator.pop(context);
                onDeleteNote();
              },
            ),
            
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
  
  Widget _buildActionTile({
    required BuildContext context,
    required String title,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return ListTile(
      title: Text(
        title, 
        style: TypographyTokens.body2.copyWith(
          color: ColorTokens.textPrimary,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: trailing,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      dense: true,
    );
  }
}
