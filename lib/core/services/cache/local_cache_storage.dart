import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'cache_storage.dart';

/// 로컬 캐시 저장소 구현
/// SharedPreferences와 파일 시스템을 사용합니다.
class LocalCacheStorage<T> implements CacheStorage<T>, BinaryCacheStorage {
  final String _namespace;
  final int _maxSize;
  final int _maxItems;
  final Duration _defaultTtl;
  final T Function(Map<String, dynamic>)? _fromJson;
  final Map<String, dynamic> Function(T)? _toJson;

  // 메모리 캐시
  final Map<String, T> _memoryCache = {};
  final Map<String, CacheMetadata> _metadata = {};
  
  SharedPreferences? _prefs;
  Directory? _cacheDir;
  bool _isInitialized = false;

  LocalCacheStorage({
    required String namespace,
    required int maxSize,
    required int maxItems,
    Duration defaultTtl = const Duration(days: 30),
    T Function(Map<String, dynamic>)? fromJson,
    Map<String, dynamic> Function(T)? toJson,
  })  : _namespace = namespace,
        _maxSize = maxSize,
        _maxItems = maxItems,
        _defaultTtl = defaultTtl,
        _fromJson = fromJson,
        _toJson = toJson;

  /// 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (kDebugMode) {
        debugPrint('📦 LocalCacheStorage($_namespace) 초기화 시작');
      }

      if (kDebugMode) {
        debugPrint('📦 LocalCacheStorage($_namespace) SharedPreferences 요청 중...');
      }
      _prefs = await SharedPreferences.getInstance();
      if (kDebugMode) {
        debugPrint('📦 LocalCacheStorage($_namespace) SharedPreferences 완료');
      }

      if (kDebugMode) {
        if (kDebugMode) {
      debugPrint('📦 LocalCacheStorage($_namespace) 캐시 디렉토리 생성 중...');
    }
      }
      _cacheDir = await _getCacheDirectory();
      await _cacheDir!.create(recursive: true);
      if (kDebugMode) {
        debugPrint('📦 LocalCacheStorage($_namespace) 캐시 디렉토리 생성 완료: ${_cacheDir!.path}');
      }
      
      if (kDebugMode) {
        debugPrint('📦 LocalCacheStorage($_namespace) 메타데이터 로드 중...');
      }
      await _loadMetadata();
      if (kDebugMode) {
        debugPrint('📦 LocalCacheStorage($_namespace) 메타데이터 로드 완료');
      }

      if (kDebugMode) {
        debugPrint('📦 LocalCacheStorage($_namespace) 만료된 캐시 정리 중...');
      }
      await cleanupExpired();
      if (kDebugMode) {
        debugPrint('📦 LocalCacheStorage($_namespace) 만료된 캐시 정리 완료');
      }
      
      _isInitialized = true;
      
      if (kDebugMode) {
        debugPrint('📦 LocalCacheStorage($_namespace) 초기화 완료');
        debugPrint('   항목: ${_metadata.length}개');
        debugPrint('   크기: ${_formatSize(await getSize())}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ LocalCacheStorage($_namespace) 초기화 실패: $e');
      }
      rethrow;
    }
  }

  @override
  Future<T?> get(String key) async {
    await _ensureInitialized();
    
    try {
      final fullKey = _getFullKey(key);
      
      // 1. 메모리 캐시 확인
      if (_memoryCache.containsKey(fullKey)) {
        await _updateAccessTime(fullKey);
        return _memoryCache[fullKey];
      }

      // 2. 메타데이터 확인
      final metadata = _metadata[fullKey];
      if (metadata == null || metadata.isExpired) {
        return null;
      }

      // 3. SharedPreferences에서 로드
      final jsonString = _prefs!.getString(fullKey);
      if (jsonString != null && _fromJson != null) {
        final jsonData = json.decode(jsonString) as Map<String, dynamic>;
        final value = _fromJson!(jsonData);
        
        // 메모리 캐시에 저장
        _memoryCache[fullKey] = value;
        await _updateAccessTime(fullKey);
        
        return value;
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 캐시 조회 실패($_namespace): $key, $e');
      }
      return null;
    }
  }

  @override
  Future<void> set(String key, T value, {Duration? ttl}) async {
    await _ensureInitialized();
    
    try {
      final fullKey = _getFullKey(key);
      final effectiveTtl = ttl ?? _defaultTtl;
      final now = DateTime.now();
      
      // JSON 직렬화
      String? jsonString;
      int dataSize = 0;
      
      if (_toJson != null) {
        final jsonData = _toJson!(value);
        jsonString = json.encode(jsonData);
        dataSize = jsonString.length;
      }

      // 용량 확인 및 정리
      await _ensureCapacity(dataSize);

      // SharedPreferences에 저장
      if (jsonString != null) {
        await _prefs!.setString(fullKey, jsonString);
      }

      // 메모리 캐시 업데이트
      _memoryCache[fullKey] = value;
      
      // 메타데이터 업데이트
      _metadata[fullKey] = CacheMetadata(
        key: fullKey,
        createdAt: now,
        lastAccessedAt: now,
        expiresAt: now.add(effectiveTtl),
        size: dataSize,
        dataType: T.toString(),
      );

      await _saveMetadata();
      
      if (kDebugMode) {
        if (kDebugMode) {
        debugPrint('📦 캐시 저장($_namespace): $key (${_formatSize(dataSize)})');
      }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 캐시 저장 실패($_namespace): $key, $e');
      }
      rethrow;
    }
  }

  @override
  Future<void> delete(String key) async {
    await _ensureInitialized();
    
    try {
      final fullKey = _getFullKey(key);
      
      await _prefs!.remove(fullKey);
      _memoryCache.remove(fullKey);
      _metadata.remove(fullKey);
      
      await _saveMetadata();
      
      if (kDebugMode) {
        debugPrint('📦 캐시 삭제($_namespace): $key');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 캐시 삭제 실패($_namespace): $key, $e');
      }
    }
  }

  @override
  Future<void> deleteByPattern(String pattern) async {
    await _ensureInitialized();
    
    try {
      final regex = RegExp(pattern);
      final keysToDelete = _metadata.keys
          .where((key) => regex.hasMatch(key))
          .toList();

      for (final key in keysToDelete) {
        await _prefs!.remove(key);
        _memoryCache.remove(key);
        _metadata.remove(key);
      }

      await _saveMetadata();
      
      if (kDebugMode) {
        debugPrint('📦 패턴 캐시 삭제($_namespace): $pattern (${keysToDelete.length}개)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 패턴 캐시 삭제 실패($_namespace): $pattern, $e');
      }
    }
  }

  @override
  Future<void> clear() async {
    await _ensureInitialized();
    
    try {
      // SharedPreferences에서 네임스페이스 키들 삭제
      final keys = _prefs!.getKeys()
          .where((key) => key.startsWith('${_namespace}:'))
          .toList();
      
      for (final key in keys) {
        await _prefs!.remove(key);
      }

      // 캐시 디렉토리 삭제
      if (await _cacheDir!.exists()) {
        await _cacheDir!.delete(recursive: true);
        await _cacheDir!.create(recursive: true);
      }

      _memoryCache.clear();
      _metadata.clear();
      
      await _saveMetadata();
      
      if (kDebugMode) {
        debugPrint('📦 전체 캐시 삭제($_namespace): ${keys.length}개');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 전체 캐시 삭제 실패($_namespace): $e');
      }
    }
  }

  @override
  Future<List<String>> getKeys() async {
    await _ensureInitialized();
    return _metadata.keys
        .map((fullKey) => _getOriginalKey(fullKey))
        .toList();
  }

  @override
  Future<int> getSize() async {
    await _ensureInitialized();
    return _metadata.values
        .fold<int>(0, (sum, metadata) => sum + metadata.size);
  }

  @override
  Future<int> getItemCount() async {
    await _ensureInitialized();
    return _metadata.length;
  }

  @override
  Future<void> cleanupExpired() async {
    // 초기화되지 않은 상태에서는 실행하지 않음 (순환 호출 방지)
    if (!_isInitialized) return;
    
    try {
      if (kDebugMode) {
        debugPrint('📦 LocalCacheStorage($_namespace) 만료된 캐시 검색 시작');
      }
      
      final now = DateTime.now();
      final expiredKeys = _metadata.entries
          .where((entry) => entry.value.isExpired)
          .map((entry) => entry.key)
          .toList();

      if (kDebugMode) {
        debugPrint('📦 LocalCacheStorage($_namespace) 만료된 캐시 검색 완료: ${expiredKeys.length}개 발견');
      }

      if (expiredKeys.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('📦 LocalCacheStorage($_namespace) 만료된 캐시 삭제 시작');
        }
        
        for (final key in expiredKeys) {
          await _prefs!.remove(key);
          _memoryCache.remove(key);
          _metadata.remove(key);
        }

        if (kDebugMode) {
          debugPrint('📦 LocalCacheStorage($_namespace) 만료된 캐시 삭제 완료');
        }

        if (kDebugMode) {
          debugPrint('📦 LocalCacheStorage($_namespace) 메타데이터 저장 시작');
        }
        
        await _saveMetadata();
        
        if (kDebugMode) {
          debugPrint('📦 LocalCacheStorage($_namespace) 메타데이터 저장 완료');
        }
        
        if (kDebugMode) {
          debugPrint('📦 만료된 캐시 정리($_namespace): ${expiredKeys.length}개');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 만료된 캐시 정리 실패($_namespace): $e');
      }
    }
  }

  @override
  Future<Map<String, dynamic>> getStats() async {
    await _ensureInitialized();
    
    final totalSize = await getSize();
    final itemCount = await getItemCount();
    
    return {
      'namespace': _namespace,
      'itemCount': itemCount,
      'maxItems': _maxItems,
      'totalSize': totalSize,
      'totalSizeMB': totalSize / (1024 * 1024),
      'maxSizeMB': _maxSize / (1024 * 1024),
      'usagePercent': totalSize > 0 && _maxSize > 0 ? (totalSize / _maxSize * 100).round() : 0,
      'memoryHitRate': _memoryCache.length > 0 && itemCount > 0 ? (_memoryCache.length / itemCount * 100).round() : 0,
    };
  }

  // === BinaryCacheStorage 구현 ===

  @override
  Future<Uint8List?> getBinary(String key) async {
    await _ensureInitialized();
    
    try {
      final filePath = await getFilePath(key);
      if (filePath != null && await File(filePath).exists()) {
        await _updateAccessTime(_getFullKey(key));
        return await File(filePath).readAsBytes();
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 바이너리 캐시 조회 실패($_namespace): $key, $e');
      }
      return null;
    }
  }

  @override
  Future<void> setBinary(String key, Uint8List data, {Duration? ttl}) async {
    await setFile(key, data, 'bin', ttl: ttl);
  }

  @override
  Future<String?> setFile(String key, Uint8List data, String extension, {Duration? ttl}) async {
    await _ensureInitialized();
    
    try {
      final fullKey = _getFullKey(key);
      final effectiveTtl = ttl ?? _defaultTtl;
      final now = DateTime.now();
      
      // 용량 확인 및 정리
      await _ensureCapacity(data.length);

      // 파일 저장
      final fileName = '${fullKey.replaceAll(':', '_')}.$extension';
      final filePath = path.join(_cacheDir!.path, fileName);
      final file = File(filePath);
      
      await file.writeAsBytes(data);

      // 메타데이터 업데이트
      _metadata[fullKey] = CacheMetadata(
        key: fullKey,
        createdAt: now,
        lastAccessedAt: now,
        expiresAt: now.add(effectiveTtl),
        size: data.length,
        dataType: 'binary',
      );

      await _saveMetadata();
      
      if (kDebugMode) {
        debugPrint('📦 파일 캐시 저장($_namespace): $key (${_formatSize(data.length)})');
      }
      
      return filePath;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 파일 캐시 저장 실패($_namespace): $key, $e');
      }
      return null;
    }
  }

  @override
  Future<String?> getFilePath(String key) async {
    await _ensureInitialized();
    
    try {
      final fullKey = _getFullKey(key);
      final metadata = _metadata[fullKey];
      
      if (metadata == null || metadata.isExpired) {
        return null;
      }

      // 파일 경로 생성 (확장자는 메타데이터에서 추정)
      final fileName = '${fullKey.replaceAll(':', '_')}';
      final cacheFiles = await _cacheDir!.list().toList();
      
      for (final file in cacheFiles) {
        if (file is File && path.basenameWithoutExtension(file.path) == fileName) {
          await _updateAccessTime(fullKey);
          return file.path;
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 파일 경로 조회 실패($_namespace): $key, $e');
      }
      return null;
    }
  }

  // === Private Methods ===

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  String _getFullKey(String key) => '${_namespace}:$key';
  
  String _getOriginalKey(String fullKey) => fullKey.substring(_namespace.length + 1);

  Future<Directory> _getCacheDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory(path.join(appDir.path, 'cache', _namespace));
  }

  Future<void> _updateAccessTime(String fullKey) async {
    final metadata = _metadata[fullKey];
    if (metadata != null) {
      _metadata[fullKey] = CacheMetadata(
        key: metadata.key,
        createdAt: metadata.createdAt,
        lastAccessedAt: DateTime.now(),
        expiresAt: metadata.expiresAt,
        size: metadata.size,
        dataType: metadata.dataType,
      );
    }
  }

  Future<void> _ensureCapacity(int newDataSize) async {
    final currentSize = await getSize();
    final currentCount = await getItemCount();

    // 항목 수 제한
    if (currentCount >= _maxItems) {
      await _removeOldestItems(currentCount - _maxItems + 1);
    }

    // 용량 제한
    if (currentSize + newDataSize > _maxSize) {
      final targetSize = _maxSize - newDataSize;
      await _removeItemsUntilSize(targetSize);
    }
  }

  Future<void> _removeOldestItems(int count) async {
    final sortedEntries = _metadata.entries.toList()
      ..sort((a, b) => a.value.lastAccessedAt.compareTo(b.value.lastAccessedAt));

    final keysToRemove = sortedEntries
        .take(count)
        .map((entry) => entry.key)
        .toList();

    for (final key in keysToRemove) {
      await _prefs!.remove(key);
      _memoryCache.remove(key);
      
      // 파일도 삭제
      final fileName = key.replaceAll(':', '_');
      final cacheFiles = await _cacheDir!.list().toList();
      for (final file in cacheFiles) {
        if (file is File && path.basenameWithoutExtension(file.path) == fileName) {
          await file.delete();
          break;
        }
      }
      
      _metadata.remove(key);
    }

    if (keysToRemove.isNotEmpty) {
      await _saveMetadata();
    }
  }

  Future<void> _removeItemsUntilSize(int targetSize) async {
    while (await getSize() > targetSize && _metadata.isNotEmpty) {
      await _removeOldestItems(1);
    }
  }

  Future<void> _loadMetadata() async {
    try {
      if (kDebugMode) {
        debugPrint('📦 LocalCacheStorage($_namespace) 메타데이터 JSON 읽기 시작');
      }
      
      final metadataJson = _prefs!.getString('${_namespace}:_metadata');
      
      if (kDebugMode) {
        debugPrint('📦 LocalCacheStorage($_namespace) 메타데이터 JSON 읽기 완료: ${metadataJson != null ? '데이터 있음' : '데이터 없음'}');
      }
      
      if (metadataJson != null) {
        if (kDebugMode) {
          debugPrint('📦 LocalCacheStorage($_namespace) JSON 파싱 시작');
        }
        
        final metadataMap = json.decode(metadataJson) as Map<String, dynamic>;
        
        if (kDebugMode) {
          debugPrint('📦 LocalCacheStorage($_namespace) JSON 파싱 완료: ${metadataMap.length}개 항목');
        }
        
        if (kDebugMode) {
          debugPrint('📦 LocalCacheStorage($_namespace) 메타데이터 객체 생성 시작');
        }
        
        for (final entry in metadataMap.entries) {
          _metadata[entry.key] = CacheMetadata.fromJson(entry.value as Map<String, dynamic>);
        }
        
        if (kDebugMode) {
          debugPrint('📦 LocalCacheStorage($_namespace) 메타데이터 객체 생성 완료');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 메타데이터 로드 실패($_namespace): $e');
      }
    }
  }

  Future<void> _saveMetadata() async {
    try {
      final metadataMap = <String, dynamic>{};
      for (final entry in _metadata.entries) {
        metadataMap[entry.key] = entry.value.toJson();
      }
      
      await _prefs!.setString('${_namespace}:_metadata', json.encode(metadataMap));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 메타데이터 저장 실패($_namespace): $e');
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
} 