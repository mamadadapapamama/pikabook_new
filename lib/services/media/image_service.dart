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
import '../../services/usage_limit_service.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import '../../views/screens/full_image_screen.dart';

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
  
  // Firebase Storage 참조
  final FirebaseStorage _storage = FirebaseStorage.instance;
  
  // 기본값 및 상수
  static const String _fallbackImagePath = 'images/fallback_image.jpg';
  static const int _maxImageDimension = 1200; // 최대 이미지 크기 (픽셀)
  static const int _defaultJpegQuality = 85; // 기본 JPEG 품질
  
  ImageService._internal() {
    // 초기화 로직
  }

  // 현재 사용자 ID 가져오기
  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

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
      
      final storageRef = _storage.ref().child(storagePath);
      
      // 먼저 URL을 가져와서 존재 여부 확인
      try {
        await storageRef.getDownloadURL();
      } catch (e) {
        if (e is FirebaseException && e.code == 'object-not-found') {
          debugPrint('Firebase Storage에서 파일을 찾을 수 없음: $storagePath');
          
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
        
        // 사용자 ID 없이 직접 경로도 시도
        if (storagePath != relativePath) {
          return await _tryDownloadDirectPath(relativePath, file);
        }
        return null;
      }
    } catch (storageError) {
      debugPrint('Firebase Storage에서 다운로드 중 오류: $storageError');
      
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
      final directRef = _storage.ref().child(relativePath);
      await directRef.writeToFile(file);
      
      if (await file.exists() && await file.length() > 0) {
        return file;
      }
    } catch (retryError) {
      debugPrint('직접 경로로 재시도 중 오류: $retryError');
    }
    return null;
  }

  /// 이미지 바이트 가져오기 (메모리에 로드)
  Future<Uint8List?> getImageBytes(String? relativePath) async {
    try {
      if (relativePath == null || relativePath.isEmpty) {
        return null;
      }
      
      // 먼저 로컬 파일에서 시도
      final file = await getImageFile(relativePath);
      if (file != null && await file.exists()) {
        return await file.readAsBytes();
      }
      
      return null;
    } catch (e) {
      debugPrint('이미지 바이트 가져오기 중 오류: $e');
      return null;
    }
  }

  /// 이미지 업로드 (로컬 저장소에 저장)
  Future<String> uploadImage(File imageFile) async {
    try {
      // 파일 유효성 확인
      if (!await imageFile.exists()) {
        debugPrint('이미지 파일이 존재하지 않습니다 - 대체 파일 경로 반환');
        return _getFallbackPath();
      }
      
      // 사용량 제한 확인
      final usage = await _usageLimitService.getBetaUsageLimits();
      
      // 저장 공간 제한 도달 시 오류 발생
      if (usage['storageLimitReached'] == true) {
        debugPrint('저장 공간 제한에 도달했습니다 - 대체 파일 경로 반환');
        return _getFallbackPath();
      }
      
      // 이미지 저장 및 최적화
      String relativePath = await saveAndOptimizeImage(imageFile);
      
      // 결과 검증
      if (relativePath.isEmpty) {
        debugPrint('이미지 저장 결과 경로가 비어 있습니다 - 대체 경로 생성');
        relativePath = _createEmergencyPath(imageFile);
      }
      
      return relativePath;
    } catch (e) {
      debugPrint('이미지 업로드 중 예외 발생: $e - 대체 파일 경로 반환');
      
      // 오류 발생 시 기본 경로 반환 (null 체크 오류 방지)
      return _getFallbackPath();
    }
  }

  /// 이미지 파일을 앱의 영구 저장소에 저장하고 최적화
  Future<String> saveAndOptimizeImage(File imageFile) async {
    try {
      // 파일 유효성 확인
      if (!await imageFile.exists()) {
        debugPrint('이미지 파일이 존재하지 않습니다');
        return _createEmergencyPath(imageFile);
      }
      
      // 앱의 영구 저장소 디렉토리 가져오기
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/images');

      // 이미지 디렉토리가 없으면 생성
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      // 이미지 파일의 해시값 계산 (파일 내용 기반 고유 식별자)
      final fileHash = await _computeFileHash(imageFile);
      
      // 해시값을 파일명에 사용 (동일 내용의 파일은 동일한 이름을 가짐)
      final fileExtension = path.extension(imageFile.path).toLowerCase();
      final fileName = '$fileHash$fileExtension';
      final targetPath = '${imagesDir.path}/$fileName';
      final relativePath = 'images/$fileName';
      
      // 동일한 해시값의 파일이 이미 존재하는지 확인
      final existingFile = File(targetPath);
      if (await existingFile.exists()) {
        final fileSize = await existingFile.length();
        if (fileSize > 0) {
          return relativePath; // 이미 존재하는 파일 사용
        } else {
          // 빈 파일이면 삭제하고 다시 처리
          await existingFile.delete();
        }
      }

      // 이미지 압축 및 저장 (단일 통합 메서드)
      final result = await _compressAndSaveImage(imageFile, targetPath);
      
      // 압축 결과가 없거나 실패한 경우
      if (!result.success) {
        // 원본 파일을 타겟 경로에 복사
        await _copyOriginalToTarget(imageFile, targetPath);
      }
      
      // Firebase Storage에 업로드 시도 - 중복 업로드 방지를 위해 존재 여부 확인 추가
      try {
        // Firebase Storage 업로드는 별도 스레드에서 비동기로 처리 (앱 응답성 유지)
        await _uploadToFirebaseStorageIfNotExists(File(targetPath), relativePath);
      } catch (e) {
        debugPrint('Firebase Storage 업로드 중 오류: $e');
      }
      
      // 스토리지 사용량 추적 - 압축된 실제 파일 크기 사용
      await _trackStorageUsage(File(targetPath));

      return relativePath;
    } catch (e) {
      debugPrint('이미지 저장 및 최적화 중 치명적 오류: $e');
      return _createEmergencyPath(imageFile);
    }
  }
  
  /// 이미지 압축 및 저장 (다양한 방법 시도)
  Future<_CompressionResult> _compressAndSaveImage(File imageFile, String targetPath) async {
    try {
      // 이미지 정보 가져오기
      final Uint8List imageBytes = await imageFile.readAsBytes();
      final img.Image? image = img.decodeImage(imageBytes);
      
      // 이미지 디코딩 실패시
      if (image == null) {
        return _CompressionResult.failure('이미지 디코딩 실패');
      }
      
      // 1. 이미지 리사이징 (필요한 경우)
      img.Image processedImage = image;
      if (image.width > _maxImageDimension || image.height > _maxImageDimension) {
        processedImage = _resizeImage(image);
      }
      
      // 2. 다양한 압축 방법 시도 (통합된 방식)
      bool compressionSuccess = false;
      
      // 2.1 첫 번째 시도: JPG 인코딩
      try {
        final jpegBytes = img.encodeJpg(processedImage, quality: _defaultJpegQuality);
        await File(targetPath).writeAsBytes(jpegBytes);
        compressionSuccess = true;
      } catch (jpgError) {
        debugPrint('JPG 인코딩 실패: $jpgError');
        
        // 2.2 두 번째 시도: PNG 인코딩
        try {
          final pngBytes = img.encodePng(processedImage);
          await File(targetPath).writeAsBytes(pngBytes);
          compressionSuccess = true;
        } catch (pngError) {
          debugPrint('PNG 인코딩도 실패: $pngError');
        }
      }
      
      // 3. 압축 성공 여부 확인
      final targetFile = File(targetPath);
      if (!compressionSuccess || !await targetFile.exists() || await targetFile.length() == 0) {
        return _CompressionResult.failure('이미지 압축 및 저장 실패');
      }
      
      // 4. 메모리 해제 힌트
      processedImage.clear();
      
      return _CompressionResult.success();
    } catch (e) {
      return _CompressionResult.failure('이미지 압축 중 예외 발생: $e');
    }
  }
  
  /// 이미지 리사이징 (단순화된 로직)
  img.Image _resizeImage(img.Image image) {
    final int maxDimension = _maxImageDimension;
    
    if (image.width <= maxDimension && image.height <= maxDimension) {
      return image; // 이미 적절한 크기
    }
    
    // 가로/세로 비율 유지하며 리사이징
    double ratio;
    if (image.width > image.height) {
      ratio = maxDimension / image.width;
    } else {
      ratio = maxDimension / image.height;
    }
    
    return img.copyResize(
      image,
      width: (image.width * ratio).round(),
      height: (image.height * ratio).round(),
      interpolation: img.Interpolation.average,
    );
  }
  
  /// 원본 파일을 타겟 경로에 복사 (Helper)
  Future<void> _copyOriginalToTarget(File originalFile, String targetPath) async {
    try {
      await originalFile.copy(targetPath);
    } catch (e) {
      debugPrint('원본 파일 복사 중 오류: $e');
      
      // 타겟 디렉토리 확인 및 생성
      final dir = Directory(path.dirname(targetPath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      try {
        // 다시 시도
        await originalFile.copy(targetPath);
      } catch (retryError) {
        debugPrint('원본 파일 복사 재시도 중 오류: $retryError');
        
        // 최후의 수단: 빈 파일 생성
        final file = File(targetPath);
        await file.create();
        await file.writeAsBytes(Uint8List(0));
      }
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
  
  /// Firebase Storage에 이미지 업로드 (중복 확인)
  Future<void> _uploadToFirebaseStorageIfNotExists(File file, String relativePath) async {
    try {
      if (!await _imageExists(relativePath)) {
        // 파일이 존재하지 않는 경우에만 업로드
        final ref = _storage.ref().child(relativePath);
        
        // 존재 여부 이중 체크
        try {
          await ref.getDownloadURL();
          debugPrint('이미지가 이미 존재함: $relativePath');
          return;
        } catch (e) {
          // 파일이 존재하지 않음 - 정상 진행
          debugPrint('신규 이미지 업로드 시작: $relativePath');
        }
        
        // 파일 크기 확인
        final fileSize = await file.length();
        if (fileSize <= 0) {
          throw Exception('파일 크기가 0바이트 이하: $relativePath');
        }
        
        // 파일 확장자 확인
        final extension = path.extension(file.path).toLowerCase();
        final contentType = _getContentType(extension);
        
        // 업로드 메타데이터 설정
        final metadata = SettableMetadata(
          contentType: contentType,
          customMetadata: {
            'uploaded': DateTime.now().toIso8601String(),
            'size': fileSize.toString(),
          },
        );
        
        // 업로드 작업
        final uploadTask = ref.putFile(file, metadata);
        
        // 업로드 완료 대기
        await uploadTask.whenComplete(() => debugPrint('이미지 업로드 완료: $relativePath'));
        
        // 업로드 상태 확인
        final snapshot = await uploadTask;
        if (snapshot.state == TaskState.success) {
          debugPrint('이미지 성공적으로 업로드됨: $relativePath');
        } else {
          debugPrint('이미지 업로드 실패 상태: ${snapshot.state}');
        }
      } else {
        debugPrint('이미지가 이미 존재함: $relativePath');
      }
    } catch (e) {
      debugPrint('_uploadToFirebaseStorageIfNotExists 오류: $e');
      // 업로드 실패해도 치명적 오류 처리하지 않음 (로컬 파일 사용)
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
  Future<bool> _trackStorageUsage(File compressedFile) async {
    try {
      // 실제 파일 크기 측정
      final actualSize = await compressedFile.length();
      
      // 사용량 추적
      final canAddStorage = await _usageLimitService.addStorageUsage(actualSize);
      if (!canAddStorage) {
        debugPrint('⚠️ 저장 공간 제한에 도달했습니다. 이미지를 추가로 저장할 수 없습니다.');
      }
      
      return canAddStorage;
    } catch (e) {
      debugPrint('저장 공간 사용량 추적 중 오류: $e');
      return true; // 오류 발생 시 기본적으로 허용
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
  
  // 현재 이미지 파일 가져오기
  File? getCurrentImageFile() {
    return _currentImageFile;
  }
  
  // 현재 이미지 설정
  void setCurrentImageFile(File? file) {
    _currentImageFile = file;
  }
  
  // 페이지 이미지 로드 (NoteDetailImageHandler에서 가져옴)
  Future<File?> loadPageImage(dynamic pageOrUrl) async {
    String? imageUrl;
    
    // page_model.Page 객체인지 문자열인지 확인
    if (pageOrUrl is String) {
      imageUrl = pageOrUrl;
    } else if (pageOrUrl != null && pageOrUrl.imageUrl != null) {
      imageUrl = pageOrUrl.imageUrl;
    }
    
    if (imageUrl == null || imageUrl.isEmpty) {
      return null;
    }
    
    final imageFile = await getImageFile(imageUrl);
    _currentImageFile = imageFile;
    return imageFile;
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
}