import 'package:flutter/material.dart';
import 'package:badges/badges.dart' as badges;
import '../models/note.dart';
import 'package:flutter/services.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';

class NoteDetailAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Note? note;
  final VoidCallback onShowMoreOptions;
  final Function() onFlashCardPressed;

  const NoteDetailAppBar({
    Key? key,
    required this.note,
    required this.onShowMoreOptions,
    required this.onFlashCardPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: note != null
          ? Text(
              note!.originalText,
              overflow: TextOverflow.ellipsis,
              style: TypographyTokens.headline3.copyWith(
                color: ColorTokens.textPrimary,
              ),
            )
          : const Text('노트 상세'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      actions: [
        if (note != null) ...[
          IconButton(
            icon: note!.flashcardCount > 0
                ? badges.Badge(
                    badgeContent: Text(
                      '${note!.flashcardCount}',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                    child: const Icon(Icons.flash_on),
                  )
                : const Icon(Icons.flash_on),
            onPressed: onFlashCardPressed,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: onShowMoreOptions,
            tooltip: '더 보기',
          ),
        ],
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
