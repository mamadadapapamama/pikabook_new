import 'package:flutter/material.dart';
import 'dart:io';
import 'package:google_fonts/google_fonts.dart';
import '../models/note.dart';
import '../utils/date_formatter.dart';
import '../services/image_service.dart';
import '../services/note_service.dart';
import '../services/page_service.dart';
import '../views/screens/flashcard_screen.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import '../theme/tokens/ui_tokens.dart';
import '../utils/segment_utils.dart';
import 'flashcard_counter_badge.dart';
import 'page_count_badge.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// 홈페이지 노트리스트 화면에서 사용되는 카드 위젯

class NoteListItem extends StatefulWidget {
  final Note note;
  final VoidCallback onTap;
  final Function(bool) onFavoriteToggle;
  final VoidCallback onDelete;

  const NoteListItem({
    Key? key,
    required this.note,
    required this.onTap,
    required this.onFavoriteToggle,
    required this.onDelete,
  }) : super(key: key);

  @override
  State<NoteListItem> createState() => _NoteListItemState();
}

class _NoteListItemState extends State<NoteListItem> {
  final ImageService _imageService = ImageService();
  final NoteService _noteService = NoteService();
  File? _imageFile;
  bool _isLoadingImage = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(NoteListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 이미지 URL이 변경되면 새로 로드
    if (oldWidget.note.imageUrl != widget.note.imageUrl) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    if (widget.note.imageUrl == null || widget.note.imageUrl!.isEmpty) return;

    setState(() {
      _isLoadingImage = true;
    });

    try {
      final imageFile = await _imageService.getImageFile(widget.note.imageUrl);
      if (mounted) {
        setState(() {
          _imageFile = imageFile;
          _isLoadingImage = false;
        });
      }
    } catch (e) {
      debugPrint('이미지 로드 중 오류 발생: $e');
      if (mounted) {
        setState(() {
          _isLoadingImage = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dismissibleKey = Key(widget.note.id ?? 'note-${DateTime.now().millisecondsSinceEpoch}');
    
    return SegmentUtils.buildDismissibleSegment(
      key: dismissibleKey,
      onDelete: widget.onDelete,
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        // 노트 삭제 확인 대화상자
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('노트 삭제', style: TypographyTokens.headline3),
            content: Text('이 노트를 삭제하시겠습니까?', style: TypographyTokens.body1),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('취소', style: TypographyTokens.button),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  '삭제',
                  style: TypographyTokens.button.copyWith(color: ColorTokens.error),
                ),
              ),
            ],
          ),
        ) ?? false;
      },
      child: ClipRRect(
        // 모서리 둥글게 처리 (Card와 동일한 둥근 모서리 적용)
        borderRadius: BorderRadius.circular(SpacingTokens.radiusXs),
        child: Card(
          margin: EdgeInsets.symmetric(
            vertical: SpacingTokens.sm,
            horizontal: 0,
          ),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SpacingTokens.radiusXs),
            side: BorderSide(
              color: ColorTokens.primarylight,
              width: 1,
            ),
          ),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(SpacingTokens.radiusXs),
            child: Padding(
              padding: EdgeInsets.all(SpacingTokens.md+2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 이미지 썸네일
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(SpacingTokens.xs),
                        child: SizedBox(
                          width: 80,
                          height: 80,
                          child: _imageFile != null
                              ? Image.file(
                                  _imageFile!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: Colors.grey[100],
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Image.asset(
                                            'assets/images/thumbnail_empty.png',
                                            width: 40,
                                            height: 40,
                                            fit: BoxFit.contain,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '이미지 없음',
                                            style: GoogleFonts.notoSansKr(
                                              fontSize: 10,
                                              color: ColorTokens.textGrey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                )
                              : _isLoadingImage
                                  ? Center(
                                      child: SizedBox(
                                        width: SpacingTokens.lg,
                                        height: SpacingTokens.lg,
                                        child: const CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(ColorTokens.primary)),
                                      ),
                                    )
                                  : Container(
                                      color: Colors.grey[100],
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Image.asset(
                                            'assets/images/thumbnail_empty.png',
                                            width: 40,
                                            height: 40,
                                            fit: BoxFit.contain,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '이미지 없음',
                                            style: GoogleFonts.notoSansKr(
                                              fontSize: 10,
                                              color: ColorTokens.textGrey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(width: SpacingTokens.md),
                  
                  // 노트 내용
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 노트 제목 및 날짜
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.note.originalText.length > 50
                                  ? widget.note.originalText.substring(0, 50) + "..."
                                  : widget.note.originalText,
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: ColorTokens.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: SpacingTokens.xs / 2),
                            Row(
                              children: [
                                Text(
                                  DateFormatter.formatDate(widget.note.updatedAt),
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.normal,
                                    color: ColorTokens.textGrey,
                                  ),
                                ),
                                SizedBox(width: SpacingTokens.xs),
                                Text(
                                  '|',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.normal,
                                    color: ColorTokens.textGrey,
                                  ),
                                ),
                                SizedBox(width: SpacingTokens.xs),
                                // 페이지 카운트 배지 위젯 사용
                                PageCountBadge(
                                  noteId: widget.note.id,
                                  initialCount: widget.note.imageCount ?? 
                                               (widget.note.pages.length > 0 ? 
                                               widget.note.pages.length : 1),
                                ),
                              ],
                            ),
                          ],
                        ),
                        SizedBox(height: SpacingTokens.sm),
                        
                        // 플래시카드 표시
                        if (widget.note.flashcardCount > 0 || widget.note.flashCards.isNotEmpty)
                          FlashcardCounterBadge(
                            count: widget.note.flashcardCount > 0 
                                ? widget.note.flashcardCount 
                                : widget.note.flashCards.length,
                            noteId: widget.note.id,
                          ),
                      ],
                    ),
                  ),
                  
                  // 즐겨찾기 아이콘
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => widget.onFavoriteToggle(!widget.note.isFavorite),
                      splashColor: ColorTokens.primary.withOpacity(0.1),
                      highlightColor: ColorTokens.primary.withOpacity(0.05),
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: EdgeInsets.all(SpacingTokens.xs),
                        child: widget.note.isFavorite
                            ? Image.asset(
                                'assets/images/icon_like_fill.png',
                                width: SpacingTokens.iconSizeMedium,
                                height: SpacingTokens.iconSizeMedium,
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(
                                    Icons.favorite,
                                    color: ColorTokens.primary,
                                    size: SpacingTokens.iconSizeMedium,
                                  );
                                },
                              )
                            : Image.asset(
                                'assets/images/icon_like.png',
                                width: SpacingTokens.iconSizeMedium,
                                height: SpacingTokens.iconSizeMedium,
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(
                                    Icons.favorite_border,
                                    color: const Color(0xFFB2B2B2),
                                    size: SpacingTokens.iconSizeMedium,
                                  );
                                },
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
