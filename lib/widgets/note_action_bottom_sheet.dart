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
            
            // 즐겨찾기 추가/제거
            _buildActionTile(
              context: context,
              title: isFavorite ? '즐겨찾기 해제' : '즐겨찾기 추가',
              trailing: Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
                color: isFavorite ? ColorTokens.primary : ColorTokens.greyMedium
              ),
              onTap: () {
                Navigator.pop(context);
                onToggleFavorite();
              },
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
            
            // 텍스트 모드 그룹 타이틀
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '텍스트 모드',
                  style: TypographyTokens.caption.copyWith(
                    color: ColorTokens.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            
            // 문장별 구분 모드
            _buildActionTile(
              context: context,
              title: '문장별 구분',
              trailing: Icon(
                Icons.check_circle,
                color: !isFullTextMode ? ColorTokens.primary : ColorTokens.greyMedium
              ),
              onTap: () {
                Navigator.pop(context);
                if (isFullTextMode) {
                  onToggleFullTextMode();
                }
              },
            ),
            
            // 원문 전체 모드
            _buildActionTile(
              context: context,
              title: '원문 전체',
              trailing: Icon(
                Icons.check_circle,
                color: isFullTextMode ? ColorTokens.primary : ColorTokens.greyMedium
              ),
              onTap: () {
                Navigator.pop(context);
                if (!isFullTextMode) {
                  onToggleFullTextMode();
                }
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
