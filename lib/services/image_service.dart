import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ImageService {
  static final ImageService _instance = ImageService._internal();
  factory ImageService() => _instance;

  // 이미지 메모리 캐시 (상대 경로 -> 파일)
  final Map<String, File> _imageCache = {};

  // 이미지 바이너리 캐시 (상대 경로 -> 바이너리 데이터)
  final Map<String, Uint8List> _imageBinaryCache = {};

  // 캐시 타임스탬프 (상대 경로 -> 마지막 액세스 시간)
  final Map<String, DateTime> _cacheTimestamps = {};

  // 최대 캐시 항목 수
  final int _maxCacheItems = 100;

  // 캐시 유효 시간 (기본값: 24시간)
  final Duration _cacheValidity = const Duration(hours: 24);

  // SharedPreferences 키 접두사
  static const String _prefKeyPrefix = 'image_cache_timestamp_';

  ImageService._internal() {
    // 앱 시작 시 캐시 정리
    _cleanupExpiredCache();
  }

  // 이미지 파일을 앱의 영구 저장소에 저장하고 최적화
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

      // 메모리 캐시에 저장
      _cacheImage(relativePath, compressedFile);

      // 캐시 타임스탬프 저장
      await _saveCacheTimestamp(relativePath);

      return relativePath;
    } catch (e) {
      debugPrint('이미지 저장 및 최적화 중 오류 발생: $e');
      throw Exception('이미지 저장 및 최적화 중 오류가 발생했습니다: $e');
    }
  }

  // 이미지 압축 및 저장
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

  // 저장된 이미지의 전체 경로 가져오기
  Future<String> getFullImagePath(String relativePath) async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/$relativePath';
  }

  // 이미지 파일 가져오기 (캐싱 적용)
  Future<File?> getImageFile(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) {
      return null;
    }

    try {
      // 1. 메모리 캐시 확인
      if (_imageCache.containsKey(relativePath)) {
        // 캐시 타임스탬프 업데이트
        _cacheTimestamps[relativePath] = DateTime.now();
        await _saveCacheTimestamp(relativePath);
        debugPrint('메모리 캐시에서 이미지 로드: $relativePath');
        return _imageCache[relativePath];
      }

      // 2. 디스크에서 로드
      final fullPath = await getFullImagePath(relativePath);
      final file = File(fullPath);
      if (await file.exists()) {
        // 메모리 캐시에 저장
        _cacheImage(relativePath, file);
        await _saveCacheTimestamp(relativePath);
        debugPrint('디스크에서 이미지 로드 및 캐싱: $relativePath');
        return file;
      }

      debugPrint('이미지 파일을 찾을 수 없음: $relativePath');
      return null;
    } catch (e) {
      debugPrint('이미지 파일 가져오기 중 오류 발생: $e');
      return null;
    }
  }

  // 이미지 바이너리 데이터 가져오기 (캐싱 적용)
  Future<Uint8List?> getImageBytes(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) {
      return null;
    }

    try {
      // 1. 바이너리 메모리 캐시 확인
      if (_imageBinaryCache.containsKey(relativePath)) {
        // 캐시 타임스탬프 업데이트
        _cacheTimestamps[relativePath] = DateTime.now();
        await _saveCacheTimestamp(relativePath);
        debugPrint('바이너리 캐시에서 이미지 로드: $relativePath');
        return _imageBinaryCache[relativePath];
      }

      // 2. 파일 가져오기
      final file = await getImageFile(relativePath);
      if (file != null && await file.exists()) {
        // 파일을 바이너리로 읽고 캐시에 저장
        final bytes = await file.readAsBytes();
        _imageBinaryCache[relativePath] = bytes;
        _cacheTimestamps[relativePath] = DateTime.now();
        await _saveCacheTimestamp(relativePath);
        return bytes;
      }

      return null;
    } catch (e) {
      debugPrint('이미지 바이너리 가져오기 중 오류 발생: $e');
      return null;
    }
  }

  // 캐시 타임스탬프 저장
  Future<void> _saveCacheTimestamp(String relativePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_prefKeyPrefix$relativePath',
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      debugPrint('캐시 타임스탬프 저장 중 오류 발생: $e');
    }
  }

  // 캐시 타임스탬프 확인
  Future<bool> isCacheValid(String relativePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestampStr = prefs.getString('$_prefKeyPrefix$relativePath');

      if (timestampStr == null) return false;

      final timestamp = DateTime.parse(timestampStr);
      return DateTime.now().difference(timestamp) < _cacheValidity;
    } catch (e) {
      debugPrint('캐시 타임스탬프 확인 중 오류 발생: $e');
      return false;
    }
  }

  // 이미지를 메모리 캐시에 저장
  void _cacheImage(String relativePath, File file) {
    _imageCache[relativePath] = file;
    _cacheTimestamps[relativePath] = DateTime.now();

    // 캐시 크기 제한 확인
    _cleanCacheIfNeeded();
  }

  // 캐시 크기 제한을 위한 정리
  void _cleanCacheIfNeeded() {
    if (_imageCache.length <= _maxCacheItems) return;

    // 가장 오래된 항목부터 삭제
    final sortedEntries = _cacheTimestamps.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    // 캐시 크기를 80%로 줄임
    final itemsToRemove = (_imageCache.length - (_maxCacheItems * 0.8)).ceil();

    for (var i = 0; i < itemsToRemove && i < sortedEntries.length; i++) {
      final relativePath = sortedEntries[i].key;
      _imageCache.remove(relativePath);
      _imageBinaryCache.remove(relativePath);
      _cacheTimestamps.remove(relativePath);
      debugPrint('메모리 캐시에서 이미지 제거: $relativePath');
    }
  }

  // 만료된 캐시 정리
  Future<void> _cleanupExpiredCache() async {
    try {
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      // 만료된 타임스탬프 제거
      for (final key in allKeys) {
        if (key.startsWith(_prefKeyPrefix)) {
          final timestampStr = prefs.getString(key);
          if (timestampStr != null) {
            final timestamp = DateTime.parse(timestampStr);
            if (now.difference(timestamp) > _cacheValidity) {
              await prefs.remove(key);
              final relativePath = key.substring(_prefKeyPrefix.length);
              debugPrint('만료된 이미지 캐시 타임스탬프 제거: $relativePath');
            }
          }
        }
      }

      // 메모리 캐시에서 만료된 항목 제거
      final expiredKeys = <String>[];
      _cacheTimestamps.forEach((key, timestamp) {
        if (now.difference(timestamp) > _cacheValidity) {
          expiredKeys.add(key);
        }
      });

      for (final key in expiredKeys) {
        _imageCache.remove(key);
        _imageBinaryCache.remove(key);
        _cacheTimestamps.remove(key);
        debugPrint('만료된 이미지 메모리 캐시 제거: $key');
      }
    } catch (e) {
      debugPrint('만료된 캐시 정리 중 오류 발생: $e');
    }
  }

  // 메모리 캐시 초기화
  void clearMemoryCache() {
    _imageCache.clear();
    _imageBinaryCache.clear();
    _cacheTimestamps.clear();
    debugPrint('이미지 메모리 캐시 초기화 완료');
  }

  // 이미지 삭제
  Future<bool> deleteImage(String? relativePath) async {
    if (relativePath == null || relativePath.isEmpty) {
      return false;
    }

    try {
      // 메모리 캐시에서 제거
      _imageCache.remove(relativePath);
      _imageBinaryCache.remove(relativePath);
      _cacheTimestamps.remove(relativePath);

      // 캐시 타임스탬프 제거
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefKeyPrefix$relativePath');

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

  // 이미지 업로드 (로컬 저장소에 저장)
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

  // 갤러리에서 여러 이미지 선택
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

  // 카메라로 이미지 촬영
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

  // 캐시 통계 정보 (디버깅용)
  Map<String, dynamic> getCacheStats() {
    return {
      'memoryItems': _imageCache.length,
      'binaryItems': _imageBinaryCache.length,
      'oldestCacheTime': _cacheTimestamps.isEmpty
          ? null
          : _cacheTimestamps.values.reduce((a, b) => a.isBefore(b) ? a : b),
      'newestCacheTime': _cacheTimestamps.isEmpty
          ? null
          : _cacheTimestamps.values.reduce((a, b) => a.isAfter(b) ? a : b),
    };
  }

  // 모든 캐시 초기화
  Future<void> clearAllCache() async {
    // 메모리 캐시 초기화
    clearMemoryCache();

    // 타임스탬프 초기화
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      for (final key in allKeys) {
        if (key.startsWith(_prefKeyPrefix)) {
          await prefs.remove(key);
        }
      }

      debugPrint('이미지 캐시 타임스탬프 초기화 완료');
    } catch (e) {
      debugPrint('이미지 캐시 타임스탬프 초기화 중 오류 발생: $e');
    }
  }
}
