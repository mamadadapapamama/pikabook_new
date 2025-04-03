import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'unified_cache_service.dart';
import 'usage_limit_service.dart';

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
      
      // 스토리지 사용량 추적 (사용량 제한 확인 후 업데이트)
      await _trackStorageUsage(compressedFileSize);
      
      debugPrint('이미지 압축 완료: ${(originalFileSize / 1024).toStringAsFixed(2)}KB -> ${(compressedFileSize / 1024).toStringAsFixed(2)}KB (${(100 - (compressedFileSize / originalFileSize * 100)).toStringAsFixed(0)}% 감소)');

      return relativePath;
    } catch (e) {
      debugPrint('이미지 저장 및 최적화 중 오류 발생: $e');
      throw Exception('이미지 저장 및 최적화 중 오류가 발생했습니다: $e');
    }
  }
  
  /// 저장 공간 사용량 추적
  Future<bool> _trackStorageUsage(int sizeInBytes) async {
    try {
      final canAddStorage = await _usageLimitService.addStorageUsage(sizeInBytes);
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
  Future<File> compressAndSaveImage(File file, String targetPath) async {
    try {
      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        targetPath,
        quality: 70,
        minWidth: 1000,
        minHeight: 1000,
      );

      if (result == null) {
        throw Exception('이미지 압축에 실패했습니다.');
      }

      // XFile을 File로 변환
      return File(result.path);
    } catch (e) {
      debugPrint('이미지 압축 중 오류 발생: $e');
      // 압축에 실패한 경우 원본 파일을 복사
      final newFile = await file.copy(targetPath);
      return newFile;
    }
  }

  /// 저장된 이미지의 전체 경로 가져오기
  Future<String> getFullImagePath(String relativePath) async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/$relativePath';
  }

  /// 이미지가 정말 존재하는지 확인
  Future<bool> _isImageFileExists(String fullPath) async {
    try {
      final file = File(fullPath);
      final exists = await file.exists();
      
      if (exists) {
        // 파일 크기 확인 (0바이트 파일인지 체크)
        final stat = await file.stat();
        if (stat.size > 0) {
          return true;
        }
      }
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
          return null;
        }
      }
      
      debugPrint('이미지 서비스: 이미지 파일을 찾을 수 없음: $relativePath (경로: $fullPath)');
      
      // 파일이 존재하지 않을 경우 null 반환
      return null;
    } catch (e) {
      debugPrint('이미지 서비스: 이미지 파일 가져오기 중 오류 발생: $e');
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

  /// 이미지가 존재하는지 확인
  Future<bool> imageExists(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) {
      return false;
    }
    
    try {
      final fullPath = await getFullImagePath(relativePath);
      final file = File(fullPath);
      
      if (await file.exists()) {
        final fileSize = await file.length();
        return fileSize > 0;
      }
      
      return false;
    } catch (e) {
      debugPrint('이미지 존재 여부 확인 중 오류: $e');
      return false;
    }
  }
}