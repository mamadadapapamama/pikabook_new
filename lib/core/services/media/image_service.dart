import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../common/usage_limit_service.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import '../../../views/screens/full_image_screen.dart';
import 'image_cache_service.dart';

// compute 함수에 전달하기 위한 최상위 레벨 함수
Future<_CompressionResult> _compressImageIsolate(Map<String, dynamic> params) async {
  final Uint8List imageBytes = params['imageBytes'];
  final String targetPath = params['targetPath'];
  final int maxDimension = params['maxDimension'];
  final int quality = params['quality'];

  try {
    img.Image? image = img.decodeImage(imageBytes);
    if (image == null) {
      return _CompressionResult.failure('이미지 디코딩 실패');
    }

    // 리사이징
    if (image.width > maxDimension || image.height > maxDimension) {
      double ratio = (image.width > image.height)
          ? maxDimension / image.width
          : maxDimension / image.height;
      image = img.copyResize(
        image,
        width: (image.width * ratio).round(),
        height: (image.height * ratio).round(),
        interpolation: img.Interpolation.average,
      );
    }

    // 압축 시도 (JPG)
    try {
      final jpegBytes = img.encodeJpg(image, quality: quality);
      await File(targetPath).writeAsBytes(jpegBytes);
      return _CompressionResult.success();
    } catch (jpgError) {
      debugPrint('JPG 인코딩 실패 (Isolate): $jpgError');
      // PNG 시도
      try {
        final pngBytes = img.encodePng(image);
        await File(targetPath).writeAsBytes(pngBytes);
        return _CompressionResult.success();
      } catch (pngError) {
        debugPrint('PNG 인코딩 실패 (Isolate): $pngError');
        return _CompressionResult.failure('이미지 압축 실패 (JPG/PNG)');
      }
    }
  } catch (e) {
    return _CompressionResult.failure('이미지 처리 중 예외 (Isolate): $e');
  }
}

/// 압축된 결과를 나타내는 클래스 (내부 사용)
class _CompressionResult {
  final bool success;
  final String? error;
  
  _CompressionResult({required this.success, this.error});
  
  factory _CompressionResult.success() => _CompressionResult(success: true);
  factory _CompressionResult.failure(String error) => _CompressionResult(success: false, error: error);
}

/// 이미지 관리 서비스
/// 이미지 저장, 로드, 압축 등의 기능을 제공합니다.
/// 메모리 관리와 최적화에 중점을 둠

class ImageService {
  // 싱글톤 패턴 구현
  static final ImageService _instance = ImageService._internal();
  factory ImageService() => _instance;

  // 통합 캐시 서비스 참조 - 현재 사용되지 않음 (제거)
  final UsageLimitService _usageLimitService = UsageLimitService();
  
  // 이미지 캐시 서비스 추가
  final ImageCacheService _imageCacheService = ImageCacheService();
  
  // Firebase Storage 참조
  final FirebaseStorage _storage = FirebaseStorage.instance;
  
  // 기본값 및 상수
  static const String _fallbackImagePath = 'images/fallback_image.jpg';
  static const int _maxImageDimension = 1200; // 최대 이미지 크기 (픽셀)
  static const int _defaultJpegQuality = 85; // 기본 JPEG 품질
  
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
    try {
      debugPrint('이미지 선택 시작: $source');
      
      // 이미지 피커 설정
      final ImagePicker picker = ImagePicker();
      
      // 이미지 선택 API 호출 (iOS에서 오류가 발생할 수 있음)
      XFile? pickedFile;
      
      try {
        pickedFile = await picker.pickImage(
          source: source,
          maxWidth: 2048,    // 이미지 최대 크기 제한
          maxHeight: 2048,
          requestFullMetadata: false, // 불필요한 메타데이터 요청 안함
        );
        
        // 사용자가 취소한 경우
        if (pickedFile == null) {
          debugPrint('이미지 선택이 취소되었습니다');
          return null;
        }
      } catch (pickError) {
        debugPrint('이미지 선택 API 오류: $pickError');
        return null;
      }
      
      // XFile을 File로 변환
      final File file = File(pickedFile.path);
      
      // 파일 존재 확인 (엄격한 체크)
      bool fileExists = false;
      int fileSize = 0;
      
      try {
        fileExists = file.existsSync();
        fileSize = fileExists ? file.lengthSync() : 0;
        debugPrint('파일 상태: 존재=$fileExists, 크기=$fileSize, 경로=${file.path}');
      } catch (fileCheckError) {
        debugPrint('파일 확인 중 오류: $fileCheckError');
      }
      
      if (!fileExists || fileSize == 0) {
        debugPrint('선택된 이미지 파일이 유효하지 않습니다: 존재=$fileExists, 크기=$fileSize');
        return null;
      }
      
      debugPrint('이미지 선택 성공: 경로=${file.path}, 크기=$fileSize 바이트');
      return file;
    } catch (e) {
      debugPrint('이미지 선택 중 예외 발생: $e');
      return null;
    }
  }
  
  /// 이미지 선택 (갤러리 또는 카메라)
  Future<List<File>> pickMultipleImages() async {
    try {
      debugPrint('다중 이미지 선택 시작');
      
      // 이미지 피커 설정
      final ImagePicker picker = ImagePicker();
      
      // 다중 이미지 선택 호출
      List<XFile>? pickedFiles;
      
      try {
        pickedFiles = await picker.pickMultiImage(
          maxWidth: 2048,    // 이미지 최대 크기 제한
          maxHeight: 2048,
          requestFullMetadata: false, // 불필요한 메타데이터 요청 안함
        );
        
        // 사용자가 취소했거나 선택된 이미지가 없는 경우
        if (pickedFiles.isEmpty) {
          debugPrint('다중 이미지 선택이 취소되었거나 이미지가 선택되지 않았습니다');
          return [];
        }
      } catch (pickError) {
        debugPrint('다중 이미지 선택 API 오류: $pickError');
        return [];
      }
      
      // 선택된 이미지들을 File 객체로 변환 (유효한 것만)
      final List<File> validFiles = [];
      
      for (final XFile pickedFile in pickedFiles) {
        final File file = File(pickedFile.path);
        
        // 파일 존재 및 유효성 확인
        if (file.existsSync() && file.lengthSync() > 0) {
          validFiles.add(file);
        } else {
          debugPrint('유효하지 않은 이미지 파일 무시: ${pickedFile.path}');
        }
      }
      
      debugPrint('선택된 유효한 이미지 수: ${validFiles.length}');
      return validFiles;
    } catch (e) {
      debugPrint('다중 이미지 선택 중 예외 발생: $e');
      return [];
    }
  }

  /// 이미지 파일 가져오기
  Future<File?> getImageFile(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) {
      return null;
    }

    try {
      // 로컬 파일 경로 확인
      final appDir = await getApplicationDocumentsDirectory();
      final filePath = '${appDir.path}/$relativePath';
      final file = File(filePath);

      // 로컬 파일이 있으면 반환
      if (await file.exists()) {
        return file;
      }

      // 파일이 없으면 다운로드
      return await downloadImage(relativePath);
    } catch (e) {
      debugPrint('이미지 파일 가져오기 중 오류: $e');
      return null;
    }
  }

  /// 이미지 다운로드
  Future<File?> downloadImage(String relativePath) async {
    try {
      if (relativePath.isEmpty) {
        return null;
      }

      // 로컬 파일 준비
      final appDir = await getApplicationDocumentsDirectory();
      final filePath = '${appDir.path}/$relativePath';
      
      // 디렉토리 생성
      final dir = Directory(path.dirname(filePath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // 파일이 이미 존재하는지 확인
      final file = File(filePath);
      if (await file.exists()) {
        // 파일이 유효한지 확인 (크기가 0이 아닌지)
        final fileSize = await file.length();
        if (fileSize > 0) {
          return file;
        }
        // 크기가 0이면 파일 삭제하고 다시 다운로드
        await file.delete();
      }
      
      // URL 형태인지 확인
      if (relativePath.startsWith('http')) {
        return await _downloadFromUrl(relativePath, file);
      } else {
        return await _downloadFromFirebase(relativePath, file);
      }
    } catch (e) {
      debugPrint('이미지 다운로드 중 오류: $e');
      return null;
    }
  }
  
  /// URL에서 이미지 다운로드
  Future<File?> _downloadFromUrl(String url, File file) async {
    try {
      // HTTP를 통해 이미지 다운로드
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        return file;
      } else {
        debugPrint('HTTP 다운로드 실패: $url, 상태 코드: ${response.statusCode}');
        return null;
      }
    } catch (httpError) {
      debugPrint('HTTP 다운로드 중 오류: $httpError');
      return null;
    }
  }
  
  /// Firebase에서 이미지 다운로드
  Future<File?> _downloadFromFirebase(String relativePath, File file) async {
    try {
      // 상대 경로가 사용자 ID를 포함하는지 확인
      String storagePath = relativePath;
      if (!relativePath.startsWith('users/') && _currentUserId != null) {
        storagePath = 'users/$_currentUserId/$relativePath';
      }
      
      // Firebase 다운로드 재시도 방지 (메모리에 경로 캐싱)
      if (_failedDownloadPaths.contains(storagePath)) {
        debugPrint('이전에 실패한 다운로드 경로, 재시도 방지: $storagePath');
        return null;
      }
      
      final storageRef = _storage.ref().child(storagePath);
      
      // 먼저 URL을 가져와서 존재 여부 확인
      try {
        await storageRef.getDownloadURL();
      } catch (e) {
        if (e is FirebaseException && e.code == 'object-not-found') {
          debugPrint('Firebase Storage에서 파일을 찾을 수 없음: $storagePath');
          _failedDownloadPaths.add(storagePath); // 실패한 경로 캐싱
          
          // 사용자 ID 없이 직접 경로도 시도
          if (storagePath != relativePath) {
            return await _tryDownloadDirectPath(relativePath, file);
          }
          return null;
        }
        // 다른 오류는 무시하고 계속 진행
      }
      
      // 파일 다운로드
      await storageRef.writeToFile(file);
      
      // 다운로드 후 파일 확인
      if (await file.exists() && await file.length() > 0) {
        return file;
      } else {
        debugPrint('Firebase에서 다운로드했으나 파일이 비어 있음: $storagePath');
        _failedDownloadPaths.add(storagePath); // 실패한 경로 캐싱
        
        // 사용자 ID 없이 직접 경로도 시도
        if (storagePath != relativePath) {
          return await _tryDownloadDirectPath(relativePath, file);
        }
        return null;
      }
    } catch (storageError) {
      debugPrint('Firebase Storage에서 다운로드 중 오류: $storageError');
      
      // 실패한 경로 캐싱 (사용 중인 storagePath 변수 사용)
      final String pathToCache = relativePath.startsWith('users/') ? 
          relativePath : (_currentUserId != null ? 'users/$_currentUserId/$relativePath' : relativePath);
      _failedDownloadPaths.add(pathToCache);
      
      // 사용자 ID 없이 직접 경로도 시도
      if (relativePath.startsWith('users/') || _currentUserId == null) {
        return null;
      }
      return await _tryDownloadDirectPath(relativePath, file);
    }
  }
  
  /// 직접 경로로 다운로드 시도
  Future<File?> _tryDownloadDirectPath(String relativePath, File file) async {
    try {
      // 실패한 다운로드 캐싱
      if (_failedDownloadPaths.contains(relativePath)) {
        debugPrint('이전에 실패한 직접 경로, 재시도 방지: $relativePath');
        return null;
      }
      
      final directRef = _storage.ref().child(relativePath);
      await directRef.writeToFile(file);
      
      if (await file.exists() && await file.length() > 0) {
        return file;
      }
      
      // 실패한 경로 캐싱
      _failedDownloadPaths.add(relativePath);
    } catch (retryError) {
      debugPrint('직접 경로로 재시도 중 오류: $retryError');
      _failedDownloadPaths.add(relativePath);
    }
    return null;
  }

  /// 이미지 바이트 가져오기 (메모리에 로드)
  Future<Uint8List?> getImageBytes(String? relativePath) async {
    try {
      if (relativePath == null || relativePath.isEmpty) {
        return null;
      }
      
      // 1. 먼저 메모리 캐시 확인
      final cachedBytes = _imageCacheService.getFromCache(relativePath);
      if (cachedBytes != null) {
        return cachedBytes;
      }
      
      // 2. 로컬 파일에서 시도
      final file = await getImageFile(relativePath);
      if (file != null && await file.exists()) {
        final bytes = await file.readAsBytes();
        
        // 유효한 이미지인지 확인 (0바이트 체크)
        if (bytes.isNotEmpty) {
          // 결과 메모리 캐시에 저장
          _imageCacheService.addToCache(relativePath, bytes);
          return bytes;
        }
      }
      
      return null;
    } catch (e) {
      debugPrint('이미지 바이트 가져오기 중 오류: $e');
      return null;
    }
  }

  /// 이미지 업로드 (파일 경로 또는 파일 객체)
  Future<String> uploadImage(dynamic image) async {
    try {
      if (image == null) {
        throw Exception('이미지가 null입니다');
      }
      
      // 최종 저장 경로
      String targetPath;
      
      // 이미지가 경로인 경우
      if (image is String) {
        final imagePath = image;
      
        // 해당 경로에 파일이 존재하는지 확인
        if (!await File(imagePath).exists()) {
          throw Exception('파일이 존재하지 않습니다: $imagePath');
      }
      
      // 이미지 저장 및 최적화
        targetPath = await saveAndOptimizeImage(imagePath);
      }
      // 이미지가 File 객체인 경우
      else if (image is File) {
        final imageFile = image;
      
        // 파일이 존재하는지 확인
        if (!await imageFile.exists()) {
          throw Exception('파일이 존재하지 않습니다: ${imageFile.path}');
        }
        
        // 이미지 저장 및 최적화 (경로 전달)
        targetPath = await saveAndOptimizeImage(imageFile.path);
      }
      else {
        throw Exception('지원되지 않는 이미지 형식입니다: ${image.runtimeType}');
      }
      
      return targetPath;
    } catch (e) {
      debugPrint('⚠️ 이미지 업로드 중 오류 발생: $e');
      return _fallbackImagePath;
    }
  }

  /// 이미지 저장 및 최적화 
  /// 
  /// 이미지를 압축하고 최적화한 후 로컬 및 Firebase Storage에 저장합니다.
  /// [imagePath]는 원본 이미지 경로, [quality]는 압축 품질입니다.
  Future<String> saveAndOptimizeImage(String imagePath, {int quality = 85}) async {
    if (kDebugMode) {
      print('이미지 저장 시작: $imagePath');
    }

    // 이미지 파일 확인
    final originalFile = File(imagePath);
    if (!await originalFile.exists()) {
      throw Exception('원본 이미지 파일을 찾을 수 없습니다: $imagePath');
      }
      
    // 이미지 크기 확인 및 저장 공간 제한 확인
    final fileSize = await originalFile.length();
    final canStoreFile = await _checkStorageLimit(originalFile);
    if (!canStoreFile) {
      throw Exception('저장 공간 제한을 초과했습니다. 이미지를 저장할 수 없습니다.');
      }

    // 사용자별 디렉토리 생성
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filename = 'img_$timestamp${path.extension(imagePath)}';
    
    // 사용자 ID 기반 경로 생성
    final userId = _currentUserId ?? 'anonymous';
    final relativePath = path.join('images', userId, filename);
    final targetPath = path.join(await _localPath, relativePath);
      
    // 타겟 디렉토리 확인 및 생성
    final directory = Directory(path.dirname(targetPath));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
        }

    try {
      // 압축 시도
      final result = await FlutterImageCompress.compressAndGetFile(
        originalFile.absolute.path,
        targetPath,
        minWidth: 1920,
        minHeight: 1920,
        quality: quality,
      );

      if (result == null) {
        // 압축 실패 시 원본 파일 복사
        await _copyOriginalToTarget(originalFile, targetPath);
        debugPrint('이미지 압축 실패, 원본 파일 사용: $targetPath');
      } else {
        debugPrint('이미지 압축 성공: ${await result.length()} bytes');
      }

      // Firebase에 업로드
      try {
        await _uploadToFirebaseStorageIfNotExists(File(targetPath), relativePath);
      } catch (e) {
        debugPrint('Firebase 업로드 실패, 로컬 파일 사용: $e');
      }
      
      // 저장 공간 사용량 추적
      final compressedFile = File(targetPath);
      final tracked = await _trackStorageUsage(compressedFile);
      if (!tracked) {
        debugPrint('⚠️ 저장 공간 사용량 추적 실패, 로컬 파일만 사용: $targetPath');
      }

      return relativePath;
    } catch (e) {
      debugPrint('이미지 저장 중 오류 발생: $e');
      
      // 에러 발생 시 원본 파일 복사 시도
      try {
        await _copyOriginalToTarget(originalFile, targetPath);
        
        // 저장 공간 사용량 추적 (원본 파일 크기)
        final tracked = await _trackStorageUsage(originalFile);
        if (!tracked) {
          debugPrint('⚠️ 원본 파일 저장 공간 사용량 추적 실패, 로컬 파일만 사용: $targetPath');
        }
        
        return relativePath;
      } catch (copyError) {
        throw Exception('이미지 저장 실패: $e, 복사 오류: $copyError');
      }
    }
  }
  
  /// 스토리지 용량 제한 확인
  Future<bool> _checkStorageLimit(File imageFile) async {
    try {
      final fileSize = await imageFile.length();
      debugPrint('💾 이미지 파일 크기: ${_formatSize(fileSize)}');
      
      final usageLimitService = UsageLimitService();
      final currentStorageUsage = await usageLimitService.getUserCurrentStorageSize();
      final currentLimits = await usageLimitService.getCurrentLimits();
        
      // 스토리지 제한 가져오기 (기본값 50MB)
      final storageLimitBytes = currentLimits['storageBytes'] ?? (50 * 1024 * 1024);
      
      debugPrint('💾 현재 스토리지 사용량: ${_formatSize(currentStorageUsage)}');
      debugPrint('💾 스토리지 제한: ${_formatSize(storageLimitBytes)}');
      
      // 현재 사용량 + 새 파일 크기
      final estimatedTotalUsage = currentStorageUsage + fileSize;
      
      debugPrint('💾 예상 총 사용량: ${_formatSize(estimatedTotalUsage)}');
      debugPrint('💾 사용량 초과 여부: ${estimatedTotalUsage > storageLimitBytes}');
      
      // "버퍼 추가" 전략: 사용량이 제한을 초과해도 현재 작업은 완료하고
      // 다음 작업부터 제한 메시지를 표시하기 위해 항상 true 반환
      // _trackStorageUsage 메서드에서 allowOverLimit=true로 사용량을 증가시킴
      return true;
    } catch (e) {
      debugPrint('⚠️ 스토리지 제한 확인 중 오류: $e');
      return true; // 오류 발생 시 기본적으로 저장 허용
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
  
  /// 비상 대체 경로 생성 (Helper)
  String _createEmergencyPath(File imageFile) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileExtension = path.extension(imageFile.path).toLowerCase();
    return 'images/emergency_$timestamp$fileExtension';
  }
  
  /// 폴백 이미지 경로 반환 (Helper)
  String _getFallbackPath() {
    return _fallbackImagePath;
  }

  /// 파일 내용의 SHA-256 해시값 계산
  Future<String> _computeFileHash(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes);
      return digest.toString();
    } catch (e) {
      debugPrint('파일 해시 계산 중 오류: $e');
      
      // 오류 발생 시 UUID로 대체 (내용 기반 중복 감지는 불가능)
      return const Uuid().v4();
    }
  }
  
  /// Firebase Storage에 파일 업로드 (존재하지 않는 경우에만)
  Future<void> _uploadToFirebaseStorageIfNotExists(File file, String relativePath) async {
    if (_currentUserId == null) {
      debugPrint('로그인된 사용자가 없어 Firebase Storage 업로드를 건너뜁니다');
      return;
    }

    try {
      // Firebase Storage 참조 생성
      final storageRef = _storage.ref().child(relativePath);
        
      // 이미 존재하는지 확인 시도
        try {
        await storageRef.getDownloadURL();
        debugPrint('파일이 이미 Firebase Storage에 존재합니다: $relativePath');
        return; // 이미 존재하면 업로드 건너뛰기
        } catch (e) {
        // 파일이 존재하지 않는 경우 (예외 발생) 계속 진행
      }
      
      // 업로드 실행
      await storageRef.putFile(file);
      debugPrint('Firebase Storage에 파일 업로드 완료: $relativePath');
    } catch (e) {
      debugPrint('Firebase Storage 업로드 오류: $e');
      throw Exception('Firebase Storage 업로드 실패: $e');
    }
  }
  
  /// 확장자에 따른 컨텐츠 타입 결정
  String _getContentType(String extension) {
    switch(extension) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.bmp':
        return 'image/bmp';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      default:
        return 'application/octet-stream';
    }
  }
  
  /// 이미지 URL이 Firebase Storage에 존재하는지 확인
  Future<bool> _imageExists(String relativePath) async {
    try {
      final ref = _storage.ref().child(relativePath);
      await ref.getDownloadURL();
      return true;
    } catch (e) {
      if (e is FirebaseException && e.code == 'object-not-found') {
        return false;
      }
      // 다른 오류는 존재하지 않는 것으로 간주 (안전)
      debugPrint('이미지 존재 확인 중 오류: $e');
      return false;
    }
  }
  
  /// 저장 공간 사용량 추적
  Future<bool> _trackStorageUsage(File file) async {
    try {
      // 실제 파일 크기 측정
      final actualSize = await file.length();
      
      // 사용량 추적 (버퍼 지원 활성화)
      await _usageLimitService.addStorageUsage(actualSize, allowOverLimit: true);
      
      debugPrint('저장 공간 사용량 추적: +${actualSize / 1024}KB');
      return true;
    } catch (e) {
      debugPrint('저장 공간 사용량 추적 중 오류: $e');
      return false; // 추적에 실패하면 false 반환
    }
  }
  
  /// 이미지 존재 여부 확인 (추가된 메서드)
  Future<bool> imageExists(String? imageUrl) async {
    if (imageUrl == null || imageUrl.isEmpty) {
      return false;
    }
    
    try {
      // Firebase 저장소 URL인 경우
      if (imageUrl.contains('firebasestorage.googleapis.com')) {
        // URL에서 상대 경로 추출 시도
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
        
        // 직접 HTTP 요청으로 체크
        final response = await http.head(Uri.parse(imageUrl));
        return response.statusCode == 200;
      } else {
        // 일반 HTTP URL
        final response = await http.head(Uri.parse(imageUrl));
        return response.statusCode == 200;
      }
    } catch (e) {
      debugPrint('이미지 존재 확인 중 오류 (URL): $e');
      return false;
    }
  }
  
  /// 이미지 삭제 (추가된 메서드)
  Future<bool> deleteImage(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) {
      return false;
    }

    try {
      // 디스크에서 제거
      final appDir = await getApplicationDocumentsDirectory();
      final filePath = '${appDir.path}/$relativePath';
      final file = File(filePath);
      
      if (await file.exists()) {
        // 파일 삭제
        await file.delete();
        
        // Firebase에서도 삭제 시도
        try {
          if (_currentUserId != null) {
            final storagePath = 'users/$_currentUserId/$relativePath';
            final storageRef = _storage.ref().child(storagePath);
            await storageRef.delete();
          }
        } catch (e) {
          // Firebase 삭제 실패는 무시 (로컬만 삭제해도 됨)
          debugPrint('Firebase에서 이미지 삭제 중 오류: $e');
        }
        
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('이미지 삭제 중 오류 발생: $e');
      return false;
    }
  }

  /// 임시 파일 정리 (추가된 메서드)
  Future<void> cleanupTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory(tempDir.path);
      final entities = await dir.list().toList();
      
      int removedCount = 0;
      
      // 이미지 관련 임시 파일 찾기
      for (var entity in entities) {
        if (entity is File) {
          final fileName = path.basename(entity.path);
          
          // 앱이 생성한 임시 이미지 파일 확인 (_img_, image_ 등의 패턴 포함)
          if ((fileName.contains('image_') || fileName.contains('_img_')) && 
              (fileName.endsWith('.jpg') || fileName.endsWith('.png'))) {
            
            // 파일 정보 확인
            FileStat stat = await entity.stat();
            
            // 24시간 이상 지난 파일 삭제
            final now = DateTime.now();
            if (now.difference(stat.modified).inHours > 24) {
              try {
                await entity.delete();
                removedCount++;
              } catch (e) {
                // 오류 무시
              }
            }
          }
        }
      }
      
      if (removedCount > 0) {
        debugPrint('$removedCount개의 임시 파일을 정리했습니다.');
      }
    } catch (e) {
      debugPrint('임시 파일 정리 중 오류: $e');
    }
  }
  
  /// 이미지 캐시 정리 (추가된 메서드)
  Future<void> clearImageCache() async {
    try {
      // 이미지 캐시 서비스 캐시 정리
      _imageCacheService.clearCache();
      
      // 대기 중인 이미지 프로바이더 캐시 정리
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      
      debugPrint('이미지 캐시를 정리했습니다.');
    } catch (e) {
      debugPrint('이미지 캐시 정리 중 오류: $e');
    }
  }

  /// 이미지 선택 (갤러리) - 대체 메서드
  /// 일반 ImagePicker가 작동하지 않을 때 사용
  Future<File?> pickImageAlternative({ImageSource source = ImageSource.gallery}) async {
    try {
      debugPrint('이미지 선택 시작 (단순화된 메서드): $source');
      
      // 단순화된 이미지 피커 구현
      final ImagePicker picker = ImagePicker();
      
      // 기본 옵션만 사용하여 이미지 선택 (최소 옵션)
      final XFile? pickedFile = await picker.pickImage(source: source);
      
      // 선택 취소 처리
      if (pickedFile == null) {
        debugPrint('이미지 선택 취소됨');
        return null;
      }
      
      // 파일 변환 및 확인
      final File file = File(pickedFile.path);
      if (!file.existsSync()) {
        debugPrint('선택된 파일이 존재하지 않음: $file.path');
        return null;
      }
      
      final int fileSize = file.lengthSync();
      if (fileSize <= 0) {
        debugPrint('선택된 파일의 크기가 0 또는 음수: $fileSize');
        return null;
      }
      
      debugPrint('이미지 선택 성공: $file.path (${fileSize}바이트)');
      return file;
    } catch (e) {
      debugPrint('이미지 선택 중 예외 발생: $e');
      return null;
    }
  }
  
  /// 여러 이미지 선택 (갤러리) - 대체 메서드
  Future<List<File>> pickMultipleImagesAlternative() async {
    try {
      debugPrint('다중 이미지 선택 시작 (단순화된 메서드)');
      
      // 단순화된 이미지 피커 구현
      final ImagePicker picker = ImagePicker();
      
      // 기본 옵션으로 이미지 선택
      final List<XFile>? pickedFiles = await picker.pickMultiImage();
      
      // 선택 취소 또는 실패 처리
      if (pickedFiles == null || pickedFiles.isEmpty) {
        debugPrint('이미지가 선택되지 않음');
        return [];
      }
      
      // 파일 변환 및 검증
      final List<File> validFiles = [];
      
      for (final XFile pickedFile in pickedFiles) {
        final File file = File(pickedFile.path);
        
        if (file.existsSync() && file.lengthSync() > 0) {
          validFiles.add(file);
          debugPrint('유효한 이미지 추가: ${file.path}');
        } else {
          debugPrint('유효하지 않은 이미지 무시: ${file.path}');
        }
      }
      
      debugPrint('총 $validFiles.length개의 이미지가 선택됨');
      return validFiles;
    } catch (e) {
      debugPrint('다중 이미지 선택 중 오류: $e');
      return [];
    }
  }

  // 현재 보고 있는 이미지 파일 관리 (NoteDetailImageHandler에서 가져옴)
  File? _currentImageFile;
  
  // 현재 이미지 파일 가져오기 - 안전 장치 추가
  File? getCurrentImageFile() {
    try {
      // 이미지 파일이 null이 아니고 존재하는지 확인
      if (_currentImageFile != null) {
        if (!_currentImageFile!.existsSync()) {
          debugPrint('⚠️ 현재 이미지 파일이 더 이상 존재하지 않습니다. null 반환');
          _currentImageFile = null;
        }
      }
      return _currentImageFile;
    } catch (e) {
      debugPrint('❌ getCurrentImageFile 오류: $e - null 반환');
      _currentImageFile = null;
      return null;
    }
  }
  
  // 현재 이미지 설정 - 안전 장치 추가
  void setCurrentImageFile(File? file) {
    try {
      // 파일이 null이 아니고 실제로 존재하는지 확인
      if (file != null && !file.existsSync()) {
        debugPrint('⚠️ 존재하지 않는 이미지 파일을 현재 이미지로 설정하려고 시도. 무시됨.');
        return;
      }
      _currentImageFile = file;
    } catch (e) {
      debugPrint('❌ setCurrentImageFile 오류: $e');
      _currentImageFile = null;
    }
  }
  
  // 페이지 이미지 로드 (NoteDetailImageHandler에서 가져옴) - 안전 장치 추가
  Future<File?> loadPageImage(dynamic pageOrUrl) async {
    try {
      String? imageUrl;
      
      // page_model.Page 객체인지 문자열인지 확인
      if (pageOrUrl is String) {
        imageUrl = pageOrUrl;
      } else if (pageOrUrl != null && pageOrUrl.imageUrl != null) {
        imageUrl = pageOrUrl.imageUrl;
      }
      
      if (imageUrl == null || imageUrl.isEmpty) {
        // 현재 이미지 초기화
        _currentImageFile = null;
        return null;
      }
      
      // 이미 실패한 다운로드인 경우 빠르게 반환
      if (_failedDownloadPaths.contains(imageUrl)) {
        debugPrint('⚠️ 이전에 실패한 이미지 URL, 재시도 방지: $imageUrl');
        // 현재 이미지 초기화
        _currentImageFile = null;
        return null;
      }
      
      final imageFile = await getImageFile(imageUrl);
      
      // 파일이 실제로 존재하고 크기가 있는지 확인
      if (imageFile != null && imageFile.existsSync() && imageFile.lengthSync() > 0) {
        _currentImageFile = imageFile;
        return imageFile;
      } else {
        debugPrint('⚠️ 이미지 로드 실패 또는 빈 파일: $imageUrl');
        _currentImageFile = null;
        // 실패한 경로 캐싱
        _failedDownloadPaths.add(imageUrl);
        return null;
      }
    } catch (e) {
      debugPrint('❌ loadPageImage 오류: $e');
      _currentImageFile = null;
      return null;
    }
  }
  
  // 이미지 확대 화면 표시 (NoteDetailImageHandler에서 가져옴)
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

  /// 이미지 업로드 및 URL 가져오기 (단일 메서드)
  Future<String> uploadAndGetUrl(File imageFile, {bool forThumbnail = false}) async {
    try {
      if (!await imageFile.exists()) {
        throw Exception('이미지 파일이 존재하지 않습니다: ${imageFile.path}');
      }
      
      // 이미지 저장 및 최적화
      final int quality = forThumbnail ? 70 : 85; // 썸네일은 더 낮은 품질로 압축
      final String relativePath = await saveAndOptimizeImage(imageFile.path, quality: quality);
      
      // Firebase Storage에서 URL 가져오기
      String? downloadUrl;
      try {
        final storageRef = _storage.ref().child(relativePath);
        downloadUrl = await storageRef.getDownloadURL();
      } catch (e) {
        debugPrint('Firebase URL 가져오기 실패, 로컬 경로 사용: $e');
      }
      
      // URL이 있으면 반환, 없으면 로컬 상대 경로 반환
      return downloadUrl ?? relativePath;
    } catch (e) {
      debugPrint('이미지 업로드 및 URL 가져오기 오류: $e');
      return _fallbackImagePath;
    }
  }
}

// compute 함수에 타입 안전성을 제공하기 위한 래퍼 함수 및 파라미터 클래스
// compute 함수에 전달하기 위한 파라미터 클래스
@immutable
class _CompressionParams {
  final Uint8List imageBytes;
  final String targetPath;
  final int maxDimension;
  final int quality;

  const _CompressionParams({
    required this.imageBytes,
    required this.targetPath,
    required this.maxDimension,
    required this.quality,
  });
}

// compute에 직접 전달될 최상위 또는 static 래퍼 함수
Future<_CompressionResult> _compressImageIsolateWrapper(_CompressionParams params) async {
  // 실제 작업 함수 호출
  return _compressImageIsolate({
    'imageBytes': params.imageBytes,
    'targetPath': params.targetPath,
    'maxDimension': params.maxDimension,
    'quality': params.quality,
  });
}