import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';
import '../models/page.dart' as page_model;
import 'package:crypto/crypto.dart';

/// 통합 캐싱 서비스
///
/// 노트와 페이지 데이터를 위한 통합 캐싱 서비스입니다.
/// 메모리 캐싱과 로컬 저장소 캐싱을 모두 지원합니다.
/// 메모리 캐시는 앱이 실행 중일 때만 유지되며, 로컬 저장소 캐시는 앱을 재시작해도 유지됩니다.
class UnifiedCacheService {
  // 싱글톤 인스턴스
  static final UnifiedCacheService _instance = UnifiedCacheService._internal();
  factory UnifiedCacheService() => _instance;
  UnifiedCacheService._internal() {
    // 앱 시작 시 로컬 캐시 정리
    _cleanupExpiredLocalCache();
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

  /// 로컬 저장소 캐시 정리 (오래된 항목 제거)
  Future<void> _cleanupExpiredLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      final now = DateTime.now();

      for (final key in allKeys) {
        if (key.contains('timestamp_')) {
          final timestampStr = prefs.getString(key);
          if (timestampStr != null) {
            final timestamp = DateTime.parse(timestampStr);
            if (now.difference(timestamp) > _cacheValidity) {
              // 타임스탬프 키에서 원본 키 추출
              String originalKey;
              if (key.startsWith('${_noteKeyPrefix}timestamp_')) {
                originalKey = _noteKeyPrefix +
                    key.substring('${_noteKeyPrefix}timestamp_'.length);
              } else if (key.startsWith('${_pageKeyPrefix}timestamp_')) {
                originalKey = _pageKeyPrefix +
                    key.substring('${_pageKeyPrefix}timestamp_'.length);
              } else {
                continue;
              }

              await prefs.remove(originalKey);
              await prefs.remove(key);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('만료된 로컬 캐시 정리 중 오류 발생: $e');
    }
  }

  /// 노트 캐싱
  Future<void> cacheNote(Note note) async {
    if (note.id == null) return;

    final noteId = note.id!;

    // 메모리 캐시에 저장
    _noteCache[noteId] = note;
    _cacheTimestamps[noteId] = DateTime.now();

    // 캐시 크기 관리
    _cleanupMemoryCacheIfNeeded();

    // 로컬 저장소에 저장
    try {
      final prefs = await SharedPreferences.getInstance();
      final noteJson = jsonEncode(note.toJson());
      await prefs.setString('$_noteKeyPrefix$noteId', noteJson);
      await prefs.setString('${_noteKeyPrefix}timestamp_$noteId',
          DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('노트 로컬 캐싱 중 오류 발생: $e');
    }
  }

  /// 노트 목록 캐싱
  Future<void> cacheNotes(List<Note> notes) async {
    for (final note in notes) {
      await cacheNote(note);
    }
  }

  /// 캐시에서 노트 가져오기
  Future<Note?> getCachedNote(String noteId) async {
    // 1. 메모리 캐시 확인
    if (_noteCache.containsKey(noteId)) {
      final cachedTime = _cacheTimestamps[noteId];
      if (cachedTime != null &&
          DateTime.now().difference(cachedTime) < _cacheValidity) {
        debugPrint('메모리 캐시에서 노트 로드: $noteId');
        return _noteCache[noteId];
      }
    }

    // 2. 로컬 저장소 확인
    try {
      final prefs = await SharedPreferences.getInstance();
      final noteJson = prefs.getString('$_noteKeyPrefix$noteId');
      final timestampStr =
          prefs.getString('${_noteKeyPrefix}timestamp_$noteId');

      if (noteJson != null && timestampStr != null) {
        final timestamp = DateTime.parse(timestampStr);
        if (DateTime.now().difference(timestamp) < _cacheValidity) {
          debugPrint('로컬 저장소에서 노트 로드: $noteId');
          final noteMap = jsonDecode(noteJson) as Map<String, dynamic>;
          final note = Note.fromJson(noteMap);

          // 메모리 캐시 업데이트
          _noteCache[noteId] = note;
          _cacheTimestamps[noteId] = DateTime.now();

          return note;
        }
      }
    } catch (e) {
      debugPrint('캐시에서 노트 로드 중 오류 발생: $e');
    }

    return null;
  }

  /// 캐시에서 노트 목록 가져오기
  Future<List<Note>> getCachedNotes() async {
    final notes = <Note>[];

    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      for (final key in allKeys) {
        if (key.startsWith(_noteKeyPrefix) && !key.contains('timestamp')) {
          final noteId = key.substring(_noteKeyPrefix.length);
          final note = await getCachedNote(noteId);
          if (note != null) {
            notes.add(note);
          }
        }
      }
    } catch (e) {
      debugPrint('캐시에서 노트 목록 로드 중 오류 발생: $e');
    }

    return notes;
  }

  /// 캐시에서 노트 삭제
  Future<void> removeCachedNote(String noteId) async {
    // 메모리 캐시에서 삭제
    _noteCache.remove(noteId);
    _cacheTimestamps.remove(noteId);

    // 로컬 저장소에서 삭제
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_noteKeyPrefix$noteId');
      await prefs.remove('${_noteKeyPrefix}timestamp_$noteId');
    } catch (e) {
      debugPrint('캐시에서 노트 삭제 중 오류 발생: $e');
    }
  }

  /// 메모리 캐시 정리
  void _cleanupMemoryCacheIfNeeded() {
    // 노트 캐시 정리
    if (_noteCache.length > _maxNoteItems) {
      // 가장 오래된 항목부터 삭제
      final noteEntries = _cacheTimestamps.entries
          .where((entry) => _noteCache.containsKey(entry.key))
          .toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      final noteItemsToRemove =
          (_noteCache.length - (_maxNoteItems * 0.8)).ceil();
      for (int i = 0; i < noteItemsToRemove && i < noteEntries.length; i++) {
        final noteId = noteEntries[i].key;
        _noteCache.remove(noteId);
        _cacheTimestamps.remove(noteId);
      }
    }

    // 페이지 캐시 정리
    if (_pageCache.length > _maxPageItems) {
      // 가장 오래된 항목부터 삭제
      final pageEntries = _cacheTimestamps.entries
          .where((entry) => _pageCache.containsKey(entry.key))
          .toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      final pageItemsToRemove =
          (_pageCache.length - (_maxPageItems * 0.8)).ceil();
      for (int i = 0; i < pageItemsToRemove && i < pageEntries.length; i++) {
        final pageId = pageEntries[i].key;
        _pageCache.remove(pageId);
        _cacheTimestamps.remove(pageId);
      }
    }

    // 번역 캐시 정리
    if (_translationCache.length > _maxTranslationItems) {
      // 가장 오래된 항목부터 삭제
      final translationEntries = _cacheTimestamps.entries
          .where((entry) => _translationCache.containsKey(entry.key))
          .toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      final translationItemsToRemove =
          (_translationCache.length - (_maxTranslationItems * 0.8)).ceil();
      for (int i = 0;
          i < translationItemsToRemove && i < translationEntries.length;
          i++) {
        final textHash = translationEntries[i].key;
        _translationCache.remove(textHash);
        _cacheTimestamps.remove(textHash);
      }
    }
  }

  /// 페이지를 캐시에 저장
  Future<void> cachePage(String noteId, page_model.Page page) async {
    if (page.id == null) return;

    final pageId = page.id!;

    // 메모리 캐시에 저장
    _pageCache[pageId] = page;
    _cacheTimestamps[pageId] = DateTime.now();

    // 노트-페이지 관계 업데이트
    if (!_notePageIds.containsKey(noteId)) {
      _notePageIds[noteId] = [];
    }

    if (!_notePageIds[noteId]!.contains(pageId)) {
      _notePageIds[noteId]!.add(pageId);

      // 페이지 번호 순으로 정렬
      final pages = _notePageIds[noteId]!
          .map((id) => _pageCache[id])
          .whereType<page_model.Page>()
          .toList();
      pages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
      _notePageIds[noteId] = pages.map((p) => p.id!).toList();

      debugPrint(
          '메모리 캐시에 노트 $noteId의 페이지 $pageId 추가 (총 ${_notePageIds[noteId]!.length}개)');
    }

    _cleanupMemoryCacheIfNeeded();

    // 로컬 저장소에 저장
    try {
      final prefs = await SharedPreferences.getInstance();
      final pageJson = jsonEncode(page.toJson());
      await prefs.setString('$_pageKeyPrefix$pageId', pageJson);
      await prefs.setString('${_pageKeyPrefix}timestamp_$pageId',
          DateTime.now().toIso8601String());

      // 노트-페이지 관계 저장
      await _saveNotePageIdsToLocal(noteId);
    } catch (e) {
      debugPrint('페이지 로컬 캐싱 중 오류 발생: $e');
    }
  }

  /// 노트-페이지 관계를 로컬 저장소에 저장
  Future<void> _saveNotePageIdsToLocal(String noteId) async {
    try {
      if (!_notePageIds.containsKey(noteId) || _notePageIds[noteId]!.isEmpty) {
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          '$_notePageIdsPrefix$noteId', _notePageIds[noteId]!);
      await prefs.setString(
        '${_notePageIdsPrefix}timestamp_$noteId',
        DateTime.now().toIso8601String(),
      );

      debugPrint(
          '노트-페이지 관계 로컬 저장 완료: $noteId, ${_notePageIds[noteId]!.length}개 페이지');
    } catch (e) {
      debugPrint('노트-페이지 관계 로컬 저장 중 오류 발생: $e');
    }
  }

  /// 노트의 모든 페이지를 캐시에 저장
  Future<void> cachePages(String noteId, List<page_model.Page> pages) async {
    if (pages.isEmpty) return;

    // 유효한 ID가 있는 페이지만 필터링
    final validPages = pages.where((page) => page.id != null).toList();
    if (validPages.isEmpty) return;

    // 페이지 번호 순으로 정렬
    validPages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));

    // 기존 페이지 ID 목록 가져오기
    final existingIds = _notePageIds[noteId] ?? [];

    // 새 페이지 ID 목록 생성
    final newPageIds = validPages.map((page) => page.id!).toList();

    // 중복 제거하여 병합
    final mergedIds = {...existingIds, ...newPageIds}.toList();

    // 각 페이지 캐싱 (병렬 처리)
    final futures = <Future<void>>[];
    for (final page in validPages) {
      // 메모리 캐시에 직접 저장 (cachePage 호출 없이)
      if (page.id != null) {
        _pageCache[page.id!] = page;
        _cacheTimestamps[page.id!] = DateTime.now();
        futures.add(_saveSinglePageToLocal(page));
      }
    }

    // 모든 페이지 저장 완료 대기
    await Future.wait(futures);

    // 노트-페이지 관계 업데이트
    _notePageIds[noteId] = mergedIds;

    // 노트-페이지 관계 로컬 저장
    await _saveNotePageIdsToLocal(noteId);

    debugPrint(
        '노트 $noteId의 페이지 ${mergedIds.length}개가 캐시에 저장됨 (${validPages.length}개 추가)');
  }

  /// 단일 페이지를 로컬 저장소에 저장
  Future<void> _saveSinglePageToLocal(page_model.Page page) async {
    if (page.id == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final pageJson = jsonEncode(page.toJson());
      await prefs.setString('$_pageKeyPrefix${page.id}', pageJson);
      await prefs.setString(
        '${_pageKeyPrefix}timestamp_${page.id}',
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      debugPrint('페이지 ${page.id} 로컬 저장 중 오류 발생: $e');
    }
  }

  /// 노트의 모든 페이지를 캐시에서 가져오기
  Future<List<page_model.Page>> getPagesForNote(String noteId) async {
    debugPrint('노트 $noteId의 페이지 조회 시작 (캐시)');

    // 메모리에 노트-페이지 관계가 없으면 로컬 저장소에서 로드
    if (!_notePageIds.containsKey(noteId) || _notePageIds[noteId]!.isEmpty) {
      await _loadNotePageIdsFromLocal(noteId);
    }

    final pageIds = _notePageIds[noteId] ?? [];
    if (pageIds.isEmpty) {
      debugPrint('노트 $noteId의 캐시된 페이지 ID가 없음');
      return [];
    }

    debugPrint('노트 $noteId의 캐시된 페이지 ID ${pageIds.length}개 발견');

    final pages = <page_model.Page>[];
    final missingPageIds = <String>[];
    final futures = <Future<void>>[];

    // 각 페이지 ID에 대해 병렬로 처리
    for (final pageId in pageIds) {
      futures.add(_loadSinglePageAndAdd(pageId, pages, missingPageIds));
    }

    // 모든 페이지 로드 완료 대기
    await Future.wait(futures);

    // 페이지 번호 순으로 정렬
    pages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));

    if (missingPageIds.isNotEmpty) {
      debugPrint('캐시에서 찾을 수 없는 페이지 ID: $missingPageIds');

      // 누락된 페이지 ID 제거
      _notePageIds[noteId] =
          pageIds.where((id) => !missingPageIds.contains(id)).toList();
      await _saveNotePageIdsToLocal(noteId);
    }

    debugPrint(
        '캐시에서 노트 $noteId의 페이지 ID ${pageIds.length}개 중 ${pages.length}개 로드됨');
    return pages;
  }

  /// 단일 페이지를 로드하고 리스트에 추가
  Future<void> _loadSinglePageAndAdd(String pageId, List<page_model.Page> pages,
      List<String> missingPageIds) async {
    // 1. 메모리 캐시 확인
    var page = _pageCache[pageId];
    if (page != null) {
      // 페이지가 있으면 타임스탬프 업데이트
      _cacheTimestamps[pageId] = DateTime.now();
      pages.add(page);
      return;
    }

    // 2. 로컬 저장소 확인
    try {
      final prefs = await SharedPreferences.getInstance();
      final pageJson = prefs.getString('$_pageKeyPrefix$pageId');
      final timestampStr =
          prefs.getString('${_pageKeyPrefix}timestamp_$pageId');

      if (pageJson != null && timestampStr != null) {
        final timestamp = DateTime.parse(timestampStr);
        if (DateTime.now().difference(timestamp) < _cacheValidity) {
          try {
            final pageMap = jsonDecode(pageJson) as Map<String, dynamic>;
            page = page_model.Page.fromJson(pageMap);

            // 메모리 캐시 업데이트
            _pageCache[pageId] = page;
            _cacheTimestamps[pageId] = DateTime.now();

            pages.add(page);
            return;
          } catch (e) {
            debugPrint('페이지 JSON 파싱 중 오류 발생: $e');
            // 캐시 데이터가 손상된 경우 제거
            await prefs.remove('$_pageKeyPrefix$pageId');
            await prefs.remove('${_pageKeyPrefix}timestamp_$pageId');
          }
        } else {
          // 캐시가 만료된 경우 제거
          await prefs.remove('$_pageKeyPrefix$pageId');
          await prefs.remove('${_pageKeyPrefix}timestamp_$pageId');
        }
      }
    } catch (e) {
      debugPrint('로컬 저장소에서 페이지 로드 중 오류 발생: $e');
    }

    // 페이지를 찾지 못한 경우
    missingPageIds.add(pageId);
  }

  /// 로컬 저장소에서 노트-페이지 관계 로드
  Future<void> _loadNotePageIdsFromLocal(String noteId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pageIds = prefs.getStringList('$_notePageIdsPrefix$noteId');
      final timestampStr =
          prefs.getString('${_notePageIdsPrefix}timestamp_$noteId');

      // 이미 메모리에 있는 경우 스킵 (최적화)
      if (_notePageIds.containsKey(noteId) &&
          _notePageIds[noteId]!.isNotEmpty) {
        debugPrint(
            '노트 $noteId의 페이지 ID가 이미 메모리에 있음 (${_notePageIds[noteId]!.length}개)');
        return;
      }

      if (pageIds != null && pageIds.isNotEmpty) {
        // 캐시 유효성 검사
        bool isValid = true;
        if (timestampStr != null) {
          final timestamp = DateTime.parse(timestampStr);
          isValid = DateTime.now().difference(timestamp) < _cacheValidity;
        } else {
          isValid = false; // 타임스탬프가 없으면 유효하지 않음
        }

        if (isValid) {
          // 각 페이지 ID가 실제로 존재하는지 확인
          final validPageIds = <String>[];
          for (final pageId in pageIds) {
            if (await hasPage(pageId)) {
              validPageIds.add(pageId);
            }
          }

          if (validPageIds.isNotEmpty) {
            _notePageIds[noteId] = validPageIds;
            debugPrint(
                '로컬 저장소에서 노트 $noteId의 페이지 ID ${validPageIds.length}개 로드됨 (원래: ${pageIds.length}개)');

            // 유효한 페이지 ID만 저장
            if (validPageIds.length != pageIds.length) {
              await prefs.setStringList(
                  '$_notePageIdsPrefix$noteId', validPageIds);
              await prefs.setString(
                '${_notePageIdsPrefix}timestamp_$noteId',
                DateTime.now().toIso8601String(),
              );
              debugPrint(
                  '노트 $noteId의 페이지 ID 목록 업데이트됨 (${validPageIds.length}개)');
            }

            return;
          }
        }

        // 캐시가 유효하지 않거나 유효한 페이지가 없는 경우
        await prefs.remove('$_notePageIdsPrefix$noteId');
        await prefs.remove('${_notePageIdsPrefix}timestamp_$noteId');
        debugPrint('만료되거나 유효하지 않은 노트-페이지 관계 캐시 제거: $noteId');

        // 메모리에서도 제거
        _notePageIds.remove(noteId);
      } else {
        debugPrint('노트 $noteId의 페이지 ID 목록을 로컬 저장소에서 찾을 수 없음');
      }
    } catch (e) {
      debugPrint('로컬 저장소에서 노트-페이지 관계 로드 중 오류 발생: $e');
    }
  }

  /// 캐시에 페이지가 있는지 확인
  Future<bool> hasPage(String pageId) async {
    // 메모리 캐시 확인
    if (_pageCache.containsKey(pageId)) {
      return true;
    }

    // 로컬 저장소 확인
    try {
      final prefs = await SharedPreferences.getInstance();
      final pageJson = prefs.getString('$_pageKeyPrefix$pageId');
      final timestampStr =
          prefs.getString('${_pageKeyPrefix}timestamp_$pageId');

      if (pageJson != null && timestampStr != null) {
        final timestamp = DateTime.parse(timestampStr);
        return DateTime.now().difference(timestamp) < _cacheValidity;
      }
    } catch (e) {
      debugPrint('로컬 저장소에서 페이지 확인 중 오류 발생: $e');
    }

    return false;
  }

  /// 캐시에 노트의 모든 페이지가 있는지 확인
  Future<bool> hasAllPagesForNote(String noteId) async {
    debugPrint('노트 $noteId의 모든 페이지 캐시 확인');

    // 메모리에 노트-페이지 관계가 없으면 로컬 저장소에서 로드
    if (!_notePageIds.containsKey(noteId) || _notePageIds[noteId]!.isEmpty) {
      await _loadNotePageIdsFromLocal(noteId);
    }

    final pageIds = _notePageIds[noteId] ?? [];
    if (pageIds.isEmpty) {
      debugPrint('노트 $noteId의 캐시된 페이지 ID가 없음');
      return false;
    }

    // 모든 페이지가 메모리 캐시에 있는지 빠르게 확인
    bool allInMemory = true;
    for (final pageId in pageIds) {
      if (!_pageCache.containsKey(pageId)) {
        allInMemory = false;
        break;
      }
    }

    if (allInMemory) {
      debugPrint('노트 $noteId의 모든 페이지(${pageIds.length}개)가 메모리 캐시에 있음');
      return true;
    }

    // 모든 페이지가 캐시에 있는지 확인 (메모리 + 로컬 저장소)
    for (final pageId in pageIds) {
      final exists = await hasPage(pageId);
      if (!exists) {
        debugPrint('노트 $noteId의 페이지 $pageId가 캐시에 없음');
        return false;
      }
    }

    debugPrint('노트 $noteId의 모든 페이지(${pageIds.length}개)가 캐시에 있음');
    return true;
  }

  /// 캐시에서 페이지 제거
  Future<void> removePage(String pageId) async {
    // 메모리 캐시에서 제거
    _pageCache.remove(pageId);
    _cacheTimestamps.remove(pageId);

    // 로컬 저장소에서 제거
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_pageKeyPrefix$pageId');
      await prefs.remove('${_pageKeyPrefix}timestamp_$pageId');
    } catch (e) {
      debugPrint('로컬 저장소에서 페이지 제거 중 오류 발생: $e');
    }
  }

  /// 노트의 모든 페이지를 캐시에서 제거
  Future<void> removePagesForNote(String noteId) async {
    // 메모리에 노트-페이지 관계가 없으면 로컬 저장소에서 로드
    if (!_notePageIds.containsKey(noteId)) {
      await _loadNotePageIdsFromLocal(noteId);
    }

    final pageIds = _notePageIds[noteId] ?? [];
    for (final pageId in pageIds) {
      await removePage(pageId);
    }

    _notePageIds.remove(noteId);

    // 로컬 저장소에서 노트-페이지 관계 제거
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_notePageIdsPrefix$noteId');
      await prefs.remove('${_notePageIdsPrefix}timestamp_$noteId');
    } catch (e) {
      debugPrint('로컬 저장소에서 노트-페이지 관계 제거 중 오류 발생: $e');
    }
  }

  /// 전체 캐시 초기화
  Future<void> clearCache() async {
    // 메모리 캐시 초기화
    _noteCache.clear();
    _pageCache.clear();
    _cacheTimestamps.clear();
    _notePageIds.clear();

    // 로컬 저장소 캐시 초기화
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      for (final key in allKeys) {
        if (key.startsWith(_noteKeyPrefix) ||
            key.startsWith(_pageKeyPrefix) ||
            key.startsWith(_notePageIdsPrefix)) {
          await prefs.remove(key);
        }
      }
      debugPrint('캐시 초기화 완료');
    } catch (e) {
      debugPrint('로컬 저장소 캐시 초기화 중 오류 발생: $e');
    }
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

  /// 노트와 페이지를 함께 가져오기 (캐싱 활용)
  Future<Map<String, dynamic>> getNoteWithPages(String noteId) async {
    try {
      Note? note;
      List<page_model.Page> pages = [];
      bool isFromCache = false;

      debugPrint('노트 $noteId와 페이지 로드 시작');

      // 1. 캐시에서 노트 확인
      note = await getCachedNote(noteId);

      // 2. 캐시에 노트가 없으면 null 반환 (호출자가 Firestore에서 가져와야 함)
      if (note == null) {
        debugPrint('캐시에서 노트를 찾을 수 없음: $noteId');
        return {
          'note': null,
          'pages': [],
          'isFromCache': false,
        };
      } else {
        isFromCache = true;
        debugPrint('캐시에서 노트 로드: $noteId');
      }

      // 3. 캐시에서 페이지 확인
      final hasAllPages = await hasAllPagesForNote(noteId);

      if (hasAllPages) {
        // 캐시에 모든 페이지가 있으면 캐시에서 가져오기
        pages = await getPagesForNote(noteId);
        debugPrint('캐시에서 페이지 로드: ${pages.length}개');
      }

      return {
        'note': note,
        'pages': pages,
        'isFromCache': isFromCache,
      };
    } catch (e) {
      debugPrint('노트와 페이지를 가져오는 중 오류 발생: $e');
      rethrow;
    }
  }

  /// 번역 결과 캐싱
  Future<void> cacheTranslation(
      String originalText, String translatedText) async {
    if (originalText.isEmpty || translatedText.isEmpty) return;

    // 원본 텍스트의 해시 생성 (키로 사용)
    final textHash = _generateTextHash(originalText);

    // 메모리 캐시에 저장
    _translationCache[textHash] = translatedText;
    _cacheTimestamps[textHash] = DateTime.now();

    // 캐시 크기 관리
    _cleanupMemoryCacheIfNeeded();

    // 로컬 저장소에 저장
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_translationKeyPrefix$textHash', translatedText);
      await prefs.setString('${_translationKeyPrefix}timestamp_$textHash',
          DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('번역 결과 로컬 캐싱 중 오류 발생: $e');
    }
  }

  /// 캐시에서 번역 결과 가져오기
  Future<String?> getCachedTranslation(String originalText) async {
    if (originalText.isEmpty) return null;

    // 원본 텍스트의 해시 생성 (키로 사용)
    final textHash = _generateTextHash(originalText);

    // 1. 메모리 캐시 확인
    if (_translationCache.containsKey(textHash)) {
      final cachedTime = _cacheTimestamps[textHash];
      if (cachedTime != null &&
          DateTime.now().difference(cachedTime) < _cacheValidity) {
        debugPrint('메모리 캐시에서 번역 결과 로드');
        return _translationCache[textHash];
      }
    }

    // 2. 로컬 저장소 확인
    try {
      final prefs = await SharedPreferences.getInstance();
      final translatedText = prefs.getString('$_translationKeyPrefix$textHash');
      final timestampStr =
          prefs.getString('${_translationKeyPrefix}timestamp_$textHash');

      if (translatedText != null && timestampStr != null) {
        final timestamp = DateTime.parse(timestampStr);
        if (DateTime.now().difference(timestamp) < _cacheValidity) {
          debugPrint('로컬 저장소에서 번역 결과 로드');

          // 메모리 캐시 업데이트
          _translationCache[textHash] = translatedText;
          _cacheTimestamps[textHash] = DateTime.now();

          return translatedText;
        }
      }
    } catch (e) {
      debugPrint('캐시에서 번역 결과 로드 중 오류 발생: $e');
    }

    return null;
  }

  /// 텍스트 해시 생성
  String _generateTextHash(String text) {
    final bytes = utf8.encode(text);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
