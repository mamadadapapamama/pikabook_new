import 'package:flutter/foundation.dart';
import '../models/page.dart' as page_model;

/// 페이지 콘텐츠를 메모리에 캐싱하는 서비스
///
/// 앱이 실행 중일 때만 캐시를 유지하며, 앱이 종료되면 캐시가 사라집니다.
/// 메모리 사용량을 최소화하기 위해 캐시 크기를 제한하고 오래된 항목을 자동으로 제거합니다.
class PageCacheService {
  // 싱글톤 인스턴스
  static final PageCacheService _instance = PageCacheService._internal();
  factory PageCacheService() => _instance;
  PageCacheService._internal();

  // 페이지 캐시 (페이지 ID -> 페이지 객체)
  final Map<String, page_model.Page> _pageCache = {};

  // 노트별 페이지 ID 목록 (노트 ID -> 페이지 ID 목록)
  final Map<String, List<String>> _notePageIds = {};

  // 캐시 타임스탬프 (페이지 ID -> 마지막 액세스 시간)
  final Map<String, DateTime> _cacheTimestamps = {};

  // 캐시 유효 시간 (기본값: 30분)
  final Duration _cacheValidity = const Duration(minutes: 30);

  // 최대 캐시 항목 수
  final int _maxCacheItems = 200;

  /// 페이지를 캐시에 저장
  void cachePage(String pageId, page_model.Page page) {
    _pageCache[pageId] = page;
    _cacheTimestamps[pageId] = DateTime.now();
    _cleanCacheIfNeeded();
  }

  /// 노트의 모든 페이지를 캐시에 저장
  void cachePages(String noteId, List<page_model.Page> pages) {
    final pageIds = <String>[];

    for (final page in pages) {
      if (page.id != null) {
        cachePage(page.id!, page);
        pageIds.add(page.id!);
      }
    }

    // 기존 페이지 ID 목록과 병합 (중복 제거)
    final existingIds = _notePageIds[noteId] ?? [];
    final mergedIds = {...existingIds, ...pageIds}.toList();

    _notePageIds[noteId] = mergedIds;

    debugPrint(
        '노트 $noteId의 페이지 ${mergedIds.length}개가 캐시에 저장됨 (${pages.length}개 추가)');
  }

  /// 캐시에서 페이지 가져오기
  page_model.Page? getPage(String pageId) {
    final page = _pageCache[pageId];
    if (page == null) return null;

    // 페이지가 있으면 타임스탬프 업데이트
    _cacheTimestamps[pageId] = DateTime.now();
    return page;
  }

  /// 노트의 모든 페이지를 캐시에서 가져오기
  List<page_model.Page> getPagesForNote(String noteId) {
    final pageIds = _notePageIds[noteId] ?? [];
    final pages = <page_model.Page>[];

    for (final pageId in pageIds) {
      final page = getPage(pageId);
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

  /// 캐시에 페이지가 있는지 확인
  bool hasPage(String pageId) {
    return _pageCache.containsKey(pageId);
  }

  /// 캐시에 노트의 모든 페이지가 있는지 확인
  bool hasAllPagesForNote(String noteId) {
    final pageIds = _notePageIds[noteId] ?? [];
    if (pageIds.isEmpty) {
      debugPrint('노트 $noteId의 캐시된 페이지 ID가 없음');
      return false;
    }

    final allPagesExist = pageIds.every((pageId) => hasPage(pageId));
    debugPrint(
        '노트 $noteId의 모든 페이지(${pageIds.length}개) 캐시 존재 여부: $allPagesExist');
    return allPagesExist;
  }

  /// 캐시에서 페이지 제거
  void removePage(String pageId) {
    _pageCache.remove(pageId);
    _cacheTimestamps.remove(pageId);
  }

  /// 노트의 모든 페이지를 캐시에서 제거
  void removePagesForNote(String noteId) {
    final pageIds = _notePageIds[noteId] ?? [];
    for (final pageId in pageIds) {
      removePage(pageId);
    }
    _notePageIds.remove(noteId);
  }

  /// 캐시 정리 (오래된 항목 제거)
  void clearOldCache() {
    final now = DateTime.now();
    final expiredKeys = _cacheTimestamps.entries
        .where((entry) => now.difference(entry.value) > _cacheValidity)
        .map((entry) => entry.key)
        .toList();

    for (final key in expiredKeys) {
      _pageCache.remove(key);
      _cacheTimestamps.remove(key);

      // 노트 페이지 ID 목록에서도 제거
      for (final noteId in _notePageIds.keys) {
        _notePageIds[noteId]?.remove(key);
      }
    }

    // 빈 노트 항목 제거
    _notePageIds.removeWhere((_, pageIds) => pageIds.isEmpty);
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

      // 노트 페이지 ID 목록에서도 제거
      for (final noteId in _notePageIds.keys) {
        _notePageIds[noteId]?.remove(pageId);
      }
    }

    // 빈 노트 항목 제거
    _notePageIds.removeWhere((_, pageIds) => pageIds.isEmpty);
  }

  /// 전체 캐시 초기화
  void clearCache() {
    _pageCache.clear();
    _cacheTimestamps.clear();
    _notePageIds.clear();
  }

  /// 캐시 통계 정보 (디버깅용)
  Map<String, dynamic> getCacheStats() {
    return {
      'totalItems': _pageCache.length,
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
