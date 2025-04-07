import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'usage_limit_service.dart';
import 'package:image/image.dart' as img;

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
    // 애니메이션 타이머 관련 설정
    timeDilation = 1.0;
  }

  // 현재 사용자 ID 가져오기
  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  /// 이미지 선택 (갤러리)
  Future<File?> pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      // 타이머 출력 방지
      timeDilation = 1.0;
      
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 85, // 약간 압축
      );
      
      if (pickedFile == null) {
        return null;
      }
      
      return File(pickedFile.path);
    } catch (e) {
      debugPrint('이미지 선택 중 오류: $e');
      return null;
    }
  }
  
  /// 여러 이미지 선택 (갤러리)
  Future<List<File>> pickMultipleImages() async {
    try {
      // 타이머 출력 방지
      timeDilation = 1.0;
      
      final picker = ImagePicker();
      final pickedFiles = await picker.pickMultiImage(
        imageQuality: 85, // 약간 압축
      );
      
      if (pickedFiles.isEmpty) {
        return [];
      }
      
      return pickedFiles.map((xFile) => File(xFile.path)).toList();
    } catch (e) {
      debugPrint('여러 이미지 선택 중 오류: $e');
      return [];
    }
  }

  /// 이미지 파일 가져오기
  Future<File?> getImageFile(String? relativePath) async {
    // 타이머 출력 방지
    timeDilation = 1.0;

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

      // Firebase Storage에서 다운로드 준비
      final storageRef = _storage.ref().child(relativePath);
      
      // 로컬 파일 준비
      final appDir = await getApplicationDocumentsDirectory();
      final filePath = '${appDir.path}/$relativePath';
      
      // 디렉토리 생성
      final dir = Directory(path.dirname(filePath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // 파일 다운로드
      final file = File(filePath);
      await storageRef.writeToFile(file);
      
      return file;
    } catch (e) {
      debugPrint('이미지 다운로드 중 오류: $e');
      return null;
    }
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
      // 타이머 출력 방지
      timeDilation = 1.0;
      
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
        _uploadToFirebaseStorageIfNotExists(File(targetPath), relativePath).then((_) {
          // 업로드 완료 후 추가 작업은 없음
        }).catchError((error) {
          debugPrint('Firebase Storage 배경 업로드 중 오류: $error');
        });
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
  
  /// 이미지 압축 및 저장 (단일 통합 메서드)
  Future<_CompressionResult> _compressAndSaveImage(File imageFile, String targetPath) async {
    try {
      // 타이머 출력 방지
      timeDilation = 1.0;
      
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
  
  /// Firebase Storage에 이미지 업로드 (존재하지 않는 경우에만)
  Future<String?> _uploadToFirebaseStorageIfNotExists(File file, String relativePath) async {
    try {
      // Firebase 초기화 체크
      if (FirebaseAuth.instance.app == null) {
        debugPrint('Firebase가 초기화되지 않았습니다');
        return null;
      }
      
      final userId = _currentUserId;
      if (userId == null) {
        return null;
      }
      
      // 사용자별 경로 지정: users/{userId}/images/{fileName}
      final storagePath = 'users/$userId/$relativePath';
      final storageRef = _storage.ref().child(storagePath);
      
      // 이미지가 이미 존재하는지 확인
      try {
        await storageRef.getMetadata();
        
        // 이미 존재하는 경우 URL 반환
        final downloadUrl = await storageRef.getDownloadURL();
        return downloadUrl;
      } catch (e) {
        // 파일이 존재하지 않는 경우에만 업로드 진행
        final uploadTask = storageRef.putFile(file);
        
        // 업로드 완료 대기
        final snapshot = await uploadTask;
        
        // 이미지 URL 가져오기
        final downloadUrl = await snapshot.ref.getDownloadURL();
        
        return downloadUrl;
      }
    } catch (e) {
      debugPrint('Firebase Storage 업로드 중 오류: $e');
      return null; // 실패해도 앱은 계속 작동하도록 예외를 다시 발생시키지 않음
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
}
}