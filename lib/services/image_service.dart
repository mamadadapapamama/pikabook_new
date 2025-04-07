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

  ImageService._internal() {
    // 애니메이션 타이머 관련 설정
    timeDilation = 1.0;
  }

  // 현재 사용자 ID 가져오기
  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  /// 이미지 파일을 앱의 영구 저장소에 저장하고 최적화
  Future<String> saveAndOptimizeImage(File imageFile) async {
    try {
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
        return relativePath;
      }

      // 원본 파일 크기 확인 (사용량 추적용)
      final originalFileSize = await imageFile.length();

      // 이미지 최적화 및 저장
      final compressedFile = await compressAndSaveImage(imageFile, targetPath);
      
      // 압축 후 파일 크기 확인 (사용량 추적용)
      final compressedFileSize = await compressedFile.length();
      
      // Firebase Storage에 업로드 시도 - 중복 업로드 방지를 위해 존재 여부 확인 추가
      try {
        // Firebase Storage 업로드는 별도 스레드에서 비동기로 처리 (앱 응답성 유지)
        unawaited(_uploadToFirebaseStorageIfNotExists(compressedFile, relativePath));
      } catch (e) {
        // 오류 처리
      }
      
      // 스토리지 사용량 추적 - 압축된 실제 파일 크기 사용
      await _trackStorageUsage(compressedFile);

      return relativePath;
    } catch (e) {
      throw Exception('이미지 저장 및 최적화 중 오류가 발생했습니다: $e');
    }
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

  /// 이미지 압축 및 저장
  Future<File> compressAndSaveImage(File imageFile, String targetPath) async {
    try {
      // 이미지 정보 가져오기
      final Uint8List imageBytes = await imageFile.readAsBytes();
      final img.Image? image = img.decodeImage(imageBytes);
      
      if (image == null) {
        throw Exception('이미지를 디코딩할 수 없습니다');
      }
      
      // 이미지 크기 확인
      final originalWidth = image.width;
      final originalHeight = image.height;
      
      // 이미지 리사이징 (필요한 경우)
      img.Image processedImage = _resizeImageIfNeeded(image, originalWidth, originalHeight);
      
      // 단계별 압축 시도
      return await _compressWithMultipleApproaches(
        processedImage, 
        imageFile, 
        targetPath
      );
    } catch (e) {
      // 대체 압축 방법 시도 - 직접 라이브러리 사용
      try {
        final compressedFile = await _applyFallbackCompression(imageFile, targetPath);
        if (compressedFile != null) {
          return compressedFile;
        }
      } catch (fallbackError) {
        // 오류 처리
      }
      
      // 모든 압축 방법 실패 시 원본 복사
      final origFile = await imageFile.copy(targetPath);
      return origFile;
    }
  }
  
  /// 이미지 리사이징 로직
  img.Image _resizeImageIfNeeded(img.Image image, int originalWidth, int originalHeight) {
    final int maxDimension = 1200; // 최대 너비/높이 제한
    
    if (originalWidth > maxDimension || originalHeight > maxDimension) {
      // 비율 유지하며 리사이징
      if (originalWidth > originalHeight) {
        final ratio = maxDimension / originalWidth;
        final resized = img.copyResize(
          image,
          width: maxDimension,
          height: (originalHeight * ratio).round(),
          interpolation: img.Interpolation.average,
        );
        return resized;
      } else {
        final ratio = maxDimension / originalHeight;
        final resized = img.copyResize(
          image,
          width: (originalWidth * ratio).round(), 
          height: maxDimension,
          interpolation: img.Interpolation.average,
        );
        return resized;
      }
    }
    return image; // 리사이징 필요 없음
  }
  
  /// 여러 압축 방법을 시도하는 내부 메서드
  Future<File> _compressWithMultipleApproaches(
    img.Image processedImage, 
    File originalFile, 
    String targetPath
  ) async {
    // Flutter Image Compress 라이브러리 활용
    final File tempFile = File('$targetPath.temp');
    
    try {
      // 1단계: 중간 품질의 JPG로 인코딩
      final jpegBytes = img.encodeJpg(
        processedImage,
        quality: 85, // 높은 품질로 시작
      );
      
      // 임시 파일에 쓰기
      await tempFile.writeAsBytes(jpegBytes);
      
      // 2단계: 추가 압축 (flutter_image_compress 사용)
      final compressedBytes = await FlutterImageCompress.compressWithFile(
        tempFile.path,
        minWidth: processedImage.width,
        minHeight: processedImage.height,
        quality: 80, // 약간 더 압축
        format: CompressFormat.jpeg,
      );
      
      if (compressedBytes == null || compressedBytes.isEmpty) {
        throw Exception('이미지 추가 압축에 실패했습니다');
      }
      
      // 최종 파일에 압축된 이미지 쓰기
      final File compressedFile = File(targetPath);
      await compressedFile.writeAsBytes(compressedBytes);
      
      // 압축 후 실제 파일 크기 확인
      final compressedSize = await compressedFile.length();
      
      // 3단계: 필요시 추가 압축 (파일이 여전히 큰 경우)
      if (compressedSize > 500 * 1024) { // 500KB 이상일 경우
        return await _applyExtraCompression(compressedFile, processedImage);
      }
      
      return compressedFile;
    } catch (e) {
      throw e;
    } finally {
      // 임시 파일 정리
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      
      // 메모리 해제 힌트
      processedImage.clear();
    }
  }
  
  /// 추가 압축이 필요한 경우 적용 (3단계)
  Future<File> _applyExtraCompression(File compressedFile, img.Image processedImage) async {
    // 더 강한 압축 적용
    final secondCompressBytes = await FlutterImageCompress.compressWithFile(
      compressedFile.path,
      minWidth: processedImage.width ~/ 1.2, // 약간 더 크기 축소
      minHeight: processedImage.height ~/ 1.2,
      quality: 65, // 낮은 품질로 다시 압축
      format: CompressFormat.jpeg,
    );
    
    if (secondCompressBytes != null && secondCompressBytes.isNotEmpty) {
      await compressedFile.writeAsBytes(secondCompressBytes);
    }
    
    return compressedFile;
  }
  
  /// 모든 압축 방법이 실패한 경우 대체 압축 방법 적용
  Future<File?> _applyFallbackCompression(File imageFile, String targetPath) async {
    // 직접 FlutterImageCompress로 압축 시도
    final result = await FlutterImageCompress.compressWithFile(
      imageFile.path,
      quality: 70,
      format: CompressFormat.jpeg,
    );
    
    if (result != null && result.isNotEmpty) {
      final File compressedFile = File(targetPath);
      await compressedFile.writeAsBytes(result);
      return compressedFile;
    }
    
    return null;
  }

  /// 저장된 이미지의 전체 경로 가져오기
  Future<String> getFullImagePath(String relativePath) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fullPath = '${appDir.path}/$relativePath';
      return fullPath;
    } catch (e) {
      debugPrint('이미지 경로 변환 중 오류: $e');
      // 오류 발생 시 상대 경로 그대로 반환
      return relativePath;
    }
  }

  /// 이미지가 정말 존재하는지 확인
  Future<bool> imageExists(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) {
      return false;
    }
    
    try {
      final fullPath = await getFullImagePath(relativePath);
      final file = File(fullPath);
      
      if (await file.exists()) {
        final fileSize = await file.length();
        final exists = fileSize > 0;
        return exists;
      }
      
      return false;
    } catch (e) {
      debugPrint('이미지 존재 여부 확인 중 오류: $e');
      return false;
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
      // 디스크에서 로드
      final fullPath = await getFullImagePath(relativePath);
      final file = File(fullPath);
      
      // 이미지 파일이 실제로 존재하는지 확인
      if (await file.exists()) {
        final fileSize = await file.length();
        if (fileSize > 0) {
          return file;
        }
      }
      
      // 로컬에 없으면 Firebase Storage에서 다운로드 시도
      final downloadedFile = await _downloadFromFirebaseStorage(relativePath, fullPath);
      if (downloadedFile != null) {
        return downloadedFile;
      }
      
      // 파일이 존재하지 않을 경우 null 반환
      return null;
    } catch (e) {
      debugPrint('이미지 서비스: 이미지 파일 가져오기 중 오류 발생: $e');
      return null;
    }
  }
  
  /// Firebase Storage에서 이미지 다운로드
  Future<File?> _downloadFromFirebaseStorage(String relativePath, String localPath) async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        return null;
      }
      
      // 사용자별 경로 지정: users/{userId}/images/{fileName}
      final storagePath = 'users/$userId/$relativePath';
      final storageRef = _storage.ref().child(storagePath);
      
      // 파일이 존재하는지 메타데이터로 확인
      try {
        await storageRef.getMetadata();
      } catch (e) {
        return null;
      }
      
      // 디렉토리 확인 및 생성
      final dirPath = path.dirname(localPath);
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // 로컬 파일 생성
      final file = File(localPath);
      
      // 파일 다운로드
      await storageRef.writeToFile(file);
      
      // 다운로드된 파일 확인
      if (await file.exists() && await file.length() > 0) {
        return file;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  /// 앱 에셋에서 더미 이미지를 파일로 복사
  Future<File?> _copyAssetImageToFile(String fullPath) async {
    try {
      // 디렉토리 확인 및 생성
      final dirPath = path.dirname(fullPath);
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // 파일 생성
      final file = File(fullPath);
      if (!await file.exists()) {
        await file.create(recursive: true);
        
        // 1x1 투명 PNG 데이터
        final placeholderBytes = [
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 
          0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 
          0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 
          0x0A, 0x49, 0x44, 0x41, 0x54, 0x08, 0xD7, 0x63, 0x60, 0x00, 0x00, 0x00, 
          0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, 0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 
          0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
        ];
        
        // 파일에 PNG 데이터 쓰기
        await file.writeAsBytes(placeholderBytes);
      }
      
      return file;
    } catch (e) {
      return null;
    }
  }

  /// 이미지 바이너리 데이터 가져오기
  Future<Uint8List?> getImageBytes(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) {
      return null;
    }

    try {
      // 파일 가져오기
      final file = await getImageFile(relativePath);
      if (file != null && await file.exists()) {
        try {
          // 파일을 바이너리로 읽기
          final bytes = await file.readAsBytes();
          // 빈 파일이 아닌지 확인
          if (bytes.isNotEmpty) {
            return bytes;
          }
        } catch (e) {
          debugPrint('이미지 바이너리 읽기 중 오류: $e');
        }
      }
      
      // 대체 이미지 데이터 제공 (실제 구현시 적절한 이미지 데이터 추가)
      return Uint8List(0);
    } catch (e) {
      debugPrint('이미지 바이너리 가져오기 중 오류 발생: $e');
      return null;
    }
  }

  /// 이미지 삭제
  Future<bool> deleteImage(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) {
      return false;
    }

    try {
      // 디스크에서 제거
      final file = await getImageFile(relativePath);
      if (file != null && await file.exists()) {
        // 파일 크기 확인 (사용량 추적 감소용)
        final fileSize = await file.length();
        
        // 파일 삭제
        await file.delete();
        
        // 저장 공간 사용량 감소 (향후 구현)
        
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('이미지 삭제 중 오류 발생: $e');
      return false;
    }
  }

  /// 이미지 업로드 (로컬 저장소에 저장)
  Future<String> uploadImage(File imageFile) async {
    try {
      // 사용량 제한 확인
      final usage = await _usageLimitService.getBetaUsageLimits();
      
      // 저장 공간 제한 도달 시 오류 발생
      if (usage['storageLimitReached'] == true) {
        throw Exception('저장 공간 제한에 도달했습니다. 더 이상 이미지를 업로드할 수 없습니다.');
      }
      
      // 이미지 저장 및 최적화
      final relativePath = await saveAndOptimizeImage(imageFile);
      return relativePath;
    } catch (e) {
      throw Exception('이미지 업로드 중 오류가 발생했습니다: $e');
    }
  }

  /// 갤러리에서 여러 이미지 선택
  Future<List<File>> pickMultipleImages() async {
    try {
      // 사용량 제한 확인
      final usage = await _usageLimitService.getBetaUsageLimits();
      
      // 저장 공간 제한 도달 시 오류 발생
      if (usage['storageLimitReached'] == true) {
        throw Exception('저장 공간 제한에 도달했습니다. 더 이상 이미지를 추가할 수 없습니다.');
      }
      
      final picker = ImagePicker();
      final pickedFiles = await picker.pickMultiImage();

      if (pickedFiles.isEmpty) {
        return [];
      }

      // XFile을 File로 변환
      return pickedFiles.map((xFile) => File(xFile.path)).toList();
    } catch (e) {
      throw Exception('이미지 선택 중 오류가 발생했습니다: $e');
    }
  }

  /// 사진 찍기/선택하기 (통합 메소드)
  Future<File?> pickImage({required ImageSource source}) async {
    try {
      // 사용량 제한 확인
      final usage = await _usageLimitService.getBetaUsageLimits();
      
      // 저장 공간 제한 도달 시 오류 발생
      if (usage['storageLimitReached'] == true) {
        throw Exception('저장 공간 제한에 도달했습니다. 더 이상 이미지를 추가할 수 없습니다.');
      }
      
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: source);

      if (pickedFile == null) {
        return null;
      }

      return File(pickedFile.path);
    } catch (e) {
      return null;
    }
  }

  /// 임시 파일 경로 생성 (제대로 정리되지 않으면 때때로 임시 파일이 쌓일 수 있음)
  Future<String> createTempFilePath() async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final uuid = const Uuid().v4();
    return '${tempDir.path}/image_${timestamp}_$uuid.jpg';
  }
  
  /// 임시 파일 정리
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
        // 삭제된 파일 개수 기록
      }
    } catch (e) {
      // 오류 무시
    }
  }
  
  /// 이미지 캐시 정리 (메모리 압박 시)
  Future<void> clearImageCache() async {
    try {
      // 대기 중인 이미지 프로바이더 캐시 정리
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (e) {
      // 오류 무시
    }
  }
  
  /// 현재 이미지 디렉토리 총 사용량 계산 (MB)
  Future<double> calculateTotalStorageUsage() async {
    try {
      // 앱 문서 폴더의 이미지 디렉토리
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/images');
      
      if (!await imagesDir.exists()) {
        return 0.0;
      }
      
      // 이미지 디렉토리 내 모든 파일의 크기 합산
      int totalBytes = 0;
      await for (final entity in imagesDir.list(recursive: true)) {
        if (entity is File) {
          try {
            final stats = await entity.stat();
            totalBytes += stats.size;
          } catch (e) {
            // 오류 무시
          }
        }
      }
      
      // MB 단위로 변환 (소수점 2자리까지)
      final totalMB = totalBytes / (1024 * 1024);
      
      return totalMB;
    } catch (e) {
      return 0.0;
    }
  }
}