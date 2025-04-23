import 'package:flutter/material.dart';
import 'dart:io';
import '../../views/screens/full_image_screen.dart';
import '../../core/widgets/dot_loading_indicator.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/models/page.dart' as page_model;
import 'package:flutter/foundation.dart';
import 'note_detail_state.dart'; // LoadingState import 추가
import 'package:flutter/rendering.dart';

/// 이미지 컨테이너 스타일 정의
enum ImageContainerStyle {
  standard,   // 기본 스타일
  noteDetail, // 노트 상세 스타일
  minimal,    // 최소화된 스타일
}

/// 페이지 이미지를 표시하는 위젯
/// FirstImageContainer와 통합되었습니다.
class PageImageWidget extends StatelessWidget {
  final File? imageFile;
  final String? imageUrl;
  final page_model.Page? page;
  final String? pageId;
  final bool isLoading;
  final bool showTitle;
  final String title;
  final ImageContainerStyle style;
  final double? height;
  final double? width;
  final Function(File)? onFullScreenTap;
  final VoidCallback? onTap;
  final bool enableFullScreen;
  final Function(LoadingState)? onLoadingStateChanged;
  final Function(ComponentState)? onStateChanged;
  final bool showLoadingUI;

  const PageImageWidget({
    super.key,
    this.imageFile,
    this.imageUrl,
    this.page,
    this.pageId,
    this.isLoading = false,
    this.showTitle = false,
    this.title = '',
    this.style = ImageContainerStyle.standard,
    this.height = 200,
    this.width,
    this.onFullScreenTap,
    this.onTap,
    this.enableFullScreen = true,
    this.onLoadingStateChanged,
    this.onStateChanged,
    this.showLoadingUI = false,
  });

  @override
  Widget build(BuildContext context) {
    // 이미지가 없는 경우
    if ((imageFile == null && (imageUrl == null || imageUrl!.isEmpty)) || 
        (page != null && page!.originalText == '___PROCESSING___')) {
      
      // 상태 콜백 호출 (로딩 중)
      if (onStateChanged != null) {
        onStateChanged!(ComponentState.loading);
      }
      
      // 로딩 UI 제거하고 빈 공간만 표시
      return const SizedBox(height: 150);
    }

    // 이미지 로드 성공 시 상태 업데이트
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (onStateChanged != null) {
        onStateChanged!(ComponentState.ready);
      }
    });

    return GestureDetector(
      onTap: () {
        if (onTap != null) {
          onTap!();
        } else if (enableFullScreen) {
          _openFullScreenImage(context);
        }
      },
      child: Container(
        height: 200, // 이미지 높이 고정
        width: width ?? double.infinity,
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
              if (enableFullScreen)
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

  // 이미지 위젯
  Widget _buildImage() {
    if (imageFile != null) {
      return Image.file(
        imageFile!,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildEmptyImageWidget();
        },
        // 이미지 로딩 중에도 기본 이미지 표시
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return child;
          } else {
            // 로딩 인디케이터 대신 빈 이미지만 표시
            return _buildEmptyImageWidget();
          }
        },
      );
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      if (imageUrl!.startsWith('http')) {
        // 네트워크 이미지 처리
        return Image.network(
          imageUrl!,
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildEmptyImageWidget();
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            // 로딩 인디케이터 제거하고 빈 이미지만 표시
            return _buildEmptyImageWidget();
          },
        );
      } else {
        // 로컬 이미지 경로 처리
        return FutureBuilder<File?>(
          future: _getImageFile(imageUrl!),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              // 로딩 인디케이터 제거하고 빈 이미지만 표시
              return _buildEmptyImageWidget();
            } else if (snapshot.hasData && snapshot.data != null) {
              return Image.file(
                snapshot.data!,
                height: height,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildEmptyImageWidget();
                },
              );
            } else {
              return _buildEmptyImageWidget();
            }
          },
        );
      }
    } else {
      return _buildEmptyImageWidget();
    }
  }

  // 이미지 URL을 파일로 변환
  Future<File?> _getImageFile(String imageUrl) async {
    try {
      if (imageUrl.startsWith('images/')) {
        // 로컬 파일 경로 가져오기
        final directory = await getApplicationDocumentsDirectory();
        final filePath = '${directory.path}/$imageUrl';
        final file = File(filePath);
        
        if (await file.exists()) {
          return file;
        }
      }
      return null;
    } catch (e) {
      debugPrint('이미지 파일 로드 오류: $e');
      return null;
    }
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

  // 에러 위젯
  Widget _buildErrorWidget() {
    return Container(
      width: double.infinity,
      height: height,
      color: Colors.grey[200],
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('이미지를 불러올 수 없습니다.'),
          ],
        ),
      ),
    );
  }

  // 스타일에 따른 마진 설정
  EdgeInsets _getContainerMargin() {
    switch (style) {
      case ImageContainerStyle.minimal:
        return EdgeInsets.zero;
      case ImageContainerStyle.noteDetail:
        return const EdgeInsets.only(top: 16);
      case ImageContainerStyle.standard:
      default:
        return const EdgeInsets.symmetric(vertical: 8);
    }
  }

  // 전체 화면 이미지 뷰어 열기
  void _openFullScreenImage(BuildContext context) {
    if (imageFile == null && imageUrl == null) return;

    if (imageFile != null && onFullScreenTap != null) {
      onFullScreenTap!(imageFile!);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FullImageScreen(
          imageFile: imageFile,
          imageUrl: imageUrl,
          title: title.isNotEmpty ? title : '이미지 보기',
        ),
      ),
    );
  }
}
