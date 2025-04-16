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
          _imageLoadError = false;
        });

        debugPrint('노트 이미지 로드 시작: ${widget.note.imageUrl}');

        // 이미지 다운로드
        final downloadedImage = await _imageService.downloadImage(widget.note.imageUrl!);

        if (mounted) { // 위젯이 여전히 마운트되어 있는지 확인
          if (downloadedImage != null) {
            setState(() {
              _imageFile = downloadedImage;
              _isLoadingImage = false;
            });
            debugPrint('노트 이미지 로드 성공: ${widget.note.id}');
          } else {
            setState(() {
              _isLoadingImage = false;
              _imageLoadError = true;
            });
            debugPrint('노트 이미지 로드 실패 (파일 없음): ${widget.note.id}');
          }
        }
      } catch (e) {
        debugPrint('이미지 로드 중 오류: $e');
        if (mounted) { // 위젯이 여전히 마운트되어 있는지 확인
          setState(() {
            _isLoadingImage = false;
            _imageLoadError = true;
          });
        }
      }
    } else {
      setState(() {
        _isLoadingImage = false;
        _imageFile = null; // 이미지 URL이 없는 경우 이미지 파일 정보 초기화
      });
      debugPrint('노트에 이미지 URL이 없음: ${widget.note.id}');
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
      background: Container(
        color: Colors.red,
        child: const Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: Icon(
              Icons.delete,
              color: Colors.white,
            ),
          ),
        ),
      ),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('노트 삭제'),
              content: const Text('정말로 이 노트를 삭제하시겠습니까?'),
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
            );
          },
        );
      },
      onDismissed: (direction) {
        widget.onDismissed();
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
        elevation: 1.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
          side: const BorderSide(color: Color(0xFFFFF0E8), width: 1.0),
        ),
        color: Colors.white,
        child: InkWell(
          onTap: () => widget.onNoteTapped(widget.note.id ?? ''),
          borderRadius: BorderRadius.circular(8.0),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 썸네일 이미지
                ClipRRect(
                  borderRadius: BorderRadius.circular(4.0),
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: _buildImageWidget(),
                  ),
                ),
                const SizedBox(width: 16.0),
                // 노트 정보
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.note.originalText.isEmpty ? '제목 없음' : widget.note.originalText,
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 20.0,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0E2823),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2.0),
                      Row(
                        children: [
                          Text(
                            _getFormattedDate(),
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12.0,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF969696),
                            ),
                          ),
                          const SizedBox(width: 4.0),
                          const Text(
                            '|',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12.0,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF969696),
                            ),
                          ),
                          const SizedBox(width: 4.0),
                          Text(
                            '${widget.note.pages.length} pages',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12.0,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF969696),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8.0),
                      if (widget.note.flashcardCount > 0 || widget.note.flashCards.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFD53C),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 20,
                                height: 20,
                                alignment: Alignment.center,
                                child: Stack(
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: const Color(0xFF665518),
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      left: 4,
                                      child: Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFD53C),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: const Color(0xFF665518),
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${widget.note.flashcardCount > 0 ? widget.note.flashcardCount : widget.note.flashCards.length}',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF226357),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // 즐겨찾기 아이콘
                GestureDetector(
                  onTap: () {
                    widget.onFavoriteToggled(
                      widget.note.id ?? '',
                      !widget.note.isFavorite,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: Icon(
                      widget.note.isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: widget.note.isFavorite 
                        ? const Color(0xFFFE6A15) 
                        : const Color(0xFFD3E0DD),
                      size: 24.0,
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
  
  Widget _buildImageWidget() {
    if (_isLoadingImage) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    } else if (_imageLoadError || _imageFile == null) {
      return Container(
        color: Colors.grey[200],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.image_not_supported,
                color: Colors.grey[400],
                size: 32.0,
              ),
              const SizedBox(height: 8.0),
              Text(
                '이미지를 불러올 수 없습니다',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12.0,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      return Image.file(
        _imageFile!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('이미지 렌더링 오류: $error');
          return Container(
            color: Colors.grey[200],
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.broken_image,
                    color: Colors.grey[400],
                    size: 32.0,
                  ),
                  const SizedBox(height: 8.0),
                  Text(
                    '이미지 오류',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12.0,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }
  }
}
