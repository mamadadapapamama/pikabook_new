import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:collection/collection.dart';
import '../../../core/models/flash_card.dart';
import '../../../core/models/processed_text.dart';

/// 통합 캐시 서비스
/// 앱 전체에서 사용되는 캐시를 관리합니다.
class UnifiedCacheService {
  // 싱글톤 패턴 구현
  static final UnifiedCacheService _instance = UnifiedCacheService._internal();
  factory UnifiedCacheService() => _instance;
  
  // Firebase 인스턴스
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  
  // 캐시 저장소
  final Map<String, dynamic> _cache = {};
  
  // LRU 캐시 관리를 위한 타임스탬프 맵
  final Map<String, DateTime> _lastAccessed = {};
  
  // 초기화 완료 여부
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  
  // 최대 캐시 항목 수
  static const int _maxSegmentCacheItems = 100;
  static const int _maxFlashcardCacheItems = 200;
  
  // Firebase 컬렉션/버킷 경로
  static const String _segmentsCollection = 'segments_cache';
  static const String _ttsBucket = 'tts_cache';
  static const String _flashcardsCollection = 'flashcards';
  
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
  
  /// 세그먼트 캐시 키 생성
  String _getSegmentCacheKey(String imageId, TextProcessingMode mode) {
    return 'segments_${imageId}_${mode.toString().split('.').last}';
  }
  
  /// TTS 캐시 키 생성
  String _getTtsCacheKey(String segmentId) {
    return 'tts_$segmentId';
  }
  
  /// 플래시카드 캐시 키 생성
  String _getFlashcardCacheKey(String noteId) {
    return 'flashcards_$noteId';
  }
  
  /// 세그먼트 결과 캐싱
  Future<void> cacheSegments(String imageId, TextProcessingMode mode, List<Map<String, String>> segments) async {
    try {
      final key = _getSegmentCacheKey(imageId, mode);
      
      // 로컬 캐시에 저장
      _cache[key] = segments;
      _updateLastAccessed(key);
      
      // 캐시 크기 제한 확인
      _checkSegmentCacheSize();
      
      // 백그라운드에서 클라우드에 업로드
      _uploadSegmentsToCloud(key, segments);
      
      debugPrint('세그먼트 캐싱 완료: $key (${segments.length}개 세그먼트)');
    } catch (e) {
      debugPrint('세그먼트 캐싱 중 오류 발생: $e');
    }
  }
  
  /// 세그먼트 결과 조회
  Future<List<Map<String, String>>?> getSegments(String imageId, TextProcessingMode mode) async {
    try {
      final key = _getSegmentCacheKey(imageId, mode);
      
      // 1. 로컬 캐시 확인
      var segments = _cache[key] as List<Map<String, String>>?;
      if (segments != null) {
        _updateLastAccessed(key);
        return segments;
      }
      
      // 2. 클라우드 캐시 확인
      segments = await _getSegmentsFromCloud(key);
      if (segments != null) {
        // 로컬 캐시에 저장
        _cache[key] = segments;
        _updateLastAccessed(key);
        _checkSegmentCacheSize();
        return segments;
      }
      
      return null;
    } catch (e) {
      debugPrint('세그먼트 조회 중 오류 발생: $e');
      return null;
    }
  }
  
  /// TTS 데이터 캐싱
  Future<String?> cacheTts(String segmentId, Uint8List audioData) async {
    try {
      final key = _getTtsCacheKey(segmentId);
      
      // 로컬 파일로 저장
      final appDir = await getApplicationDocumentsDirectory();
      final filePath = '${appDir.path}/$key.mp3';
      final file = File(filePath);
      await file.writeAsBytes(audioData);
      
      // 메모리에 경로 정보만 캐싱
      _cache[key] = filePath;
      _updateLastAccessed(key);
      
      // 백그라운드에서 클라우드에 업로드
      _uploadTtsToCloud(key, audioData);
      
      debugPrint('TTS 캐싱 완료: $key');
      return filePath;
    } catch (e) {
      debugPrint('TTS 캐싱 중 오류 발생: $e');
      return null;
    }
  }
  
  /// TTS 데이터 조회
  Future<String?> getTtsPath(String segmentId) async {
    try {
      final key = _getTtsCacheKey(segmentId);
      
      // 1. 로컬 캐시 확인
      var filePath = _cache[key] as String?;
      if (filePath != null && await File(filePath).exists()) {
        _updateLastAccessed(key);
        return filePath;
      }
      
      // 2. 클라우드 캐시 확인
      final audioData = await _getTtsFromCloud(key);
      if (audioData != null) {
        // 로컬에 저장
        filePath = await cacheTts(segmentId, audioData);
        return filePath;
      }
      
      return null;
    } catch (e) {
      debugPrint('TTS 조회 중 오류 발생: $e');
      return null;
    }
  }
  
  /// LRU 캐시 관리를 위한 마지막 접근 시간 업데이트
  void _updateLastAccessed(String key) {
    _lastAccessed[key] = DateTime.now();
  }
  
  /// 세그먼트 캐시 크기 제한 확인
  void _checkSegmentCacheSize() {
    final segmentKeys = _cache.keys.where((key) => key.startsWith('segments_')).toList();
    
    if (segmentKeys.length > _maxSegmentCacheItems) {
      // LRU 알고리즘으로 정렬
      segmentKeys.sort((a, b) => 
        (_lastAccessed[a] ?? DateTime(0)).compareTo(_lastAccessed[b] ?? DateTime(0)));
      
      // 가장 오래된 항목부터 제거
      final keysToRemove = segmentKeys.sublist(0, segmentKeys.length - _maxSegmentCacheItems);
      for (final key in keysToRemove) {
        _cache.remove(key);
        _lastAccessed.remove(key);
      }
      debugPrint('세그먼트 캐시 정리: ${keysToRemove.length}개 항목 제거');
    }
  }
  
  /// 클라우드에 세그먼트 업로드
  Future<void> _uploadSegmentsToCloud(String key, List<Map<String, String>> segments) async {
    try {
      await _firestore.collection(_segmentsCollection).doc(key).set({
        'segments': segments,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('세그먼트 클라우드 업로드 중 오류 발생: $e');
    }
  }
  
  /// 클라우드에서 세그먼트 조회
  Future<List<Map<String, String>>?> _getSegmentsFromCloud(String key) async {
    try {
      final doc = await _firestore.collection(_segmentsCollection).doc(key).get();
      if (doc.exists) {
        final data = doc.data();
        return List<Map<String, String>>.from(data?['segments'] ?? []);
      }
      return null;
    } catch (e) {
      debugPrint('세그먼트 클라우드 조회 중 오류 발생: $e');
      return null;
    }
  }
  
  /// 클라우드에 TTS 업로드
  Future<void> _uploadTtsToCloud(String key, Uint8List audioData) async {
    try {
      final ref = _storage.ref().child('$_ttsBucket/$key.mp3');
      await ref.putData(audioData);
    } catch (e) {
      debugPrint('TTS 클라우드 업로드 중 오류 발생: $e');
    }
  }
  
  /// 클라우드에서 TTS 조회
  Future<Uint8List?> _getTtsFromCloud(String key) async {
    try {
      final ref = _storage.ref().child('$_ttsBucket/$key.mp3');
      final maxSize = 10 * 1024 * 1024; // 10MB
      return await ref.getData(maxSize);
    } catch (e) {
      debugPrint('TTS 클라우드 조회 중 오류 발생: $e');
      return null;
    }
  }
  
  /// 이미지 관련 캐시 삭제
  Future<void> clearImageCache(String imageId) async {
    try {
      // 로컬 캐시 삭제
      for (final mode in TextProcessingMode.values) {
        final key = _getSegmentCacheKey(imageId, mode);
        _cache.remove(key);
        _lastAccessed.remove(key);
      }
      
      // 클라우드 캐시 삭제
      for (final mode in TextProcessingMode.values) {
        final key = _getSegmentCacheKey(imageId, mode);
        await _firestore.collection(_segmentsCollection).doc(key).delete();
      }
      
      debugPrint('이미지 캐시 삭제 완료: $imageId');
    } catch (e) {
      debugPrint('이미지 캐시 삭제 중 오류 발생: $e');
    }
  }
  
  /// 세그먼트 관련 캐시 삭제
  Future<void> clearSegmentCache(String segmentId) async {
    try {
      final key = _getTtsCacheKey(segmentId);
      
      // 로컬 캐시 삭제
      final filePath = _cache[key] as String?;
      if (filePath != null) {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
        _cache.remove(key);
        _lastAccessed.remove(key);
      }
      
      // 클라우드 캐시 삭제
      final ref = _storage.ref().child('$_ttsBucket/$key.mp3');
      await ref.delete();
      
      debugPrint('세그먼트 캐시 삭제 완료: $segmentId');
    } catch (e) {
      debugPrint('세그먼트 캐시 삭제 중 오류 발생: $e');
    }
  }
  
  /// 플래시카드 캐싱
  Future<void> cacheFlashcards(String noteId, List<FlashCard> flashcards) async {
    try {
      final key = _getFlashcardCacheKey(noteId);
      
      // 로컬 캐시에 저장
      _cache[key] = flashcards;
      _updateLastAccessed(key);
      
      // 캐시 크기 제한 확인
      _checkFlashcardCacheSize();
      
      // 백그라운드에서 클라우드에 업로드
      _uploadFlashcardsToCloud(noteId, flashcards);
      
      debugPrint('플래시카드 캐싱 완료: $key (${flashcards.length}개)');
    } catch (e) {
      debugPrint('플래시카드 캐싱 중 오류 발생: $e');
    }
  }

  /// 플래시카드 조회
  Future<List<FlashCard>?> getFlashcards(String noteId) async {
    try {
      final key = _getFlashcardCacheKey(noteId);
      
      // 1. 로컬 캐시 확인
      var flashcards = _cache[key] as List<FlashCard>?;
      if (flashcards != null) {
        _updateLastAccessed(key);
        return flashcards;
      }
      
      // 2. 클라우드 캐시 확인
      flashcards = await _getFlashcardsFromCloud(noteId);
      if (flashcards != null) {
        // 로컬 캐시에 저장
        _cache[key] = flashcards;
        _updateLastAccessed(key);
        _checkFlashcardCacheSize();
        return flashcards;
      }
      
      return null;
    } catch (e) {
      debugPrint('플래시카드 조회 중 오류 발생: $e');
      return null;
    }
  }

  /// 플래시카드 캐시 크기 제한 확인
  void _checkFlashcardCacheSize() {
    final flashcardKeys = _cache.keys.where((key) => key.startsWith('flashcards_')).toList();
    
    if (flashcardKeys.length > _maxFlashcardCacheItems) {
      // LRU 알고리즘으로 정렬
      flashcardKeys.sort((a, b) => 
        (_lastAccessed[a] ?? DateTime(0)).compareTo(_lastAccessed[b] ?? DateTime(0)));
      
      // 가장 오래된 항목부터 제거
      final keysToRemove = flashcardKeys.sublist(0, flashcardKeys.length - _maxFlashcardCacheItems);
      for (final key in keysToRemove) {
        _cache.remove(key);
        _lastAccessed.remove(key);
      }
      debugPrint('플래시카드 캐시 정리: ${keysToRemove.length}개 항목 제거');
    }
  }

  /// 클라우드에 플래시카드 업로드
  Future<void> _uploadFlashcardsToCloud(String noteId, List<FlashCard> flashcards) async {
    try {
      final batch = _firestore.batch();
      
      // 기존 플래시카드 삭제
      final existingDocs = await _firestore
          .collection(_flashcardsCollection)
          .where('noteId', isEqualTo: noteId)
          .get();
      
      for (var doc in existingDocs.docs) {
        batch.delete(doc.reference);
      }
      
      // 새로운 플래시카드 추가
      for (var card in flashcards) {
        final docRef = _firestore.collection(_flashcardsCollection).doc();
        batch.set(docRef, card.toJson());
      }
      
      await batch.commit();
      debugPrint('플래시카드 클라우드 업로드 완료: $noteId (${flashcards.length}개)');
    } catch (e) {
      debugPrint('플래시카드 클라우드 업로드 중 오류 발생: $e');
    }
  }

  /// 클라우드에서 플래시카드 조회
  Future<List<FlashCard>?> _getFlashcardsFromCloud(String noteId) async {
    try {
      final querySnapshot = await _firestore
          .collection(_flashcardsCollection)
          .where('noteId', isEqualTo: noteId)
          .get();
      
      if (querySnapshot.docs.isEmpty) return null;
      
      return querySnapshot.docs
          .map((doc) => FlashCard.fromJson(doc.data()))
          .toList();
    } catch (e) {
      debugPrint('플래시카드 클라우드 조회 중 오류 발생: $e');
      return null;
    }
  }

  /// 플래시카드 캐시 삭제
  Future<void> clearFlashcardCache(String noteId) async {
    try {
      final key = _getFlashcardCacheKey(noteId);
      
      // 로컬 캐시 삭제
      _cache.remove(key);
      _lastAccessed.remove(key);
      
      // 클라우드 캐시 삭제
      final querySnapshot = await _firestore
          .collection(_flashcardsCollection)
          .where('noteId', isEqualTo: noteId)
          .get();
      
      final batch = _firestore.batch();
      for (var doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      
      debugPrint('플래시카드 캐시 삭제 완료: $noteId');
    } catch (e) {
      debugPrint('플래시카드 캐시 삭제 중 오류 발생: $e');
    }
  }
  
  /// 모든 캐시 초기화
  Future<void> clear() async {
    try {
      // 로컬 캐시 초기화
      _cache.clear();
      _lastAccessed.clear();
      
      // 로컬 파일 삭제
      final appDir = await getApplicationDocumentsDirectory();
      final ttsDir = Directory('${appDir.path}/tts_cache');
      if (await ttsDir.exists()) {
        await ttsDir.delete(recursive: true);
      }
      
      debugPrint('모든 캐시 초기화 완료');
    } catch (e) {
      debugPrint('캐시 초기화 중 오류 발생: $e');
    }
  }
  
  /// 동기화 상태 확인
  Future<bool> isSynced(String imageId, TextProcessingMode mode) async {
    try {
      final key = _getSegmentCacheKey(imageId, mode);
      final localData = _cache[key];
      if (localData == null) return false;
      
      final cloudDoc = await _firestore.collection(_segmentsCollection).doc(key).get();
      if (!cloudDoc.exists) return false;
      
      final cloudData = cloudDoc.data()?['segments'] as List?;
      if (cloudData == null) return false;
      
      // 간단한 데이터 비교
      if (localData.length != cloudData.length) return false;
      
      for (var i = 0; i < localData.length; i++) {
        final localSegment = localData[i] as Map<String, String>;
        final cloudSegment = cloudData[i] as Map<String, dynamic>;
        
        if (localSegment.length != cloudSegment.length) return false;
        
        for (final key in localSegment.keys) {
          if (localSegment[key] != cloudSegment[key]?.toString()) return false;
        }
      }
      
      return true;
    } catch (e) {
      debugPrint('동기화 상태 확인 중 오류 발생: $e');
      return false;
    }
  }
} 