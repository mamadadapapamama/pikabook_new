import 'package:flutter/material.dart';

import '../../../../models/note.dart';
import '../../../../theme/tokens/color_tokens.dart';
import '../../../../theme/tokens/typography_tokens.dart';
import '../../../../theme/tokens/spacing_tokens.dart';
import '../../../widgets/edit_title_dialog.dart';

/// 노트 상세 화면의 앱바 위젯
/// 
/// 노트 제목, 뒤로가기 버튼, 편집 버튼 등을 표시합니다.

class NoteDetailAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Note? note;
  final VoidCallback onBack;
  final Function(String) onUpdateTitle;
  
  const NoteDetailAppBar({
    super.key,
    required this.note,
    required this.onBack,
    required this.onUpdateTitle,
  });
  
  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
  
  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: ColorTokens.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: onBack,
        color: ColorTokens.textPrimary,
      ),
      title: _buildTitle(context),
      actions: [
        IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () => _showEditTitleDialog(context),
          color: ColorTokens.textPrimary,
        ),
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () => _showMoreOptions(context),
          color: ColorTokens.textPrimary,
        ),
      ],
    );
  }
  
  // 제목 위젯 빌드
  Widget _buildTitle(BuildContext context) {
    return Text(
      note?.title ?? '노트',
      style: TypographyTokens.subtitle1.copyWith(
        color: ColorTokens.textPrimary,
        fontWeight: FontWeight.w500,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
  
  // 제목 편집 다이얼로그 표시
  void _showEditTitleDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => EditTitleDialog(
        initialTitle: note?.title ?? '노트',
        onSave: onUpdateTitle,
      ),
    );
  }
  
  // 추가 옵션 메뉴 표시
  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ColorTokens.surface,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(
          vertical: SpacingTokens.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: const Text('즐겨찾기에 추가'),
              onTap: () {
                Navigator.pop(context);
                // 즐겨찾기 추가 로직
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('공유'),
              onTap: () {
                Navigator.pop(context);
                // 공유 로직
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: ColorTokens.error),
              title: Text(
                '삭제',
                style: TextStyle(color: ColorTokens.error),
              ),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirmation(context);
              },
            ),
          ],
        ),
      ),
    );
  }
  
  // 삭제 확인 다이얼로그 표시
  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('노트 삭제'),
        content: const Text(
          '정말로 이 노트를 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context); // 노트 상세 화면 닫기
              // 삭제 로직은 노트 상세 화면에서 처리
            },
            child: Text(
              '삭제',
              style: TextStyle(color: ColorTokens.error),
            ),
          ),
        ],
      ),
    );
  }
} 