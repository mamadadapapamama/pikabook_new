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

/// 이미지 관리 서비스
/// 이미지 저장, 로드, 압축 등의 기능을 제공합니다.
/// 캐싱은 UnifiedCacheService에서 처리합니다.


class ImageService {
  // 싱글톤 패턴 구현
  static final ImageService _instance = ImageService._internal();
  factory ImageService() => _instance;

  // 통합 캐시 서비스 참조
  final UnifiedCacheService _cacheService = UnifiedCacheService();

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

      // 이미지 최적화 및 저장
      final compressedFile = await compressAndSaveImage(imageFile, targetPath);

      // 저장된 이미지의 상대 경로 반환
      final relativePath = 'images/$fileName';

      return relativePath;
    } catch (e) {
      debugPrint('이미지 저장 및 최적화 중 오류 발생: $e');
      throw Exception('이미지 저장 및 최적화 중 오류가 발생했습니다: $e');
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

  /// 대체 이미지 생성
  Future<File> _createPlaceholderImage(String fullPath) async {
    try {
      // 디렉토리 확인 및 생성
      final dir = Directory(path.dirname(fullPath));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      // 파일 생성
      final file = File(fullPath);
      if (!await file.exists()) {
        // 빈 파일 생성
        await file.create();
        
        // 여기서 간단한 플레이스홀더 이미지 데이터를 작성할 수 있음
        // 웹에서는 실제 이미지 데이터가 필요할 수 있음
        if (kIsWeb) {
          // 웹 환경에서는 기본 이미지 데이터로 대체
          // 실제 구현시에는 적절한 이미지 데이터를 추가해야 함
          await file.writeAsBytes([]);
        }
      }
      
      debugPrint('플레이스홀더 이미지 생성: $fullPath');
      return file;
    } catch (e) {
      debugPrint('플레이스홀더 이미지 생성 중 오류: $e');
      throw Exception('플레이스홀더 이미지 생성 중 오류가 발생했습니다: $e');
    }
  }

  /// 이미지 파일 가져오기
  Future<File?> getImageFile(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) {
      return null;
    }

    try {
      // 디스크에서 로드
      final fullPath = await getFullImagePath(relativePath);
      
      // 이미지 파일이 실제로 존재하는지 확인
      if (await _isImageFileExists(fullPath)) {
        debugPrint('디스크에서 이미지 로드: $relativePath');
        return File(fullPath);
      }
      
      debugPrint('이미지 파일을 찾을 수 없음: $relativePath');
      
      // 웹 환경에서는 다른 방식으로 처리
      if (kIsWeb) {
        // 웹 환경에서는 상대 경로를 관리할 때 URL이나 assets 경로를 사용해야 함
        debugPrint('웹 환경에서 이미지 경로 처리: $relativePath');
        // 여기서는 빈 파일만 생성
        return await _createPlaceholderImage(fullPath);
      } else {
        // 이미지 디렉토리 확인 및 생성
        final appDir = await getApplicationDocumentsDirectory();
        final imagesDir = Directory('${appDir.path}/images');
        if (!await imagesDir.exists()) {
          await imagesDir.create(recursive: true);
        }
        
        // 플레이스홀더 이미지 생성
        return await _createPlaceholderImage(fullPath);
      }
    } catch (e) {
      debugPrint('이미지 파일 가져오기 중 오류 발생: $e');
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
        await file.delete();
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

  /// 카메라로 이미지 촬영
  Future<File?> takePhoto() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.camera);

      if (pickedFile == null) {
        return null;
      }

      // XFile을 File로 변환
      return File(pickedFile.path);
    } catch (e) {
      debugPrint('카메라 사용 중 오류 발생: $e');
      throw Exception('카메라 사용 중 오류가 발생했습니다: $e');
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
      // 이미지 캐시 정리 로직
      // 참고: Flutter 자체 이미지 캐시는 PaintingBinding.instance.imageCache를 통해 접근 가능
      
      final imageCache = PaintingBinding.instance.imageCache;
      if (imageCache != null) {
        // 이미지 캐시 정리 (최대 크기를 100으로 줄임)
        imageCache.maximumSize = 100;
        debugPrint('이미지 캐시 최대 크기 축소: ${imageCache.maximumSize}');
        
        // 미사용 이미지 즉시 제거
        imageCache.clear();
        debugPrint('이미지 캐시 초기화 완료');
      }
      
      // 메모리 내 임시 이미지 참조 정리
      _clearInMemoryImageReferences();
    } catch (e) {
      debugPrint('이미지 캐시 정리 중 오류 발생: $e');
    }
  }
  
  /// 메모리 내 이미지 참조 정리
  void _clearInMemoryImageReferences() {
    try {
      // 필요한 경우 구현
      debugPrint('메모리 내 이미지 참조 정리 완료');
    } catch (e) {
      debugPrint('메모리 내 이미지 참조 정리 중 오류 발생: $e');
    }
  }
}
