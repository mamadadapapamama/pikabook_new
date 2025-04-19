import 'dart:io';
import 'package:flutter/material.dart';

import '../../../../models/page.dart' as page_model;
import '../../../../services/image/image_service.dart';

/// 이미지 로딩 로직을 담당하는 클래스
/// 
/// 이 클래스는 이미지 로딩, 캐싱, 관리 등의 로직을 처리합니다.

class ImageLoadingManager {
  final ImageService imageService;
  final Function(File?) onImageLoaded;
  
  // 상태 변수
  File? _currentImageFile;
  bool _isLoading = false;
  
  ImageLoadingManager({
    required this.imageService,
    required this.onImageLoaded,
  });
  
  // 현재 이미지 파일 가져오기
  File? get currentImageFile => _currentImageFile;
  
  // 로딩 상태 가져오기
  bool get isLoading => _isLoading;
  
  // 페이지 이미지 로드
  Future<void> loadImageForPage(page_model.Page? page) async {
    if (page == null || page.imageUrl == null || page.imageUrl!.isEmpty) {
      _updateImageFile(null);
      return;
    }
    
    _isLoading = true;
    
    try {
      debugPrint('페이지 이미지 로드 시작: ${page.imageUrl}');
      
      // 이미지 서비스를 통해 이미지 가져오기
      final imageFile = await imageService.getImageFile(page.imageUrl);
      
      // 이미지 파일이 없거나 빈 파일인 경우 다시 다운로드 시도
      if (imageFile == null || !await imageFile.exists() || await imageFile.length() == 0) {
        debugPrint('이미지 파일이 존재하지 않거나 비어있습니다. 다시 다운로드 시도');
        
        // Firebase Storage에서 직접 다운로드 시도
        final redownloadedFile = await imageService.downloadImage(page.imageUrl!);
        _updateImageFile(redownloadedFile);
        
        return;
      }
      
      _updateImageFile(imageFile);
      debugPrint('이미지 로드 완료: ${page.imageUrl}');
      
    } catch (e) {
      debugPrint('페이지 이미지 로드 중 오류: $e');
      _updateImageFile(null);
    } finally {
      _isLoading = false;
    }
  }
  
  // 이미지 캐시 정리
  Future<void> clearCache() async {
    await imageService.clearImageCache();
  }
  
  // 이미지 파일 업데이트
  void _updateImageFile(File? file) {
    _currentImageFile = file;
    onImageLoaded(file);
  }
  
  // 리소스 정리
  Future<void> dispose() async {
    // 필요한 리소스 정리
    _currentImageFile = null;
  }
} 