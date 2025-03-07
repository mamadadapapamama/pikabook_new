import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';

/// 노트 데이터 캐싱 서비스
class NoteCacheService {
  // 싱글톤 패턴 구현
  static final NoteCacheService _instance = NoteCacheService._internal();
  factory NoteCacheService() => _instance;
  NoteCacheService._internal();

  // 메모리 캐시
  final Map<String, Note> _memoryCache = {};
  final Map<String, DateTime> _memoryCacheTimestamps = {};

  // 캐시 설정
  static const Duration _cacheDuration = Duration(hours: 24); // 캐시 유효 기간
  static const int _maxCacheSize = 50; // 최대 캐시 항목 수
  static const String _prefKeyPrefix = 'note_cache_'; // SharedPreferences 키 접두사

  /// 노트 캐싱
  Future<void> cacheNote(Note note) async {
    if (note.id == null) return;

    // 메모리 캐시에 저장
    _memoryCache[note.id!] = note;
    _memoryCacheTimestamps[note.id!] = DateTime.now();

    // 캐시 크기 관리
    _cleanupMemoryCache();

    // 로컬 저장소에 저장
    try {
      final prefs = await SharedPreferences.getInstance();
      final noteJson = jsonEncode(note.toJson());
      await prefs.setString('$_prefKeyPrefix${note.id}', noteJson);
      await prefs.setString('${_prefKeyPrefix}timestamp_${note.id}',
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
    if (_memoryCache.containsKey(noteId)) {
      final cachedTime = _memoryCacheTimestamps[noteId];
      if (cachedTime != null &&
          DateTime.now().difference(cachedTime) < _cacheDuration) {
        debugPrint('메모리 캐시에서 노트 로드: $noteId');
        return _memoryCache[noteId];
      }
    }

    // 2. 로컬 저장소 확인
    try {
      final prefs = await SharedPreferences.getInstance();
      final noteJson = prefs.getString('$_prefKeyPrefix$noteId');
      final timestampStr =
          prefs.getString('${_prefKeyPrefix}timestamp_$noteId');

      if (noteJson != null && timestampStr != null) {
        final timestamp = DateTime.parse(timestampStr);
        if (DateTime.now().difference(timestamp) < _cacheDuration) {
          debugPrint('로컬 저장소에서 노트 로드: $noteId');
          final noteMap = jsonDecode(noteJson) as Map<String, dynamic>;
          final note = Note.fromJson(noteMap);

          // 메모리 캐시 업데이트
          _memoryCache[noteId] = note;
          _memoryCacheTimestamps[noteId] = DateTime.now();

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
        if (key.startsWith(_prefKeyPrefix) && !key.contains('timestamp')) {
          final noteId = key.substring(_prefKeyPrefix.length);
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
    _memoryCache.remove(noteId);
    _memoryCacheTimestamps.remove(noteId);

    // 로컬 저장소에서 삭제
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefKeyPrefix$noteId');
      await prefs.remove('${_prefKeyPrefix}timestamp_$noteId');
    } catch (e) {
      debugPrint('캐시에서 노트 삭제 중 오류 발생: $e');
    }
  }

  /// 캐시 초기화
  Future<void> clearCache() async {
    // 메모리 캐시 초기화
    _memoryCache.clear();
    _memoryCacheTimestamps.clear();

    // 로컬 저장소 캐시 초기화
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      for (final key in allKeys) {
        if (key.startsWith(_prefKeyPrefix)) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      debugPrint('캐시 초기화 중 오류 발생: $e');
    }
  }

  /// 메모리 캐시 정리
  void _cleanupMemoryCache() {
    if (_memoryCache.length <= _maxCacheSize) return;

    // 가장 오래된 항목부터 삭제
    final sortedEntries = _memoryCacheTimestamps.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    final itemsToRemove = sortedEntries.length - _maxCacheSize;
    for (int i = 0; i < itemsToRemove; i++) {
      final noteId = sortedEntries[i].key;
      _memoryCache.remove(noteId);
      _memoryCacheTimestamps.remove(noteId);
    }
  }

  /// 만료된 캐시 정리
  Future<void> cleanupExpiredCache() async {
    final now = DateTime.now();

    // 메모리 캐시 정리
    _memoryCacheTimestamps.removeWhere((key, timestamp) {
      final isExpired = now.difference(timestamp) > _cacheDuration;
      if (isExpired) {
        _memoryCache.remove(key);
      }
      return isExpired;
    });

    // 로컬 저장소 캐시 정리
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      for (final key in allKeys) {
        if (key.startsWith('${_prefKeyPrefix}timestamp_')) {
          final timestampStr = prefs.getString(key);
          if (timestampStr != null) {
            final timestamp = DateTime.parse(timestampStr);
            if (now.difference(timestamp) > _cacheDuration) {
              final noteId =
                  key.substring('${_prefKeyPrefix}timestamp_'.length);
              await prefs.remove('$_prefKeyPrefix$noteId');
              await prefs.remove(key);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('만료된 캐시 정리 중 오류 발생: $e');
    }
  }
}
