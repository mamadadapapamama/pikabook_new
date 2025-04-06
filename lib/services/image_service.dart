import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'unified_cache_service.dart';
import 'usage_limit_service.dart';
import 'package:image/image.dart' as img;

/// 이미지 관리 서비스
/// 이미지 저장, 로드, 압축 등의 기능을 제공합니다.
/// 캐싱은 UnifiedCacheService에서 처리합니다.


class ImageService {
  // 싱글톤 패턴 구현
  static final ImageService _instance = ImageService._internal();
  factory ImageService() => _instance;

  // 통합 캐시 서비스 참조
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  
  // 사용량 제한 서비스
  final UsageLimitService _usageLimitService = UsageLimitService();
  
  // Firebase Storage 참조
  final FirebaseStorage _storage = FirebaseStorage.instance;

  ImageService._internal();

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

      // 고유한 파일명 생성
      final uuid = const Uuid().v4();
      final fileExtension = path.extension(imageFile.path);
      final fileName = '$uuid$fileExtension';
      final targetPath = '${imagesDir.path}/$fileName';

      // 원본 파일 크기 확인 (사용량 추적용)
      final originalFileSize = await imageFile.length();

      // 이미지 최적화 및 저장
      final compressedFile = await compressAndSaveImage(imageFile, targetPath);
      
      // 압축 후 파일 크기 확인 (사용량 추적용)
      final compressedFileSize = await compressedFile.length();
      
      // 저장된 이미지의 상대 경로 반환
      final relativePath = 'images/$fileName';
      
      // Firebase Storage에 업로드 시도
      try {
        await _uploadToFirebaseStorage(compressedFile, relativePath);
      } catch (e) {
        debugPrint('Firebase Storage 업로드 실패, 로컬만 저장됨: $e');
      }
      
      // 스토리지 사용량 추적 - 압축된 실제 파일 크기 사용
      await _trackStorageUsage(compressedFile);
      
      debugPrint('이미지 압축 완료: ${(originalFileSize / 1024).toStringAsFixed(2)}KB -> ${(compressedFileSize / 1024).toStringAsFixed(2)}KB (${(100 - (compressedFileSize / originalFileSize * 100)).toStringAsFixed(0)}% 감소)');

      return relativePath;
    } catch (e) {
      debugPrint('이미지 저장 및 최적화 중 오류 발생: $e');
      throw Exception('이미지 저장 및 최적화 중 오류가 발생했습니다: $e');
    }
  }
  
  /// Firebase Storage에 이미지 업로드
  Future<String> _uploadToFirebaseStorage(File file, String relativePath) async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        throw Exception('로그인이 필요합니다');
      }
      
      // 사용자별 경로 지정: users/{userId}/images/{fileName}
      final storagePath = 'users/$userId/$relativePath';
      final storageRef = _storage.ref().child(storagePath);
      
      // 이미지 업로드
      debugPrint('Firebase Storage에 이미지 업로드 시작: $storagePath');
      final uploadTask = storageRef.putFile(file);
      
      // 업로드 상태 모니터링 (선택적)
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        debugPrint('이미지 업로드 진행률: ${(progress * 100).toStringAsFixed(1)}%');
      });
      
      // 업로드 완료 대기
      final snapshot = await uploadTask;
      
      // 이미지 URL 가져오기
      final downloadUrl = await snapshot.ref.getDownloadURL();
      debugPrint('Firebase Storage 업로드 완료: $downloadUrl');
      
      return downloadUrl;
    } catch (e) {
      debugPrint('Firebase Storage 업로드 중 오류: $e');
      throw e;
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
      
      debugPrint('저장 공간 사용량 추가: ${(actualSize / 1024).toStringAsFixed(2)}KB');
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
      
      // 더 적극적인 이미지 리사이징 적용 (파일 크기 감소)
      img.Image processedImage;
      final int maxDimension = 1200; // 최대 너비/높이 제한 - 더 작게 설정
      
      if (originalWidth > maxDimension || originalHeight > maxDimension) {
        // 비율 유지하며 리사이징
        if (originalWidth > originalHeight) {
          final ratio = maxDimension / originalWidth;
          processedImage = img.copyResize(
            image,
            width: maxDimension,
            height: (originalHeight * ratio).round(),
            interpolation: img.Interpolation.average,
          );
        } else {
          final ratio = maxDimension / originalHeight;
          processedImage = img.copyResize(
            image,
            width: (originalWidth * ratio).round(), 
            height: maxDimension,
            interpolation: img.Interpolation.average,
          );
        }
        debugPrint('이미지 리사이징: $originalWidth x $originalHeight → ${processedImage.width} x ${processedImage.height}');
      } else {
        processedImage = image;
      }
      
      // iOS 앱 스토어 리뷰를 위한 메모리 최적화
      // 메타데이터 관련 코드는 해당 라이브러리에서 직접 지원하지 않으므로 제거
      
      // 압축 및 저장 (파일 크기 최적화를 위해 높은 압축률 사용)
      final compressedBytes = img.encodeJpg(
        processedImage,
        quality: 65, // 이미지 품질 (파일 크기 최적화를 위해 65로 낮춤)
      );
      
      // 앱 스토어 리뷰 최적화: 메모리 관리 개선
      final File compressedFile = File(targetPath);
      await compressedFile.writeAsBytes(compressedBytes);
      
      // 압축 후 실제 파일 크기 확인
      final compressedSize = await compressedFile.length();
      debugPrint('압축 전 이미지 크기: ${imageBytes.length} 바이트, 압축 후: $compressedSize 바이트');
      
      // 메모리 해제를 위한 명시적 처리
      imageBytes.clear();
      processedImage.clear(); // 처리된 이미지도 명시적으로 메모리 해제
      
      // 백그라운드에서 GC 힌트
      scheduleMicrotask(() {
        // 가비지 컬렉션 힌트
        debugPrint('이미지 처리 후 메모리 최적화 수행');
      });
      
      return compressedFile;
    } catch (e) {
      debugPrint('이미지 압축 및 저장 중 오류 발생: $e');
      // 원본 이미지를 그대로 복사 (압축 실패 시 대체 방안)
      final origFile = await imageFile.copy(targetPath);
      
      // 원본 이미지를 사용할 경우에도 저장 공간 사용량 추적 코드 제거 (중복 추적 방지)
      
      return origFile;
    }
  }

  /// 저장된 이미지의 전체 경로 가져오기
  Future<String> getFullImagePath(String relativePath) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fullPath = '${appDir.path}/$relativePath';
      debugPrint('이미지 전체 경로 변환: $relativePath → $fullPath');
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
      debugPrint('이미지 존재 확인: 경로가 비어있음');
      return false;
    }
    
    try {
      final fullPath = await getFullImagePath(relativePath);
      final file = File(fullPath);
      
      if (await file.exists()) {
        final fileSize = await file.length();
        final exists = fileSize > 0;
        debugPrint('이미지 존재 확인: $relativePath (${exists ? '존재함' : '크기가 0'}, 크기: $fileSize 바이트)');
        return exists;
      }
      
      debugPrint('이미지 존재 확인: $relativePath (파일 없음)');
      return false;
    } catch (e) {
      debugPrint('이미지 존재 여부 확인 중 오류: $e');
      return false;
    }
  }

  /// 이미지 파일 가져오기
  Future<File?> getImageFile(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) {
      debugPrint('이미지 서비스: 상대 경로가 비어있습니다');
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
          debugPrint('이미지 서비스: 디스크에서 이미지 로드 성공: $relativePath (크기: $fileSize 바이트)');
          return file;
        } else {
          debugPrint('이미지 서비스: 파일은 존재하지만 크기가 0입니다: $relativePath');
        }
      }
      
      debugPrint('이미지 서비스: 로컬 이미지 파일을 찾을 수 없음: $relativePath (경로: $fullPath), Firebase에서 시도합니다...');
      
      // 로컬에 없으면 Firebase Storage에서 다운로드 시도
      final downloadedFile = await _downloadFromFirebaseStorage(relativePath, fullPath);
      if (downloadedFile != null) {
        debugPrint('이미지 서비스: Firebase에서 이미지 다운로드 성공: $relativePath');
        return downloadedFile;
      }
      
      debugPrint('이미지 서비스: 이미지 파일을 Firebase에서도 찾을 수 없음: $relativePath');
      
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
        debugPrint('Firebase Storage에 이미지가 없음: $storagePath');
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
      debugPrint('Firebase Storage에서 이미지 다운로드 시작: $storagePath');
      await storageRef.writeToFile(file);
      
      // 다운로드된 파일 확인
      if (await file.exists() && await file.length() > 0) {
        debugPrint('Firebase Storage에서 다운로드 완료: $localPath (${await file.length()} 바이트)');
        return file;
      } else {
        debugPrint('Firebase Storage에서 다운로드 실패: 파일이 비어있거나 없음');
        return null;
      }
    } catch (e) {
      debugPrint('Firebase Storage에서 다운로드 중 오류: $e');
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
        debugPrint('더미 이미지 파일 생성 완료: $fullPath (1x1 투명 PNG)');
      }
      
      return file;
    } catch (e) {
      debugPrint('더미 이미지 파일 생성 중 오류: $e');
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
      debugPrint('이미지 업로드 중 오류 발생: $e');
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
      debugPrint('이미지 선택 중 오류 발생: $e');
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
      debugPrint('이미지 선택 중 오류 발생: $e');
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
                debugPrint('임시 파일 삭제 중 오류: $e');
              }
            }
          }
        }
      }
      
      if (removedCount > 0) {
        debugPrint('임시 이미지 파일 $removedCount개 정리 완료');
      }
    } catch (e) {
      debugPrint('임시 파일 정리 중 오류 발생: $e');
    }
  }
  
  /// 이미지 캐시 정리 (메모리 압박 시)
  Future<void> clearImageCache() async {
    try {
      // 대기 중인 이미지 프로바이더 캐시 정리
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      
      debugPrint('이미지 메모리 캐시 정리 완료');
    } catch (e) {
      debugPrint('이미지 캐시 정리 중 오류 발생: $e');
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
            debugPrint('파일 크기 확인 중 오류: $e');
          }
        }
      }
      
      // MB 단위로 변환 (소수점 2자리까지)
      final totalMB = totalBytes / (1024 * 1024);
      debugPrint('총 이미지 저장 공간 사용량: ${totalMB.toStringAsFixed(2)}MB');
      
      return totalMB;
    } catch (e) {
      debugPrint('저장 공간 사용량 계산 중 오류: $e');
      return 0.0;
    }
  }
  
  /// 이미지 저장소 초기화 (위험한 작업 - 신중히 사용)
  Future<bool> initializeImageStorage() async {
    try {
      // 앱 문서 폴더의 이미지 디렉토리
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/images');
      
      if (await imagesDir.exists()) {
        // 디렉토리 전체 삭제
        await imagesDir.delete(recursive: true);
        
        // 디렉토리 다시 생성
        await imagesDir.create(recursive: true);
        
        debugPrint('이미지 저장소 초기화 완료');
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('이미지 저장소 초기화 중 오류: $e');
      return false;
    }
  }
}