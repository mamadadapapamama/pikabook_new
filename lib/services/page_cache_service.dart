import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/page.dart' as page_model;

/// 페이지 콘텐츠를 캐싱하는 서비스
///
/// 메모리 캐싱과 로컬 저장소 캐싱을 모두 지원합니다.
/// 메모리 캐시는 앱이 실행 중일 때만 유지되며, 로컬 저장소 캐시는 앱을 재시작해도 유지됩니다.
/// 메모리 사용량을 최소화하기 위해 캐시 크기를 제한하고 오래된 항목을 자동으로 제거합니다.
class PageCacheService {
  // 싱글톤 인스턴스
  static final PageCacheService _instance = PageCacheService._internal();
  factory PageCacheService() => _instance;
  PageCacheService._internal() {
    // 앱 시작 시 로컬 캐시 정리
    _cleanupExpiredLocalCache();
  }

  // 페이지 캐시 (페이지 ID -> 페이지 객체)
  final Map<String, page_model.Page> _pageCache = {};

  // 노트별 페이지 ID 목록 (노트 ID -> 페이지 ID 목록)
  final Map<String, List<String>> _notePageIds = {};

  // 캐시 타임스탬프 (페이지 ID -> 마지막 액세스 시간)
  final Map<String, DateTime> _cacheTimestamps = {};

  // 캐시 유효 시간 (기본값: 24시간)
  final Duration _cacheValidity = const Duration(hours: 24);

  // 최대 캐시 항목 수
  final int _maxCacheItems = 200;

  // SharedPreferences 키 접두사
  static const String _prefKeyPrefix = 'page_cache_';
  static const String _prefNotePageIdsPrefix = 'note_page_ids_';

  /// 페이지를 캐시에 저장
  Future<void> cachePage(String pageId, page_model.Page page) async {
    // 메모리 캐시에 저장
    _pageCache[pageId] = page;
    _cacheTimestamps[pageId] = DateTime.now();
    _cleanCacheIfNeeded();

    // 로컬 저장소에 저장
    try {
      final prefs = await SharedPreferences.getInstance();
      final pageJson = jsonEncode(page.toJson());
      await prefs.setString('$_prefKeyPrefix$pageId', pageJson);
      await prefs.setString('${_prefKeyPrefix}timestamp_$pageId',
          DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('페이지 로컬 캐싱 중 오류 발생: $e');
    }
  }

  /// 노트의 모든 페이지를 캐시에 저장
  Future<void> cachePages(String noteId, List<page_model.Page> pages) async {
    final pageIds = <String>[];

    for (final page in pages) {
      if (page.id != null) {
        await cachePage(page.id!, page);
        pageIds.add(page.id!);
      }
    }

    // 기존 페이지 ID 목록과 병합 (중복 제거)
    final existingIds = _notePageIds[noteId] ?? [];
    final mergedIds = {...existingIds, ...pageIds}.toList();

    _notePageIds[noteId] = mergedIds;

    // 로컬 저장소에 노트-페이지 관계 저장
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('$_prefNotePageIdsPrefix$noteId', mergedIds);
    } catch (e) {
      debugPrint('노트-페이지 관계 로컬 캐싱 중 오류 발생: $e');
    }

    debugPrint(
        '노트 $noteId의 페이지 ${mergedIds.length}개가 캐시에 저장됨 (${pages.length}개 추가)');
  }

  /// 캐시에서 페이지 가져오기
  Future<page_model.Page?> getPage(String pageId) async {
    // 1. 메모리 캐시 확인
    var page = _pageCache[pageId];
    if (page != null) {
      // 페이지가 있으면 타임스탬프 업데이트
      _cacheTimestamps[pageId] = DateTime.now();
      return page;
    }

    // 2. 로컬 저장소 확인
    try {
      final prefs = await SharedPreferences.getInstance();
      final pageJson = prefs.getString('$_prefKeyPrefix$pageId');
      final timestampStr =
          prefs.getString('${_prefKeyPrefix}timestamp_$pageId');

      if (pageJson != null && timestampStr != null) {
        final timestamp = DateTime.parse(timestampStr);
        if (DateTime.now().difference(timestamp) < _cacheValidity) {
          debugPrint('로컬 저장소에서 페이지 로드: $pageId');
          final pageMap = jsonDecode(pageJson) as Map<String, dynamic>;
          page = page_model.Page.fromJson(pageMap);

          // 메모리 캐시 업데이트
          _pageCache[pageId] = page;
          _cacheTimestamps[pageId] = DateTime.now();

          return page;
        }
      }
    } catch (e) {
      debugPrint('로컬 저장소에서 페이지 로드 중 오류 발생: $e');
    }

    return null;
  }

  /// 노트의 모든 페이지를 캐시에서 가져오기
  Future<List<page_model.Page>> getPagesForNote(String noteId) async {
    // 메모리에 노트-페이지 관계가 없으면 로컬 저장소에서 로드
    if (!_notePageIds.containsKey(noteId)) {
      await _loadNotePageIdsFromLocal(noteId);
    }

    final pageIds = _notePageIds[noteId] ?? [];
    final pages = <page_model.Page>[];

    for (final pageId in pageIds) {
      final page = await getPage(pageId);
      if (page != null) {
        pages.add(page);
      }
    }

    // 페이지 번호 순으로 정렬
    pages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));

    debugPrint(
        '캐시에서 노트 $noteId의 페이지 ID ${pageIds.length}개 중 ${pages.length}개 로드됨');
    return pages;
  }

  /// 로컬 저장소에서 노트-페이지 관계 로드
  Future<void> _loadNotePageIdsFromLocal(String noteId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pageIds = prefs.getStringList('$_prefNotePageIdsPrefix$noteId');

      if (pageIds != null) {
        _notePageIds[noteId] = pageIds;
        debugPrint('로컬 저장소에서 노트 $noteId의 페이지 ID ${pageIds.length}개 로드됨');
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
      final pageJson = prefs.getString('$_prefKeyPrefix$pageId');
      final timestampStr =
          prefs.getString('${_prefKeyPrefix}timestamp_$pageId');

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
    // 메모리에 노트-페이지 관계가 없으면 로컬 저장소에서 로드
    if (!_notePageIds.containsKey(noteId)) {
      await _loadNotePageIdsFromLocal(noteId);
    }

    final pageIds = _notePageIds[noteId] ?? [];
    if (pageIds.isEmpty) {
      debugPrint('노트 $noteId의 캐시된 페이지 ID가 없음');
      return false;
    }

    // 모든 페이지가 캐시에 있는지 확인
    for (final pageId in pageIds) {
      final exists = await hasPage(pageId);
      if (!exists) {
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
      await prefs.remove('$_prefKeyPrefix$pageId');
      await prefs.remove('${_prefKeyPrefix}timestamp_$pageId');
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
      await prefs.remove('$_prefNotePageIdsPrefix$noteId');
    } catch (e) {
      debugPrint('로컬 저장소에서 노트-페이지 관계 제거 중 오류 발생: $e');
    }
  }

  /// 메모리 캐시 정리 (오래된 항목 제거)
  void clearOldMemoryCache() {
    final now = DateTime.now();
    final expiredKeys = _cacheTimestamps.entries
        .where((entry) => now.difference(entry.value) > _cacheValidity)
        .map((entry) => entry.key)
        .toList();

    for (final key in expiredKeys) {
      _pageCache.remove(key);
      _cacheTimestamps.remove(key);
    }
  }

  /// 로컬 저장소 캐시 정리 (오래된 항목 제거)
  Future<void> _cleanupExpiredLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      final now = DateTime.now();

      for (final key in allKeys) {
        if (key.startsWith('${_prefKeyPrefix}timestamp_')) {
          final timestampStr = prefs.getString(key);
          if (timestampStr != null) {
            final timestamp = DateTime.parse(timestampStr);
            if (now.difference(timestamp) > _cacheValidity) {
              final pageId =
                  key.substring('${_prefKeyPrefix}timestamp_'.length);
              await prefs.remove('$_prefKeyPrefix$pageId');
              await prefs.remove(key);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('만료된 로컬 캐시 정리 중 오류 발생: $e');
    }
  }

  /// 캐시 크기 제한을 위한 정리
  void _cleanCacheIfNeeded() {
    if (_pageCache.length <= _maxCacheItems) return;

    // 가장 오래된 항목부터 삭제
    final sortedEntries = _cacheTimestamps.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    // 캐시 크기를 80%로 줄임
    final itemsToRemove = (_pageCache.length - (_maxCacheItems * 0.8)).ceil();

    for (var i = 0; i < itemsToRemove && i < sortedEntries.length; i++) {
      final pageId = sortedEntries[i].key;
      _pageCache.remove(pageId);
      _cacheTimestamps.remove(pageId);
    }
  }

  /// 전체 캐시 초기화
  Future<void> clearCache() async {
    // 메모리 캐시 초기화
    _pageCache.clear();
    _cacheTimestamps.clear();
    _notePageIds.clear();

    // 로컬 저장소 캐시 초기화
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      for (final key in allKeys) {
        if (key.startsWith(_prefKeyPrefix) ||
            key.startsWith(_prefNotePageIdsPrefix)) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      debugPrint('로컬 저장소 캐시 초기화 중 오류 발생: $e');
    }
  }

  /// 캐시 통계 정보 (디버깅용)
  Map<String, dynamic> getCacheStats() {
    return {
      'memoryItems': _pageCache.length,
      'notesWithCachedPages': _notePageIds.length,
      'oldestCacheTime': _cacheTimestamps.isEmpty
          ? null
          : _cacheTimestamps.values.reduce((a, b) => a.isBefore(b) ? a : b),
      'newestCacheTime': _cacheTimestamps.isEmpty
          ? null
          : _cacheTimestamps.values.reduce((a, b) => a.isAfter(b) ? a : b),
    };
  }
}
