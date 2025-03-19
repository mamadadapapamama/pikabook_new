import 'package:flutter/material.dart';
import 'package:badges/badges.dart' as badges;
import '../models/note.dart';
import 'package:flutter/services.dart';

class NoteDetailAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Note? note;
  final bool isFavorite;
  final VoidCallback onEditTitle;
  final VoidCallback onToggleFavorite;
  final VoidCallback onShowMoreOptions;
  final Function() onFlashCardPressed;

  const NoteDetailAppBar({
    Key? key,
    required this.note,
    required this.isFavorite,
    required this.onEditTitle,
    required this.onToggleFavorite,
    required this.onShowMoreOptions,
    required this.onFlashCardPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: note != null
          ? GestureDetector(
              onTap: onEditTitle,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      note!.originalText,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit, size: 16),
                ],
              ),
            )
          : const Text('노트 상세'),
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
            icon: Icon(
              isFavorite ? Icons.favorite : Icons.favorite_border,
              color: isFavorite ? Colors.red : null,
            ),
            onPressed: onToggleFavorite,
            tooltip: '즐겨찾기',
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
