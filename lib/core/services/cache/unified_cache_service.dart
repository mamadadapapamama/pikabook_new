import 'package:flutter/foundation.dart';

/// 처리 모드
enum ProcessingMode {
  /// 원본 텍스트
  original,
  
  /// 번역된 텍스트
  translated,
  
  /// 핀인
  pinyin
}

/// 통합 캐시 서비스
/// 앱 전체에서 사용되는 캐시를 관리합니다.
class UnifiedCacheService {
  // 싱글톤 패턴 구현
  static final UnifiedCacheService _instance = UnifiedCacheService._internal();
  factory UnifiedCacheService() => _instance;
  
  // 캐시 저장소
  final Map<String, dynamic> _cache = {};
  
  // 초기화 완료 여부
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  
  UnifiedCacheService._internal();
  
  // 초기화 메서드
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // 캐시 초기화 로직
      _isInitialized = true;
      debugPrint('UnifiedCacheService 초기화 완료');
    } catch (e) {
      debugPrint('UnifiedCacheService 초기화 중 오류 발생: $e');
      rethrow;
    }
  }
  
  // 캐시에서 데이터를 가져옵니다.
  dynamic get(String key) {
    try {
      return _cache[key];
    } catch (e) {
      debugPrint('캐시 데이터 조회 중 오류 발생: $e');
      return null;
    }
  }
  
  // 캐시에 데이터를 저장합니다.
  void set(String key, dynamic value) {
    try {
      _cache[key] = value;
    } catch (e) {
      debugPrint('캐시 데이터 저장 중 오류 발생: $e');
    }
  }
  
  // 캐시에서 데이터를 삭제합니다.
  void remove(String key) {
    try {
      _cache.remove(key);
    } catch (e) {
      debugPrint('캐시 데이터 삭제 중 오류 발생: $e');
    }
  }
  
  // 캐시를 모두 비웁니다.
  void clear() {
    try {
      _cache.clear();
    } catch (e) {
      debugPrint('캐시 초기화 중 오류 발생: $e');
    }
  }
  
  // 특정 노트의 캐시를 비웁니다.
  void clearNoteCaches(String noteId) {
    try {
      final keysToRemove = _cache.keys.where((key) => key.startsWith('note_$noteId')).toList();
      for (final key in keysToRemove) {
        _cache.remove(key);
      }
    } catch (e) {
      debugPrint('노트 캐시 초기화 중 오류 발생: $e');
    }
  }
  
  // 페이지 내용을 가져옵니다.
  Future<Map<String, dynamic>?> getPageContent(String text, ProcessingMode mode) async {
    try {
      final cacheKey = 'page_${text}_$mode';
      final cachedData = _cache[cacheKey];
      if (cachedData != null) {
        return Map<String, dynamic>.from(cachedData);
      }
      return null;
    } catch (e) {
      debugPrint('페이지 내용 조회 중 오류 발생: $e');
      return null;
    }
  }
  
  // 페이지 내용을 캐시에 저장합니다.
  Future<void> cachePageContent(
    String text, {
    required String originalText,
    required String translatedText,
    String? pinyin,
    String? ttsPath,
  }) async {
    try {
      final cacheKey = 'page_$text';
      final data = {
        'originalText': originalText,
        'translatedText': translatedText,
        if (pinyin != null) 'pinyin': pinyin,
        if (ttsPath != null) 'ttsPath': ttsPath,
      };
      _cache[cacheKey] = data;
    } catch (e) {
      debugPrint('페이지 내용 캐시 저장 중 오류 발생: $e');
    }
  }
} 