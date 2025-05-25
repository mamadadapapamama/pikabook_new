import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/models/note.dart';

/// 노트 캐싱을 담당하는 서비스
/// 노트 목록을 로컬에 캐싱하고 관리합니다.
class NoteCacheService {
  // 싱글톤 패턴 구현
  static final NoteCacheService _instance = NoteCacheService._internal();
  factory NoteCacheService() => _instance;
  NoteCacheService._internal();

  // Firebase Auth 인스턴스
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 캐시 관련 상수
  static const String _cachedNotesKey = 'cached_notes';
  static const String _lastCacheTimeKey = 'last_notes_cache_time';
  
  /// 캐시된 노트 목록 가져오기
  Future<List<Note>> getCachedNotes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = _auth.currentUser;
      
      if (user == null) {
        return [];
      }
      
      // 사용자별 캐시 키 생성
      final cacheKey = '${_cachedNotesKey}_${user.uid}';
      
      // 캐시에서 노트 목록 읽기
      final notesJson = prefs.getString(cacheKey);
      if (notesJson == null || notesJson.isEmpty) {
        return [];
      }
      
      // JSON 파싱
      final List<dynamic> notesList = jsonDecode(notesJson) as List<dynamic>;
      
      // Note 객체로 변환
      return notesList
          .map((noteJson) => Note.fromJson(noteJson as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[NoteCacheService] 캐시된 노트 목록을 가져오는 중 오류 발생: $e');
      return [];
    }
  }
  
  /// 노트 목록 캐싱
  Future<void> cacheNotes(List<Note> notes) async {
    try {
      if (notes.isEmpty) {
        debugPrint('[NoteCacheService] 캐싱할 노트가 없음');
        return;
      }
      
      final prefs = await SharedPreferences.getInstance();
      final user = _auth.currentUser;
      
      if (user == null) {
        debugPrint('[NoteCacheService] 캐싱 실패: 로그인된 사용자 없음');
        return;
      }
      
      // 사용자별 캐시 키 생성
      final cacheKey = '${_cachedNotesKey}_${user.uid}';
      
      // 노트 목록을 JSON으로 변환
      final List<Map<String, dynamic>> notesJsonList = notes.map((note) => note.toJson()).toList();
      final notesJson = jsonEncode(notesJsonList);
      
      // 캐시에 저장
      await prefs.setString(cacheKey, notesJson);
      
      // 캐시 시간 저장
      await saveLastCacheTime(DateTime.now());
      
      debugPrint('[NoteCacheService] 노트 ${notes.length}개 캐싱 완료');
    } catch (e) {
      debugPrint('[NoteCacheService] 노트 캐싱 중 오류 발생: $e');
    }
  }
  
  /// 마지막 캐시 시간 저장
  Future<void> saveLastCacheTime(DateTime time) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = _auth.currentUser;
      
      if (user == null) {
        return;
      }
      
      // 사용자별 시간 캐시 키 생성
      final timeKey = '${_lastCacheTimeKey}_${user.uid}';
      
      // ISO8601 형식으로 저장
      await prefs.setString(timeKey, time.toIso8601String());
      
      debugPrint('[NoteCacheService] 마지막 캐시 시간 저장: ${time.toIso8601String()}');
    } catch (e) {
      debugPrint('[NoteCacheService] 캐시 시간 저장 중 오류 발생: $e');
    }
  }
  
  /// 마지막 캐시 시간 조회
  Future<DateTime?> getLastCacheTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = _auth.currentUser;
      
      if (user == null) {
        return null;
      }
      
      // 사용자별 시간 캐시 키 생성
      final timeKey = '${_lastCacheTimeKey}_${user.uid}';
      
      // 저장된 시간 읽기
      final timeString = prefs.getString(timeKey);
      if (timeString == null || timeString.isEmpty) {
        return null;
      }
      
      // ISO8601 형식에서 DateTime으로 변환
      return DateTime.parse(timeString);
    } catch (e) {
      debugPrint('[NoteCacheService] 마지막 캐시 시간 조회 중 오류 발생: $e');
      return null;
    }
  }
  
  /// 캐시 유효성 확인
  bool isCacheValid({Duration validDuration = const Duration(minutes: 5)}) {
    final lastRefreshTime = getLastCacheTimeSync();
    if (lastRefreshTime == null) return false;

    final now = DateTime.now();
    final difference = now.difference(lastRefreshTime);
    return difference < validDuration;
  }
  
  /// 마지막 캐시 시간 동기적 조회 (로컬 캐시)
  DateTime? _lastRefreshTime;
  
  /// 마지막 캐시 시간을 로컬에 캐싱하고 반환
  Future<DateTime?> updateLastCacheTimeCache() async {
    _lastRefreshTime = await getLastCacheTime();
    return _lastRefreshTime;
  }
  
  /// 캐시된 마지막 갱신 시간 반환 (로컬 메모리)
  DateTime? getLastCacheTimeSync() {
    return _lastRefreshTime;
  }
  
  /// 캐시 삭제
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final user = _auth.currentUser;
      
      if (user == null) {
        return;
      }
      
      // 사용자별 캐시 키 생성
      final cacheKey = '${_cachedNotesKey}_${user.uid}';
      final timeKey = '${_lastCacheTimeKey}_${user.uid}';
      
      // 캐시 데이터 삭제
      await prefs.remove(cacheKey);
      await prefs.remove(timeKey);
      _lastRefreshTime = null;
      
      debugPrint('[NoteCacheService] 노트 캐시 삭제 완료');
    } catch (e) {
      debugPrint('[NoteCacheService] 캐시 삭제 중 오류 발생: $e');
    }
  }
}
