import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../cache/cache_manager.dart';

/// TTS 캐시 전용 서비스
/// CacheManager를 사용하여 TTS 오디오 파일을 캐시합니다.
class TTSCacheService {
  // 싱글톤 패턴
  static final TTSCacheService _instance = TTSCacheService._internal();
  factory TTSCacheService() => _instance;
  TTSCacheService._internal();

  final CacheManager _cacheManager = CacheManager();
  bool _isInitialized = false;

  /// 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // CacheManager는 App.dart에서 이미 초기화됨
      _isInitialized = true;

      if (kDebugMode) {
        debugPrint('🔊 TTSCacheService 초기화 완료 (CacheManager는 App.dart에서 초기화됨)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ TTSCacheService 초기화 실패: $e');
      }
      rethrow;
    }
  }

  /// TTS 오디오 캐싱
  Future<String?> cacheTTSAudio({
    required String noteId,
    required String pageId,
    required String segmentId,
    required String voiceId,
    required Uint8List audioData,
  }) async {
    await _ensureInitialized();

    return await _cacheManager.cacheTTS(
      noteId: noteId,
      pageId: pageId,
      segmentId: segmentId,
      voiceId: voiceId,
      audioData: audioData,
    );
  }

  /// TTS 오디오 조회
  Future<Uint8List?> getTTSAudio({
    required String noteId,
    required String pageId,
    required String segmentId,
    required String voiceId,
  }) async {
    await _ensureInitialized();

    return await _cacheManager.getTTS(
      noteId: noteId,
      pageId: pageId,
      segmentId: segmentId,
      voiceId: voiceId,
    );
  }

  /// TTS 파일 경로 조회
  Future<String?> getTTSPath({
    required String noteId,
    required String pageId,
    required String segmentId,
    required String voiceId,
  }) async {
    await _ensureInitialized();

    return await _cacheManager.getTTSPath(
      noteId: noteId,
      pageId: pageId,
      segmentId: segmentId,
      voiceId: voiceId,
    );
  }

  /// 노트의 모든 TTS 캐시 삭제
  Future<void> clearNoteTTSCache(String noteId) async {
    await _ensureInitialized();
    await _cacheManager.clearNoteTTS(noteId);
  }

  /// 전체 TTS 캐시 삭제
  Future<void> clearAllTTSCache() async {
    await _ensureInitialized();
    // TTS 캐시만 삭제하는 방법이 없으므로 전체 캐시 정리 사용
    await _cacheManager.cleanupExpiredCache();
  }

  /// 초기화 확인
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  /// 리소스 해제
  Future<void> dispose() async {
    _isInitialized = false;
    if (kDebugMode) {
      debugPrint('🔊 TTSCacheService 리소스 해제 완료');
    }
  }
} 