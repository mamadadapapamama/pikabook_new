import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../core/models/note.dart';
import '../core/utils/date_formatter.dart';
import '../core/services/media/image_service.dart';
import '../core/services/content/note_service.dart';
import 'flashcard_counter_badge.dart';
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
  bool _imageLoadError = false;
  String? _cachedImageUrl; // 현재 캐시된 이미지 URL
  bool _mounted = true; // 마운트 상태 추적

  @override
  void initState() {
    super.initState();
    _loadImageIfNeeded();
  }

  @override
  void dispose() {
    _mounted = false;
    super.dispose();
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

  // setState를 안전하게 호출하는 헬퍼 메서드
  void _safeSetState(VoidCallback fn) {
    if (_mounted && mounted) {
      setState(fn);
    }
  }

  // 이미지 관련 메서드들
  // -----------------------------------------------------

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
    
    // 이미지 URL이 없거나 비어있으면 바로 반환
    if (imageUrl.isEmpty) {
      // 현재 로딩 중이거나 이미지가 있는 경우만 상태 업데이트
      if (_isLoadingImage || _imageFile != null) {
        _safeSetState(() {
          _isLoadingImage = false;
          _imageFile = null;
          _imageLoadError = false;
        });
      }
      return;
    }

    // 이미 로딩 중이면 중복 요청 방지
    if (_isLoadingImage) return;

    // 로딩 상태 변경 (상태 변경 최소화)
    _safeSetState(() {
      _isLoadingImage = true;
      _imageLoadError = false;
    });

    try {
      // 이미지 URL 처리 최적화
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
              // 모든 시도 실패 - 조용히 처리
            }
          }
        }
      }

      // 모든 작업 완료 후 한 번만 상태 업데이트
      if (downloadedImage != null) {
        _safeSetState(() {
          _imageFile = downloadedImage;
          _isLoadingImage = false;
          _cachedImageUrl = imageUrl; // URL 캐싱 추가
        });
      } else {
        _safeSetState(() {
          _isLoadingImage = false;
          _imageLoadError = true;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('이미지 로드 오류: $e');
      }
      _safeSetState(() {
        _isLoadingImage = false;
        _imageLoadError = true;
      });
    }
  }
  
  // 이미지 위젯 생성
  Widget _buildImageWidget() {
    // 메모이제이션을 위한 키
    final String cacheKey = '${widget.note.id}_${widget.note.imageUrl}';
    
    if (_isLoadingImage) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(ColorTokens.primary),
          strokeWidth: 2.0,
        ),
      );
    } else if (_imageLoadError || _imageFile == null) {
      // 이미지 URL이 있지만 로드에 실패한 경우나 이미지가 없는 경우 기본 이미지 표시
      return Image.asset(
        'assets/images/thumbnail_empty.png',
        fit: BoxFit.cover,
        width: 80,
        height: 80,
      );
    } else {
      return Image.file(
        _imageFile!,
        fit: BoxFit.cover,
        key: ValueKey(cacheKey), // 고유 키 설정으로 불필요한 리빌드 방지
        cacheHeight: 240, // 썸네일 2배 크기로 메모리 최적화
        cacheWidth: 240,
        errorBuilder: (context, error, stackTrace) {
          if (kDebugMode) {
            debugPrint('이미지 렌더링 오류: $error');
          }
          return Image.asset(
            'assets/images/thumbnail_empty.png',
            fit: BoxFit.cover,
          );
        },
      );
    }
  }
  // -----------------------------------------------------

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _getFormattedDate() {
    final noteDate = widget.note.createdAt;
    return DateFormatter.formatDate(noteDate);
  }

// 노트 리스트 아이템 카드 삭제 기능
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
}
