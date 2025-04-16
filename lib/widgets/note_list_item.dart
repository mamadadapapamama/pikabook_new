import 'dart:io';
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../utils/date_formatter.dart';
import '../services/image_service.dart';
import '../services/note_service.dart';
import 'flashcard_counter_badge.dart';
import 'package:image_picker/image_picker.dart';

/// 홈페이지 노트리스트 화면에서 사용되는 카드 위젯

class NoteListItem extends StatefulWidget {
  final Note note;
  final Function() onDismissed;
  final Function(String noteId) onNoteTapped;
  final Function(String noteId, bool isFavorite) onFavoriteToggled;
  final bool isFilteredList;

  const NoteListItem({
    super.key,
    required this.note,
    required this.onDismissed,
    required this.onNoteTapped,
    required this.onFavoriteToggled,
    this.isFilteredList = false,
  });

  @override
  _NoteListItemState createState() => _NoteListItemState();
}

class _NoteListItemState extends State<NoteListItem> {
  final ImageService _imageService = ImageService();
  final NoteService _noteService = NoteService();
  File? _imageFile;
  bool _isLoadingImage = false;
  bool _isUploadingImage = false;
  bool _imageLoadError = false;

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
    if (widget.note.imageUrl != null && widget.note.imageUrl!.isNotEmpty) {
      try {
        setState(() {
          _isLoadingImage = true;
        });

        // 이미지 다운로드
        final downloadedImage = await _imageService.downloadImage(widget.note.imageUrl!);

        if (downloadedImage != null) {
          setState(() {
            _imageFile = downloadedImage;
            _isLoadingImage = false;
          });
        } else {
          setState(() {
            _isLoadingImage = false;
            _imageLoadError = true;
          });
        }
      } catch (e) {
        debugPrint('이미지 로드 중 오류: $e');
        setState(() {
          _isLoadingImage = false;
          _imageLoadError = true;
        });
      }
    } else {
      setState(() {
        _isLoadingImage = false;
      });
    }
  }

  Future<void> _updateNoteImage(File imageFile) async {
    try {
      setState(() {
        _isUploadingImage = true;
        _imageFile = imageFile;
      });

      // 이미지 업로드
      final String? uploadedUrl = await _imageService.uploadImage(imageFile);

      if (uploadedUrl != null) {
        // 노트 이미지 URL 업데이트
        await _noteService.updateNoteImageUrl(widget.note.id!, uploadedUrl);
        
        setState(() {
          _isUploadingImage = false;
        });
        
        if (mounted) {
          _showSnackBar('이미지가 업데이트 되었습니다');
        }
      } else {
        setState(() {
          _isUploadingImage = false;
        });
        if (mounted) {
          _showSnackBar('이미지 업로드 실패');
        }
      }
    } catch (e) {
      setState(() {
        _isUploadingImage = false;
      });
      if (mounted) {
        _showSnackBar('이미지 업로드 중 오류 발생: $e');
      }
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final pickedFile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      
      if (pickedFile != null) {
        _updateNoteImage(File(pickedFile.path));
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('갤러리에서 이미지를 가져오지 못했습니다: $e');
      }
    }
  }

  Future<void> _pickImageFromCamera() async {
    try {
      final pickedFile = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      
      if (pickedFile != null) {
        _updateNoteImage(File(pickedFile.path));
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('카메라에서 이미지를 가져오지 못했습니다: $e');
      }
    }
  }

  void _showImageSourceOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('갤러리에서 선택'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImageFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('카메라로 촬영'),
              onTap: () {
                Navigator.of(context).pop();
                _pickImageFromCamera();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _getFormattedDate() {
    final noteDate = widget.note.createdAt;
    return DateFormatter.formatDate(noteDate);
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(widget.note.id ?? ''),
      direction: widget.isFilteredList
          ? DismissDirection.none
          : DismissDirection.endToStart,
      onDismissed: (direction) {
        widget.onDismissed();
      },
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(
          Icons.delete,
          color: Colors.white,
        ),
      ),
      confirmDismiss: (direction) async {
        // 삭제 확인 대화상자
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('노트 삭제'),
            content: const Text('이 노트를 삭제하시겠습니까?'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('삭제'),
              ),
            ],
          ),
        ) ?? false;
      },
      child: InkWell(
        onTap: () {
          widget.onNoteTapped(widget.note.id ?? '');
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 썸네일 이미지
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: _buildNoteImage(),
                ),
              ),
              const SizedBox(width: 16),
              // 노트 내용
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.note.originalText.isEmpty ? '제목 없음' : widget.note.originalText,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            widget.note.isFavorite ? Icons.favorite : Icons.favorite_border,
                            color: widget.note.isFavorite ? Colors.red : Colors.grey,
                          ),
                          onPressed: () {
                            widget.onFavoriteToggled(
                              widget.note.id ?? '',
                              !widget.note.isFavorite,
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          _getFormattedDate(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (widget.note.sourceLanguage.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${widget.note.sourceLanguage}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
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
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildNoteImage() {
    if (_isLoadingImage) {
      return const Center(
        child: SizedBox(
          width: 80,
          height: 80,
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    if (_imageFile != null) {
      return Image.file(
        _imageFile!,
        fit: BoxFit.cover,
        width: 80,
        height: 80,
        errorBuilder: (context, error, stackTrace) {
          return _buildEmptyThumbnail();
        },
      );
    }
    
    return _buildEmptyThumbnail();
  }
  
  Widget _buildEmptyThumbnail() {
    return Container(
      width: 80,
      height: 80,
      color: Colors.grey[200],
      child: const Icon(
        Icons.image,
        size: 40,
        color: Colors.grey,
      ),
    );
  }
}
