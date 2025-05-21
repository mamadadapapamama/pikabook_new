import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../common/usage_limit_service.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../../../views/screens/full_image_screen.dart';
import 'image_cache_service.dart';
import 'image_picker_service.dart';
import 'image_compression.dart';

/// 이미지 관리 서비스
/// 이미지 저장, 로드, 압축 등의 기능을 제공합니다.
/// 메모리 관리와 최적화에 중점을 둠
class ImageService {
  // 싱글톤 패턴 구현
  static final ImageService _instance = ImageService._internal();
  factory ImageService() => _instance;

  // Firebase Storage 경로 상수
  static const String _storageBasePath = 'images';
  static const String _userImagesPath = 'users';
  static const int _maxRetryCount = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  // 서비스 인스턴스
  final UsageLimitService _usageLimitService = UsageLimitService();
  final ImageCacheService _imageCacheService = ImageCacheService();
  final ImagePickerService _pickerService = ImagePickerService();
  final ImageCompression _compression = ImageCompression();
  final FirebaseStorage _storage = FirebaseStorage.instance;
  
  // 기본값 및 상수
  static const String _fallbackImagePath = 'images/fallback_image.jpg';
  
  ImageService._internal() {
    debugPrint('🖼️ ImageService: 생성자 호출됨');
  }

  // 현재 사용자 ID 가져오기
  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  // 클래스 내부에서 모든 메서드에서 공유할 실패한 다운로드 경로 목록
  static final Set<String> _failedDownloadPaths = <String>{};

  // Firebase Storage에 업로드된 이미지 URL 캐시
  final Map<String, String> _fileUrlCache = {};

  /// 앱 내부 저장소 경로를 반환합니다.
  Future<String> get _localPath async {
    final appDir = await getApplicationDocumentsDirectory();
    return appDir.path;
  }

  /// 이미지 선택 (갤러리)
  Future<File?> pickImage({ImageSource source = ImageSource.gallery}) async {
    return source == ImageSource.gallery 
        ? (await _pickerService.pickGalleryImages()).firstOrNull
        : await _pickerService.takeCameraPhoto();
  }
  
  /// 이미지 선택 (갤러리 또는 카메라)
  Future<List<File>> pickMultipleImages() async {
    return _pickerService.pickGalleryImages();
  }

  /// Firebase Storage 경로 생성
  String _getStoragePath(String relativePath) {
    if (relativePath.startsWith('$_userImagesPath/')) {
      return relativePath;
    }
    return _currentUserId != null 
        ? '$_userImagesPath/$_currentUserId/$_storageBasePath/$relativePath'
        : '$_storageBasePath/$relativePath';
  }

  /// 이미지 파일 가져오기 (재시도 로직 포함)
  Future<File?> getImageFile(String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) return null;

    // 1. 로컬 파일 확인
    final file = File(imagePath);
    if (await file.exists()) return file;

    // 2. Firebase Storage에서 다운로드
    if (imagePath.startsWith('gs://')) {
      return _downloadWithRetry(imagePath, _downloadFromFirebase);
    }

    // 3. URL에서 다운로드
    if (imagePath.startsWith('http')) {
      return _downloadWithRetry(imagePath, _downloadFromUrl);
    }

    return null;
  }

  Future<File?> _downloadWithRetry(
    String path,
    Future<File?> Function(String) downloadFn,
  ) async {
    int retryCount = 0;
    while (retryCount < _maxRetryCount) {
      try {
        final file = await downloadFn(path);
        if (file != null && await file.exists()) {
          return file;
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('다운로드 실패 (${retryCount + 1}/$_maxRetryCount): $e');
        }
      }

      retryCount++;
      if (retryCount < _maxRetryCount) {
        await Future.delayed(_retryDelay * retryCount);
      }
    }

    if (kDebugMode) {
      debugPrint('다운로드 최대 재시도 횟수 초과: $path');
    }
    return null;
  }

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
      if (kDebugMode) {
        debugPrint('Firebase 다운로드 실패: $e');
      }
      return null;
    }
  }

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
      if (kDebugMode) {
        debugPrint('URL 다운로드 실패: $e');
      }
      return null;
    }
  }

  /// 이미지 바이트 가져오기 (메모리에 로드)
  Future<Uint8List?> getImageBytes(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) return null;
    
    try {
      // 1. 캐시 확인
      final cachedBytes = _imageCacheService.getFromCache(relativePath);
      if (cachedBytes != null) return cachedBytes;
      
      // 2. 파일에서 로드
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

  /// 이미지 업로드 (파일 경로 또는 파일 객체)
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
      
      final canStoreFile = await _checkStorageLimit(originalFile);
      if (!canStoreFile) {
        throw Exception('저장 공간 제한을 초과했습니다');
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
        await _uploadToFirebaseStorageIfNotExists(File(targetPath), relativePath);
      } catch (e) {
        debugPrint('Firebase 업로드 실패: $e');
      }
      
      // 저장 공간 사용량 추적
      final compressedFile = File(targetPath);
      await _trackStorageUsage(compressedFile);

      return relativePath;
    } catch (e) {
      debugPrint('이미지 저장 실패: $e');
      throw Exception('이미지 저장 실패: $e');
    }
  }
  
  /// 스토리지 용량 제한 확인
  Future<bool> _checkStorageLimit(File imageFile) async {
    try {
      final fileSize = await imageFile.length();
      final currentStorageUsage = await _usageLimitService.getUserCurrentStorageSize();
      final currentLimits = await _usageLimitService.getCurrentLimits();
      final storageLimitBytes = currentLimits['storageBytes'] ?? (50 * 1024 * 1024);
      return true; // 현재 작업은 완료하고 다음 작업부터 제한 메시지 표시
    } catch (e) {
      debugPrint('스토리지 제한 확인 실패: $e');
      return true;
    }
  }
  
  /// 파일 크기를 포맷팅
  String _formatSize(num bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  
  /// 원본 파일을 타겟 경로에 복사 (Helper)
  Future<void> _copyOriginalToTarget(File originalFile, String targetPath) async {
    try {
      await originalFile.copy(targetPath);
    } catch (e) {
      debugPrint('원본 파일 복사 중 오류: $e');
      throw Exception('원본 파일 복사 실패: $e');
    }
  }
  
  /// Firebase Storage에 파일 업로드 (존재하지 않는 경우에만)
  Future<void> _uploadToFirebaseStorageIfNotExists(File file, String relativePath) async {
    if (_currentUserId == null) return;

    try {
      final storageRef = _storage.ref().child(relativePath);
      try {
        await storageRef.getDownloadURL();
        return;
      } catch (e) {
        // 파일이 존재하지 않는 경우 계속 진행
      }
      
      await storageRef.putFile(file);
    } catch (e) {
      throw Exception('Firebase Storage 업로드 실패: $e');
    }
  }
  
  /// 저장 공간 사용량 추적
  Future<bool> _trackStorageUsage(File file) async {
    try {
      final actualSize = await file.length();
      await _usageLimitService.addStorageUsage(actualSize, allowOverLimit: true);
      return true;
    } catch (e) {
      debugPrint('저장 공간 사용량 추적 실패: $e');
      return false;
    }
  }
  
  /// 이미지 존재 여부 확인
  Future<bool> imageExists(String? imageUrl) async {
    if (imageUrl == null || imageUrl.isEmpty) return false;
    
    try {
      if (imageUrl.contains('firebasestorage.googleapis.com')) {
        final uri = Uri.parse(imageUrl);
        final pathSegments = uri.pathSegments;
        
        if (pathSegments.length > 2 && pathSegments.contains('o')) {
          final encodedPath = pathSegments[pathSegments.indexOf('o') + 1];
          String relativePath = Uri.decodeComponent(encodedPath);
          
          if (relativePath.startsWith('/')) {
            relativePath = relativePath.substring(1);
          }
          
          return _imageExists(relativePath);
        }
        
        final response = await http.head(Uri.parse(imageUrl));
        return response.statusCode == 200;
      }
      
      final response = await http.head(Uri.parse(imageUrl));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('이미지 존재 확인 실패: $e');
      return false;
    }
  }
  
  /// 이미지 URL이 Firebase Storage에 존재하는지 확인
  Future<bool> _imageExists(String relativePath) async {
    try {
      final ref = _storage.ref().child(relativePath);
      await ref.getDownloadURL();
      return true;
    } catch (e) {
      if (e is FirebaseException && e.code == 'object-not-found') return false;
      debugPrint('이미지 존재 확인 실패: $e');
      return false;
    }
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

  /// 이미지 캐시 정리
  Future<void> clearImageCache() async {
    await _imageCacheService.clearImageCache();
  }

  /// 임시 파일 정리
  Future<void> cleanupTempFiles() async {
    await _imageCacheService.cleanupTempFiles();
  }

  // 현재 보고 있는 이미지 파일 관리
  File? _currentImageFile;
  
  // 현재 이미지 파일 가져오기 - 안전 장치 추가
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
  
  // 현재 이미지 설정 - 안전 장치 추가
  void setCurrentImageFile(File? file) {
    try {
      if (file != null && !file.existsSync()) return;
      _currentImageFile = file;
    } catch (e) {
      _currentImageFile = null;
    }
  }
  
  // 페이지 이미지 로드 - 안전 장치 추가
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
}