import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../views/screens/full_image_screen.dart';
import '../../../core/widgets/dot_loading_indicator.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../core/services/media/image_service.dart';

/// 페이지 이미지를 표시하는 위젯
/// FirstImageContainer와 통합되었습니다.
class PageImageWidget extends StatefulWidget {
  final File? imageFile;
  final String? imageUrl;
  final page_model.Page? page;
  final String? pageId;
  final bool isLoading;
  final double? height;
  final double? width;
  final Function(File)? onFullScreenTap;
  final VoidCallback? onTap;
  final bool enableFullScreen;

  const PageImageWidget({
    super.key,
    this.imageFile,
    this.imageUrl,
    this.page,
    this.pageId,
    this.isLoading = false,
    this.height = 200,
    this.width,
    this.onFullScreenTap,
    this.onTap,
    this.enableFullScreen = true,
  });

  @override
  State<PageImageWidget> createState() => _PageImageWidgetState();
}

class _PageImageWidgetState extends State<PageImageWidget> {
  // ImageService 인스턴스
  final ImageService _imageService = ImageService();
  
  // 이미지 로딩 상태 관리
  File? _loadedImageFile;
  bool _isLoadingImage = false;
  String? _lastImageUrl;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadImageIfNeeded();
  }

  @override
  void didUpdateWidget(PageImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // imageUrl이 변경된 경우에만 이미지 재로드
    if (widget.imageUrl != oldWidget.imageUrl) {
      if (kDebugMode) {
        debugPrint('🖼️ imageUrl 변경됨: ${oldWidget.imageUrl} → ${widget.imageUrl}');
      }
      // 상태 리셋
      _loadedImageFile = null;
      _isLoadingImage = false;
      _lastImageUrl = null;
      _hasError = false;
      
      _loadImageIfNeeded();
    }
  }

  void _loadImageIfNeeded() {
    // 이미 로드된 이미지가 있거나 로딩 중이면 스킵
    if (_loadedImageFile != null || _isLoadingImage) {
      if (kDebugMode) {
        debugPrint('🖼️ 이미지 로딩 스킵: 이미 로드됨=${_loadedImageFile != null}, 로딩중=$_isLoadingImage');
      }
      return;
    }
    
    if (widget.imageUrl != null && 
        widget.imageUrl!.isNotEmpty && 
        widget.imageUrl != _lastImageUrl) {
      
      _lastImageUrl = widget.imageUrl;
      _loadImage(widget.imageUrl!);
    }
  }

  Future<void> _loadImage(String imageUrl) async {
    if (_isLoadingImage) {
      if (kDebugMode) {
        debugPrint('🖼️ 이미 로딩 중이므로 중복 로딩 방지: $imageUrl');
      }
      return;
    }
    
    if (kDebugMode) {
      debugPrint('🖼️ ImageService를 통한 이미지 로딩 시작: $imageUrl');
    }
    
    setState(() {
      _isLoadingImage = true;
      _hasError = false;
      _loadedImageFile = null;
    });

    try {
      // ImageService를 통해 이미지 파일 가져오기
      final imageFile = await _imageService.getImageFile(imageUrl);
      
      if (mounted) {
        setState(() {
          _loadedImageFile = imageFile;
          _isLoadingImage = false;
          _hasError = imageFile == null;
        });
        
        if (kDebugMode) {
          if (imageFile != null) {
            debugPrint('🖼️ ✅ ImageService 이미지 로딩 성공: ${imageFile.path}');
          } else {
            debugPrint('🖼️ ❌ ImageService 이미지 로딩 실패: $imageUrl');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingImage = false;
          _hasError = true;
          _loadedImageFile = null;
        });
        
        if (kDebugMode) {
          debugPrint('🖼️ ❌ ImageService 이미지 로딩 오류: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 디버그 로그는 상태 변경이 있을 때만 출력
    if (kDebugMode && (_loadedImageFile == null && !_isLoadingImage)) {
      debugPrint('🖼️ PageImageWidget build: imageFile=${widget.imageFile?.path}, imageUrl=${widget.imageUrl}, isLoading=${widget.isLoading}');
    }
    
    // 이미지가 없는 경우 또는 로딩 중인 경우
    if ((widget.imageFile == null && (widget.imageUrl == null || widget.imageUrl!.isEmpty)) || widget.isLoading) {
      if (kDebugMode) {
        debugPrint('🖼️ 이미지 없음 또는 로딩 중 - 로딩 인디케이터 표시');
      }
      return _buildLoadingIndicator();
    }

    return GestureDetector(
      onTap: () {
        if (widget.onTap != null) {
          widget.onTap!();
        } else if (widget.enableFullScreen) {
          _openFullScreenImage(context);
        }
      },
      child: Container(
        height: 200, // 이미지 높이 고정
        width: widget.width ?? double.infinity,
        margin: const EdgeInsets.only(top: 16), // noteDetail 스타일 고정
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 이미지
              _buildImage(),
              
              // 확대 아이콘 (enableFullScreen이 true인 경우)
              if (widget.enableFullScreen)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(128),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(
                      Icons.zoom_in,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // 로딩 인디케이터 위젯
  Widget _buildLoadingIndicator() {
    return Container(
      height: 200, // 이미지 높이 고정
      width: widget.width ?? double.infinity,
      margin: const EdgeInsets.only(top: 16), // noteDetail 스타일 고정
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 기본 이미지 (배경)
          _buildEmptyImageWidget(),
          
          // 로딩 인디케이터 (전경)
          if (widget.isLoading)
            const Center(
              child: DotLoadingIndicator(
                message: '이미지 로딩 중...',
                dotColor: ColorTokens.primary,
              ),
            ),
        ],
      ),
    );
  }

  // 이미지 위젯
  Widget _buildImage() {
    // 로딩 중이거나 오류가 있을 때만 로그 출력
    if (kDebugMode && (_isLoadingImage || _hasError || _loadedImageFile == null)) {
      debugPrint('🖼️ _buildImage 호출: imageFile=${widget.imageFile != null}, loadedFile=${_loadedImageFile != null}, isLoading=$_isLoadingImage');
    }
    
    // 1. Image Picker를 통해 새로 선택된 이미지 파일인 경우
    if (widget.imageFile != null) {
      if (kDebugMode) {
        debugPrint('🖼️ Image Picker로 선택된 새 이미지 사용: ${widget.imageFile!.path}');
      }
      return Image.file(
        widget.imageFile!,
        height: widget.height,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          if (kDebugMode) {
            debugPrint('🖼️ 새 이미지 파일 로드 오류: $error');
          }
          return _buildEmptyImageWidget();
        },
      );
    }
    
    // 2. Firestore/로컬 스토리지에서 로드된 기존 이미지인 경우
    if (_loadedImageFile != null) {
      // 성공적으로 로드된 경우는 로그 출력하지 않음 (무한 반복 방지)
      return Image.file(
        _loadedImageFile!,
        height: widget.height,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          if (kDebugMode) {
            debugPrint('🖼️ 저장된 이미지 표시 오류: $error');
          }
          return _buildEmptyImageWidget();
        },
      );
    }
    
    // 3. 이미지 로딩 중인 경우
    if (_isLoadingImage) {
      if (kDebugMode) {
        debugPrint('🖼️ 이미지 로딩 중 표시');
      }
      return Stack(
        children: [
          _buildEmptyImageWidget(),
          const Center(
            child: CircularProgressIndicator(),
          ),
        ],
      );
    }
    
    // 4. 기본 빈 이미지 (이미지가 없는 경우)
    if (kDebugMode) {
      debugPrint('🖼️ 기본 빈 이미지 표시');
    }
    return _buildEmptyImageWidget();
  }

  // 기본 빈 이미지 위젯
  Widget _buildEmptyImageWidget() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[100],
      ),
      child: Image.asset(
        'assets/images/image_empty.png',
        fit: BoxFit.cover,
      ),
    );
  }

  // 전체 화면 이미지 뷰어 열기
  void _openFullScreenImage(BuildContext context) {
    final imageFile = widget.imageFile ?? _loadedImageFile;
    if (imageFile == null) return;

    if (widget.onFullScreenTap != null) {
      widget.onFullScreenTap!(imageFile);
      return;
    }

    // ImageService의 showFullImage 메서드 활용
    _imageService.showFullImage(context, imageFile, '이미지 보기');
  }
}
