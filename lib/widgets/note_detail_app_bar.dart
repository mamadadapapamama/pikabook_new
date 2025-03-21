import 'package:flutter/material.dart';
import 'package:badges/badges.dart' as badges;
import 'package:google_fonts/google_fonts.dart';
import '../models/note.dart';
import 'package:flutter/services.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';

class NoteDetailAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Note? note;
  final VoidCallback onShowMoreOptions;
  final Function() onFlashCardPressed;
  final int currentPageIndex;
  final int totalPages;

  const NoteDetailAppBar({
    Key? key,
    required this.note,
    required this.onShowMoreOptions,
    required this.onFlashCardPressed,
    this.currentPageIndex = 0,
    this.totalPages = 0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final String pageNumberText = '${currentPageIndex + 1}/$totalPages';
    
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded),
        color: ColorTokens.secondary,
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  note?.originalText ?? '노트 상세',
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 24, 
                    fontWeight: FontWeight.w700,
                    color: ColorTokens.textPrimary,
                  ),
                ),
                if (totalPages > 0)
                  Text(
                    'page $pageNumberText',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFFB2B2B2),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      titleSpacing: 0,
      toolbarHeight: 70,
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
            color: ColorTokens.primary,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: onShowMoreOptions,
            tooltip: '더 보기',
            color: const Color(0xFFB2B2B2),
          ),
        ],
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(4.0),
        child: _buildProgressBar(context),
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final progressWidth = totalPages > 0 
        ? (currentPageIndex + 1) / totalPages * screenWidth 
        : 0.0;
    
    return Container(
      height: 4,
      width: double.infinity,
      color: const Color(0xFFFFF0E8),
      child: Row(
        children: [
          Container(
            width: progressWidth,
            color: ColorTokens.primary,
          ),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(74);  // 70(toolbar) + 4(progress bar)
}
