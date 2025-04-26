import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as path;

/// 이미지 캐싱 서비스
/// 앱 내에서 사용되는 이미지를 메모리에 캐싱하여 성능을 향상시킵니다.
/// 전역적으로 접근 가능한 싱글톤 패턴으로 구현되었습니다.
class ImageCacheService {
  // 싱글톤 인스턴스
  static final ImageCacheService _instance = ImageCacheService._internal();
  factory ImageCacheService() => _instance;

  // 이미지 바이트 캐시 (경로 -> 이미지 바이트)
  final Map<String, Uint8List> _memoryImageCache = {};
  
  // 이미지 키 타임스탬프 (LRU 정책용)
  final Map<String, DateTime> _accessTimestamps = {};
  
  // 캐시 크기 제한
  final int _maxCacheSize = 20; // 메모리에 최대 20개 이미지만 보관
  
  // 캐시 적중/실패 통계
  int _cacheHits = 0;
  int _cacheMisses = 0;
  
  ImageCacheService._internal() {
    if (kDebugMode) {
      debugPrint('🖼️ ImageCacheService: 내부 생성자(_internal) 호출됨');
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
    
    if (kDebugMode) {
      debugPrint('메모리 캐시에 이미지 추가: $relativePath (${imageBytes.length ~/ 1024}KB)');
    }
    
    // 캐시 크기 제한 확인 및 관리
    _manageCache();
    
    // 경로 정규화 (슬래시 방향 통일)
    final normalizedPath = _normalizePath(relativePath);
    
    // 캐시에 추가
    _memoryImageCache[normalizedPath] = imageBytes;
    _accessTimestamps[normalizedPath] = DateTime.now();
  }
  
  /// 메모리 캐시에서 이미지 가져오기
  Uint8List? getFromCache(String? relativePath) {
    if (relativePath == null || relativePath.isEmpty) return null;
    
    // 경로 정규화 (슬래시 방향 통일)
    final normalizedPath = _normalizePath(relativePath);
    
    // 캐시에서 이미지 조회
    final cachedBytes = _memoryImageCache[normalizedPath];
    
    if (cachedBytes != null) {
      // 접근 타임스탬프 업데이트 (LRU 정책)
      _accessTimestamps[normalizedPath] = DateTime.now();
      
      // 캐시 적중 통계 업데이트
      _cacheHits++;
      
      if (kDebugMode && _cacheHits % 10 == 0) { // 로그 줄이기 위해 10번에 1번만 출력
        debugPrint('메모리 캐시 히트($_cacheHits번째): $normalizedPath');
      }
      
      return cachedBytes;
    } else {
      // 캐시 미스 통계 업데이트
      _cacheMisses++;
      return null;
    }
  }
  
  /// 캐시 관리 (LRU - Least Recently Used 정책)
  void _manageCache() {
    // 캐시 크기가 제한을 초과하는 경우
    if (_memoryImageCache.length >= _maxCacheSize) {
      // 가장 오래 사용되지 않은 항목 찾기
      String? leastRecentlyUsedKey;
      DateTime? oldestTimestamp;
      
      _accessTimestamps.forEach((key, timestamp) {
        if (_memoryImageCache.containsKey(key) && 
            (oldestTimestamp == null || timestamp.isBefore(oldestTimestamp!))) {
          oldestTimestamp = timestamp;
          leastRecentlyUsedKey = key;
        }
      });
      
      // 가장 오래 사용되지 않은 항목 제거
      if (leastRecentlyUsedKey != null) {
        _memoryImageCache.remove(leastRecentlyUsedKey);
        _accessTimestamps.remove(leastRecentlyUsedKey);
        
        if (kDebugMode) {
          debugPrint('메모리 캐시 정리: $leastRecentlyUsedKey 제거됨 (LRU 정책)');
        }
      }
    }
  }
  
  /// 캐시 정리 (전체 또는 일부)
  void clearCache({bool partial = false}) {
    if (partial) {
      // 부분 정리: 절반만 정리
      final itemsToKeep = _maxCacheSize ~/ 2;
      
      // 최근 접근 시간으로 정렬
      final sortedKeys = _accessTimestamps.keys.toList()
        ..sort((a, b) {
          final timeA = _accessTimestamps[a]!;
          final timeB = _accessTimestamps[b]!;
          return timeB.compareTo(timeA); // 최근 것이 앞으로 (내림차순)
        });
      
      // 최근 항목들은 유지, 나머지는 제거
      final keysToKeep = sortedKeys.take(itemsToKeep).toSet();
      final keysToRemove = _memoryImageCache.keys
          .where((key) => !keysToKeep.contains(key))
          .toList();
      
      for (final key in keysToRemove) {
        _memoryImageCache.remove(key);
        _accessTimestamps.remove(key);
      }
      
      if (kDebugMode) {
        debugPrint('메모리 캐시 부분 정리: ${keysToRemove.length}개 항목 제거됨');
      }
    } else {
      // 전체 정리
      _memoryImageCache.clear();
      _accessTimestamps.clear();
      
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
    
    _memoryImageCache.remove(normalizedPath);
    _accessTimestamps.remove(normalizedPath);
    
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
    final totalBytes = _memoryImageCache.values
        .fold<int>(0, (sum, bytes) => sum + bytes.length);
    
    return {
      'itemCount': _memoryImageCache.length,
      'maxItems': _maxCacheSize,
      'totalBytes': totalBytes,
      'totalKB': totalBytes ~/ 1024,
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
} 