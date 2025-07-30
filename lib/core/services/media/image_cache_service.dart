import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

/// 이미지 캐싱 서비스
/// 앱 내에서 사용되는 이미지를 메모리에 캐싱하여 성능을 향상시킵니다.
/// 전역적으로 접근 가능한 싱글톤 패턴으로 구현되었습니다.
class ImageCacheService {
  // 싱글톤 인스턴스
  static final ImageCacheService _instance = ImageCacheService._internal();
  factory ImageCacheService() => _instance;

  // 캐시 설정 (메모리 최적화)
  static const int _maxCacheItems = 10; // 20 → 10 (50% 절약)
  static const int _maxCacheSize = 25 * 1024 * 1024; // 50MB → 25MB (50% 절약)

  // 이미지 바이트 캐시 (경로 -> 이미지 바이트)
  final Map<String, Uint8List> _memoryImageCache = {};
  
  // 이미지 키 타임스탬프 (LRU 정책용)
  final Map<String, DateTime> _accessTimestamps = {};
  
  final Map<String, int> _imageSizes = {};
  
  int _totalCacheSize = 0;
  
  // 캐시 적중/실패 통계
  int _cacheHits = 0;
  int _cacheMisses = 0;
  
  // Firebase Storage 참조
  final FirebaseStorage _storage = FirebaseStorage.instance;
  
  ImageCacheService._internal() {
    if (kDebugMode) {
      debugPrint('🖼️ ImageCacheService: 초기화됨');
    }
    
    // Flutter의 내장 이미지 캐시도 관리
    _configureFlutterImageCache();
  }
  
  /// Flutter의 내장 이미지 캐시 설정
  void _configureFlutterImageCache() {
    // 디버그 모드에서는 더 작은 크기의 캐시 사용
    final int imageCount = kDebugMode ? 50 : 100;
    final int sizeBytes = kDebugMode ? 50 * 1024 * 1024 : 100 * 1024 * 1024; // 50MB or 100MB
    
    PaintingBinding.instance.imageCache.maximumSize = imageCount;
    PaintingBinding.instance.imageCache.maximumSizeBytes = sizeBytes;
    
    if (kDebugMode) {
      debugPrint('Flutter 이미지 캐시 설정: 최대 $imageCount개 이미지, ${sizeBytes ~/ (1024 * 1024)}MB');
    }
  }
  
  /// 메모리 캐시에 이미지 추가
  void addToCache(String relativePath, Uint8List imageBytes) {
    if (imageBytes.isEmpty) return;
    
    final normalizedPath = _normalizePath(relativePath);
    final imageSize = imageBytes.length;
    
    // 캐시 크기 제한 확인
    while (_totalCacheSize + imageSize > _maxCacheSize || 
           _memoryImageCache.length >= _maxCacheItems) {
      _removeOldestItem();
    }
    
    // 새 항목 추가
    _memoryImageCache[normalizedPath] = imageBytes;
    _accessTimestamps[normalizedPath] = DateTime.now();
    _imageSizes[normalizedPath] = imageSize;
    _totalCacheSize += imageSize;
    
    if (kDebugMode) {
      debugPrint('캐시 추가: $normalizedPath (${imageSize ~/ 1024}KB)');
    }
  }
  
  /// 메모리 캐시에서 이미지 가져오기
  Uint8List? getFromCache(String? relativePath) {
    if (relativePath == null || relativePath.isEmpty) return null;
    
    final normalizedPath = _normalizePath(relativePath);
    final cachedBytes = _memoryImageCache[normalizedPath];
    
    if (cachedBytes != null) {
      _accessTimestamps[normalizedPath] = DateTime.now();
      _cacheHits++;
      return cachedBytes;
    }
    
      _cacheMisses++;
      return null;
    }
  
  void _removeOldestItem() {
    if (_memoryImageCache.isEmpty) return;
    
    String? oldestKey;
      DateTime? oldestTimestamp;
      
      _accessTimestamps.forEach((key, timestamp) {
        if (_memoryImageCache.containsKey(key) && 
            (oldestTimestamp == null || timestamp.isBefore(oldestTimestamp!))) {
          oldestTimestamp = timestamp;
        oldestKey = key;
        }
      });
      
    if (oldestKey != null) {
      removeFromCache(oldestKey!);
    }
  }
  
  /// 캐시 정리 (전체 또는 일부)
  void clearCache({bool partial = false}) {
    if (partial) {
      // 가장 오래된 항목부터 제거
      final itemsToKeep = _maxCacheItems ~/ 2;
      final sortedKeys = _accessTimestamps.keys.toList()
        ..sort((a, b) => _accessTimestamps[a]!.compareTo(_accessTimestamps[b]!));
      
      for (var i = 0; i < sortedKeys.length - itemsToKeep; i++) {
        removeFromCache(sortedKeys[i]);
      }
    } else {
      _memoryImageCache.clear();
      _accessTimestamps.clear();
      _imageSizes.clear();
      _totalCacheSize = 0;
      
      // Flutter 이미지 캐시도 정리
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      
      if (kDebugMode) {
        debugPrint('메모리 캐시 전체 정리 완료');
      }
    }
    
    // 통계 초기화
    _cacheHits = 0;
    _cacheMisses = 0;
  }
  
  /// 특정 이미지 경로 캐시에서 제거
  void removeFromCache(String relativePath) {
    final normalizedPath = _normalizePath(relativePath);
    final imageSize = _imageSizes[normalizedPath] ?? 0;
    
    _memoryImageCache.remove(normalizedPath);
    _accessTimestamps.remove(normalizedPath);
    _imageSizes.remove(normalizedPath);
    _totalCacheSize -= imageSize;
    
    if (kDebugMode) {
      debugPrint('메모리 캐시에서 이미지 제거: $normalizedPath');
    }
  }
  
  /// 경로 정규화 (OS별 경로 구분자 처리)
  String _normalizePath(String relativePath) {
    // URL이면 그대로 반환
    if (relativePath.startsWith('http')) {
      return relativePath;
    }
    
    // path 패키지로 정규화
    return path.normalize(relativePath).replaceAll('\\', '/');
  }
  
  /// 캐시 상태 정보 가져오기
  Map<String, dynamic> getCacheStats() {
    return {
      'itemCount': _memoryImageCache.length,
      'maxItems': _maxCacheItems,
      'totalSize': _totalCacheSize,
      'totalSizeMB': _totalCacheSize ~/ (1024 * 1024),
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'hitRatio': _cacheHits + _cacheMisses > 0 
          ? _cacheHits / (_cacheHits + _cacheMisses) 
          : 0.0,
    };
  }
  
  /// 이미지 피쳐 플래그 설정
  /// kDebugMode에서만 작동, 성능 벤치마킹 용도
  bool _disableImageCaching = false;
  
  void setDisableImageCaching(bool value) {
    if (!kDebugMode) return;
    
    _disableImageCaching = value;
    debugPrint('이미지 캐싱 ${value ? '비활성화' : '활성화'} 됨 (디버그 모드 전용)');
    
    if (value) {
      clearCache();
    }
  }
  
  /// 캐싱이 비활성화되었는지 확인
  bool get isCachingDisabled => _disableImageCaching && kDebugMode;
  
  /// Firebase Storage에서 이미지 다운로드 및 캐싱
  Future<Uint8List?> downloadAndCacheImage(String relativePath) async {
    try {
      final storageRef = _storage.ref().child(relativePath);
      final maxSize = 10 * 1024 * 1024; // 10MB 제한
      final bytes = await storageRef.getData(maxSize);
      
      if (bytes != null) {
        addToCache(relativePath, bytes);
        return bytes;
      }
      return null;
    } catch (e) {
      debugPrint('Firebase Storage에서 이미지 다운로드 실패: $e');
      return null;
    }
  }

  /// 이미지 캐시 정리
  /// 
  /// 메모리 캐시와 Flutter의 내장 이미지 캐시를 모두 정리합니다.
  Future<void> clearImageCache() async {
    try {
      clearCache();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      
      if (kDebugMode) {
        debugPrint('이미지 캐시 정리 완료');
      }
    } catch (e) {
      debugPrint('이미지 캐시 정리 실패: $e');
    }
  }

  /// 임시 이미지 파일 정리
  /// 
  /// 임시 디렉토리에서 24시간 이상 된 이미지 파일을 정리합니다.
  /// 이미지 파일은 'image_' 또는 '_img_'로 시작하고 .jpg 또는 .png로 끝나는 파일만 대상으로 합니다.
  Future<void> cleanupTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory(tempDir.path);
      final entities = await dir.list().toList();
      
      int removedCount = 0;
      
      for (var entity in entities) {
        if (entity is File) {
          final fileName = path.basename(entity.path);
          
          if ((fileName.contains('image_') || fileName.contains('_img_')) && 
              (fileName.endsWith('.jpg') || fileName.endsWith('.png'))) {
            
            final stat = await entity.stat();
            if (DateTime.now().difference(stat.modified).inHours > 24) {
              try {
                await entity.delete();
                removedCount++;
              } catch (e) {
                // 무시
              }
            }
          }
        }
      }
      
      if (kDebugMode && removedCount > 0) {
        debugPrint('$removedCount개의 임시 이미지 파일 정리됨');
      }
    } catch (e) {
      debugPrint('임시 파일 정리 실패: $e');
    }
  }

  /// 바이트 크기를 사람이 읽기 쉬운 형식으로 변환
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
} 