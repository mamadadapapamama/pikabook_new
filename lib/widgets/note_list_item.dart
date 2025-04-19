import 'dart:io';
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../utils/date_formatter.dart';
import '../services/image_service.dart';
import '../services/note_service.dart';
import 'flashcard_counter_badge.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../theme/tokens/color_tokens.dart';
import 'package:firebase_storage/firebase_storage.dart';

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
    if (widget.note.imageUrl == null || widget.note.imageUrl!.isEmpty) {
      setState(() {
        _isLoadingImage = false;
        _imageFile = null;
        _imageLoadError = false;
      });
      debugPrint('노트에 이미지 URL이 없음: ${widget.note.id}');
      return;
    }

    try {
      setState(() {
        _isLoadingImage = true;
        _imageLoadError = false;
      });

      debugPrint('노트 이미지 로드 시작: ${widget.note.imageUrl}');
      
      File? downloadedImage;
      
      // 이미지 URL 처리 개선
      final String imageUrl = widget.note.imageUrl!;
      
      // Firebase Storage URL 패턴 체크
      bool isFirebaseUrl = imageUrl.startsWith('http') && 
          (imageUrl.contains('firebasestorage.googleapis.com') || 
           imageUrl.contains('firebase') || 
           imageUrl.contains('storage'));
      
      if (isFirebaseUrl) {
        // Firebase Storage URL에서 직접 다운로드
        downloadedImage = await _imageService.downloadImage(imageUrl);
        debugPrint('Firebase URL에서 다운로드 시도: $imageUrl');
      } else {
        // 상대 경로로 시도
        downloadedImage = await _imageService.downloadImage(imageUrl);
        debugPrint('상대 경로로 다운로드 시도: $imageUrl');
        
        // 실패한 경우 전체 URL로 다시 시도
        if (downloadedImage == null) {
          try {
            // Firebase Storage 참조 생성 시도
            final storageRef = FirebaseStorage.instance.ref().child(imageUrl);
            final fullUrl = await storageRef.getDownloadURL();
            downloadedImage = await _imageService.downloadImage(fullUrl);
            debugPrint('전체 URL로 재시도 성공: $fullUrl');
          } catch (e) {
            debugPrint('전체 URL로 재시도 중 오류: $e');
            
            // 마지막 시도: 기본 경로를 붙여서 시도
            try {
              final fallbackUrl = 'images/$imageUrl';
              final storageRef = FirebaseStorage.instance.ref().child(fallbackUrl);
              final fullUrl = await storageRef.getDownloadURL();
              downloadedImage = await _imageService.downloadImage(fullUrl);
              debugPrint('기본 경로 추가 시도 성공: $fallbackUrl');
            } catch (e) {
              debugPrint('기본 경로 추가 시도 실패: $e');
            }
          }
        }
      }

      if (mounted) {
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
      if (mounted) {
        setState(() {
          _isLoadingImage = false;
          _imageLoadError = true;
        });
      }
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
                  style: TextButton.styleFrom(foregroundColor: ColorTokens.primary),
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
                            '${widget.note.imageCount ?? widget.note.pages.length} pages',
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
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(ColorTokens.primary),
          strokeWidth: 2.0,
        ),
      );
    } else if (_imageLoadError || _imageFile == null) {
      // 이미지 URL이 있지만 로드에 실패한 경우
      final hasUrl = widget.note.imageUrl != null && widget.note.imageUrl!.isNotEmpty;
      
      return GestureDetector(
        onTap: hasUrl ? _loadImage : _showImageSourceOptions, // 이미지가 있으면 다시 로드 시도, 없으면 선택 다이얼로그
        child: Container(
          color: Colors.grey[200],
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  hasUrl ? Icons.refresh : Icons.add_photo_alternate,
                  color: hasUrl ? Colors.grey[400] : ColorTokens.primary,
                  size: 32.0,
                ),
                if (hasUrl) ...[
                  const SizedBox(height: 4.0),
                  Text(
                    '이미지 불러오기 실패\n다시 시도',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 10.0,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 4.0),
                  Text(
                    '이미지 추가',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 10.0,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    } else {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            _imageFile!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              debugPrint('이미지 렌더링 오류: $error');
              // 오류 발생 시 다시 로드 시도할 수 있는 UI 제공
              return GestureDetector(
                onTap: _loadImage,
                child: Container(
                  color: Colors.grey[200],
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.refresh,
                          color: Colors.grey[400],
                          size: 32.0,
                        ),
                        const SizedBox(height: 4.0),
                        Text(
                          '이미지 다시 로드',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 10.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          // 업로드 중이면 오버레이 표시
          if (_isUploadingImage)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
        ],
      );
    }
  }
}
