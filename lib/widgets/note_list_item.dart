import 'package:flutter/material.dart';
import 'dart:io';
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
import 'flashcard_counter_badge.dart';
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
  final PageService _pageService = PageService();
  File? _imageFile;
  bool _isLoadingImage = false;
  int _pageCount = 0;
  bool _isLoadingPageCount = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
    
    // 페이지 카운트 초기화: 생성 시 이미지 개수가 있다면 이를 기본값으로 설정
    _pageCount = widget.note.imageCount ?? widget.note.pages.length;
    _loadPageCount();
  }

  @override
  void didUpdateWidget(NoteListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.imageUrl != widget.note.imageUrl) {
      _loadImage();
    }
    if (oldWidget.note.id != widget.note.id) {
      _loadPageCount();
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

  Future<void> _loadPageCount() async {
    if (widget.note.id == null) return;
    
    setState(() {
      _isLoadingPageCount = true;
    });
    
    try {
      // 노트의 최신 정보 가져오기
      final noteDoc = await FirebaseFirestore.instance.collection('notes').doc(widget.note.id).get();
      if (noteDoc.exists) {
        final data = noteDoc.data();
        if (data != null) {
          int count = 0;
          
          // 1. totalPageCount 필드 확인 (가장 정확한 정보)
          if (data.containsKey('totalPageCount') && data['totalPageCount'] is int) {
            count = data['totalPageCount'] as int;
          }
          // 2. pages 배열 확인 (다음으로 정확한 정보)
          else if (data['pages'] is List) {
            count = (data['pages'] as List).length;
          }
          // 3. 이미지 수로 추정 (노트 생성 시점에는 이미지 수 = 페이지 수)
          else if (data.containsKey('imageCount') && data['imageCount'] is int) {
            count = data['imageCount'] as int;
          }
          
          if (mounted) {
            setState(() {
              _pageCount = count;
              _isLoadingPageCount = false;
            });
          }
          return;
        }
      }
      
      // 페이지 컬렉션에서 직접 조회 (가장 느린 방법이지만 정확함)
      final pages = await _pageService.getPagesForNote(widget.note.id!);
      if (mounted) {
        setState(() {
          _pageCount = pages.length;
          _isLoadingPageCount = false;
        });
      }
    } catch (e) {
      debugPrint('페이지 수 로드 중 오류 발생: $e');
      // 이미 위젯이 있는 pages 리스트를 사용
      if (mounted) {
        setState(() {
          _pageCount = widget.note.imageCount ?? widget.note.pages.length;
          _isLoadingPageCount = false;
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
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: SpacingTokens.xs,
                                  vertical: SpacingTokens.xs / 4,
                                ),
                                decoration: BoxDecoration(
                                  color: ColorTokens.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(SpacingTokens.xs),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.auto_stories,
                                      size: 10,
                                      color: ColorTokens.primary,
                                    ),
                                    SizedBox(width: 2),
                                    Text(
                                      _isLoadingPageCount 
                                        ? '로딩 중...' 
                                        : '$_pageCount 페이지',
                                      style: TypographyTokens.poppins.copyWith(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: ColorTokens.primary,
                                      ),
                                    ),
                                  ],
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
