import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/note.dart';
import '../../models/page.dart' as page_model;
import '../../models/processed_text.dart';
import '../../models/flash_card.dart'; // FlashCard 모델 임포트 추가
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../features/note_detail/managers/page_content_manager.dart'; // SegmentManager 임포트

// 캐시 작업 유형 (통계용)
enum CacheOperationType {
  read,
  write,
  delete,
}

/// 노트, 페이지의 통합 캐싱 서비스입니다.
/// 메모리 캐싱과 로컬 저장소 캐싱을 모두 지원합니다.
/// 메모리 캐시는 앱이 실행 중일 때만 유지되며, 로컬 저장소 캐시는 앱을 재시작해도 유지됩니다.

class UnifiedCacheService {
  // 싱글톤 인스턴스
  static final UnifiedCacheService _instance = UnifiedCacheService._internal();
  factory UnifiedCacheService() => _instance;

  // 초기화 완료 여부
  bool _isInitialized = false;
  
  // 현재 사용자 ID (캐시 분리를 위해 사용)
  String? _currentUserId;
  
  // 메모리 캐시 맵 (범용)
  final Map<String, dynamic> _memoryCache = {};
  
  // 캐시 사용 통계
  final Map<String, int> _cacheHitCount = {};
  final Map<String, int> _cacheMissCount = {};

  // SharedPreferences 인스턴스
  SharedPreferences? _prefs;

  final Set<String> _initializationLocks = {};
  
  // 생성자 로그 추가
  UnifiedCacheService._internal() {
    debugPrint('💾 UnifiedCacheService: 내부 생성자(_internal) 호출됨');
    _initCurrentUserId(); // 기존 초기화 메서드 호출 유지
  }
  
  // 현재 사용자 ID 초기화
  Future<void> _initCurrentUserId() async {
    debugPrint('    [CacheService] _initCurrentUserId 시작');
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.uid.isNotEmpty) {
        debugPrint('    [CacheService] Firebase에서 사용자 ID 가져옴: ${user.uid}');
        await setCurrentUserId(user.uid);
      } else {
        debugPrint('    [CacheService] Firebase에 현재 사용자 없음');
      }
    } catch (e) {
      debugPrint('    [CacheService] 초기 사용자 ID 로드 중 오류 발생: $e');
    }
    debugPrint('    [CacheService] _initCurrentUserId 완료');
  }
  
  // 사용자 ID 설정 - 사용자 로그인 시 호출됨
  Future<void> setCurrentUserId(String userId) async {
    await _ensureInitialized();
    final oldUserId = _currentUserId;
    _currentUserId = userId;
    
    // 사용자가 변경된 경우 메모리 캐시 초기화
    if (oldUserId != null && oldUserId != userId) {
      debugPrint('사용자 변경 감지: $oldUserId -> $userId. 메모리 캐시 초기화');
      _clearMemoryCache();
    }
    
    // 현재 사용자 ID를 로컬에 저장
    await _prefs!.setString('cache_current_user_id', userId);
    _memoryCache['cache_current_user_id'] = userId;
    debugPrint('캐시 서비스에 사용자 ID 설정됨: $userId');
  }
  
  // 사용자 ID 제거 - 로그아웃 또는 계정 삭제 시 호출됨
  Future<void> clearCurrentUserId() async {
    _currentUserId = null;
    
    // 메모리 캐시 초기화
    _clearMemoryCache();
    
    // 저장된 사용자 ID 제거
    await _prefs!.remove('cache_current_user_id');
    _memoryCache.remove('cache_current_user_id');
    debugPrint('캐시 서비스에서 사용자 ID 제거됨');
  }
  
  // 사용자 ID 가져오기 (로컬 저장소에서)
  Future<String?> _getStoredUserId() async {
    await _ensureInitialized();
    return _prefs!.getString('cache_current_user_id');
  }

  // 명시적 초기화 메서드 추가
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 사용자 ID 초기화
      _currentUserId = await _getStoredUserId();
      if (_currentUserId != null) {
        debugPrint('캐시 서비스 초기화: 저장된 사용자 ID 로드됨 - $_currentUserId');
      } else {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          _currentUserId = user.uid;
          debugPrint('캐시 서비스 초기화: 현재 로그인된 사용자 ID 사용 - $_currentUserId');
        } else {
          debugPrint('캐시 서비스 초기화: 로그인된 사용자 없음');
        }
      }
      
      _isInitialized = true;
      debugPrint('UnifiedCacheService 초기화 완료');

      // 캐시 정리는 별도 Future로 실행
      Future.delayed(Duration(seconds: 5), () {
        _cleanupExpiredLocalCache();
      });
    } catch (e) {
      debugPrint('캐시 서비스 초기화 중 오류 발생: $e');
    }
  }

  /// 로컬 저장소 캐시 정리 (오래된 항목 제거)
  Future<int> _cleanupExpiredLocalCache([int? maxAgeHours]) async {
    if (!_isInitialized) return 0;

    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      
      // 타임스탬프 포함된 키 찾기
      final timestampKeys = allKeys.where((key) => key.contains('_timestamp')).toList();
      
      // 한 번에 50개 키만 처리 (메모리 최적화)
      final keysToProcess = timestampKeys.take(50).toList();
      
      int removedCount = 0;
      
      // 현재 시간
      final now = DateTime.now();
      
      // 타임스탬프 확인
      for (final key in keysToProcess) {
        try {
          final timestampStr = prefs.getString(key);
          if (timestampStr == null) continue;
          
          final timestamp = DateTime.parse(timestampStr);
          
          // 기본 캐시 유효 기간보다 오래된 항목 또는 maxAgeHours가 지정된 경우 그 시간을 초과한 항목
          if (maxAgeHours != null && now.difference(timestamp).inHours > maxAgeHours) {
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
          _cleanupExpiredLocalCache(maxAgeHours);
        });
      }
      
      return removedCount;
    } catch (e) {
      debugPrint('만료된 로컬 캐시 정리 중 오류 발생: $e');
      return 0;
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
  
  // 사용자별 캐시 키 생성 (로컬 저장소용)
  String _getUserSpecificKey(String baseKey) {
    if (_currentUserId == null || _currentUserId!.isEmpty) {
      // 사용자 ID가 없을 경우 기본 키 사용 (이전 버전과의 호환성)
      return baseKey;
    }
    return '${_currentUserId}_$baseKey';
  }

  /// 노트 캐싱 - 메모리에만 저장
  Future<void> cacheNote(Note note) async {
    if (note.id == null) return;
    if (!_isInitialized) await initialize();

    final noteId = note.id!;
    _noteCache[noteId] = note;
    _cacheTimestamps[noteId] = DateTime.now();
  }

  /// 노트 가져오기 - 메모리에서만 조회
  Future<Note?> getCachedNote(String noteId) async {
    if (!_isInitialized) await initialize();
    
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
    if (!_isInitialized) await initialize();

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

      // 페이지 ID 목록 저장 (사용자별)
      final pageIdsKey = _getUserSpecificKey('note_pages_$noteId');
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

        // 사용자 ID 포함하여 배치 처리
        futures.add(compute(
          _serializePagesBatch, 
          {'pages': batch, 'userId': _currentUserId ?? ''}
        ));
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
  static Map<String, String> _serializePagesBatch(Map<String, dynamic> params) {
    final List<page_model.Page> pages = params['pages'];
    final String userId = params['userId'] ?? '';
    
    final result = <String, String>{};
    final now = DateTime.now().toIso8601String();
    
    final userPrefix = userId.isNotEmpty ? '${userId}_' : '';

    for (final page in pages) {
      if (page.id != null) {
        final pageKey = '${userPrefix}page_${page.id}';
        final timestampKey = '${pageKey}_timestamp';

        // 페이지 데이터 JSON 직렬화
        result[pageKey] = jsonEncode(page.toJson());
        result[timestampKey] = now;
      }
    }

    return result;
  }

  /// 페이지 캐시 크기 확인 및 제한
  void _checkPageCacheSize([int? maxPageItems]) {
    final maxItems = maxPageItems ?? _maxPageItems;
    
    if (_pageCache.length <= maxItems) return;
    
    // 타임스탬프 기준으로 정렬
    final sortedKeys = _pageCache.keys.toList()
      ..sort((a, b) {
        final timeA = _cacheTimestamps[a] ?? DateTime.now();
        final timeB = _cacheTimestamps[b] ?? DateTime.now();
        return timeA.compareTo(timeB); // 오름차순 (오래된 것부터)
      });
    
    // 제거할 항목 수 계산
    final removeCount = _pageCache.length - maxItems;
    
    // 오래된 항목부터 제거
    for (int i = 0; i < removeCount && i < sortedKeys.length; i++) {
      final key = sortedKeys[i];
      _pageCache.remove(key);
      _cacheTimestamps.remove(key);
    }
    
    debugPrint('오래된 페이지 캐시 $removeCount개 정리 완료');
  }

  /// 페이지 가져오기 - 메모리에서만 조회
  Future<page_model.Page?> getCachedPage(String pageId) async {
    if (!_isInitialized) await initialize();
    
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
    if (!_isInitialized) await initialize();
    
    if (_notePageIds.containsKey(noteId)) {
      return List<String>.from(_notePageIds[noteId] ?? []);
    }
    return [];
  }

  /// 노트의 모든 페이지 가져오기 - 메모리에서만 조회
  Future<List<page_model.Page>> getPagesForNote(String noteId) async {
    if (!_isInitialized) await initialize();
    
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
    if (!_isInitialized) await initialize();
    
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
    if (!_isInitialized) await initialize();
    
    return _notePageIds.containsKey(noteId) && _notePageIds[noteId]!.isNotEmpty;
  }

  /// 캐시에서 노트 삭제
  Future<void> removeCachedNote(String noteId) async {
    if (!_isInitialized) await initialize();
    
    _noteCache.remove(noteId);
    _cacheTimestamps.remove(noteId);
    _notePageIds.remove(noteId);
    
    // 로컬 저장소에서도 삭제
    try {
      final prefs = await SharedPreferences.getInstance();
      final userKey = _getUserSpecificKey('note_cache_$noteId');
      await prefs.remove(userKey);
      await prefs.remove('${userKey}_timestamp');
    } catch (e) {
      debugPrint('로컬 노트 캐시 삭제 중 오류: $e');
    }
  }

  /// 캐시에서 페이지 삭제
  Future<void> removePage(String pageId) async {
    if (!_isInitialized) await initialize();
    
    _pageCache.remove(pageId);
    _cacheTimestamps.remove(pageId);

    // 노트-페이지 관계에서도 제거
    for (final noteId in _notePageIds.keys) {
      _notePageIds[noteId]?.remove(pageId);
    }
    
    // 로컬 저장소에서도 삭제
    try {
      final prefs = await SharedPreferences.getInstance();
      final userKey = _getUserSpecificKey('page_cache_$pageId');
      await prefs.remove(userKey);
      await prefs.remove('${userKey}_timestamp');
    } catch (e) {
      debugPrint('로컬 페이지 캐시 삭제 중 오류: $e');
    }
  }

  /// 노트의 모든 페이지를 캐시에서 삭제
  Future<void> removePagesForNote(String noteId) async {
    if (!_isInitialized) await initialize();
    
    final pageIds = List<String>.from(_notePageIds[noteId] ?? []);
    for (final pageId in pageIds) {
      _pageCache.remove(pageId);
      _cacheTimestamps.remove(pageId);
      
      // 로컬 저장소에서도 삭제
      try {
        final prefs = await SharedPreferences.getInstance();
        final userKey = _getUserSpecificKey('page_cache_$pageId');
        await prefs.remove(userKey);
        await prefs.remove('${userKey}_timestamp');
      } catch (e) {
        debugPrint('로컬 페이지 캐시 삭제 중 오류: $e');
      }
    }
    _notePageIds.remove(noteId);
    
    // 노트 페이지 ID 목록도 삭제
    try {
      final prefs = await SharedPreferences.getInstance();
      final userKey = _getUserSpecificKey('note_pages_$noteId');
      await prefs.remove(userKey);
      await prefs.remove('${userKey}_timestamp');
    } catch (e) {
      debugPrint('노트 페이지 ID 목록 삭제 중 오류: $e');
    }
  }

  /// 메모리 캐시 초기화
  void _clearMemoryCache() {
    _memoryCache.clear();
    _noteCache.clear();
    _pageCache.clear();
    _translationCache.clear();
    _notePageIds.clear();
    _cacheTimestamps.clear();
    _cacheHitCount.clear();
    _cacheMissCount.clear();
    debugPrint('메모리 캐시가 초기화되었습니다');
  }
  
  /// 메모리 캐시 초기화 (공개 메서드)
  void clearCache() {
    _clearMemoryCache();
    debugPrint('모든 메모리 캐시가 초기화되었습니다.');
  }

  /// 번역 결과를 캐시에서 조회
  Future<String?> getTranslationCache(String key) async {
    try {
      // 1. 메모리 캐시 확인
      if (_translationCache.containsKey(key)) {
        return _translationCache[key];
      }
      
      // 2. 로컬 스토리지 확인
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'translation_cache_$key';
      final cachedValue = prefs.getString(cacheKey);
      
      if (cachedValue != null) {
        // 메모리 캐시에도 저장
        _translationCache[key] = cachedValue;
        return cachedValue;
      }
      
      return null;
    } catch (e) {
      debugPrint('번역 캐시 조회 중 오류: $e');
      return null;
    }
  }

  /// 번역 결과를 캐시에 저장
  Future<void> setTranslationCache(String key, String translation) async {
    try {
      // 1. 메모리 캐시에 저장
      _translationCache[key] = translation;
      
      // 2. 로컬 스토리지에 저장
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'translation_cache_$key';
      await prefs.setString(cacheKey, translation);
    } catch (e) {
      debugPrint('번역 캐시 저장 중 오류: $e');
    }
  }

  /// 특정 언어 조합의 모든 번역 캐시를 초기화
  Future<void> clearTranslationCache(String sourceLanguage, String targetLanguage) async {
    try {
      final keyPrefix = '$sourceLanguage:$targetLanguage:';
      
      // 1. 메모리 캐시 초기화
      _translationCache.removeWhere((key, _) => key.startsWith(keyPrefix));
      
      // 2. 로컬 스토리지 초기화 (필요한 경우)
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      
      for (final key in allKeys) {
        if (key.startsWith('translation_cache_$keyPrefix')) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      debugPrint('번역 캐시 초기화 중 오류: $e');
    }
  }

  /// 번역 가져오기
  Future<String?> getTranslation(
      String originalText, String targetLanguage) async {
    if (originalText.isEmpty) return null;
    if (!_isInitialized) await initialize();

    // 긴 텍스트의 경우 해시 사용
    final textHash = _generateTextHash(originalText);
    final baseKey = '${textHash}_${targetLanguage.toLowerCase()}';
    final key = _translationKeyPrefix + baseKey;

    // 메모리 캐시 확인
    if (_translationCache.containsKey(key)) {
      return _translationCache[key];
    }

    // 로컬 캐시 확인 (사용자별)
    try {
      final prefs = await SharedPreferences.getInstance();
      final userKey = _getUserSpecificKey(key);
      final cachedData = prefs.getString(userKey);
      final timestampKey = _getUserSpecificKey('${_translationKeyPrefix}timestamp_$baseKey');
      final timestampStr = prefs.getString(timestampKey);

      if (cachedData != null && timestampStr != null) {
        try {
          final timestamp = DateTime.parse(timestampStr);
          if (DateTime.now().difference(timestamp) < _cacheValidity) {
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
    if (!_isInitialized) await initialize();

    // 긴 텍스트의 경우 해시 사용
    final textHash = _generateTextHash(originalText);
    final baseKey = '${textHash}_${targetLanguage.toLowerCase()}';
    final key = _translationKeyPrefix + baseKey;

    // 메모리 캐시에 저장
    _translationCache[key] = translatedText;
    _cacheTimestamps[key] = DateTime.now();

    // 로컬 캐시에 저장 (사용자별)
    try {
      final prefs = await SharedPreferences.getInstance();
      final userKey = _getUserSpecificKey(key);
      final timestampKey = _getUserSpecificKey('${_translationKeyPrefix}timestamp_$baseKey');
      
      await prefs.setString(userKey, translatedText);
      await prefs.setString(
          timestampKey,
          DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('번역 로컬 캐싱 중 오류: $e');
    }

    // 캐시 크기 제한
    _limitCacheSize();
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

  /// 번역 캐시 크기 제한
  void _limitCacheSize() {
    // 번역 캐시 크기 제한
    if (_translationCache.length > _maxTranslationItems) {
      // 가장 오래된 항목부터 제거
      final sortedEntries = _cacheTimestamps.entries
          .where((entry) => _translationCache.containsKey(entry.key))
          .toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      
      final itemsToRemove = _translationCache.length - (_maxTranslationItems * 0.8).toInt();
      if (itemsToRemove > 0) {
        for (int i = 0; i < itemsToRemove && i < sortedEntries.length; i++) {
          final key = sortedEntries[i].key;
          _translationCache.remove(key);
          _cacheTimestamps.remove(key);
        }
        
        debugPrint('번역 캐시 크기 제한: $itemsToRemove개 항목 제거');
      }
    }
  }

  /// 모든 캐시 지우기 (로그아웃 또는 로그인 시 호출)
  Future<void> clearAllCache() async {
    try {
      await _ensureInitialized();
      
      // 메모리 캐시 초기화
      _clearMemoryCache();
      
      // SharedPreferences 초기화
      final keys = [
        'cache_current_user_id',
        sourceLanguageKey,
        targetLanguageKey,
      ];
      
      for (final key in keys) {
        await _prefs!.remove(key);
      }
      
      debugPrint('모든 캐시가 초기화되었습니다.');
    } catch (e) {
      debugPrint('캐시 초기화 중 오류 발생: $e');
      rethrow;
    }
  }
  
  /// 사용자 전환 시 호출 - 이전 사용자의 메모리 캐시 정리
  Future<void> handleUserSwitch(String newUserId) async {
    if (_currentUserId == newUserId) return;
    
    // 메모리 캐시 초기화
    clearCache();
    
    // 새 사용자 ID 설정
    await setCurrentUserId(newUserId);
    
    debugPrint('사용자 전환 처리 완료: $newUserId');
  }

  /// 현재 사용자 ID 가져오기 (없으면 빈 문자열 반환)
  Future<String> _getCurrentUserId() async {
    if (_currentUserId != null && _currentUserId!.isNotEmpty) {
      return _currentUserId!;
    }
    
    // 로컬 저장소에서 사용자 ID 조회
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedUserId = prefs.getString('cache_current_user_id');
      if (cachedUserId != null && cachedUserId.isNotEmpty) {
        _currentUserId = cachedUserId;
        return cachedUserId;
      }
    } catch (e) {
      debugPrint('로컬에서 사용자 ID 로드 중 오류: $e');
    }
    
    // Firebase에서 사용자 ID 조회
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && user.uid.isNotEmpty) {
        _currentUserId = user.uid;
        return user.uid;
      }
    } catch (e) {
      debugPrint('Firebase에서 사용자 ID 로드 중 오류: $e');
    }
    
    // 기본값 반환
    return '';
  }

  /// 텍스트 캐싱 (원본 또는 번역 텍스트)
  Future<void> cacheText(String textType, String pageId, String text) async {
    if (!_isInitialized) await initialize();
    
    final userId = await _getCurrentUserId();
    final key = '${userId}_${textType}_$pageId';
    
    // 메모리 캐시에 저장
    _memoryCache[key] = text;
    
    // 로컬 저장소에도 저장
    final prefs = await SharedPreferences.getInstance();
    if (text.length < 1000) { // 텍스트 길이가 너무 길면 로컬 저장소에 저장하지 않음
      await prefs.setString(key, text);
    }
    
    // 캐시 사용 통계 업데이트
    _updateCacheStats(key, CacheOperationType.write);
  }
  
  /// 처리된 텍스트 캐싱 (가공된 데이터)
  Future<void> cacheProcessedText(
    String pageId,
    String processingMode,
    dynamic processedData,
  ) async {
    if (!_isInitialized) await initialize();
    
    final userId = await _getCurrentUserId();
    final key = '${userId}_processed_${processingMode}_$pageId';
    
    // 캐시에 저장 (JSON 변환)
    final jsonData = jsonEncode(processedData);
    _memoryCache[key] = jsonData;
    
    // 캐시 사용 통계 업데이트
    _updateCacheStats(key, CacheOperationType.write);
  }
  
  /// 캐시된 처리 텍스트 조회
  Future<dynamic> getCachedProcessedText(
    String pageId,
    String processingMode,
  ) async {
    if (!_isInitialized) await initialize();
    
    final userId = await _getCurrentUserId();
    final key = '${userId}_processed_${processingMode}_$pageId';
    
    // 캐시에서 조회
    final cachedData = _memoryCache[key];
    if (cachedData == null) {
      return null;
    }
    
    // 캐시 사용 통계 업데이트
    _updateCacheStats(key, CacheOperationType.read);
    
    // JSON 파싱하여 반환 (맵 형태로 반환)
    try {
      if (cachedData is String) {
        final decoded = jsonDecode(cachedData);
        debugPrint('처리된 텍스트를 맵으로 디코딩: ${decoded.runtimeType}');
        return decoded; // Map<String, dynamic> 형태로 반환
      }
      return cachedData;
    } catch (e) {
      debugPrint('처리된 텍스트 디코딩 오류: $e');
      return cachedData;
    }
  }

  /// 캐시 사용 통계 업데이트
  void _updateCacheStats(String key, CacheOperationType operation) {
    if (operation == CacheOperationType.read) {
      if (_cacheHitCount.containsKey(key)) {
        _cacheHitCount[key] = _cacheHitCount[key]! + 1;
      } else {
        _cacheHitCount[key] = 1;
      }
    } else if (operation == CacheOperationType.write) {
      if (_cacheMissCount.containsKey(key)) {
        _cacheMissCount[key] = _cacheMissCount[key]! + 1;
      } else {
        _cacheMissCount[key] = 1;
      }
    } else if (operation == CacheOperationType.delete) {
      _cacheHitCount.remove(key);
      _cacheMissCount.remove(key);
    }
  }

  /// 캐시된 노트 목록 가져오기
  Future<List<Note>> getCachedNotes() async {
    if (!_isInitialized) await initialize();
    
    final notes = _noteCache.values.toList();
    
    // 타임스탬프 기준 정렬 (최신순)
    notes.sort((a, b) {
      final timeA = _cacheTimestamps[a.id] ?? DateTime.now();
      final timeB = _cacheTimestamps[b.id] ?? DateTime.now();
      return timeB.compareTo(timeA); // 내림차순 (최신순)
    });
    
    return notes;
  }
  
  /// 노트 목록 캐싱
  Future<void> cacheNotes(List<Note> notes) async {
    if (!_isInitialized) await initialize();
    if (notes.isEmpty) return;
    
    final now = DateTime.now();
    
    // 메모리 캐시에 저장
    for (final note in notes) {
      if (note.id != null) {
        _noteCache[note.id!] = note;
        _cacheTimestamps[note.id!] = now;
      }
    }
    
    // 캐시 크기 제한 확인
    if (_noteCache.length > _maxNoteItems) {
      _clearOldestNotes();
    }
  }
  
  /// 가장 오래된 노트 캐시 정리
  void _clearOldestNotes([int? keepCount]) {
    final maxItems = keepCount ?? _maxNoteItems;
    
    if (_noteCache.length <= maxItems) return;
    
    // 타임스탬프 기준으로 정렬
    final sortedKeys = _noteCache.keys.toList()
      ..sort((a, b) {
        final timeA = _cacheTimestamps[a] ?? DateTime.now();
        final timeB = _cacheTimestamps[b] ?? DateTime.now();
        return timeA.compareTo(timeB); // 오름차순 (오래된 것부터)
      });
    
    // 제거할 항목 수 계산
    final removeCount = _noteCache.length - maxItems;
    
    // 오래된 항목부터 제거
    for (int i = 0; i < removeCount && i < sortedKeys.length; i++) {
      final key = sortedKeys[i];
      _noteCache.remove(key);
      _cacheTimestamps.remove(key);
    }
    
    debugPrint('오래된 노트 캐시 $removeCount개 정리 완료');
  }
  
  /// 오래된 캐시 정리
  Future<void> cleanupOldCache() async {
    // 메모리 캐시 정리
    _clearOldestNotes();
    _checkPageCacheSize();
    
    // 로컬 저장소 캐시 정리
    await _cleanupExpiredLocalCache();
  }

  /// 앱 스토어 심사를 위한 메모리 최적화
  Future<void> optimizeForAppReview() async {
    debugPrint('앱 스토어 심사를 위한 캐시 서비스 최적화 시작');
    
    // 1. 메모리 캐시 최적화
    final noteCount = _noteCache.length;
    if (noteCount > 10) {
      // 최신 10개 노트만 유지
      _clearOldestNotes(10);
      debugPrint('메모리 최적화: 노트 캐시 축소 ($noteCount → ${_noteCache.length})');
    }
    
    // 2. 페이지 캐시 최적화
    final pageCount = _pageCache.length;
    if (pageCount > 50) {
      // 50개 페이지만 유지
      _checkPageCacheSize(50);
      debugPrint('메모리 최적화: 페이지 캐시 축소 ($pageCount → ${_pageCache.length})');
    }
    
    // 3. 임시 캐시 데이터 제거
    _memoryCache.clear();
    debugPrint('메모리 최적화: 임시 캐시 데이터 모두 제거');
    
    // 4. 사용하지 않는 디스크 캐시 파일 정리
    final expiredCount = await _cleanupExpiredLocalCache(24);
    debugPrint('디스크 최적화: $expiredCount개 만료된 캐시 파일 제거');
    
    debugPrint('앱 스토어 심사를 위한 캐시 서비스 최적화 완료');
  }

  // 언어 설정 관련 키
  static const String sourceLanguageKey = 'source_language';
  static const String targetLanguageKey = 'target_language';

  // 소스 언어 가져오기
  Future<String> getSourceLanguage() async {
    await _ensureInitialized();
    return _memoryCache[sourceLanguageKey] as String? ??
           _prefs?.getString(sourceLanguageKey) ?? 'zh-CN'; // 기본값: 중국어 간체자
  }

  // 타겟 언어 가져오기
  Future<String> getTargetLanguage() async {
    await _ensureInitialized();
    return _memoryCache[targetLanguageKey] as String? ?? 
           _prefs?.getString(targetLanguageKey) ?? 'ko'; // 기본값: 한국어
  }

  // 소스 언어 설정
  Future<void> setSourceLanguage(String language) async {
    await _ensureInitialized();
    await _prefs!.setString(sourceLanguageKey, language);
    _memoryCache[sourceLanguageKey] = language;
  }

  // 타겟 언어 설정
  Future<void> setTargetLanguage(String language) async {
    await _ensureInitialized();
    await _prefs!.setString(targetLanguageKey, language);
    _memoryCache[targetLanguageKey] = language;
  }

  // ProcessedText 캐싱 메서드 - 추가된 부분
  final Map<String, ProcessedText> _processedTextCache = {};
  
  // ProcessedText 캐싱 (메모리)
  Future<void> setProcessedText(String pageId, ProcessedText processedText) async {
    await _ensureInitialized();
    final key = 'processed_text_$pageId';
    _processedTextCache[pageId] = processedText;
    _cacheTimestamps[pageId] = DateTime.now();
    
    // 통계 업데이트
    _updateCacheStats(key, CacheOperationType.write);
    
    debugPrint('ProcessedText 메모리 캐싱 완료: 페이지 ID=$pageId');
  }
  
  // ProcessedText 조회 (메모리)
  Future<ProcessedText?> getProcessedText(String pageId) async {
    await _ensureInitialized();
    final key = 'processed_text_$pageId';
    
    debugPrint('ProcessedText 캐시 조회 시도: $key');
    
    if (_processedTextCache.containsKey(pageId)) {
      final timestamp = _cacheTimestamps[pageId];
      debugPrint('ProcessedText 캐시 타임스탬프: $timestamp');
      
      _cacheTimestamps[pageId] = DateTime.now();
      _updateCacheStats(key, CacheOperationType.read);
      
      return _processedTextCache[pageId];
    }
    
    debugPrint('ProcessedText 캐시 미스: $key');
    _updateCacheStats(key, CacheOperationType.read);
    return null;
  }
  
  // ProcessedText 삭제 (메모리)
  Future<void> removeProcessedText(String pageId) async {
    await _ensureInitialized();
    final key = 'processed_text_$pageId';
    
    _processedTextCache.remove(pageId);
    _cacheTimestamps.remove(pageId);
    
    // 통계 업데이트
    _updateCacheStats(key, CacheOperationType.delete);
    
    debugPrint('ProcessedText 메모리 캐시 삭제 완료: 페이지 ID=$pageId');
  }

  // 초기화 확인 및 수행
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      _prefs = await SharedPreferences.getInstance();
      _isInitialized = true;
    }
  }

  /// 특정 노트의 페이지 목록 캐시에서 가져오기
  Future<List<page_model.Page>> getCachedPagesByNoteId(String noteId) async {
    try {
      if (!_isInitialized) await initialize();

      // 캐시에서 페이지 ID 목록 가져오기
      final pageIds = _notePageIds[noteId] ?? [];
      if (pageIds.isEmpty) {
        return [];
      }

      // 페이지 ID로 페이지 객체 가져오기
      final pages = <page_model.Page>[];
      for (final pageId in pageIds) {
        final page = _pageCache[pageId];
        if (page != null) {
          pages.add(page);
        }
      }

      // 페이지 번호로 정렬
      pages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));

      return pages;
    } catch (e) {
      debugPrint('캐시에서 페이지 목록을 가져오는 중 오류 발생: $e');
      return [];
    }
  }
  
  /// 특정 노트의 플래시카드 목록 캐시에서 가져오기
  Future<List<FlashCard>> getFlashcardsByNoteId(String noteId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'flashcards_$noteId';
      
      // 캐시된 값이 없으면 빈 배열 반환
      if (!prefs.containsKey(key)) {
        return [];
      }
      
      final jsonString = prefs.getString(key) ?? '[]';
      
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => FlashCard.fromJson(json)).toList();
    } catch (e) {
      debugPrint('캐시에서 플래시카드 목록을 가져오는 중 오류 발생: $e');
      return [];
    }
  }
  
  /// 플래시카드 목록 캐싱
  Future<void> cacheFlashcards(List<FlashCard> flashcards) async {
    if (flashcards.isEmpty) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 노트 ID별로 그룹화
      final groupedByNote = <String, List<FlashCard>>{};
      for (final card in flashcards) {
        if (card.noteId != null && card.noteId!.isNotEmpty) {
          if (!groupedByNote.containsKey(card.noteId)) {
            groupedByNote[card.noteId!] = [];
          }
          groupedByNote[card.noteId]!.add(card);
        }
      }
      
      // 노트 ID별로 캐싱
      for (final entry in groupedByNote.entries) {
        final noteId = entry.key;
        final cards = entry.value;
        
        final jsonList = cards.map((card) => card.toJson()).toList();
        final jsonString = jsonEncode(jsonList);
        
        await prefs.setString('flashcards_$noteId', jsonString);
        debugPrint('노트 $noteId의 플래시카드 ${cards.length}개 캐싱 완료');
      }
    } catch (e) {
      debugPrint('플래시카드 캐싱 중 오류 발생: $e');
    }
  }
  
  /// 단일 플래시카드 캐싱
  Future<void> cacheFlashcard(FlashCard flashcard) async {
    if (flashcard.noteId == null || flashcard.noteId!.isEmpty) return;
    
    try {
      // 해당 노트의 기존 캐시된 플래시카드 가져오기
      final cachedCards = await getFlashcardsByNoteId(flashcard.noteId!);
      
      // 이미 같은 ID의 카드가 있는지 확인
      final existingIndex = cachedCards.indexWhere((card) => card.id == flashcard.id);
      
      if (existingIndex >= 0) {
        // 기존 카드 업데이트
        cachedCards[existingIndex] = flashcard;
      } else {
        // 새 카드 추가
        cachedCards.add(flashcard);
      }
      
      // 업데이트된 목록 다시 캐싱
      await cacheFlashcards(cachedCards);
      
      debugPrint('플래시카드 ${flashcard.id} 캐싱 완료');
    } catch (e) {
      debugPrint('단일 플래시카드 캐싱 중 오류 발생: $e');
    }
  }

  /// 캐시에서 플래시카드 삭제
  Future<void> removeFlashcard(String flashcardId, String? noteId) async {
    if (noteId == null || noteId.isEmpty) return;
    
    try {
      // 해당 노트의 기존 캐시된 플래시카드 가져오기
      final cachedCards = await getFlashcardsByNoteId(noteId);
      
      // 지정된 ID의 카드 제거
      cachedCards.removeWhere((card) => card.id == flashcardId);
      
      // 업데이트된 목록 다시 캐싱
      await cacheFlashcards(cachedCards);
      
      debugPrint('플래시카드 $flashcardId 캐시에서 삭제 완료');
    } catch (e) {
      debugPrint('플래시카드 삭제 중 오류 발생: $e');
    }
  }
}
