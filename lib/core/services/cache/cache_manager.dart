import 'package:flutter/foundation.dart';
import '../../../core/models/processed_text.dart';
import '../../../core/models/note.dart';
import 'cache_storage.dart';
import 'local_cache_storage.dart';

/// 통합 캐시 매니저
/// 모든 캐시 타입을 관리하고 비즈니스 로직을 제공합니다.
class CacheManager {
  // 싱글톤 패턴
  static final CacheManager _instance = CacheManager._internal();
  factory CacheManager() => _instance;
  CacheManager._internal();

  // 캐시 저장소들
  late final LocalCacheStorage<Map<String, dynamic>> _noteContentsCache;
  late final LocalCacheStorage<Map<String, dynamic>> _noteMetadataCache;
  late final LocalCacheStorage<Uint8List> _imageCache;
  late final LocalCacheStorage<Uint8List> _ttsCache;

  bool _isInitialized = false;

  /// 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Note Contents 캐시 (100MB)
      _noteContentsCache = LocalCacheStorage<Map<String, dynamic>>(
        namespace: 'note_contents',
        maxSize: 100 * 1024 * 1024, // 100MB
        maxItems: 5000,
        fromJson: (json) => json,
        toJson: (data) => data,
      );

      // Note Metadata 캐시 (10MB)
      _noteMetadataCache = LocalCacheStorage<Map<String, dynamic>>(
        namespace: 'note_metadata',
        maxSize: 10 * 1024 * 1024, // 10MB
        maxItems: 1000,
        fromJson: (json) => json,
        toJson: (data) => data,
      );

      // Image 캐시 (500MB)
      _imageCache = LocalCacheStorage<Uint8List>(
        namespace: 'images',
        maxSize: 500 * 1024 * 1024, // 500MB
        maxItems: 2000,
      );

      // TTS 캐시 (200MB)
      _ttsCache = LocalCacheStorage<Uint8List>(
        namespace: 'tts',
        maxSize: 200 * 1024 * 1024, // 200MB
        maxItems: 1000,
      );

      // 모든 캐시 초기화
      await Future.wait([
        _noteContentsCache.initialize(),
        _noteMetadataCache.initialize(),
        _imageCache.initialize(),
        _ttsCache.initialize(),
      ]);

      _isInitialized = true;

      if (kDebugMode) {
        debugPrint('🏗️ CacheManager 초기화 완료');
        await _printCacheStats();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ CacheManager 초기화 실패: $e');
      }
      rethrow;
    }
  }

  // === Note Contents 캐시 ===

  /// 노트 컨텐츠 캐시 키 생성
  /// 형식: "note:{noteId}:page:{pageId}:mode:{dataMode}:type:{chinese|translation|pinyin}"
  String _generateNoteContentKey({
    required String noteId,
    required String pageId,
    required String dataMode,
    required String type,
  }) {
    return 'note:$noteId:page:$pageId:mode:$dataMode:type:$type';
  }

  /// 노트 컨텐츠 저장
  Future<void> cacheNoteContent({
    required String noteId,
    required String pageId,
    required String dataMode,
    required String type, // chinese, translation, pinyin
    required Map<String, dynamic> content,
  }) async {
    await _ensureInitialized();

    try {
      final key = _generateNoteContentKey(
        noteId: noteId,
        pageId: pageId,
        dataMode: dataMode,
        type: type,
      );

      await _noteContentsCache.set(key, content);

      if (kDebugMode) {
        debugPrint('📝 노트 컨텐츠 캐시 저장: $key');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 노트 컨텐츠 캐시 저장 실패: $e');
      }
    }
  }

  /// 노트 컨텐츠 조회
  Future<Map<String, dynamic>?> getNoteContent({
    required String noteId,
    required String pageId,
    required String dataMode,
    required String type,
  }) async {
    await _ensureInitialized();

    try {
      final key = _generateNoteContentKey(
        noteId: noteId,
        pageId: pageId,
        dataMode: dataMode,
        type: type,
      );

      return await _noteContentsCache.get(key);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 노트 컨텐츠 캐시 조회 실패: $e');
      }
      return null;
    }
  }

  /// 노트의 모든 컨텐츠 삭제
  Future<void> clearNoteContents(String noteId) async {
    await _ensureInitialized();

    try {
      await _noteContentsCache.deleteByPattern(r'note:' + noteId + r':.*');

      if (kDebugMode) {
        debugPrint('📝 노트 컨텐츠 캐시 삭제: $noteId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 노트 컨텐츠 캐시 삭제 실패: $e');
      }
    }
  }

  // === Note Metadata 캐시 ===

  /// 노트 메타데이터 저장
  Future<void> cacheNoteMetadata(String noteId, Note note) async {
    await _ensureInitialized();

    try {
      await _noteMetadataCache.set(noteId, note.toJson());

      if (kDebugMode) {
        debugPrint('📋 노트 메타데이터 캐시 저장: $noteId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 노트 메타데이터 캐시 저장 실패: $e');
      }
    }
  }

  /// 노트 메타데이터 조회
  Future<Note?> getNoteMetadata(String noteId) async {
    await _ensureInitialized();

    try {
      final data = await _noteMetadataCache.get(noteId);
      if (data != null) {
        return Note.fromJson(data);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 노트 메타데이터 캐시 조회 실패: $e');
      }
      return null;
    }
  }

  /// 모든 노트 메타데이터 조회
  Future<List<Note>> getAllNoteMetadata() async {
    await _ensureInitialized();

    try {
      final keys = await _noteMetadataCache.getKeys();
      final notes = <Note>[];

      for (final key in keys) {
        final data = await _noteMetadataCache.get(key);
        if (data != null) {
          try {
            notes.add(Note.fromJson(data));
          } catch (e) {
            if (kDebugMode) {
              debugPrint('❌ 노트 메타데이터 파싱 실패: $key, $e');
            }
          }
        }
      }

      return notes;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 전체 노트 메타데이터 조회 실패: $e');
      }
      return [];
    }
  }

  /// 노트 메타데이터 삭제
  Future<void> clearNoteMetadata(String noteId) async {
    await _ensureInitialized();

    try {
      await _noteMetadataCache.delete(noteId);

      if (kDebugMode) {
        debugPrint('📋 노트 메타데이터 캐시 삭제: $noteId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 노트 메타데이터 캐시 삭제 실패: $e');
      }
    }
  }

  // === Image 캐시 ===

  /// 이미지 캐시 키 생성
  /// 형식: "image:{noteId}:page:{pageId}:optimized"
  String _generateImageKey({
    required String noteId,
    required String pageId,
  }) {
    return 'image:$noteId:page:$pageId:optimized';
  }

  /// 이미지 캐싱
  Future<String?> cacheImage({
    required String noteId,
    required String pageId,
    required Uint8List imageData,
  }) async {
    await _ensureInitialized();

    try {
      final key = _generateImageKey(noteId: noteId, pageId: pageId);
      return await _imageCache.setFile(key, imageData, 'jpg');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 이미지 캐시 저장 실패: $e');
      }
      return null;
    }
  }

  /// 이미지 조회
  Future<Uint8List?> getImage({
    required String noteId,
    required String pageId,
  }) async {
    await _ensureInitialized();

    try {
      final key = _generateImageKey(noteId: noteId, pageId: pageId);
      return await _imageCache.getBinary(key);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 이미지 캐시 조회 실패: $e');
      }
      return null;
    }
  }

  /// 이미지 파일 경로 조회
  Future<String?> getImagePath({
    required String noteId,
    required String pageId,
  }) async {
    await _ensureInitialized();

    try {
      final key = _generateImageKey(noteId: noteId, pageId: pageId);
      return await _imageCache.getFilePath(key);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 이미지 경로 조회 실패: $e');
      }
      return null;
    }
  }

  /// 노트의 모든 이미지 삭제
  Future<void> clearNoteImages(String noteId) async {
    await _ensureInitialized();

    try {
      await _imageCache.deleteByPattern(r'image:' + noteId + r':.*');

      if (kDebugMode) {
        debugPrint('🖼️ 노트 이미지 캐시 삭제: $noteId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 노트 이미지 캐시 삭제 실패: $e');
      }
    }
  }

  // === TTS 캐시 ===

  /// TTS 캐시 키 생성
  /// 형식: "tts:{noteId}:page:{pageId}:segment:{segmentId}:voice:{voiceId}"
  String _generateTTSKey({
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
    await _ensureInitialized();

    try {
      final key = _generateTTSKey(
        noteId: noteId,
        pageId: pageId,
        segmentId: segmentId,
        voiceId: voiceId,
      );
      return await _ttsCache.setFile(key, audioData, 'mp3');
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ TTS 캐시 저장 실패: $e');
      }
      return null;
    }
  }

  /// TTS 오디오 조회
  Future<Uint8List?> getTTS({
    required String noteId,
    required String pageId,
    required String segmentId,
    required String voiceId,
  }) async {
    await _ensureInitialized();

    try {
      final key = _generateTTSKey(
        noteId: noteId,
        pageId: pageId,
        segmentId: segmentId,
        voiceId: voiceId,
      );
      return await _ttsCache.getBinary(key);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ TTS 캐시 조회 실패: $e');
      }
      return null;
    }
  }

  /// TTS 파일 경로 조회
  Future<String?> getTTSPath({
    required String noteId,
    required String pageId,
    required String segmentId,
    required String voiceId,
  }) async {
    await _ensureInitialized();

    try {
      final key = _generateTTSKey(
        noteId: noteId,
        pageId: pageId,
        segmentId: segmentId,
        voiceId: voiceId,
      );
      return await _ttsCache.getFilePath(key);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ TTS 경로 조회 실패: $e');
      }
      return null;
    }
  }

  /// 노트의 모든 TTS 삭제
  Future<void> clearNoteTTS(String noteId) async {
    await _ensureInitialized();

    try {
      await _ttsCache.deleteByPattern(r'tts:' + noteId + r':.*');

      if (kDebugMode) {
        debugPrint('🔊 노트 TTS 캐시 삭제: $noteId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 노트 TTS 캐시 삭제 실패: $e');
      }
    }
  }

  // === 통합 관리 ===

  /// 특정 노트의 모든 캐시 삭제
  Future<void> clearNoteCache(String noteId) async {
    await _ensureInitialized();

    try {
      await Future.wait([
        clearNoteContents(noteId),
        clearNoteMetadata(noteId),
        clearNoteImages(noteId),
        clearNoteTTS(noteId),
      ]);

      if (kDebugMode) {
        debugPrint('🗑️ 노트 전체 캐시 삭제 완료: $noteId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 노트 전체 캐시 삭제 실패: $e');
      }
    }
  }

  /// 전체 캐시 삭제
  Future<void> clearAllCache() async {
    await _ensureInitialized();

    try {
      await Future.wait([
        _noteContentsCache.clear(),
        _noteMetadataCache.clear(),
        _imageCache.clear(),
        _ttsCache.clear(),
      ]);

      if (kDebugMode) {
        debugPrint('🗑️ 전체 캐시 삭제 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 전체 캐시 삭제 실패: $e');
      }
    }
  }

  /// 만료된 캐시 정리
  Future<void> cleanupExpiredCache() async {
    await _ensureInitialized();

    try {
      await Future.wait([
        _noteContentsCache.cleanupExpired(),
        _noteMetadataCache.cleanupExpired(),
        _imageCache.cleanupExpired(),
        _ttsCache.cleanupExpired(),
      ]);

      if (kDebugMode) {
        debugPrint('🧹 만료된 캐시 정리 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 만료된 캐시 정리 실패: $e');
      }
    }
  }

  /// 전체 캐시 상태 조회
  Future<Map<String, dynamic>> getCacheStats() async {
    await _ensureInitialized();

    try {
      final stats = await Future.wait([
        _noteContentsCache.getStats(),
        _noteMetadataCache.getStats(),
        _imageCache.getStats(),
        _ttsCache.getStats(),
      ]);

      final totalSize = stats.fold<int>(0, (sum, stat) => sum + (stat['totalSize'] as int));
      final totalItems = stats.fold<int>(0, (sum, stat) => sum + (stat['itemCount'] as int));

      return {
        'totalSize': totalSize,
        'totalSizeMB': totalSize / (1024 * 1024),
        'totalItems': totalItems,
        'maxSizeMB': 810, // 500 + 200 + 100 + 10
        'usagePercent': totalSize > 0 ? (totalSize / (810 * 1024 * 1024) * 100).round() : 0,
        'noteContents': stats[0],
        'noteMetadata': stats[1],
        'images': stats[2],
        'tts': stats[3],
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 캐시 상태 조회 실패: $e');
      }
      return {};
    }
  }

  // === Private Methods ===

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  Future<void> _printCacheStats() async {
    final stats = await getCacheStats();
    debugPrint('📊 캐시 상태:');
    debugPrint('   전체 크기: ${stats['totalSizeMB']?.toStringAsFixed(1)} MB');
    debugPrint('   전체 항목: ${stats['totalItems']}개');
    debugPrint('   사용률: ${stats['usagePercent']}%');
  }
} 