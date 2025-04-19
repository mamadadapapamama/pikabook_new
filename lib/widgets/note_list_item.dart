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
  String? _cachedImageUrl; // 현재 캐시된 이미지 URL

  @override
  void initState() {
    super.initState();
    _loadImageIfNeeded();
  }

  @override
  void didUpdateWidget(NoteListItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 노트 ID 또는 이미지 URL이 변경된 경우에만 로드
    if (oldWidget.note.id != widget.note.id || 
        oldWidget.note.imageUrl != widget.note.imageUrl) {
      _loadImageIfNeeded();
    }
  }

  // 이미지 로드가 필요한지 확인 후 로드
  void _loadImageIfNeeded() {
    final imageUrl = widget.note.imageUrl;
    
    // 이미 동일한 URL을 로드 중이거나, 이미 로드했거나, URL이 없는 경우는 제외
    if (_isLoadingImage || 
        (imageUrl == _cachedImageUrl && _imageFile != null) || 
        imageUrl == null || 
        imageUrl.isEmpty) {
      return;
    }
    
    _loadImage();
  }

  Future<void> _loadImage() async {
    final String imageUrl = widget.note.imageUrl ?? '';
    final String noteId = widget.note.id ?? '';
    
    // 이미지 URL이 없거나 비어있으면 바로 반환
    if (imageUrl.isEmpty) {
      if (_isLoadingImage || _imageFile != null) {
        setState(() {
          _isLoadingImage = false;
          _imageFile = null;
          _imageLoadError = false;
        });
      }
      return;
    }

    // 이미 로딩 중이면 중복 요청 방지
    if (_isLoadingImage) return;

    // 로딩 상태만 변경
    if (!_isLoadingImage) {
      setState(() {
        _isLoadingImage = true;
        _imageLoadError = false;
      });
    }

    try {
      // 이미지 URL 처리 개선
      File? downloadedImage;
      
      // Firebase Storage URL 패턴 체크
      bool isFirebaseUrl = imageUrl.startsWith('http') && 
          (imageUrl.contains('firebasestorage.googleapis.com') || 
           imageUrl.contains('firebase') || 
           imageUrl.contains('storage'));
      
      if (isFirebaseUrl) {
        // Firebase Storage URL에서 직접 다운로드
        downloadedImage = await _imageService.downloadImage(imageUrl);
      } else {
        // 상대 경로로 시도
        downloadedImage = await _imageService.downloadImage(imageUrl);
        
        // 실패한 경우 전체 URL로 다시 시도
        if (downloadedImage == null) {
          try {
            // Firebase Storage 참조 생성 시도
            final storageRef = FirebaseStorage.instance.ref().child(imageUrl);
            final fullUrl = await storageRef.getDownloadURL();
            downloadedImage = await _imageService.downloadImage(fullUrl);
          } catch (e) {
            // 마지막 시도: 기본 경로를 붙여서 시도
            try {
              final fallbackUrl = 'images/$imageUrl';
              final storageRef = FirebaseStorage.instance.ref().child(fallbackUrl);
              final fullUrl = await storageRef.getDownloadURL();
              downloadedImage = await _imageService.downloadImage(fullUrl);
            } catch (e) {
              // 모든 시도 실패
            }
          }
        }
      }

      // 마운트 상태와 결과에 따라 단 한 번의 setState 호출
      if (mounted) {
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
      }
    } catch (e) {
      // 오류 발생 시에만 상태 변경
      if (mounted) {
        setState(() {
          _isLoadingImage = false;
          _imageLoadError = true;
        });
      }
    }
  }

  Future<void> _updateNoteImage(File imageFile) async {
    if (_isUploadingImage) return; // 이미 업로드 중이면 중복 요청 방지
    
    setState(() {
      _isUploadingImage = true;
      _imageFile = imageFile;
    });

    try {
      // 이미지 업로드
      final String? uploadedUrl = await _imageService.uploadImage(imageFile);

      if (uploadedUrl != null) {
        // 노트 이미지 URL 업데이트
        await _noteService.updateNoteImageUrl(widget.note.id!, uploadedUrl);
        
        if (mounted) {
          setState(() {
            _isUploadingImage = false;
            _cachedImageUrl = uploadedUrl; // 캐시된 URL 업데이트
          });
          _showSnackBar('이미지가 업데이트 되었습니다');
        }
      } else {
        if (mounted) {
          setState(() {
            _isUploadingImage = false;
          });
          _showSnackBar('이미지 업로드 실패');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploadingImage = false;
        });
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
    // 이미지 URL을 키로 사용하여 불필요한 재로드 방지
    final String cacheKey = widget.note.id ?? '' + (widget.note.imageUrl ?? '');
    
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
            key: ValueKey(cacheKey), // 고유 키 설정으로 불필요한 리빌드 방지
            cacheHeight: 240, // 썸네일 2배 크기로 메모리 최적화
            cacheWidth: 240,
            errorBuilder: (context, error, stackTrace) {
              debugPrint('이미지 렌더링 오류: $error');
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
