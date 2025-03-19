import 'package:flutter/material.dart';
import 'dart:io';
import '../models/note.dart';
import '../utils/date_formatter.dart';
import '../services/image_service.dart';
import '../services/note_service.dart';
import '../views/screens/flashcard_screen.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import '../theme/tokens/ui_tokens.dart';
import 'flashcard_counter_badge.dart';

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
    return Dismissible(
      key: Key(widget.note.id ?? 'note-${DateTime.now().millisecondsSinceEpoch}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: SpacingTokens.md),
        color: ColorTokens.error,
        child: const Icon(
          Icons.delete,
          color: Colors.white,
        ),
      ),
      confirmDismiss: (direction) async {
        return await _confirmDelete(context);
      },
      onDismissed: (direction) {
        widget.onDelete();
      },
      child: Card(
        margin: EdgeInsets.symmetric(
          vertical: SpacingTokens.sm,
          horizontal: 0,
        ),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SpacingTokens.radiusXs),
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
                                    color: Colors.grey[200],
                                    child: const Icon(Icons.image_not_supported,
                                        color: Colors.grey),
                                  );
                                },
                              )
                            : _isLoadingImage
                                ? Center(
                                    child: SizedBox(
                                      width: SpacingTokens.lg,
                                      height: SpacingTokens.lg,
                                      child: const CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  )
                                : Image.asset(
                                    'assets/images/note_thumbnail.png',
                                    fit: BoxFit.cover,
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
                            style: TypographyTokens.poppins.copyWith(
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
                                style: TypographyTokens.poppins.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.normal,
                                  color: const Color(0xFF969696),
                                ),
                              ),
                              SizedBox(width: SpacingTokens.xs),
                              Text(
                                '|',
                                style: TypographyTokens.poppins.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.normal,
                                  color: const Color(0xFF969696),
                                ),
                              ),
                              SizedBox(width: SpacingTokens.xs),
                              Text(
                                '${widget.note.pages.length} pages',
                                style: TypographyTokens.poppins.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.normal,
                                  color: const Color(0xFF969696),
                                ),
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
                InkWell(
                  onTap: () => widget.onFavoriteToggle(!widget.note.isFavorite),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog(
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
            child: Text('삭제', style: TypographyTokens.button.copyWith(color: ColorTokens.error)),
          ),
        ],
      ),
    );
  }
}
