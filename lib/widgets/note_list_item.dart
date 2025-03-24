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
  bool _initialLoadCompleted = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
    
    // 페이지 카운트 초기화 로직 개선
    // 노트 생성 직후에는 imageCount가 정확한 값을 가짐 (이미지 개수 = 페이지 개수)
    if (widget.note.imageCount != null && widget.note.imageCount! > 0) {
      _pageCount = widget.note.imageCount!;
      // 이미 올바른 값을 가지고 있다면 불필요한 로딩 과정 생략 (깜빡임 방지)
      _isLoadingPageCount = false;
    } else if (widget.note.pages.isNotEmpty) {
      _pageCount = widget.note.pages.length;
      _isLoadingPageCount = false;
    } else {
      _pageCount = 1; // 기본값 설정
    }
    
    // 백그라운드에서 추가 정보 로드 (UI 깜빡임 방지)
    _loadPageCountInBackground();
  }

  /// 백그라운드에서 페이지 수 정보를 가져옵니다.
  /// UI의 깜빡임 없이 업데이트하기 위해 로딩 상태를 표시하지 않습니다.
  Future<void> _loadPageCountInBackground() async {
    if (widget.note.id == null) return;
    
    try {
      // 노트의 최신 정보 가져오기
      final noteDoc = await FirebaseFirestore.instance.collection('notes').doc(widget.note.id).get();
      if (noteDoc.exists && mounted) {
        final data = noteDoc.data();
        if (data != null) {
          int? serverCount;
          
          // 우선순위 1: totalPageCount 필드
          if (data.containsKey('totalPageCount') && data['totalPageCount'] is int) {
            final count = data['totalPageCount'] as int;
            if (count > 0) serverCount = count;
          }
          
          // 우선순위 2: pages 배열
          if (serverCount == null && data['pages'] is List) {
            final count = (data['pages'] as List).length;
            if (count > 0) serverCount = count;
          }
          
          // 우선순위 3: imageCount
          if (serverCount == null && data.containsKey('imageCount') && data['imageCount'] is int) {
            final count = data['imageCount'] as int;
            if (count > 0) serverCount = count;
          }
          
          // 서버 값이 현재 값보다 클 때만 업데이트 (내림 방지)
          if (serverCount != null && serverCount > _pageCount && mounted) {
            setState(() {
              _pageCount = serverCount!;
              _isLoadingPageCount = false;
              _initialLoadCompleted = true;
            });
          } else if (mounted) {
            setState(() {
              _isLoadingPageCount = false;
              _initialLoadCompleted = true;
            });
          }
          return;
        }
      }
      
      if (mounted) {
        setState(() {
          _isLoadingPageCount = false;
          _initialLoadCompleted = true;
        });
      }
    } catch (e) {
      // 에러 발생 시 로딩 상태만 업데이트하고 카운트는 유지
      debugPrint('백그라운드 페이지 수 로드 중 오류 발생: $e');
      if (mounted) {
        setState(() {
          _isLoadingPageCount = false;
          _initialLoadCompleted = true;
        });
      }
    }
  }

  @override
  void didUpdateWidget(NoteListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 이미지 URL이 변경되면 새로 로드
    if (oldWidget.note.imageUrl != widget.note.imageUrl) {
      _loadImage();
    }
    
    // 노트 ID가 변경되거나 이미지 카운트가 증가한 경우에만 페이지 카운트 업데이트
    // 이미지 카운트가 감소한 경우는 무시 (내림 방지)
    bool shouldUpdateCount = oldWidget.note.id != widget.note.id;
    
    if (widget.note.imageCount != null && oldWidget.note.imageCount != null &&
        widget.note.imageCount! > oldWidget.note.imageCount!) {
      shouldUpdateCount = true;
    }
    
    if (shouldUpdateCount) {
      if (widget.note.imageCount != null && widget.note.imageCount! > 0) {
        // 즉시 UI 업데이트
        setState(() {
          _pageCount = widget.note.imageCount!;
          _isLoadingPageCount = false;
        });
      }
      
      // 백그라운드에서 추가 정보 로드
      _loadPageCountInBackground();
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
                                  color: const Color(0xFF969696),
                                ),
                              ),
                              SizedBox(width: SpacingTokens.xs),
                              Text(
                                '|',
                                style: GoogleFonts.poppins(
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
                                      style: GoogleFonts.poppins(
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
            child: Text(
              '삭제', 
              style: TypographyTokens.button.copyWith(color: ColorTokens.error),
            ),
          ),
        ],
      ),
    );
  }
}
