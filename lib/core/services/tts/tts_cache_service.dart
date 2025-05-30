import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path/path.dart' as path;

/// TTS 캐시 서비스
/// TTS 오디오 파일의 로컬 및 Firebase 캐시를 관리합니다.
class TTSCacheService {
  // 싱글톤 패턴
  static final TTSCacheService _instance = TTSCacheService._internal();
  factory TTSCacheService() => _instance;
  TTSCacheService._internal();

  // Firebase 인스턴스
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 캐시 설정
  static const int _maxCacheSize = 200 * 1024 * 1024; // 200MB
  static const int _maxCacheItems = 1000;
  static const int _ttlDays = 30; // 30일 TTL
  static const String _ttsBucket = 'tts_cache';
  static const String _ttsCollection = 'tts_metadata';

  // 메모리 캐시 (파일 경로만 저장)
  final Map<String, String> _memoryCache = {};
  final Map<String, DateTime> _accessTimestamps = {};
  final Map<String, int> _fileSizes = {};
  
  int _totalCacheSize = 0;
  bool _isInitialized = false;

  /// 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await _loadCacheMetadata();
      await _cleanupExpiredFiles();
      _isInitialized = true;
      
      if (kDebugMode) {
        debugPrint('🔊 TTSCacheService 초기화 완료');
        debugPrint('   캐시 항목: ${_memoryCache.length}개');
        debugPrint('   총 크기: ${_formatSize(_totalCacheSize)}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ TTSCacheService 초기화 실패: $e');
      }
      rethrow;
    }
  }

  /// 캐시 키 생성
  /// 형식: "tts:{noteId}:page:{pageId}:segment:{segmentId}:voice:{voiceId}"
  String _generateCacheKey({
    required String noteId,
    required String pageId,
    required String segmentId,
    required String voiceId,
  }) {
    return 'tts:$noteId:page:$pageId:segment:$segmentId:voice:$voiceId';
  }

  /// TTS 오디오 캐싱
  Future<String?> cacheTTS({
    required String noteId,
    required String pageId,
    required String segmentId,
    required String voiceId,
    required Uint8List audioData,
  }) async {
    try {
      final cacheKey = _generateCacheKey(
        noteId: noteId,
        pageId: pageId,
        segmentId: segmentId,
        voiceId: voiceId,
      );

      // 로컬 파일 경로 생성
      final localPath = await _getLocalFilePath(cacheKey);
      final file = File(localPath);

      // 디렉토리 생성
      await file.parent.create(recursive: true);

      // 파일 저장
      await file.writeAsBytes(audioData);

      // 메모리 캐시 업데이트
      _memoryCache[cacheKey] = localPath;
      _accessTimestamps[cacheKey] = DateTime.now();
      _fileSizes[cacheKey] = audioData.length;
      _totalCacheSize += audioData.length;

      // 캐시 크기 제한 확인
      await _checkCacheSize();

      // Firebase에 백그라운드 업로드
      _uploadToFirebase(cacheKey, audioData);

      if (kDebugMode) {
        debugPrint('🔊 TTS 캐싱 완료: $cacheKey (${_formatSize(audioData.length)})');
      }

      return localPath;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ TTS 캐싱 실패: $e');
      }
      return null;
    }
  }

  /// TTS 오디오 조회
  Future<String?> getTTSPath({
    required String noteId,
    required String pageId,
    required String segmentId,
    required String voiceId,
  }) async {
    try {
      final cacheKey = _generateCacheKey(
        noteId: noteId,
        pageId: pageId,
        segmentId: segmentId,
        voiceId: voiceId,
      );

      // 1. 메모리 캐시 확인
      final cachedPath = _memoryCache[cacheKey];
      if (cachedPath != null && await File(cachedPath).exists()) {
        _updateAccessTime(cacheKey);
        return cachedPath;
      }

      // 2. 로컬 파일 시스템 확인
      final localPath = await _getLocalFilePath(cacheKey);
      if (await File(localPath).exists()) {
        final fileSize = await File(localPath).length();
        _memoryCache[cacheKey] = localPath;
        _accessTimestamps[cacheKey] = DateTime.now();
        _fileSizes[cacheKey] = fileSize;
        _totalCacheSize += fileSize;
        return localPath;
      }

      // 3. Firebase에서 다운로드
      final audioData = await _downloadFromFirebase(cacheKey);
      if (audioData != null) {
        return await cacheTTS(
          noteId: noteId,
          pageId: pageId,
          segmentId: segmentId,
          voiceId: voiceId,
          audioData: audioData,
        );
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ TTS 조회 실패: $e');
      }
      return null;
    }
  }

  /// 특정 노트의 TTS 캐시 삭제
  Future<void> clearNoteCache(String noteId) async {
    try {
      final keysToRemove = _memoryCache.keys
          .where((key) => key.startsWith('tts:$noteId:'))
          .toList();

      for (final key in keysToRemove) {
        await _removeFromCache(key);
      }

      // Firebase에서도 삭제
      await _deleteFromFirebase(noteId);

      if (kDebugMode) {
        debugPrint('🔊 노트 TTS 캐시 삭제 완료: $noteId (${keysToRemove.length}개 파일)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 노트 TTS 캐시 삭제 실패: $e');
      }
    }
  }

  /// 전체 TTS 캐시 삭제
  Future<void> clearAllCache() async {
    try {
      // 로컬 파일 삭제
      final cacheDir = await _getCacheDirectory();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }

      // 메모리 캐시 초기화
      _memoryCache.clear();
      _accessTimestamps.clear();
      _fileSizes.clear();
      _totalCacheSize = 0;

      if (kDebugMode) {
        debugPrint('🔊 전체 TTS 캐시 삭제 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 전체 TTS 캐시 삭제 실패: $e');
      }
    }
  }

  /// 캐시 상태 정보
  Map<String, dynamic> getCacheStats() {
    return {
      'itemCount': _memoryCache.length,
      'maxItems': _maxCacheItems,
      'totalSize': _totalCacheSize,
      'totalSizeMB': _totalCacheSize / (1024 * 1024),
      'maxSizeMB': _maxCacheSize / (1024 * 1024),
      'usagePercent': (_totalCacheSize / _maxCacheSize * 100).round(),
    };
  }

  // === Private Methods ===

  /// 로컬 파일 경로 생성
  Future<String> _getLocalFilePath(String cacheKey) async {
    final cacheDir = await _getCacheDirectory();
    final fileName = '${cacheKey.replaceAll(':', '_')}.mp3';
    return path.join(cacheDir.path, fileName);
  }

  /// 캐시 디렉토리 경로
  Future<Directory> _getCacheDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory(path.join(appDir.path, 'tts_cache'));
  }

  /// 접근 시간 업데이트
  void _updateAccessTime(String cacheKey) {
    _accessTimestamps[cacheKey] = DateTime.now();
  }

  /// 캐시 크기 제한 확인 및 정리
  Future<void> _checkCacheSize() async {
    // 항목 수 제한
    if (_memoryCache.length > _maxCacheItems) {
      await _removeOldestItems(_memoryCache.length - _maxCacheItems);
    }

    // 용량 제한
    while (_totalCacheSize > _maxCacheSize && _memoryCache.isNotEmpty) {
      await _removeOldestItems(1);
    }
  }

  /// 가장 오래된 항목들 제거 (LRU)
  Future<void> _removeOldestItems(int count) async {
    final sortedKeys = _accessTimestamps.keys.toList()
      ..sort((a, b) => _accessTimestamps[a]!.compareTo(_accessTimestamps[b]!));

    final keysToRemove = sortedKeys.take(count).toList();
    
    for (final key in keysToRemove) {
      await _removeFromCache(key);
    }

    if (kDebugMode) {
      debugPrint('🔊 TTS 캐시 정리: ${keysToRemove.length}개 항목 제거');
    }
  }

  /// 캐시에서 항목 제거
  Future<void> _removeFromCache(String cacheKey) async {
    try {
      final filePath = _memoryCache[cacheKey];
      if (filePath != null) {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      }

      final fileSize = _fileSizes[cacheKey] ?? 0;
      _totalCacheSize -= fileSize;

      _memoryCache.remove(cacheKey);
      _accessTimestamps.remove(cacheKey);
      _fileSizes.remove(cacheKey);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 캐시 항목 제거 실패: $cacheKey, $e');
      }
    }
  }

  /// 만료된 파일 정리
  Future<void> _cleanupExpiredFiles() async {
    try {
      final now = DateTime.now();
      final expiredKeys = <String>[];

      for (final entry in _accessTimestamps.entries) {
        final daysSinceAccess = now.difference(entry.value).inDays;
        if (daysSinceAccess > _ttlDays) {
          expiredKeys.add(entry.key);
        }
      }

      for (final key in expiredKeys) {
        await _removeFromCache(key);
      }

      if (kDebugMode && expiredKeys.isNotEmpty) {
        debugPrint('🔊 만료된 TTS 파일 정리: ${expiredKeys.length}개');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 만료된 파일 정리 실패: $e');
      }
    }
  }

  /// 캐시 메타데이터 로드
  Future<void> _loadCacheMetadata() async {
    try {
      final cacheDir = await _getCacheDirectory();
      if (!await cacheDir.exists()) return;

      final files = await cacheDir.list().toList();
      _totalCacheSize = 0;

      for (final file in files) {
        if (file is File && file.path.endsWith('.mp3')) {
          final fileName = path.basenameWithoutExtension(file.path);
          final cacheKey = fileName.replaceAll('_', ':');
          final fileSize = await file.length();
          final lastModified = await file.lastModified();

          _memoryCache[cacheKey] = file.path;
          _accessTimestamps[cacheKey] = lastModified;
          _fileSizes[cacheKey] = fileSize;
          _totalCacheSize += fileSize;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 캐시 메타데이터 로드 실패: $e');
      }
    }
  }

  /// Firebase에 업로드 (백그라운드)
  Future<void> _uploadToFirebase(String cacheKey, Uint8List audioData) async {
    try {
      final ref = _storage.ref().child('$_ttsBucket/${cacheKey.replaceAll(':', '_')}.mp3');
      await ref.putData(audioData);

      // 메타데이터 저장
      await _firestore.collection(_ttsCollection).doc(cacheKey).set({
        'cacheKey': cacheKey,
        'size': audioData.length,
        'uploadedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Firebase TTS 업로드 실패: $cacheKey, $e');
      }
    }
  }

  /// Firebase에서 다운로드
  Future<Uint8List?> _downloadFromFirebase(String cacheKey) async {
    try {
      final ref = _storage.ref().child('$_ttsBucket/${cacheKey.replaceAll(':', '_')}.mp3');
      final maxSize = 50 * 1024 * 1024; // 50MB 제한
      return await ref.getData(maxSize);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Firebase TTS 다운로드 실패: $cacheKey, $e');
      }
      return null;
    }
  }

  /// Firebase에서 노트 관련 TTS 삭제
  Future<void> _deleteFromFirebase(String noteId) async {
    try {
      // Storage에서 삭제
      final listResult = await _storage.ref().child(_ttsBucket).listAll();
      for (final item in listResult.items) {
        if (item.name.startsWith('tts_${noteId}_')) {
          await item.delete();
        }
      }

      // Firestore 메타데이터 삭제
      final querySnapshot = await _firestore
          .collection(_ttsCollection)
          .where('cacheKey', isGreaterThanOrEqualTo: 'tts:$noteId:')
          .where('cacheKey', isLessThan: 'tts:$noteId;')
          .get();

      final batch = _firestore.batch();
      for (final doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Firebase TTS 삭제 실패: $noteId, $e');
      }
    }
  }

  /// 파일 크기 포맷팅
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
