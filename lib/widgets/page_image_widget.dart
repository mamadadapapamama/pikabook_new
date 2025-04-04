import 'package:flutter/material.dart';
import 'dart:io';
import '../views/screens/full_image_screen.dart';
import '../widgets/dot_loading_indicator.dart';
import 'package:path_provider/path_provider.dart';

/// 페이지 이미지를 표시하는 위젯
class PageImageWidget extends StatelessWidget {
  final File? imageFile;
  final String? imageUrl;
  final String? pageId;
  final bool isLoading;

  const PageImageWidget({
    super.key,
    required this.imageFile,
    this.imageUrl,
    this.pageId,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null && imageFile == null) {
      return const SizedBox.shrink();
    }

    return Center(
      child: isLoading
          ? _buildLoadingIndicator()
          : GestureDetector(
              onTap: () => _openFullScreenImage(context),
              child: Hero(
                tag: 'image_${pageId ?? "unknown"}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      _buildImage(),
                      // 확대 아이콘 오버레이
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(128),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(
                            Icons.zoom_in,
                            color: Colors.white,
                            size: 16,
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

  // 로딩 인디케이터 위젯
  Widget _buildLoadingIndicator() {
    return const Center(
      child: DotLoadingIndicator(
        message: '이미지 로딩 중...',
        dotColor: Color(0xFFFFD53C),
      ),
    );
  }

  // 이미지 위젯
  Widget _buildImage() {
    if (imageFile != null) {
      return Image.file(
        imageFile!,
        height: 200,
        width: double.infinity,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return _buildErrorWidget();
        },
      );
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      return FutureBuilder<File?>(
        future: _getImageFile(imageUrl!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingIndicator();
          } else if (snapshot.hasData && snapshot.data != null) {
            return Image.file(
              snapshot.data!,
              height: 200,
              width: double.infinity,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return _buildErrorWidget();
              },
            );
          } else {
            return _buildErrorWidget();
          }
        },
      );
    } else {
      return Container(
        width: double.infinity,
        height: 150,
        color: Colors.grey[200],
        child: const Center(
          child: Text('이미지를 찾을 수 없습니다.'),
        ),
      );
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
      print('이미지 파일 로드 오류: $e');
      return null;
    }
  }

  // 에러 위젯
  Widget _buildErrorWidget() {
    return Container(
      width: double.infinity,
      height: 150,
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

  // 전체 화면 이미지 뷰어 열기
  void _openFullScreenImage(BuildContext context) {
    if (imageFile == null && imageUrl == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FullImageScreen(
          imageFile: imageFile,
          imageUrl: imageUrl,
          title: '이미지 보기',
        ),
      ),
    );
  }
}
