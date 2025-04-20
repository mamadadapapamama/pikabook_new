import 'dart:io';
import 'package:flutter/material.dart';
import '../services/image_service.dart';
import '../models/page.dart' as page_model;
import '../views/screens/full_image_screen.dart';

class NoteDetailImageHandler {
  final ImageService _imageService = ImageService();
  File? _currentImageFile;
  
  // 현재 이미지 파일 가져오기
  File? getCurrentImageFile() {
    return _currentImageFile;
  }
  
  // 현재 이미지 설정
  void setCurrentImageFile(File? file) {
    _currentImageFile = file;
  }
  
  // 페이지 이미지 로드
  Future<File?> loadPageImage(page_model.Page page) async {
    if (page.imageUrl == null || page.imageUrl!.isEmpty) {
      return null;
    }
    
    final imageFile = await _imageService.getImageFile(page.imageUrl);
    _currentImageFile = imageFile;
    return imageFile;
  }
  
  // 이미지 확대 화면 표시
  void showFullImage(BuildContext context, File imageFile, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullImageScreen(
          imageFile: imageFile,
          title: title,
        ),
      ),
    );
  }
  
  // 이미지 존재 확인
  Future<bool> imageExists(File? imageFile, String? imageUrl) async {
    if (imageFile != null) return true;
    if (imageUrl == null) return false;
    return await _imageService.imageExists(imageUrl);
  }
  
  // 이미지 캐시 정리
  Future<void> clearImageCache() async {
    await _imageService.clearImageCache();
    // 메모리 최적화 힌트
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}
