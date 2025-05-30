import 'package:flutter/foundation.dart';
import '../../../core/models/processed_text.dart';
import '../../../core/models/note.dart';
import '../../../core/models/flash_card.dart';
import 'cache_storage.dart';
import 'local_cache_storage.dart';

/// 통합 캐시 매니저
/// 모든 캐시 타입을 관리하고 비즈니스 로직을 제공합니다.
class CacheManager {
  // 싱글톤 패턴
  static final CacheManager _instance = CacheManager._internal();
  factory CacheManager() => _instance;
  CacheManager._internal();

  // 캐시 저장소들 (nullable로 변경)
  LocalCacheStorage<Map<String, dynamic>>? _noteContentsCache;
  LocalCacheStorage<Map<String, dynamic>>? _noteMetadataCache;
  LocalCacheStorage<Map<String, dynamic>>? _flashcardCache;
  LocalCacheStorage<Uint8List>? _imageCache;
  LocalCacheStorage<Uint8List>? _ttsCache;

  bool _isInitialized = false;

  /// 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (kDebugMode) {
        debugPrint('🏗️ CacheManager 초기화 시작');
      }

      // Note Contents 캐시 (100MB)
      if (kDebugMode) {
        debugPrint('📝 Note Contents 캐시 생성 중...');
      }
      _noteContentsCache = LocalCacheStorage<Map<String, dynamic>>(
        namespace: 'note_contents',
        maxSize: 100 * 1024 * 1024, // 100MB
        maxItems: 5000,
        fromJson: (json) => json,
        toJson: (data) => data,
      );

      // Note Metadata 캐시 (10MB)
      if (kDebugMode) {
        debugPrint('📋 Note Metadata 캐시 생성 중...');
      }
      _noteMetadataCache = LocalCacheStorage<Map<String, dynamic>>(
        namespace: 'note_metadata',
        maxSize: 10 * 1024 * 1024, // 10MB
        maxItems: 500,
        fromJson: (json) => json,
        toJson: (data) => data,
      );

      // Flashcard 캐시 (10MB)
      if (kDebugMode) {
        debugPrint('🃏 Flashcard 캐시 생성 중...');
      }
      _flashcardCache = LocalCacheStorage<Map<String, dynamic>>(
        namespace: 'flashcards',
        maxSize: 10 * 1024 * 1024, // 10MB
        maxItems: 1000,
        fromJson: (json) => json,
        toJson: (data) => data,
      );

      // Image 캐시 (300MB)
      if (kDebugMode) {
        debugPrint('🖼️ Image 캐시 생성 중...');
      }
      _imageCache = LocalCacheStorage<Uint8List>(
        namespace: 'images',
        maxSize: 300 * 1024 * 1024, // 300MB
        maxItems: 1000,
      );

      // TTS 캐시 (200MB)
      if (kDebugMode) {
        debugPrint('🔊 TTS 캐시 생성 중...');
      }
      _ttsCache = LocalCacheStorage<Uint8List>(
        namespace: 'tts',
        maxSize: 200 * 1024 * 1024, // 200MB
        maxItems: 1000,
      );

      if (kDebugMode) {
        debugPrint('⚙️ 모든 캐시 저장소 생성 완료, 초기화 시작...');
      }

      // 모든 캐시 초기화 - 개별적으로 실행하여 문제 지점 파악
      if (kDebugMode) {
        debugPrint('📝 Note Contents 캐시 초기화 중...');
      }
      await _noteContentsCache!.initialize();
      
      if (kDebugMode) {
        debugPrint('📋 Note Metadata 캐시 초기화 중...');
      }
      await _noteMetadataCache!.initialize();
      
      if (kDebugMode) {
        debugPrint('🃏 Flashcard 캐시 초기화 중...');
      }
      await _flashcardCache!.initialize();
      
      if (kDebugMode) {
        debugPrint('🖼️ Image 캐시 초기화 중...');
      }
      await _imageCache!.initialize();
      
      if (kDebugMode) {
        debugPrint('🔊 TTS 캐시 초기화 중...');
      }
      await _ttsCache!.initialize();

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

      await _noteContentsCache!.set(key, content);

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
      return await _noteContentsCache!.get(key);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 노트 컨텐츠 조회 실패: $e');
      }
      return null;
    }
  }

  /// 모든 노트 컨텐츠 캐시 키 조회
  Future<List<String>> getAllNoteContentKeys() async {
    await _ensureInitialized();
    
    try {
      return await _noteContentsCache!.getKeys();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 노트 컨텐츠 키 조회 실패: $e');
      }
      return [];
    }
  }

  /// 노트의 모든 컨텐츠 삭제
  Future<void> clearNoteContents(String noteId) async {
    await _ensureInitialized();

    try {
      await _noteContentsCache!.deleteByPattern(r'note:' + noteId + r':.*');

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
      await _noteMetadataCache!.set(noteId, note.toJson());

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
      final data = await _noteMetadataCache!.get(noteId);
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
      final keys = await _noteMetadataCache!.getKeys();
      final notes = <Note>[];

      for (final key in keys) {
        final data = await _noteMetadataCache!.get(key);
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
      await _noteMetadataCache!.delete(noteId);

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
      return await _imageCache!.setFile(key, imageData, 'jpg');
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
      return await _imageCache!.getBinary(key);
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
      return await _imageCache!.getFilePath(key);
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
      await _imageCache!.deleteByPattern(r'image:' + noteId + r':.*');

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
      return await _ttsCache!.setFile(key, audioData, 'mp3');
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
      return await _ttsCache!.getBinary(key);
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
      return await _ttsCache!.getFilePath(key);
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
      await _ttsCache!.deleteByPattern(r'tts:' + noteId + r':.*');

      if (kDebugMode) {
        debugPrint('🔊 노트 TTS 캐시 삭제: $noteId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 노트 TTS 캐시 삭제 실패: $e');
      }
    }
  }

  // === Flashcard 캐시 ===

  /// 플래시카드 캐시 키 생성
  /// 형식: "flashcard:{noteId}:cards"
  String _generateFlashcardKey(String noteId) {
    return 'flashcard:$noteId:cards';
  }

  /// 플래시카드 저장
  Future<void> cacheFlashcards(String noteId, List<FlashCard> flashcards) async {
    await _ensureInitialized();

    try {
      final key = _generateFlashcardKey(noteId);
      final data = {
        'flashcards': flashcards.map((card) => card.toJson()).toList(),
        'cachedAt': DateTime.now().toIso8601String(),
        'count': flashcards.length,
      };

      await _flashcardCache!.set(key, data);

      if (kDebugMode) {
        debugPrint('🃏 플래시카드 캐시 저장: $noteId (${flashcards.length}개)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 플래시카드 캐시 저장 실패: $e');
      }
    }
  }

  /// 플래시카드 조회
  Future<List<FlashCard>?> getFlashcards(String noteId) async {
    await _ensureInitialized();

    try {
      final key = _generateFlashcardKey(noteId);
      final data = await _flashcardCache!.get(key);
      
      if (data != null && data['flashcards'] != null) {
        final flashcardList = data['flashcards'] as List;
        return flashcardList
            .map((cardData) => FlashCard.fromJson(cardData as Map<String, dynamic>))
            .toList();
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 플래시카드 캐시 조회 실패: $e');
      }
      return null;
    }
  }

  /// 개별 플래시카드 저장
  Future<void> cacheFlashcard(String noteId, FlashCard flashcard) async {
    await _ensureInitialized();

    try {
      // 기존 플래시카드 목록 가져오기
      final existingCards = await getFlashcards(noteId) ?? [];
      
      // 기존 카드 중 같은 ID가 있으면 업데이트, 없으면 추가
      final existingIndex = existingCards.indexWhere((card) => card.id == flashcard.id);
      if (existingIndex >= 0) {
        existingCards[existingIndex] = flashcard;
      } else {
        existingCards.add(flashcard);
      }

      // 업데이트된 목록 저장
      await cacheFlashcards(noteId, existingCards);

      if (kDebugMode) {
        debugPrint('🃏 개별 플래시카드 캐시 저장: ${flashcard.id}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 개별 플래시카드 캐시 저장 실패: $e');
      }
    }
  }

  /// 플래시카드 삭제
  Future<void> removeFlashcard(String noteId, String flashcardId) async {
    await _ensureInitialized();

    try {
      // 기존 플래시카드 목록 가져오기
      final existingCards = await getFlashcards(noteId) ?? [];
      
      // 해당 ID의 카드 제거
      existingCards.removeWhere((card) => card.id == flashcardId);

      // 업데이트된 목록 저장
      await cacheFlashcards(noteId, existingCards);

      if (kDebugMode) {
        debugPrint('🃏 플래시카드 캐시에서 삭제: $flashcardId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 플래시카드 캐시 삭제 실패: $e');
      }
    }
  }

  /// 노트의 모든 플래시카드 캐시 삭제
  Future<void> clearFlashcardCache(String noteId) async {
    await _ensureInitialized();

    try {
      final key = _generateFlashcardKey(noteId);
      await _flashcardCache!.delete(key);

      if (kDebugMode) {
        debugPrint('🃏 플래시카드 캐시 삭제: $noteId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 플래시카드 캐시 삭제 실패: $e');
      }
    }
  }

  /// 플래시카드 캐시 유효성 확인
  Future<bool> isFlashcardCacheValid(String noteId, {Duration validDuration = const Duration(hours: 24)}) async {
    await _ensureInitialized();

    try {
      final key = _generateFlashcardKey(noteId);
      final data = await _flashcardCache!.get(key);
      
      if (data == null || data['cachedAt'] == null) return false;
      
      final cachedAt = DateTime.parse(data['cachedAt'] as String);
      final now = DateTime.now();
      final difference = now.difference(cachedAt);
      
      return difference < validDuration;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 플래시카드 캐시 유효성 확인 실패: $e');
      }
      return false;
    }
  }

  // === 통합 관리 ===

  /// 노트 목록 캐싱
  Future<void> cacheNotes(List<Note> notes) async {
    await _ensureInitialized();

    try {
      // 각 노트를 개별적으로 캐시
      for (final note in notes) {
        await cacheNoteMetadata(note.id, note);
      }

      // 마지막 캐시 시간 저장
      await _saveLastCacheTime(DateTime.now());

      if (kDebugMode) {
        debugPrint('📋 노트 목록 캐싱 완료: ${notes.length}개');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 노트 목록 캐싱 실패: $e');
      }
    }
  }

  /// 캐시된 노트 목록 조회
  Future<List<Note>> getCachedNotes() async {
    return await getAllNoteMetadata();
  }

  /// 마지막 캐시 시간 저장
  Future<void> _saveLastCacheTime(DateTime time) async {
    await _ensureInitialized();

    try {
      await _noteMetadataCache!.set('_last_cache_time', {
        'timestamp': time.toIso8601String(),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 마지막 캐시 시간 저장 실패: $e');
      }
    }
  }

  /// 마지막 캐시 시간 조회
  Future<DateTime?> getLastCacheTime() async {
    await _ensureInitialized();

    try {
      final data = await _noteMetadataCache!.get('_last_cache_time');
      if (data != null && data['timestamp'] != null) {
        return DateTime.parse(data['timestamp'] as String);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 마지막 캐시 시간 조회 실패: $e');
      }
      return null;
    }
  }

  /// 마지막 캐시 시간 로컬 메모리 캐싱
  DateTime? _lastCacheTime;

  Future<DateTime?> updateLastCacheTimeCache() async {
    _lastCacheTime = await getLastCacheTime();
    return _lastCacheTime;
  }

  /// 캐시 유효성 확인
  bool isCacheValid({Duration validDuration = const Duration(minutes: 5)}) {
    if (_lastCacheTime == null) return false;
    
    final now = DateTime.now();
    final difference = now.difference(_lastCacheTime!);
    return difference < validDuration;
  }

  /// 전체 캐시 삭제
  Future<void> clearCache() async {
    await clearAllCache();
  }

  /// 특정 노트의 모든 캐시 삭제
  Future<void> clearNoteCache(String noteId) async {
    await _ensureInitialized();

    try {
      await Future.wait([
        clearNoteContents(noteId),
        clearNoteMetadata(noteId),
        clearFlashcardCache(noteId),
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
        _noteContentsCache!.clear(),
        _noteMetadataCache!.clear(),
        _flashcardCache!.clear(),
        _imageCache!.clear(),
        _ttsCache!.clear(),
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
        _noteContentsCache!.cleanupExpired(),
        _noteMetadataCache!.cleanupExpired(),
        _flashcardCache!.cleanupExpired(),
        _imageCache!.cleanupExpired(),
        _ttsCache!.cleanupExpired(),
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
        _noteContentsCache!.getStats(),
        _noteMetadataCache!.getStats(),
        _flashcardCache!.getStats(),
        _imageCache!.getStats(),
        _ttsCache!.getStats(),
      ]);

      final totalSize = stats.fold<int>(0, (sum, stat) => sum + (stat['totalSize'] as int));
      final totalItems = stats.fold<int>(0, (sum, stat) => sum + (stat['itemCount'] as int));

      return {
        'totalSize': totalSize,
        'totalSizeMB': totalSize / (1024 * 1024),
        'totalItems': totalItems,
        'maxSizeMB': 860, // 500(이미지) + 200(TTS) + 100(노트컨텐츠) + 50(플래시카드) + 10(메타데이터)
        'usagePercent': totalSize > 0 ? (totalSize / (860 * 1024 * 1024) * 100).round() : 0,
        'noteContents': stats[0],
        'noteMetadata': stats[1],
        'flashcards': stats[2],
        'images': stats[3],
        'tts': stats[4],
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