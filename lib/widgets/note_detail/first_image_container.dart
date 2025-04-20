import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/page.dart' as page_model;
import '../../theme/tokens/color_tokens.dart';

class FirstImageContainer extends StatelessWidget {
  final page_model.Page? currentPage;
  final File? currentImageFile;
  final String noteTitle;
  final Function(File) onFullScreenTap;

  const FirstImageContainer({
    Key? key,
    required this.currentPage,
    required this.currentImageFile,
    required this.noteTitle,
    required this.onFullScreenTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 이미지가 없거나 페이지가 처리 중인 경우
    if (currentImageFile == null || currentPage == null || 
        currentPage!.originalText == '___PROCESSING___') {
      return _buildLoadingImageContainer();
    }

    // 이미지가 있는 경우 이미지 표시
    return _buildImageContainer(context);
  }

  // 로딩 중 이미지 컨테이너
  Widget _buildLoadingImageContainer() {
    return Container(
      height: 200,
      margin: const EdgeInsets.only(top: 16, left: 16, right: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          )
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(ColorTokens.primary),
              strokeWidth: 2,
            ),
            const SizedBox(height: 16),
            Text(
              '이미지 준비중...',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 이미지 컨테이너
  Widget _buildImageContainer(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (currentImageFile != null) {
          onFullScreenTap(currentImageFile!);
        }
      },
      child: Container(
        height: 200,
        margin: const EdgeInsets.only(top: 16, left: 16, right: 16),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 2),
            )
          ],
        ),
        child: Stack(
          children: [
            // 이미지
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                currentImageFile!,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.broken_image,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '이미지를 불러올 수 없습니다',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            
            // 오버레이 (확대 아이콘)
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.fullscreen,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
            
            // 이미지 정보 오버레이 (선택 사항)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.6),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                child: Text(
                  noteTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
