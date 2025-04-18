import 'dart:io';
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../utils/date_formatter.dart';
import '../services/image_service.dart';
import 'flashcard_counter_badge.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/tokens/color_tokens.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
    // 메인 imageUrl이 있으면 먼저 시도
    if (widget.note.imageUrl != null && widget.note.imageUrl!.isNotEmpty) {
      try {
        setState(() {
          _isLoadingImage = true;
          _imageLoadError = false;
        });

        debugPrint('노트 이미지 로드 시작: ${widget.note.imageUrl}');
        
        File? downloadedImage;
        
        // 1. 직접 Firebase URL인지 확인
        if (widget.note.imageUrl!.startsWith('http') && 
            widget.note.imageUrl!.contains('firebasestorage.googleapis.com')) {
          // Firebase Storage URL에서 다운로드
          downloadedImage = await _imageService.downloadImage(widget.note.imageUrl!);
        } 
        // 2. 상대 경로인 경우 
        else {
          // 이미지 다운로드
          downloadedImage = await _imageService.downloadImage(widget.note.imageUrl!);
          
          // 실패한 경우 전체 URL로 다시 시도
          if (downloadedImage == null) {
            // Firebase Storage에서 URL 가져오기 시도
            try {
              final storageRef = FirebaseStorage.instance.ref().child(widget.note.imageUrl!);
              final url = await storageRef.getDownloadURL();
              downloadedImage = await _imageService.downloadImage(url);
            } catch (e) {
              debugPrint('Firebase URL로 재시도 중 오류: $e');
            }
          }
        }

        if (mounted) { // 위젯이 여전히 마운트되어 있는지 확인
          if (downloadedImage != null) {
            setState(() {
              _imageFile = downloadedImage;
              _isLoadingImage = false;
            });
            debugPrint('노트 이미지 로드 성공: ${widget.note.id}');
            return; // 성공적으로 로드되었으므로 종료
          } else {
            // imageUrl로 로드 실패 시 pages 리스트의 첫 번째 이미지 시도
            await _tryLoadFirstPageImage();
          }
        }
      } catch (e) {
        debugPrint('이미지 로드 중 오류: $e');
        if (mounted) { // 위젯이 여전히 마운트되어 있는지 확인
          // 오류 발생 시 pages 리스트의 첫 번째 이미지 시도
          await _tryLoadFirstPageImage();
        }
      }
    } else if (widget.note.pages.isNotEmpty) {
      // imageUrl이 없으면 pages 리스트의 첫 번째 이미지 시도
      await _tryLoadFirstPageImage();
    } else {
      setState(() {
        _isLoadingImage = false;
        _imageFile = null; // 이미지 URL이 없는 경우 이미지 파일 정보 초기화
      });
      debugPrint('노트에 이미지가 없음: ${widget.note.id}');
    }
  }

  // pages 리스트의 첫 번째 이미지를 로드하는 헬퍼 메서드
  Future<void> _tryLoadFirstPageImage() async {
    // 페이지가 있는지 확인
    if (widget.note.pages.isNotEmpty) {
      try {
        final firstPage = widget.note.pages.first;
        // 페이지에 이미지 URL이 있는지 확인
        if (firstPage.imageUrl != null && firstPage.imageUrl!.isNotEmpty) {
          debugPrint('첫 번째 페이지 이미지 로드 시도: ${firstPage.imageUrl}');
          
          File? pageImage;
          
          // URL 또는 경로에 따라 다운로드 시도
          if (firstPage.imageUrl!.startsWith('http')) {
            pageImage = await _imageService.downloadImage(firstPage.imageUrl!);
          } else {
            pageImage = await _imageService.downloadImage(firstPage.imageUrl!);
            
            // 실패한 경우 Firebase URL 가져오기 시도
            if (pageImage == null) {
              try {
                final storageRef = FirebaseStorage.instance.ref().child(firstPage.imageUrl!);
                final url = await storageRef.getDownloadURL();
                pageImage = await _imageService.downloadImage(url);
              } catch (e) {
                debugPrint('첫 번째 페이지 Firebase URL 재시도 중 오류: $e');
              }
            }
          }
          
          if (mounted) {
            if (pageImage != null) {
              setState(() {
                _imageFile = pageImage;
                _isLoadingImage = false;
                _imageLoadError = false;
              });
              debugPrint('첫 번째 페이지 이미지 로드 성공');
              return;
            }
          }
        }
      } catch (e) {
        debugPrint('첫 번째 페이지 이미지 로드 중 오류: $e');
      }
    }
    
    // 모든 시도 실패
    if (mounted) {
      setState(() {
        _isLoadingImage = false;
        _imageLoadError = true;
      });
      debugPrint('모든 이미지 로드 시도 실패: ${widget.note.id}');
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
        // 노트 이미지 URL 직접 업데이트 (Firestore)
        try {
          // Firestore 직접 참조
          await FirebaseFirestore.instance
              .collection('notes')
              .doc(widget.note.id!)
              .update({
                'imageUrl': uploadedUrl,
                'updatedAt': DateTime.now(),
              });
          
          setState(() {
            _isUploadingImage = false;
          });
          
          if (mounted) {
            _showSnackBar('이미지가 업데이트 되었습니다');
          }
        } catch (firestoreError) {
          debugPrint('Firestore 업데이트 오류: $firestoreError');
          if (mounted) {
            _showSnackBar('이미지 URL 업데이트 실패');
          }
          setState(() {
            _isUploadingImage = false;
          });
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
        elevation: 0.0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
          side: const BorderSide(color: ColorTokens.primarylight, width: 1.0),
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
                  color: hasUrl ? Colors.grey[400] : ColorTokens.textGrey,
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
