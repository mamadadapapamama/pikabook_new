import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../../views/screens/full_image_screen.dart';
import 'image_cache_service.dart';
import 'image_picker_service.dart';
import 'image_compression.dart';

/// 이미지 관리 서비스
/// 이미지 저장, 로드, 압축 등의 핵심 기능만 제공
class ImageService {
  // 싱글톤 패턴
  static final ImageService _instance = ImageService._internal();
  factory ImageService() => _instance;
  ImageService._internal();

  // 상수
  static const int _maxRetryCount = 3;
  static const Duration _retryDelay = Duration(seconds: 2);
  static const String _fallbackImagePath = 'images/fallback_image.jpg';

  // 서비스 인스턴스
  final ImageCacheService _imageCacheService = ImageCacheService();
  final ImagePickerService _pickerService = ImagePickerService();
  final ImageCompression _compression = ImageCompression();
  final FirebaseStorage _storage = FirebaseStorage.instance;
  
  // 실패한 다운로드 경로 추적
  static final Set<String> _failedDownloadPaths = <String>{};
  
  // 현재 보고 있는 이미지 파일
  File? _currentImageFile;

  // 현재 사용자 ID
  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  // 앱 내부 저장소 경로
  Future<String> get _localPath async {
    final appDir = await getApplicationDocumentsDirectory();
    return appDir.path;
  }

  /// 이미지 선택
  Future<File?> pickImage({ImageSource source = ImageSource.gallery}) async {
    return source == ImageSource.gallery 
        ? (await _pickerService.pickGalleryImages()).firstOrNull
        : await _pickerService.takeCameraPhoto();
  }
  
  /// 다중 이미지 선택
  Future<List<File>> pickMultipleImages() async {
    return _pickerService.pickGalleryImages();
  }

  /// 이미지 파일 가져오기
  Future<File?> getImageFile(String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) return null;

    // 1. 절대 경로 확인
    File file = File(imagePath);
    if (await file.exists()) return file;

    // 2. 상대 경로 변환
    if (imagePath.startsWith('images/')) {
      final appDir = await getApplicationDocumentsDirectory();
      final absolutePath = '${appDir.path}/$imagePath';
      file = File(absolutePath);
      
      if (await file.exists()) return file;
    }

    // 3. Firebase Storage 다운로드
    if (imagePath.startsWith('gs://')) {
      return _downloadWithRetry(imagePath, _downloadFromFirebase);
    }

    // 4. URL 다운로드
    if (imagePath.startsWith('http')) {
      return _downloadWithRetry(imagePath, _downloadFromUrl);
    }

    return null;
  }

  /// 재시도 로직이 포함된 다운로드
  Future<File?> _downloadWithRetry(
    String path,
    Future<File?> Function(String) downloadFn,
  ) async {
    for (int i = 0; i < _maxRetryCount; i++) {
      try {
        final file = await downloadFn(path);
        if (file != null && await file.exists()) return file;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('다운로드 실패 (${i + 1}/$_maxRetryCount): $e');
        }
      }

      if (i < _maxRetryCount - 1) {
        await Future.delayed(_retryDelay * (i + 1));
      }
    }
    return null;
  }

  /// Firebase Storage에서 다운로드
  Future<File?> _downloadFromFirebase(String path) async {
    try {
      final storageRef = _storage.ref().child(path);
      final appDir = await getApplicationDocumentsDirectory();
      final filePath = '${appDir.path}/${path.split('/').last}';
      final file = File(filePath);
      
      await storageRef.writeToFile(file);
      
      if (await file.exists() && await file.length() > 0) {
        final bytes = await file.readAsBytes();
        _imageCacheService.addToCache(path, bytes);
        return file;
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('Firebase 다운로드 실패: $e');
      return null;
    }
  }

  /// URL에서 다운로드
  Future<File?> _downloadFromUrl(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final appDir = await getApplicationDocumentsDirectory();
        final filePath = '${appDir.path}/${url.split('/').last}';
        final file = File(filePath);
        
        await file.writeAsBytes(response.bodyBytes);
        _imageCacheService.addToCache(url, response.bodyBytes);
        return file;
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('URL 다운로드 실패: $e');
      return null;
    }
  }

  /// 이미지 바이트 가져오기
  Future<Uint8List?> getImageBytes(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return null;
    
    try {
      // 캐시 확인
      final cachedBytes = _imageCacheService.getFromCache(relativePath);
      if (cachedBytes != null) return cachedBytes;
      
      // 파일에서 로드
      final file = await getImageFile(relativePath);
      if (file != null && await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) {
          _imageCacheService.addToCache(relativePath, bytes);
          return bytes;
        }
      }
      return null;
    } catch (e) {
      debugPrint('이미지 바이트 가져오기 실패: $e');
      return null;
    }
  }

  /// 이미지 업로드
  Future<String> uploadImage(dynamic image, {bool forThumbnail = false}) async {
    try {
      if (image == null) throw Exception('이미지가 null입니다');
      
      String targetPath;
      if (image is String) {
        if (!await File(image).exists()) {
          throw Exception('파일이 존재하지 않습니다: $image');
        }
        targetPath = await saveAndOptimizeImage(image, quality: forThumbnail ? 70 : 85);
      } else if (image is File) {
        if (!await image.exists()) {
          throw Exception('파일이 존재하지 않습니다: ${image.path}');
        }
        targetPath = await saveAndOptimizeImage(image.path, quality: forThumbnail ? 70 : 85);
      } else {
        throw Exception('지원되지 않는 이미지 형식입니다: ${image.runtimeType}');
      }
      
      return targetPath;
    } catch (e) {
      debugPrint('이미지 업로드 실패: $e');
      return _fallbackImagePath;
    }
  }

  /// 이미지 저장 및 최적화
  Future<String> saveAndOptimizeImage(String imagePath, {int quality = 85}) async {
    try {
      final originalFile = File(imagePath);
      if (!await originalFile.exists()) {
        throw Exception('원본 이미지 파일을 찾을 수 없습니다: $imagePath');
      }

      // 저장 경로 설정
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'img_$timestamp${path.extension(imagePath)}';
      final userId = _currentUserId ?? 'anonymous';
      final relativePath = path.join('images', userId, filename);
      final targetPath = path.join(await _localPath, relativePath);
      
      // 디렉토리 생성
      final directory = Directory(path.dirname(targetPath));
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      // 이미지 압축 및 최적화
      final result = await _compression.compressAndOptimizeImage(
        imagePath,
        targetPath: targetPath,
        quality: quality
      );

      if (!result.success) {
        throw Exception(result.error ?? '압축 실패');
      }

      // Firebase Storage에 업로드
      try {
        await _uploadToFirebaseStorage(File(targetPath), relativePath);
      } catch (e) {
        debugPrint('Firebase 업로드 실패: $e');
      }

      return relativePath;
    } catch (e) {
      debugPrint('이미지 저장 실패: $e');
      throw Exception('이미지 저장 실패: $e');
    }
  }

  /// Firebase Storage에 업로드
  Future<void> _uploadToFirebaseStorage(File file, String relativePath) async {
    if (_currentUserId == null) return;

    try {
      final storageRef = _storage.ref().child(relativePath);
      
      // 파일이 이미 존재하는지 확인
      try {
        await storageRef.getDownloadURL();
        return; // 이미 존재하면 업로드 스킵
      } catch (e) {
        // 파일이 존재하지 않는 경우 계속 진행
      }
      
      await storageRef.putFile(file);
    } catch (e) {
      throw Exception('Firebase Storage 업로드 실패: $e');
    }
  }

  /// 이미지 URL 가져오기
  Future<String> getImageUrl(String relativePath) async {
    try {
      final storageRef = _storage.ref().child(relativePath);
      return await storageRef.getDownloadURL();
    } catch (e) {
      debugPrint('이미지 URL 가져오기 실패: $e');
      return relativePath;
    }
  }

  /// 현재 이미지 파일 관리
  File? getCurrentImageFile() {
    try {
      if (_currentImageFile != null && !_currentImageFile!.existsSync()) {
        _currentImageFile = null;
      }
      return _currentImageFile;
    } catch (e) {
      _currentImageFile = null;
      return null;
    }
  }

  void setCurrentImageFile(File? file) {
    try {
      if (file != null && !file.existsSync()) return;
      _currentImageFile = file;
    } catch (e) {
      _currentImageFile = null;
    }
  }

  /// 페이지 이미지 로드
  Future<File?> loadPageImage(dynamic pageOrUrl) async {
    try {
      String? imageUrl;
      
      if (pageOrUrl is String) {
        imageUrl = pageOrUrl;
      } else if (pageOrUrl != null && pageOrUrl.imageUrl != null) {
        imageUrl = pageOrUrl.imageUrl;
      }
      
      if (imageUrl == null || imageUrl.isEmpty) {
        _currentImageFile = null;
        return null;
      }
      
      if (_failedDownloadPaths.contains(imageUrl)) {
        _currentImageFile = null;
        return null;
      }
      
      final imageFile = await getImageFile(imageUrl);
      
      if (imageFile != null && imageFile.existsSync() && imageFile.lengthSync() > 0) {
        _currentImageFile = imageFile;
        return imageFile;
      }
      
      _failedDownloadPaths.add(imageUrl);
      _currentImageFile = null;
      return null;
    } catch (e) {
      _currentImageFile = null;
      return null;
    }
  }

  /// 이미지 확대 화면 표시
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

  /// 노트 삭제 시 연관된 이미지들 삭제
  Future<void> deleteNoteImages(String noteId) async {
    if (noteId.isEmpty) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final noteImagesPath = path.join(appDir.path, 'images', noteId);
      final noteDir = Directory(noteImagesPath);
      
      if (await noteDir.exists()) {
        // 로컬 이미지 파일 삭제
        await noteDir.delete(recursive: true);
        
        // Firebase Storage에서 이미지 삭제
        if (_currentUserId != null) {
          final storagePath = 'users/$_currentUserId/images/$noteId';
          final storageRef = _storage.ref().child(storagePath);
          
          try {
            final result = await storageRef.listAll();
            for (var item in result.items) {
              await item.delete();
            }
          } catch (e) {
            debugPrint('Firebase 이미지 삭제 실패: $e');
          }
        }
        
        // 캐시에서 관련 이미지 제거
        _imageCacheService.clearCache(partial: true);
      }
    } catch (e) {
      debugPrint('노트 이미지 삭제 실패: $e');
    }
  }

  /// 캐시 정리
  Future<void> clearImageCache() async {
    await _imageCacheService.clearImageCache();
  }

  /// 임시 파일 정리
  Future<void> cleanupTempFiles() async {
    await _imageCacheService.cleanupTempFiles();
  }
}