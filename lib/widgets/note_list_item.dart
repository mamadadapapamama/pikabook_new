import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../core/models/note.dart';
import '../core/utils/date_formatter.dart';
import '../core/services/media/image_service.dart';
import '../core/services/content/note_service.dart';
import 'flashcard_counter_badge.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme/tokens/color_tokens.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// 홈페이지 노트리스트 화면에서 사용되는 카드 위젯

class NoteListItem extends StatefulWidget {
  final Note note;
  final Function() onDismissed;
  final Function(Note note) onNoteTapped;
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
    final String? imageUrl = widget.note.imageUrl;
    
    // 로드할 URL이 현재 캐시된 URL과 다르거나, 파일이 없는데 URL은 있는 경우 로드 필요
    bool needsLoading = (imageUrl != _cachedImageUrl || _imageFile == null) && 
                       imageUrl != null && 
                       imageUrl.isNotEmpty;
    
    // 이미 로딩 중이면 제외
    if (_isLoadingImage) return;
    
    if (needsLoading) {
      // 로드 시작 전에 상태 초기화
      setState(() {
        _imageFile = null;
        _isLoadingImage = true;
        _imageLoadError = false;
        _cachedImageUrl = imageUrl; // 로드 시작할 URL 캐싱
      });
      _loadImage();
    } else if (imageUrl == null || imageUrl.isEmpty) {
      // URL이 없는 경우 상태 초기화 (Placeholder 표시용)
      if (_imageFile != null || _isLoadingImage || _imageLoadError) {
        setState(() {
          _imageFile = null;
          _isLoadingImage = false;
          _imageLoadError = false;
          _cachedImageUrl = null;
        });
      }
    }
  }

  Future<void> _loadImage() async {
    // 이미지 URL 가져오기 (null 체크는 _loadImageIfNeeded에서 이미 수행)
    final String imageUrl = _cachedImageUrl!;

    // _loadImageIfNeeded에서 이미 로딩 상태 설정했으므로 여기서는 설정 불필요
    // if (!_isLoadingImage) {
    //   setState(() {
    //     _isLoadingImage = true;
    //     _imageLoadError = false;
    //   });
    // }

    File? downloadedImage;
    try {
      // 이미지 URL 처리 개선
      
      // Firebase Storage URL 패턴 체크
      bool isFirebaseUrl = imageUrl.startsWith('http') && 
          (imageUrl.contains('firebasestorage.googleapis.com') || 
           imageUrl.contains('firebase') || 
           imageUrl.contains('storage'));
      
      if (isFirebaseUrl) {
        downloadedImage = await _imageService.downloadImage(imageUrl);
      } else {
        // 다른 경로 처리 (필요시 구현)
        // downloadedImage = await _imageService.downloadImageFromPath(imageUrl);
        // 임시로 에러 처리
        if (kDebugMode) {
          debugPrint("처리되지 않은 이미지 경로 유형: $imageUrl");
        }
        throw Exception("처리되지 않은 이미지 경로");
      }

      // 마운트 상태와 결과에 따라 상태 업데이트
      if (mounted) {
        setState(() {
          _imageFile = downloadedImage;
          _isLoadingImage = false;
          _imageLoadError = (downloadedImage == null);
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('이미지 로드 중 오류 발생 ($imageUrl): $e');
      }
      // 오류 발생 시 상태 변경
      if (mounted) {
        setState(() {
          _isLoadingImage = false;
          _imageLoadError = true;
          _imageFile = null; // 오류 발생 시 이미지 파일 제거
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
        decoration: BoxDecoration(
          color: ColorTokens.errorBackground,
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: const Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.all(24),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
          side: const BorderSide(color: ColorTokens.primaryverylight,width:1.0),
        ),
        color: Colors.white,
        elevation: 0,
        child: InkWell(
          onTap: () {
            try {
              if (kDebugMode) {
                debugPrint('노트 아이템 탭됨: id=${widget.note.id ?? "없음"}, 제목=${widget.note.originalText}');
              }
              
              // 노트 ID가 null이거나 비어있는 경우 처리
              if (widget.note.id == null || widget.note.id!.isEmpty) {
                if (kDebugMode) {
                  debugPrint('⚠️ 경고: 유효하지 않은 노트 ID');
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('유효하지 않은 노트 ID입니다.')),
                );
                return;
              }
              
              // 정상적인 경우 노트 객체 전체를 전달
              widget.onNoteTapped(widget.note);
            } catch (e, stackTrace) {
              if (kDebugMode) {
                debugPrint('❌ 노트 탭 처리 중 오류 발생: $e');
                debugPrint('스택 트레이스: $stackTrace');
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('노트를 열 수 없습니다: $e')),
              );
            }
          },
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
    // final String cacheKey = widget.note.id ?? '' + (_cachedImageUrl ?? '');
    
    if (_isLoadingImage) {
      // 1. 로딩 중: 로딩 인디케이터 표시
      return Container(
        color: Colors.grey[200], // 로딩 중 배경색
        child: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(ColorTokens.primary),
            strokeWidth: 2.0,
          ),
        ),
      );
    } else if (_imageFile != null) {
      // 2. 이미지 로드 성공: 이미지 표시
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            _imageFile!,
            fit: BoxFit.cover,
            // key: ValueKey(cacheKey), // 키 사용은 상태 관리에 따라 조절
            cacheHeight: 240, 
            cacheWidth: 240,
            errorBuilder: (context, error, stackTrace) {
              // 이미지 파일 렌더링 중 오류 발생 시
              if (kDebugMode) {
                debugPrint('Image.file 렌더링 오류: $error');
              }
              // 에러 상태로 전환하고 다시 빌드하도록 유도
              WidgetsBinding.instance.addPostFrameCallback((_) {
                 if (mounted) {
                    setState(() {
                      _imageLoadError = true;
                      _imageFile = null;
                    });
                 }
              });
              return _buildPlaceholderWidget(); // 임시로 placeholder 표시
            },
          ),
          // 업로드 중 오버레이 (필요시)
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
    } else if (_imageLoadError) {
      // 3. 이미지 로드 실패: 새로고침 UI 표시
      return _buildErrorWidget();
    } else {
      // 4. 초기 상태 또는 이미지 URL 없음: Placeholder 표시
      return _buildPlaceholderWidget();
    }
  }

  // Placeholder 위젯 (이미지 없음 또는 초기 상태)
  Widget _buildPlaceholderWidget() {
    return GestureDetector(
      onTap: _showImageSourceOptions, // 이미지 추가 옵션 표시
      child: Container(
        color: Colors.grey[200],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_photo_alternate_outlined,
                color: ColorTokens.primary, // 아이콘 색상 변경
                size: 32.0,
              ),
              const SizedBox(height: 4.0),
              Text(
                '이미지 추가',
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
  }

  // 이미지 로드 에러 위젯
  Widget _buildErrorWidget() {
    return GestureDetector(
      onTap: _loadImageIfNeeded, // 이미지 다시 로드 시도
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
                '이미지 로드 실패\n다시 시도',
                textAlign: TextAlign.center,
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
  }
}
