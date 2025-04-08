import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/scheduler.dart';
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
import 'package:image_picker/image_picker.dart';

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
    // 이미지 URL이 없으면 처리하지 않음
    if (widget.note.imageUrl == null || widget.note.imageUrl!.isEmpty) return;

    // 이미 로딩 중이면 중복 로딩 방지
    if (_isLoadingImage) return;

    // 로딩 시작
    if (mounted) {
      setState(() {
        _isLoadingImage = true;
      });
    }

    try {
      // 이미지 서비스를 통해 이미지 파일 가져오기
      final imageFile = await _imageService.getImageFile(widget.note.imageUrl);
      
      // 위젯이 여전히 마운트 상태인지 확인
      if (mounted) {
        setState(() {
          _imageFile = imageFile;
          _isLoadingImage = false;
        });
      }
    } catch (e) {
      debugPrint('썸네일 이미지 로드 오류: $e');
      
      // 오류 발생해도 로딩 상태 종료
      if (mounted) {
        setState(() {
          _isLoadingImage = false;
        });
      }
    }
  }

  void _handleEmptyImageTap(BuildContext context) async {
    // 이미지 업로드 로직 구현
    try {
      // 노트 ID 확인
      if (widget.note.id == null) {
        return;
      }
      
      // 이미지 선택 대화상자 표시
      await showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('갤러리에서 선택'),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickImageFromGallery();
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('카메라로 촬영'),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickImageFromCamera();
                },
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      debugPrint('이미지 선택 중 오류 발생: $e');
    }
  }
  
  // 갤러리에서 이미지 선택
  Future<void> _pickImageFromGallery() async {
    try {
      final imageFile = await _imageService.pickImage(source: ImageSource.gallery);
      if (imageFile != null && widget.note.id != null) {
        await _updateNoteImage(imageFile);
      }
    } catch (e) {
      debugPrint('갤러리에서 이미지 선택 중 오류: $e');
    }
  }
  
  // 카메라로 이미지 촬영
  Future<void> _pickImageFromCamera() async {
    try {
      final imageFile = await _imageService.pickImage(source: ImageSource.camera);
      if (imageFile != null && widget.note.id != null) {
        await _updateNoteImage(imageFile);
      }
    } catch (e) {
      debugPrint('카메라로 이미지 촬영 중 오류: $e');
    }
  }
  
  // 노트 이미지 업데이트
  Future<void> _updateNoteImage(File imageFile) async {
    // 노트 ID 검증 - null이면 조기 반환
    final String? noteId = widget.note.id;
    if (noteId == null || noteId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('노트 ID가 유효하지 않습니다')),
        );
      }
      return;
    }
    
    setState(() {
      _isLoadingImage = true;
    });
    
    try {
      // 이미지 파일 존재 여부 확인
      if (!await imageFile.exists()) {
        throw Exception('이미지 파일이 존재하지 않습니다');
      }
      
      // 이미지 업로드
      final String? imageUrl = await _imageService.uploadImage(imageFile);
      
      // 이미지 URL이 null이거나 비어있는지 확인
      if (imageUrl == null || imageUrl.isEmpty) {
        throw Exception('이미지 URL이 유효하지 않습니다');
      }
      
      // 노트 이미지 URL 업데이트
      final bool success = await _noteService.updateNoteImageUrl(noteId, imageUrl);
      
      if (!success) {
        throw Exception('노트 이미지 업데이트에 실패했습니다');
      }
      
      // 이미지 로드
      await _loadImage();
      
      // 스낵바 표시
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('노트 이미지가 업데이트되었습니다')),
        );
      }
    } catch (e) {
      debugPrint('노트 이미지 업데이트 중 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('이미지 업데이트 중 오류가 발생했습니다: $e'),
            backgroundColor: ColorTokens.error,
          ),
        );
      }
    } finally {
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
    final borderRadius = BorderRadius.circular(SpacingTokens.radiusXs);
    
    return Container(
      margin: EdgeInsets.symmetric(vertical: SpacingTokens.sm),
      child: SegmentUtils.buildDismissibleSegment(
        key: dismissibleKey,
        onDelete: widget.onDelete,
        direction: DismissDirection.endToStart,
        borderRadius: borderRadius,
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
        child: Material(
          color: Colors.white,
          child: InkWell(
            onTap: widget.onTap,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: ColorTokens.primarylight,
                  width: 1,
                ),
                borderRadius: borderRadius,
              ),
              child: Padding(
                padding: EdgeInsets.all(SpacingTokens.md+2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 이미지 썸네일 (최적화된 방식으로 구현)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(SpacingTokens.xs),
                      child: SizedBox(
                        width: 80,
                        height: 80,
                        child: _imageFile != null
                          ? Image(
                              image: FileImage(_imageFile!),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return _buildEmptyThumbnail();
                              },
                            )
                          : _buildEmptyThumbnail(),
                      ),
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
      ),
    );
  }
  
  // 빈 썸네일 표시 위젯
  Widget _buildEmptyThumbnail() {
    return Container(
      color: Colors.grey[100],
      child: Image.asset(
        'assets/images/thumbnail_empty.png',
        fit: BoxFit.cover,
      ),
    );
  }
}
