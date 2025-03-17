import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';
import '../models/page.dart' as page_model;
import '../models/processed_text.dart';
import 'package:crypto/crypto.dart';

/// 노트, 페이지의 통합 캐싱 서비스입니다.
/// 메모리 캐싱과 로컬 저장소 캐싱을 모두 지원합니다.
/// 메모리 캐시는 앱이 실행 중일 때만 유지되며, 로컬 저장소 캐시는 앱을 재시작해도 유지됩니다.

class UnifiedCacheService {
  // 싱글톤 인스턴스
  static final UnifiedCacheService _instance = UnifiedCacheService._internal();
  factory UnifiedCacheService() => _instance;

  // 초기화 완료 여부
  bool _isInitialized = false;

  UnifiedCacheService._internal() {
    debugPrint('UnifiedCacheService 생성됨 - 메모리 캐싱만 활성화');
  }

  // 명시적 초기화 메서드 추가
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 간단한 초기화만 수행
      debugPrint('UnifiedCacheService 초기화 중...');
      _isInitialized = true;

      // 캐시 정리는 별도 Future로 실행
      Future.delayed(Duration(seconds: 5), () {
        _cleanupExpiredLocalCache();
      });
    } catch (e) {
      debugPrint('캐시 서비스 초기화 중 오류 발생: $e');
    }
  }

  /// 로컬 저장소 캐시 정리 (오래된 항목 제거)
  Future<void> _cleanupExpiredLocalCache() async {
    if (!_isInitialized) return;

    try {
      debugPrint('만료된 로컬 캐시 정리 시작');
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      final now = DateTime.now();
      int removedCount = 0;

      // 타임스탬프 키만 필터링
      final timestampKeys =
          allKeys.where((key) => key.contains('timestamp_')).toList();

      // 한 번에 최대 50개만 처리 (부하 방지)
      final keysToProcess = timestampKeys.take(50).toList();

      for (final key in keysToProcess) {
        try {
          final timestampStr = prefs.getString(key);
          if (timestampStr == null) continue;

          DateTime timestamp;
          try {
            timestamp = DateTime.parse(timestampStr);
          } catch (e) {
            // 타임스탬프 형식이 잘못된 경우 해당 항목 삭제
            if (key.startsWith('${_noteKeyPrefix}timestamp_')) {
              final originalKey = _noteKeyPrefix +
                  key.substring('${_noteKeyPrefix}timestamp_'.length);
              await prefs.remove(originalKey);
            } else if (key.startsWith('${_pageKeyPrefix}timestamp_')) {
              final originalKey = _pageKeyPrefix +
                  key.substring('${_pageKeyPrefix}timestamp_'.length);
              await prefs.remove(originalKey);
            } else if (key.startsWith('${_translationKeyPrefix}timestamp_')) {
              final originalKey = _translationKeyPrefix +
                  key.substring('${_translationKeyPrefix}timestamp_'.length);
              await prefs.remove(originalKey);
            }
            await prefs.remove(key);
            removedCount++;
            continue;
          }

          if (now.difference(timestamp) > _cacheValidity) {
            String? originalKey;
            if (key.startsWith('${_noteKeyPrefix}timestamp_')) {
              originalKey = _noteKeyPrefix +
                  key.substring('${_noteKeyPrefix}timestamp_'.length);
            } else if (key.startsWith('${_pageKeyPrefix}timestamp_')) {
              originalKey = _pageKeyPrefix +
                  key.substring('${_pageKeyPrefix}timestamp_'.length);
            } else if (key.startsWith('${_translationKeyPrefix}timestamp_')) {
              originalKey = _translationKeyPrefix +
                  key.substring('${_translationKeyPrefix}timestamp_'.length);
            }

            if (originalKey != null) {
              await prefs.remove(originalKey);
              await prefs.remove(key);
              removedCount++;
            }
          }
        } catch (e) {
          debugPrint('캐시 항목 정리 중 오류 발생: $e');
          // 오류가 발생해도 계속 진행
        }
      }

      if (removedCount > 0) {
        debugPrint('만료된 캐시 항목 $removedCount개 정리 완료');
      }

      // 남은 키가 있으면 나중에 다시 정리
      if (timestampKeys.length > keysToProcess.length) {
        Future.delayed(Duration(minutes: 5), () {
          _cleanupExpiredLocalCache();
        });
      }
    } catch (e) {
      debugPrint('만료된 로컬 캐시 정리 중 오류 발생: $e');
    }
  }

  // 노트 캐시 (노트 ID -> 노트 객체)
  final Map<String, Note> _noteCache = {};

  // 페이지 캐시 (페이지 ID -> 페이지 객체)
  final Map<String, page_model.Page> _pageCache = {};

  // 노트별 페이지 ID 목록 (노트 ID -> 페이지 ID 목록)
  final Map<String, List<String>> _notePageIds = {};

  // 번역 캐시 (원본 텍스트 해시 -> 번역 텍스트)
  final Map<String, String> _translationCache = {};

  // 캐시 타임스탬프 (ID -> 마지막 액세스 시간)
  final Map<String, DateTime> _cacheTimestamps = {};

  // 캐시 유효 시간 (기본값: 24시간)
  final Duration _cacheValidity = const Duration(hours: 24);

  // 최대 캐시 항목 수
  final int _maxNoteItems = 50;
  final int _maxPageItems = 200;
  final int _maxTranslationItems = 500;

  // SharedPreferences 키 접두사
  static const String _noteKeyPrefix = 'note_cache_';
  static const String _pageKeyPrefix = 'page_cache_';
  static const String _notePageIdsPrefix = 'note_page_ids_';
  static const String _translationKeyPrefix = 'translation_cache_';

  /// 노트 캐싱 - 메모리에만 저장
  Future<void> cacheNote(Note note) async {
    if (note.id == null) return;

    final noteId = note.id!;
    _noteCache[noteId] = note;
    _cacheTimestamps[noteId] = DateTime.now();
  }

  /// 노트 가져오기 - 메모리에서만 조회
  Future<Note?> getCachedNote(String noteId) async {
    if (_noteCache.containsKey(noteId)) {
      final cachedTime = _cacheTimestamps[noteId];
      if (cachedTime != null &&
          DateTime.now().difference(cachedTime) < _cacheValidity) {
        return _noteCache[noteId];
      }
    }
    return null;
  }

  /// 페이지 캐싱 - 메모리에만 저장
  Future<void> cachePage(String noteId, page_model.Page page) async {
    if (page.id == null) return;

    final pageId = page.id!;
    _pageCache[pageId] = page;
    _cacheTimestamps[pageId] = DateTime.now();

    // 노트-페이지 관계 업데이트
    if (!_notePageIds.containsKey(noteId)) {
      _notePageIds[noteId] = [];
    }

    if (!_notePageIds[noteId]!.contains(pageId)) {
      _notePageIds[noteId]!.add(pageId);
    }
  }

  /// 여러 페이지 캐싱 (최적화된 배치 처리)
  Future<void> cachePages(String noteId, List<page_model.Page> pages) async {
    if (!_isInitialized) await initialize();
    if (pages.isEmpty) return;

    debugPrint('${pages.length}개 페이지 캐싱 시작 (노트 ID: $noteId)');

    // 페이지 ID 목록 업데이트
    final pageIds = pages
        .map((p) => p.id)
        .where((id) => id != null)
        .map((id) => id!)
        .toList();
    _notePageIds[noteId] = pageIds;

    // 메모리 캐시 업데이트 (병렬 처리)
    for (final page in pages) {
      if (page.id != null) {
        _pageCache[page.id!] = page;
        _cacheTimestamps[page.id!] = DateTime.now();
      }
    }

    // 로컬 저장소 캐싱 (배치 처리)
    try {
      final prefs = await SharedPreferences.getInstance();

      // 페이지 ID 목록 저장
      final pageIdsKey = 'note_pages_$noteId';
      await prefs.setStringList(pageIdsKey, pageIds);
      await prefs.setString(
          '${pageIdsKey}_timestamp', DateTime.now().toIso8601String());

      // 페이지 데이터 배치 저장 (JSON 변환 병렬 처리)
      final futures = <Future<Map<String, String>>>[];

      // 페이지를 배치로 나누어 처리 (최대 10개씩)
      const batchSize = 10;
      for (int i = 0; i < pages.length; i += batchSize) {
        final end =
            (i + batchSize < pages.length) ? i + batchSize : pages.length;
        final batch = pages.sublist(i, end);

        // 배치 내 페이지들의 JSON 변환을 병렬로 처리
        futures.add(compute(_serializePagesBatch, batch));
      }

      // 모든 배치 처리 완료 대기
      final results = await Future.wait(futures);

      // 결과를 SharedPreferences에 저장
      for (final pageDataMap in results) {
        for (final entry in pageDataMap.entries) {
          await prefs.setString(entry.key, entry.value);
        }
      }

      debugPrint('${pages.length}개 페이지 캐싱 완료 (노트 ID: $noteId)');
    } catch (e) {
      debugPrint('페이지 배치 캐싱 중 오류 발생: $e');
    }

    // 캐시 크기 제한 확인
    _checkPageCacheSize();
  }

  /// 페이지 배치를 직렬화하는 격리 함수 (compute에서 사용)
  static Map<String, String> _serializePagesBatch(List<page_model.Page> pages) {
    final result = <String, String>{};
    final now = DateTime.now().toIso8601String();

    for (final page in pages) {
      if (page.id != null) {
        final pageKey = 'page_${page.id}';
        final timestampKey = '${pageKey}_timestamp';

        // 페이지 데이터 JSON 직렬화
        result[pageKey] = jsonEncode(page.toJson());
        result[timestampKey] = now;
      }
    }

    return result;
  }

  /// 페이지 캐시 크기 확인 및 정리
  void _checkPageCacheSize() {
    // 메모리 캐시 크기 제한
    if (_pageCache.length > _maxPageItems) {
      debugPrint('페이지 캐시 크기 제한 초과: ${_pageCache.length}개 > $_maxPageItems개');

      // 가장 오래된 항목부터 제거
      final sortedEntries = _pageCache.keys.toList()
        ..sort((a, b) {
          final timeA = _cacheTimestamps[a] ?? DateTime.now();
          final timeB = _cacheTimestamps[b] ?? DateTime.now();
          return timeA.compareTo(timeB);
        });

      // 제거할 항목 수 계산
      final itemsToRemove = _pageCache.length - _maxPageItems;

      // 가장 오래된 항목부터 제거
      for (int i = 0; i < itemsToRemove; i++) {
        if (i < sortedEntries.length) {
          final key = sortedEntries[i];
          _pageCache.remove(key);
          _cacheTimestamps.remove(key);
        }
      }

      debugPrint('페이지 캐시 정리 완료: $itemsToRemove개 항목 제거');
    }
  }

  /// 페이지 가져오기 - 메모리에서만 조회
  Future<page_model.Page?> getCachedPage(String pageId) async {
    if (_pageCache.containsKey(pageId)) {
      final cachedTime = _cacheTimestamps[pageId];
      if (cachedTime != null &&
          DateTime.now().difference(cachedTime) < _cacheValidity) {
        return _pageCache[pageId];
      }
    }
    return null;
  }

  /// 노트의 페이지 ID 목록 가져오기 - 메모리에서만 조회
  Future<List<String>> getCachedNotePageIds(String noteId) async {
    if (_notePageIds.containsKey(noteId)) {
      return List<String>.from(_notePageIds[noteId] ?? []);
    }
    return [];
  }

  /// 노트의 모든 페이지 가져오기 - 메모리에서만 조회
  Future<List<page_model.Page>> getPagesForNote(String noteId) async {
    final pageIds = await getCachedNotePageIds(noteId);
    final pages = <page_model.Page>[];

    for (final pageId in pageIds) {
      final page = await getCachedPage(pageId);
      if (page != null) {
        pages.add(page);
      }
    }

    return pages;
  }

  /// 노트와 페이지를 함께 가져오기
  Future<Map<String, dynamic>> getNoteWithPages(String noteId) async {
    final note = await getCachedNote(noteId);
    final pages = await getPagesForNote(noteId);

    return {
      'note': note,
      'pages': pages,
      'isFromCache': note != null,
    };
  }

  /// 노트의 모든 페이지가 캐시에 있는지 확인
  Future<bool> hasAllPagesForNote(String noteId) async {
    return _notePageIds.containsKey(noteId) && _notePageIds[noteId]!.isNotEmpty;
  }

  /// 캐시에서 노트 삭제
  Future<void> removeCachedNote(String noteId) async {
    _noteCache.remove(noteId);
    _cacheTimestamps.remove(noteId);
    _notePageIds.remove(noteId);
  }

  /// 캐시에서 페이지 삭제
  Future<void> removePage(String pageId) async {
    _pageCache.remove(pageId);
    _cacheTimestamps.remove(pageId);

    // 노트-페이지 관계에서도 제거
    for (final noteId in _notePageIds.keys) {
      _notePageIds[noteId]?.remove(pageId);
    }
  }

  /// 노트의 모든 페이지를 캐시에서 삭제
  Future<void> removePagesForNote(String noteId) async {
    final pageIds = List<String>.from(_notePageIds[noteId] ?? []);
    for (final pageId in pageIds) {
      _pageCache.remove(pageId);
      _cacheTimestamps.remove(pageId);
    }
    _notePageIds.remove(noteId);
  }

  /// 전체 캐시 초기화
  void clearCache() {
    _noteCache.clear();
    _pageCache.clear();
    _notePageIds.clear();
    _cacheTimestamps.clear();
    debugPrint('모든 캐시가 초기화되었습니다.');
  }

  /// 노트 캐시 통계 정보 (디버깅용)
  Map<String, dynamic> getNoteCacheStats() {
    return {
      'memoryItems': _noteCache.length,
      'oldestCacheTime': _cacheTimestamps.isEmpty
          ? null
          : _cacheTimestamps.entries
              .where((entry) => _noteCache.containsKey(entry.key))
              .map((entry) => entry.value)
              .reduce((a, b) => a.isBefore(b) ? a : b),
      'newestCacheTime': _cacheTimestamps.isEmpty
          ? null
          : _cacheTimestamps.entries
              .where((entry) => _noteCache.containsKey(entry.key))
              .map((entry) => entry.value)
              .reduce((a, b) => a.isAfter(b) ? a : b),
    };
  }

  /// 페이지 캐시 통계 정보 (디버깅용)
  Map<String, dynamic> getPageCacheStats() {
    return {
      'memoryItems': _pageCache.length,
      'notesWithCachedPages': _notePageIds.length,
      'oldestCacheTime': _cacheTimestamps.isEmpty
          ? null
          : _cacheTimestamps.entries
              .where((entry) => _pageCache.containsKey(entry.key))
              .map((entry) => entry.value)
              .reduce((a, b) => a.isBefore(b) ? a : b),
      'newestCacheTime': _cacheTimestamps.isEmpty
          ? null
          : _cacheTimestamps.entries
              .where((entry) => _pageCache.containsKey(entry.key))
              .map((entry) => entry.value)
              .reduce((a, b) => a.isAfter(b) ? a : b),
    };
  }

  /// 텍스트 해시 생성
  String _generateTextHash(String text) {
    try {
      // 텍스트가 너무 길 경우 앞부분만 사용
      final String textToHash =
          text.length > 1000 ? text.substring(0, 1000) : text;
      final bytes = utf8.encode(textToHash);
      final digest = sha256.convert(bytes);
      return digest.toString();
    } catch (e) {
      debugPrint('텍스트 해시 생성 중 오류 발생: $e');
      // 오류 발생 시 대체 해시 생성 (텍스트 길이와 현재 시간 기반)
      return 'fallback_${text.length}_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// 여러 노트 캐싱
  Future<void> cacheNotes(List<Note> notes) async {
    for (final note in notes) {
      if (note.id != null) {
        await cacheNote(note);
      }
    }
  }

  /// 캐시된 모든 노트 가져오기
  Future<List<Note>> getCachedNotes() async {
    final now = DateTime.now();
    final validNotes = <Note>[];

    for (final entry in _noteCache.entries) {
      final cachedTime = _cacheTimestamps[entry.key];
      if (cachedTime != null && now.difference(cachedTime) < _cacheValidity) {
        validNotes.add(entry.value);
      }
    }

    return validNotes;
  }

  /// 번역 가져오기
  Future<String?> getTranslation(
      String originalText, String targetLanguage) async {
    if (originalText.isEmpty) return null;

    // 긴 텍스트의 경우 해시 사용
    final textHash = _generateTextHash(originalText);
    final key =
        _translationKeyPrefix + '${textHash}_${targetLanguage.toLowerCase()}';

    // 메모리 캐시 확인
    if (_translationCache.containsKey(key)) {
      debugPrint('메모리에서 캐시된 번역 찾음');
      return _translationCache[key];
    }

    // 로컬 캐시 확인
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(key);
      final timestampKey =
          '${_translationKeyPrefix}timestamp_${textHash}_${targetLanguage.toLowerCase()}';
      final timestampStr = prefs.getString(timestampKey);

      if (cachedData != null && timestampStr != null) {
        try {
          final timestamp = DateTime.parse(timestampStr);
          if (DateTime.now().difference(timestamp) < _cacheValidity) {
            debugPrint('로컬에서 캐시된 번역 찾음');
            // 메모리 캐시에도 저장
            _translationCache[key] = cachedData;
            _cacheTimestamps[key] = timestamp;
            return cachedData;
          }
        } catch (e) {
          debugPrint('타임스탬프 파싱 중 오류: $e');
        }
      }
    } catch (e) {
      debugPrint('로컬 캐시 접근 중 오류: $e');
    }

    return null;
  }

  /// 번역 캐싱
  Future<void> cacheTranslation(
      String originalText, String translatedText, String targetLanguage) async {
    if (originalText.isEmpty || translatedText.isEmpty) return;

    // 긴 텍스트의 경우 해시 사용
    final textHash = _generateTextHash(originalText);
    final key =
        _translationKeyPrefix + '${textHash}_${targetLanguage.toLowerCase()}';

    // 메모리 캐시에 저장
    _translationCache[key] = translatedText;
    _cacheTimestamps[key] = DateTime.now();

    // 로컬 캐시에 저장
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, translatedText);
      await prefs.setString(
          '${_translationKeyPrefix}timestamp_${textHash}_${targetLanguage.toLowerCase()}',
          DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('번역 로컬 캐싱 중 오류: $e');
    }

    // 캐시 크기 제한
    _limitCacheSize();
  }

  /// 캐시 크기 제한
  void _limitCacheSize() {
    // 번역 캐시 크기 제한
    if (_translationCache.length > _maxTranslationItems) {
      // 가장 오래된 항목부터 제거
      final sortedEntries = _cacheTimestamps.entries
          .where((entry) => entry.key.startsWith(_translationKeyPrefix))
          .toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      final itemsToRemove = sortedEntries.length - _maxTranslationItems;
      if (itemsToRemove > 0) {
        for (int i = 0; i < itemsToRemove; i++) {
          final key = sortedEntries[i].key;
          _translationCache.remove(key);
          _cacheTimestamps.remove(key);
        }
      }
    }
  }

  /// 텍스트 캐싱
  Future<void> cacheText(String type, String id, String text) async {
    try {
      // 메모리 캐시에 저장
      final key = '${type}_$id';
      final now = DateTime.now();

      // 메모리 캐시에 저장
      _cacheTimestamps[key] = now;

      // 타입에 따라 다른 캐시 맵에 저장
      if (type == 'page_original' || type == 'page_translated') {
        // 페이지 텍스트 캐싱
        final pageId = id;
        if (_pageCache.containsKey(pageId)) {
          final page = _pageCache[pageId]!;
          if (type == 'page_original') {
            _pageCache[pageId] = page.copyWith(originalText: text);
          } else {
            _pageCache[pageId] = page.copyWith(translatedText: text);
          }
        }
      }

      // 로컬 저장소에 저장
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, text);
        await prefs.setString('${type}_timestamp_$id', now.toIso8601String());
        debugPrint('텍스트 캐싱 완료: $type, ID=$id, 길이=${text.length}');
      } catch (e) {
        debugPrint('로컬 저장소에 텍스트 캐싱 중 오류: $e');
      }
    } catch (e) {
      debugPrint('텍스트 캐싱 중 오류 발생: $e');
    }
  }

  /// 핀인 캐시 로드
  Future<Map<String, String>> loadPinyinCache(String? pageId) async {
    if (pageId == null || pageId.isEmpty) return {};

    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'pinyin_cache_$pageId';
      final cachedData = prefs.getString(cacheKey);

      if (cachedData != null && cachedData.isNotEmpty) {
        final Map<String, dynamic> jsonData = json.decode(cachedData);
        final Map<String, String> pinyinCache = {};

        jsonData.forEach((key, value) {
          if (value is String) {
            pinyinCache[key] = value;
          }
        });

        debugPrint('핀인 캐시 로드 성공: ${pinyinCache.length}개 항목');
        return pinyinCache;
      }
    } catch (e) {
      debugPrint('핀인 캐시 로드 중 오류 발생: $e');
    }
    return {};
  }

  /// 핀인 캐시 저장
  Future<void> savePinyinCache(
      String? pageId, Map<String, String> cache) async {
    if (pageId == null || pageId.isEmpty || cache.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'pinyin_cache_$pageId';
      final jsonData = json.encode(cache);
      await prefs.setString(cacheKey, jsonData);
      debugPrint('핀인 캐시 저장 성공: ${cache.length}개 항목');
    } catch (e) {
      debugPrint('핀인 캐시 저장 중 오류 발생: $e');
    }
  }

  // 처리된 텍스트 캐시 (캐시 키 -> ProcessedText 객체)
  final Map<String, dynamic> _processedTextCache = {};

  // 처리된 텍스트 캐싱
  Future<void> cacheProcessedText(
    String pageId,
    String textProcessingMode,
    dynamic processedText,
  ) async {
    try {
      if (!_isInitialized) await initialize();

      // 캐시 키 생성 (페이지 ID + 처리 모드)
      final cacheKey = 'processed_text_${pageId}_${textProcessingMode}';
      final now = DateTime.now();

      // 메모리 캐시에 저장
      _processedTextCache[cacheKey] = processedText;
      _cacheTimestamps[cacheKey] = now;

      // 로컬 저장소에 저장
      try {
        final prefs = await SharedPreferences.getInstance();
        final jsonData = jsonEncode(processedText.toJson());
        await prefs.setString(cacheKey, jsonData);
        await prefs.setString('${cacheKey}_timestamp', now.toIso8601String());
        debugPrint('처리된 텍스트 캐싱 완료: 페이지 ID=$pageId, 모드=$textProcessingMode');
      } catch (e) {
        debugPrint('로컬 저장소에 처리된 텍스트 캐싱 중 오류: $e');
      }
    } catch (e) {
      debugPrint('처리된 텍스트 캐싱 중 오류 발생: $e');
    }
  }

  // 처리된 텍스트 가져오기
  Future<dynamic> getCachedProcessedText(
    String pageId,
    String textProcessingMode,
  ) async {
    try {
      if (!_isInitialized) await initialize();

      // 캐시 키 생성
      final cacheKey = 'processed_text_${pageId}_${textProcessingMode}';

      // 1. 메모리 캐시 확인
      if (_processedTextCache.containsKey(cacheKey)) {
        final cachedTime = _cacheTimestamps[cacheKey];
        if (cachedTime != null &&
            DateTime.now().difference(cachedTime) < _cacheValidity) {
          debugPrint(
              '메모리 캐시에서 처리된 텍스트 로드: 페이지 ID=$pageId, 모드=$textProcessingMode');
          return _processedTextCache[cacheKey];
        }
      }

      // 2. 로컬 저장소 확인
      final prefs = await SharedPreferences.getInstance();
      final jsonData = prefs.getString(cacheKey);
      final timestampStr = prefs.getString('${cacheKey}_timestamp');

      if (jsonData != null && timestampStr != null) {
        final timestamp = DateTime.parse(timestampStr);
        if (DateTime.now().difference(timestamp) < _cacheValidity) {
          try {
            // JSON 데이터를 ProcessedText 객체로 변환
            final Map<String, dynamic> jsonMap = jsonDecode(jsonData);
            final processedText = ProcessedText.fromJson(jsonMap);

            // 메모리 캐시에도 저장
            _processedTextCache[cacheKey] = processedText;
            _cacheTimestamps[cacheKey] = timestamp;

            debugPrint(
                '로컬 저장소에서 처리된 텍스트 로드: 페이지 ID=$pageId, 모드=$textProcessingMode');
            return processedText;
          } catch (e) {
            debugPrint('처리된 텍스트 역직렬화 중 오류: $e');
          }
        }
      }

      // 캐시 없음
      return null;
    } catch (e) {
      debugPrint('처리된 텍스트 캐시 조회 중 오류 발생: $e');
      return null;
    }
  }

  // 처리된 텍스트 캐시 삭제
  Future<void> clearProcessedTextCache(String pageId) async {
    try {
      // 메모리 캐시에서 삭제
      final keysToRemove = _processedTextCache.keys
          .where((key) => key.startsWith('processed_text_${pageId}_'))
          .toList();

      for (final key in keysToRemove) {
        _processedTextCache.remove(key);
        _cacheTimestamps.remove(key);
      }

      // 로컬 저장소에서 삭제
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      for (final key in allKeys) {
        if (key.startsWith('processed_text_${pageId}_')) {
          await prefs.remove(key);
          await prefs.remove('${key}_timestamp');
        }
      }

      debugPrint('페이지 ID=$pageId의 처리된 텍스트 캐시 삭제 완료');
    } catch (e) {
      debugPrint('처리된 텍스트 캐시 삭제 중 오류 발생: $e');
    }
  }

  // 주기적인 캐시 정리 설정
  void _setupPeriodicCacheCleanup() {
    // 30분마다 메모리 캐시 정리
    Future.delayed(const Duration(minutes: 30), () {
      if (_isInitialized) {
        debugPrint('주기적인 캐시 정리 실행');
        _clearMemoryCache();

        // 메모리 사용량 모니터링 및 필요시 추가 정리
        _monitorMemoryUsage();

        _setupPeriodicCacheCleanup(); // 재귀적으로 다음 정리 예약
      }
    });
  }

  // 메모리 사용량 모니터링
  void _monitorMemoryUsage() {
    try {
      final noteStats = getNoteCacheStats();
      final pageStats = getPageCacheStats();

      final totalItems = noteStats['memoryItems'] +
          pageStats['memoryItems'] +
          _translationCache.length +
          _processedTextCache.length;

      debugPrint('현재 메모리 캐시 상태:');
      debugPrint('- 노트: ${noteStats['memoryItems']}개');
      debugPrint('- 페이지: ${pageStats['memoryItems']}개');
      debugPrint('- 번역: ${_translationCache.length}개');
      debugPrint('- 처리된 텍스트: ${_processedTextCache.length}개');
      debugPrint('- 총 항목 수: $totalItems개');

      // 메모리 사용량이 많은 경우 추가 정리
      if (totalItems > 1000) {
        debugPrint('메모리 사용량이 많아 추가 정리 수행');
        _clearMemoryCache(aggressive: true);
      }
    } catch (e) {
      debugPrint('메모리 사용량 모니터링 중 오류: $e');
    }
  }

  // 메모리 캐시 정리
  void _clearMemoryCache({bool aggressive = false}) {
    int clearedItems = 0;

    // 공격적 정리 모드인 경우 더 많은 항목 제거
    final int maxNoteKeep = aggressive ? 10 : (_maxNoteItems ~/ 2);
    final int maxPageKeep = aggressive ? 30 : (_maxPageItems ~/ 2);
    final int maxTranslationKeep =
        aggressive ? 50 : (_maxTranslationItems ~/ 2);
    final int maxProcessedTextKeep = aggressive ? 20 : 50;

    // 노트 캐시 정리
    if (_noteCache.length > maxNoteKeep) {
      debugPrint('노트 캐시 정리 시작');

      // 노트 ID와 마지막 접근 시간으로 정렬
      final entries = <MapEntry<String, DateTime>>[];
      for (final key in _noteCache.keys) {
        final timestamp = _cacheTimestamps[key] ?? DateTime.now();
        entries.add(MapEntry(key, timestamp));
      }

      // 가장 오래된 항목부터 정렬
      entries.sort((a, b) => a.value.compareTo(b.value));

      // 오래된 항목부터 제거
      final itemsToRemove = _noteCache.length - maxNoteKeep;
      for (int i = 0; i < itemsToRemove; i++) {
        if (i < entries.length) {
          final key = entries[i].key;
          _noteCache.remove(key);
          _cacheTimestamps.remove(key);
          clearedItems++;
        }
      }
    }

    // 페이지 캐시 정리
    if (_pageCache.length > maxPageKeep) {
      debugPrint('페이지 캐시 정리 시작');

      // 페이지 ID와 마지막 접근 시간으로 정렬
      final entries = <MapEntry<String, DateTime>>[];
      for (final key in _pageCache.keys) {
        final timestamp = _cacheTimestamps[key] ?? DateTime.now();
        entries.add(MapEntry(key, timestamp));
      }

      // 가장 오래된 항목부터 정렬
      entries.sort((a, b) => a.value.compareTo(b.value));

      // 오래된 항목부터 제거
      final itemsToRemove = _pageCache.length - maxPageKeep;
      for (int i = 0; i < itemsToRemove; i++) {
        if (i < entries.length) {
          final key = entries[i].key;
          _pageCache.remove(key);
          _cacheTimestamps.remove(key);
          clearedItems++;
        }
      }
    }

    // 번역 캐시 정리
    if (_translationCache.length > maxTranslationKeep) {
      debugPrint('번역 캐시 정리 시작');

      // 번역 키와 마지막 접근 시간으로 정렬
      final entries = <MapEntry<String, DateTime>>[];
      for (final key in _translationCache.keys) {
        final timestamp = _cacheTimestamps[key] ?? DateTime.now();
        entries.add(MapEntry(key, timestamp));
      }

      // 가장 오래된 항목부터 정렬
      entries.sort((a, b) => a.value.compareTo(b.value));

      // 오래된 항목부터 제거
      final itemsToRemove = _translationCache.length - maxTranslationKeep;
      for (int i = 0; i < itemsToRemove; i++) {
        if (i < entries.length) {
          final key = entries[i].key;
          _translationCache.remove(key);
          _cacheTimestamps.remove(key);
          clearedItems++;
        }
      }
    }

    // 처리된 텍스트 캐시 정리
    if (_processedTextCache.length > maxProcessedTextKeep) {
      debugPrint('처리된 텍스트 캐시 정리 시작');

      // 키와 마지막 접근 시간으로 정렬
      final entries = <MapEntry<String, DateTime>>[];
      for (final key in _processedTextCache.keys) {
        final timestamp = _cacheTimestamps[key] ?? DateTime.now();
        entries.add(MapEntry(key, timestamp));
      }

      // 가장 오래된 항목부터 정렬
      entries.sort((a, b) => a.value.compareTo(b.value));

      // 오래된 항목부터 제거
      final itemsToRemove = _processedTextCache.length - maxProcessedTextKeep;
      for (int i = 0; i < itemsToRemove; i++) {
        if (i < entries.length) {
          final key = entries[i].key;
          _processedTextCache.remove(key);
          _cacheTimestamps.remove(key);
          clearedItems++;
        }
      }
    }

    if (clearedItems > 0) {
      debugPrint('메모리 캐시 정리 완료: 총 $clearedItems개 항목 제거');
    }
  }
}
