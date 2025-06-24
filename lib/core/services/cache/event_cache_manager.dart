import 'dart:async';
import 'package:flutter/foundation.dart';

/// 캐시 이벤트 타입
enum CacheEventType {
  userPreferencesChanged,  // 사용자 설정 변경
  planChanged,            // 플랜 정보 변경
  subscriptionChanged,    // 구독 상태 변경
  userDeleted,           // 사용자 탈퇴
  userLoggedIn,          // 사용자 로그인
  userLoggedOut,         // 사용자 로그아웃
}

/// 캐시 이벤트 데이터
class CacheEvent {
  final CacheEventType type;
  final String? userId;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  CacheEvent({
    required this.type,
    this.userId,
    this.data,
  }) : timestamp = DateTime.now();

  @override
  String toString() {
    return 'CacheEvent(type: $type, userId: $userId, timestamp: $timestamp)';
  }
}

/// 이벤트 기반 캐시 관리자
class EventCacheManager {
  static final EventCacheManager _instance = EventCacheManager._internal();
  factory EventCacheManager() => _instance;
  EventCacheManager._internal();

  // 이벤트 스트림
  final StreamController<CacheEvent> _eventController = StreamController<CacheEvent>.broadcast();
  Stream<CacheEvent> get eventStream => _eventController.stream;

  // 캐시 저장소
  final Map<String, dynamic> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};

  /// 이벤트 발생
  void emitEvent(CacheEventType type, {String? userId, Map<String, dynamic>? data}) {
    final event = CacheEvent(type: type, userId: userId, data: data);
    
    if (kDebugMode) {
      print('🔔 [EventCache] 이벤트 발생: $event');
    }
    
    _eventController.add(event);
    _handleEvent(event);
  }

  /// 이벤트 처리 (캐시 무효화)
  void _handleEvent(CacheEvent event) {
    switch (event.type) {
      case CacheEventType.userPreferencesChanged:
        _invalidateUserPreferences(event.userId);
        break;
      case CacheEventType.planChanged:
      case CacheEventType.subscriptionChanged:
        _invalidatePlanData(event.userId);
        break;
      case CacheEventType.userDeleted:
      case CacheEventType.userLoggedOut:
        _invalidateAllUserData(event.userId);
        break;
      case CacheEventType.userLoggedIn:
        _invalidateAllUserData(event.userId); // 새 사용자 데이터 로드를 위해
        break;
    }
  }

  /// 사용자 설정 캐시 무효화
  void _invalidateUserPreferences(String? userId) {
    if (userId == null) return;
    
    final keys = _cache.keys.where((key) => key.startsWith('user_preferences_$userId')).toList();
    for (final key in keys) {
      _cache.remove(key);
      _cacheTimestamps.remove(key);
    }
    
    if (kDebugMode) {
      print('🗑️ [EventCache] 사용자 설정 캐시 무효화: $userId');
    }
  }

  /// 플랜 데이터 캐시 무효화
  void _invalidatePlanData(String? userId) {
    if (userId == null) return;
    
    final keys = _cache.keys.where((key) => 
      key.startsWith('plan_$userId') || 
      key.startsWith('subscription_$userId')
    ).toList();
    
    for (final key in keys) {
      _cache.remove(key);
      _cacheTimestamps.remove(key);
    }
    
    if (kDebugMode) {
      print('🗑️ [EventCache] 플랜 데이터 캐시 무효화: $userId');
    }
  }

  /// 모든 사용자 데이터 캐시 무효화
  void _invalidateAllUserData(String? userId) {
    if (userId == null) return;
    
    final keys = _cache.keys.where((key) => key.contains(userId)).toList();
    for (final key in keys) {
      _cache.remove(key);
      _cacheTimestamps.remove(key);
    }
    
    if (kDebugMode) {
      print('🗑️ [EventCache] 모든 사용자 데이터 캐시 무효화: $userId');
    }
  }

  /// 캐시 저장
  void setCache(String key, dynamic value) {
    _cache[key] = value;
    _cacheTimestamps[key] = DateTime.now();
    
    if (kDebugMode) {
      print('💾 [EventCache] 캐시 저장: $key');
    }
  }

  /// 캐시 조회
  T? getCache<T>(String key) {
    final value = _cache[key];
    if (value != null && value is T) {
      if (kDebugMode) {
        print('📦 [EventCache] 캐시 조회 성공: $key');
      }
      return value;
    }
    return null;
  }

  /// 캐시 존재 여부 확인
  bool hasCache(String key) {
    return _cache.containsKey(key);
  }

  /// 특정 키 캐시 무효화
  void invalidateCache(String key) {
    _cache.remove(key);
    _cacheTimestamps.remove(key);
    
    if (kDebugMode) {
      print('🗑️ [EventCache] 캐시 무효화: $key');
    }
  }

  /// 모든 캐시 초기화
  void clearAllCache() {
    _cache.clear();
    _cacheTimestamps.clear();
    
    if (kDebugMode) {
      print('🗑️ [EventCache] 모든 캐시 초기화');
    }
  }

  /// 이벤트 리스너 등록
  StreamSubscription<CacheEvent> listen(void Function(CacheEvent) onEvent) {
    return _eventController.stream.listen(onEvent);
  }

  /// 캐시 상태 디버그 출력
  void debugCacheStatus() {
    if (kDebugMode) {
      print('📊 [EventCache] 현재 캐시 상태:');
      print('   총 캐시 항목: ${_cache.length}');
      for (final entry in _cache.entries) {
        final timestamp = _cacheTimestamps[entry.key];
        print('   ${entry.key}: ${timestamp?.toString() ?? "시간 정보 없음"}');
      }
    }
  }

  /// 리소스 정리
  void dispose() {
    _eventController.close();
    _cache.clear();
    _cacheTimestamps.clear();
  }
} 