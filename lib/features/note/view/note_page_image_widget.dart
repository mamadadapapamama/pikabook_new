import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/widgets/dot_loading_indicator.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/services/media/image_service.dart';

/// 노트 페이지 이미지를 표시하는 전용 위젯
/// 다양한 이미지 소스(로컬 파일, 상대 경로, URL)를 처리합니다.
class NotePageImageWidget extends StatelessWidget {
  final File? imageFile;
  final String? imageUrl;
  final VoidCallback? onTap;
  final BoxFit fit;
  final double? width;
  final double? height;

  const NotePageImageWidget({
    Key? key,
    this.imageFile,
    this.imageUrl,
    this.onTap,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width ?? double.infinity,
        height: height ?? double.infinity,
        child: _buildImageContent(),
      ),
    );
  }

  Widget _buildImageContent() {
    // 1. 로컬 파일이 있는 경우 (새로 선택된 이미지)
    if (imageFile != null) {
      return _buildFileImage(imageFile!);
    }
    
    // 2. URL이 있는 경우 (기존 저장된 이미지)
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      // 로컬 파일 경로인 경우 (절대 경로)
      if (imageUrl!.startsWith('/')) {
        return _buildFileImage(File(imageUrl!));
      }
      
      // 상대 경로인 경우 (샘플 데이터 등)
      if (imageUrl!.startsWith('images/')) {
        return _buildRelativePathImage(imageUrl!);
      }
      
      // HTTP URL인 경우
      if (imageUrl!.startsWith('http')) {
        return _buildNetworkImage(imageUrl!);
      }
      
      // assets 경로인 경우
      if (imageUrl!.startsWith('assets/')) {
        return _buildAssetImage(imageUrl!);
      }
    }
    
    // 3. 이미지가 없는 경우
    return _buildEmptyImageWidget();
  }

  /// 로컬 파일 이미지
  Widget _buildFileImage(File file) {
    return Image.file(
      file,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        if (kDebugMode) {
          debugPrint('🖼️ 로컬 파일 이미지 로드 오류: $error');
        }
        return _buildEmptyImageWidget();
      },
    );
  }

  /// 상대 경로 이미지 (ImageService 사용)
  Widget _buildRelativePathImage(String relativePath) {
    return FutureBuilder<File?>(
      future: ImageService().getImageFile(relativePath),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingWidget();
        }
        
        if (snapshot.hasData && snapshot.data != null) {
          return _buildFileImage(snapshot.data!);
        }
        
        // 실패한 경우
        if (kDebugMode) {
          debugPrint('🖼️ 상대 경로 이미지 로드 실패: $relativePath');
        }
        return _buildEmptyImageWidget();
      },
    );
  }

  /// 네트워크 이미지 (CachedNetworkImage 사용)
  Widget _buildNetworkImage(String url) {
    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      placeholder: (context, url) => _buildLoadingWidget(),
      errorWidget: (context, url, error) {
        if (kDebugMode) {
          debugPrint('🖼️ 네트워크 이미지 로드 오류: $error');
        }
        return _buildEmptyImageWidget();
      },
    );
  }

  /// Assets 이미지
  Widget _buildAssetImage(String assetPath) {
    return Image.asset(
      assetPath,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) {
        if (kDebugMode) {
          debugPrint('🖼️ Assets 이미지 로드 오류: $error');
        }
        return _buildEmptyImageWidget();
      },
    );
  }

  /// 로딩 위젯
  Widget _buildLoadingWidget() {
    return Center(
      child: DotLoadingIndicator(
        message: '이미지 로딩 중...',
        dotColor: ColorTokens.primary,
      ),
    );
  }

  /// 빈 이미지 위젯 (기본 플레이스홀더)
  Widget _buildEmptyImageWidget() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[100],
      ),
      child: Image.asset(
        'assets/images/image_empty.png',
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          // 기본 이미지도 로드 실패하면 단순한 컨테이너 표시
          return Container(
            color: Colors.grey[200],
            child: Icon(
              Icons.image_not_supported,
              color: Colors.grey[400],
              size: 48,
            ),
          );
        },
      ),
    );
  }
} 