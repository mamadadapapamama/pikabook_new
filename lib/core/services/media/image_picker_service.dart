import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';

class ImagePickerService {
  static final ImagePickerService _instance = ImagePickerService._internal();
  factory ImagePickerService() => _instance;

  final ImagePicker _picker = ImagePicker();
  bool _isProcessing = false;

  ImagePickerService._internal();

  bool get isProcessing => _isProcessing;

  void setProcessing(bool value) {
    _isProcessing = value;
  }

  /// 갤러리에서 이미지 선택
  Future<List<File>> pickGalleryImages() async {
    if (_isProcessing) {
      debugPrint('이미지 선택 처리가 이미 진행 중입니다.');
      return [];
    }

    _isProcessing = true;
    List<XFile>? selectedImages;

    try {
      selectedImages = await _picker.pickMultiImage(
        requestFullMetadata: false,
      );

      if (selectedImages == null || selectedImages.isEmpty) {
        return [];
      }

      return selectedImages
          .map((xFile) => File(xFile.path))
          .where((file) => file.existsSync() && file.lengthSync() > 0)
          .toList();
    } catch (e) {
      debugPrint('이미지 선택 중 오류: $e');
      return [];
    } finally {
      _isProcessing = false;
    }
  }

  /// 카메라로 사진 촬영
  Future<File?> takeCameraPhoto() async {
    if (_isProcessing) {
      debugPrint('카메라 촬영 처리가 이미 진행 중입니다.');
      return null;
    }

    _isProcessing = true;
    File? imageFile;

    try {
      // iOS 시뮬레이터 체크
      if (Platform.isIOS) {
        try {
          final isSimulator = await File('/Applications').exists();
          if (isSimulator) {
            throw Exception('iOS 시뮬레이터에서는 카메라를 사용할 수 없습니다.');
          }
        } catch (e) {
          // 시뮬레이터 체크 실패 시 계속 진행
        }
      }

      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        requestFullMetadata: false,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 80,
      );

      if (photo != null) {
        imageFile = File(photo.path);
        if (!imageFile.existsSync() || imageFile.lengthSync() == 0) {
          imageFile = null;
        }
      }
    } catch (e) {
      debugPrint('카메라 촬영 중 오류: $e');
      imageFile = null;
    } finally {
      _isProcessing = false;
    }

    return imageFile;
  }
}
