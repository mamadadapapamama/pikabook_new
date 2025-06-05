import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/models/processed_text.dart';
import '../../../core/models/text_unit.dart';
import '../../../core/models/processing_status.dart';
import '../../../core/models/page.dart' as page_model;
import '../cache/cache_manager.dart';
import '../authentication/user_preferences_service.dart';

/// 텍스트 처리 캐시 관리 서비스
/// 캐시 중심의 ProcessedText 관리와 실시간 리스너 담당
class TextProcessingService {
  // 싱글톤 패턴
  static final TextProcessingService _instance = TextProcessingService._internal();
  factory TextProcessingService() => _instance;
  TextProcessingService._internal();
  
  // 서비스들
  final CacheManager _cacheManager = CacheManager();
  final UserPreferencesService _preferencesService = UserPreferencesService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // 실시간 리스너 관리
  final Map<String, StreamSubscription<DocumentSnapshot>> _pageListeners = {};
  
  /// 1. 캐시 우선 ProcessedText 조회
  /// 캐시 → Firestore 순으로 확인
  Future<ProcessedText?> getProcessedText(String pageId) async {
    if (pageId.isEmpty) return null;
    
    try {
      // 1. 캐시에서 먼저 확인
      final cachedText = await _getFromCache(pageId);
      if (cachedText != null) {
        if (kDebugMode) {
          debugPrint('✅ [캐시] ProcessedText 로드: $pageId');
        }
        return cachedText;
      }
      
      // 2. Firestore에서 확인
      final firestoreText = await _getFromFirestore(pageId);
      if (firestoreText != null) {
        // 완성된 데이터만 캐시에 저장
        if (firestoreText.streamingStatus == StreamingStatus.completed) {
          await _saveToCache(pageId, firestoreText);
          if (kDebugMode) {
            debugPrint('✅ [Firestore → 캐시] ProcessedText 로드: $pageId');
          }
        } else {
          if (kDebugMode) {
            debugPrint('✅ [Firestore] 스트리밍 중 ProcessedText 로드: $pageId');
          }
        }
        return firestoreText;
      }
      
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ ProcessedText 로드 실패: $pageId, $e');
      }
      return null;
    }
  }
  
  /// 2. 페이지 처리 상태 확인
  Future<ProcessingStatus> getProcessingStatus(String pageId) async {
    if (pageId.isEmpty) return ProcessingStatus.created;
    
    try {
      final doc = await _firestore.collection('pages').doc(pageId).get();
      if (!doc.exists) return ProcessingStatus.created;
      
      final page = page_model.Page.fromFirestore(doc);
      
      // ProcessedText 기반 상태 판단
      if (page.processedText != null && page.processedText!.isNotEmpty) {
        final streamingStatus = page.processedText!['streamingStatus'];
        if (streamingStatus != null) {
          final status = StreamingStatus.values[streamingStatus as int];
          switch (status) {
            case StreamingStatus.completed:
              return ProcessingStatus.completed;
            case StreamingStatus.streaming:
              return ProcessingStatus.translating;
            case StreamingStatus.preparing:
              return ProcessingStatus.textExtracted;
            default:
              return ProcessingStatus.textExtracted;
          }
        }
      }
      
      // 기존 호환성 체크
      if (page.translatedText != null && page.translatedText!.isNotEmpty) {
        return ProcessingStatus.completed;
      }
      
      if (page.originalText != null && page.originalText!.isNotEmpty) {
        return ProcessingStatus.textExtracted;
      }
      
      return ProcessingStatus.created;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 처리 상태 확인 실패: $pageId, $e');
      }
      return ProcessingStatus.failed;
    }
  }
  
  /// 3. 텍스트 모드 변경 (캐시 중심)
  Future<ProcessedText?> changeTextMode(String pageId, TextProcessingMode newMode) async {
    if (pageId.isEmpty) return null;
    
    try {
      // 기존 텍스트 로드
      final existing = await getProcessedText(pageId);
      if (existing == null) {
        return null;
      }
      
      // 모드가 같으면 그대로 반환
      if (existing.mode == newMode) {
        return existing;
      }
      
      // 모드 변경된 새 객체 생성
      final updatedText = existing.copyWith(mode: newMode);
      
      // 완성된 데이터만 캐시 업데이트
      if (updatedText.streamingStatus == StreamingStatus.completed) {
        await _saveToCache(pageId, updatedText);
      }
      
      if (kDebugMode) {
        debugPrint('✅ [캐시] 텍스트 모드 변경: $pageId, ${existing.mode} → $newMode');
      }
      
      return updatedText;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 텍스트 모드 변경 실패: $pageId, $e');
      }
      return null;
    }
  }
  
  /// 4. 실시간 페이지 변경 리스너 설정
  StreamSubscription<DocumentSnapshot>? listenToPageChanges(
    String pageId,
    Function(ProcessedText?) onTextChanged,
  ) {
    if (pageId.isEmpty) return null;
    
    if (kDebugMode) {
      debugPrint('🔔 [리스너] 설정: $pageId');
    }
    
    // 기존 리스너 정리
    _pageListeners[pageId]?.cancel();
    
    // 이전 데이터 추적
    ProcessedText? previousProcessedText;
    
    final listener = _firestore
        .collection('pages')
        .doc(pageId)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists) {
        if (kDebugMode) {
          debugPrint('📄 [리스너] 페이지 문서 없음: $pageId');
        }
        onTextChanged(null);
        return;
      }
      
      if (kDebugMode) {
        debugPrint('🔔 [리스너] Firestore 변경 감지: $pageId');
      }
      
      try {
        final page = page_model.Page.fromFirestore(snapshot);
        ProcessedText? processedText;
        
        // 우선순위: processedText 필드 → 호환성 모드
        if (page.processedText != null && page.processedText!.isNotEmpty) {
          processedText = await _createProcessedTextFromPageData(page);
          
          if (kDebugMode) {
            final streamingStatus = processedText?.streamingStatus ?? StreamingStatus.preparing;
            debugPrint('🔄 [리스너] processedText 파싱: $pageId (${streamingStatus.name})');
          }
        } else if (page.translatedText != null && page.translatedText!.isNotEmpty) {
          processedText = await _createProcessedTextFromPage(page);
          
          if (kDebugMode) {
            debugPrint('🔄 [리스너] 호환성 모드 처리: $pageId');
          }
        }
        
        // 변경사항 확인 후 콜백 호출
        if (processedText != null && _hasProcessedTextChanged(previousProcessedText, processedText)) {
          // 완성된 데이터만 캐시에 저장
          if (processedText.streamingStatus == StreamingStatus.completed) {
            await _saveToCache(pageId, processedText);
            if (kDebugMode) {
              debugPrint('💾 [리스너 → 캐시] 완성된 데이터 저장: $pageId');
            }
          }
          
          onTextChanged(processedText);
          previousProcessedText = processedText;
          
          if (kDebugMode) {
            debugPrint('📞 [리스너] UI 콜백 호출: $pageId');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ [리스너] 처리 실패: $pageId, $e');
        }
        onTextChanged(null);
      }
    });
    
    _pageListeners[pageId] = listener;
    
    if (kDebugMode) {
      debugPrint('✅ [리스너] 설정 완료: $pageId');
    }
    
    return listener;
  }
  
  /// 5. 캐시 무효화
  Future<void> invalidateCache(String pageId) async {
    try {
      // TODO: CacheManager에 removeCachedContent 메서드 추가 필요
      if (kDebugMode) {
        debugPrint('🗑️ [캐시] 무효화 기능 준비 중: $pageId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 캐시 무효화 실패: $pageId, $e');
      }
    }
  }
  
  /// 6. 리스너 정리
  void cancelPageListener(String pageId) {
    _pageListeners[pageId]?.cancel();
    _pageListeners.remove(pageId);
    
    if (kDebugMode) {
      debugPrint('🔇 [리스너] 해제: $pageId');
    }
  }
  
  /// 모든 리스너 정리
  void cancelAllListeners() {
    for (final listener in _pageListeners.values) {
      listener.cancel();
    }
    _pageListeners.clear();
    
    if (kDebugMode) {
      debugPrint('🔇 [리스너] 모든 리스너 해제');
    }
  }
  
  // === Private Cache Methods ===
  
  /// 캐시에서 ProcessedText 로드
  Future<ProcessedText?> _getFromCache(String pageId) async {
    try {
      final pageDoc = await _firestore.collection('pages').doc(pageId).get();
      if (!pageDoc.exists) return null;
      
      final noteId = pageDoc.data()?['noteId'] as String?;
      if (noteId == null) return null;
      
      final cachedData = await _cacheManager.getNoteContent(
        noteId: noteId,
        pageId: pageId,
        dataMode: 'segment',
        type: 'processed_text',
      );
      
      if (cachedData == null || cachedData['segments'] == null) return null;
      
      return _buildProcessedTextFromCache(cachedData);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 캐시 로드 실패: $pageId, $e');
      }
      return null;
    }
  }
  
  /// 캐시 데이터에서 ProcessedText 구성
  ProcessedText _buildProcessedTextFromCache(Map<String, dynamic> cachedData) {
    final segments = cachedData['segments'] as List;
    final units = segments.map((segment) => TextUnit(
      originalText: segment['original'] ?? '',
      translatedText: segment['translated'] ?? '',
      pinyin: segment['pinyin'] ?? '',
      sourceLanguage: segment['sourceLanguage'] ?? 'zh-CN',
      targetLanguage: segment['targetLanguage'] ?? 'ko',
    )).toList();
    
    final fullOriginalText = units.map((u) => u.originalText).join(' ');
    final fullTranslatedText = units.map((u) => u.translatedText ?? '').join(' ');
    
    return ProcessedText(
      mode: _parseTextModeFromString(cachedData['mode']),
      displayMode: TextDisplayMode.full,
      fullOriginalText: fullOriginalText,
      fullTranslatedText: fullTranslatedText,
      units: units,
      sourceLanguage: cachedData['sourceLanguage'] ?? 'zh-CN',
      targetLanguage: cachedData['targetLanguage'] ?? 'ko',
      streamingStatus: StreamingStatus.completed, // 캐시된 데이터는 완성된 상태
    );
  }
  
  /// 캐시에 ProcessedText 저장
  Future<void> _saveToCache(String pageId, ProcessedText processedText) async {
    try {
      // 완성된 데이터만 캐싱
      if (processedText.streamingStatus != StreamingStatus.completed) {
        if (kDebugMode) {
          debugPrint('⚠️ [캐시] 미완성 데이터는 캐싱 안함: $pageId (${processedText.streamingStatus.name})');
        }
        return;
      }

      final pageDoc = await _firestore.collection('pages').doc(pageId).get();
      if (!pageDoc.exists) return;
      
      final noteId = pageDoc.data()?['noteId'] as String?;
      if (noteId == null) return;

      final segments = processedText.units.map((unit) => {
        'original': unit.originalText,
        'translated': unit.translatedText ?? '',
        'pinyin': unit.pinyin ?? '',
        'sourceLanguage': unit.sourceLanguage,
        'targetLanguage': unit.targetLanguage,
      }).toList();
      
      await _cacheManager.cacheNoteContent(
        noteId: noteId,
        pageId: pageId,
        dataMode: 'segment',
        type: 'processed_text',
        content: {
          'segments': segments,
          'mode': processedText.mode.toString(),
          'fullOriginalText': processedText.fullOriginalText,
          'fullTranslatedText': processedText.fullTranslatedText,
          'sourceLanguage': processedText.sourceLanguage,
          'targetLanguage': processedText.targetLanguage,
        },
      );
      
      if (kDebugMode) {
        debugPrint('💾 [캐시] 저장 완료: $pageId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 캐시 저장 실패: $pageId, $e');
      }
    }
  }
  
  // === Private Firestore Methods ===
  
  /// Firestore에서 ProcessedText 로드
  Future<ProcessedText?> _getFromFirestore(String pageId) async {
    try {
      final doc = await _firestore.collection('pages').doc(pageId).get();
      if (!doc.exists) return null;
      
      final page = page_model.Page.fromFirestore(doc);
      
      // processedText 필드 우선
      if (page.processedText != null && page.processedText!.isNotEmpty) {
        return await _createProcessedTextFromPageData(page);
      }
      
      // 호환성 모드
      if (page.translatedText != null && page.translatedText!.isNotEmpty) {
        return await _createProcessedTextFromPage(page);
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }
  
  /// Page의 processedText 필드에서 ProcessedText 생성
  Future<ProcessedText?> _createProcessedTextFromPageData(page_model.Page page) async {
    if (page.processedText == null || page.processedText!.isEmpty) {
      return null;
    }
    
    try {
      final processedData = page.processedText!;
      
      // units 배열에서 TextUnit 리스트 생성
      List<TextUnit> units = [];
      if (processedData['units'] != null && processedData['units'] is List) {
        units = (processedData['units'] as List)
            .map((unitData) => TextUnit.fromJson(Map<String, dynamic>.from(unitData)))
            .toList();
      }
      
      // 스트리밍 상태 파싱
      StreamingStatus streamingStatus = StreamingStatus.preparing;
      if (processedData['streamingStatus'] != null) {
        try {
          final statusIndex = processedData['streamingStatus'] as int;
          if (statusIndex >= 0 && statusIndex < StreamingStatus.values.length) {
            streamingStatus = StreamingStatus.values[statusIndex];
          }
        } catch (e) {
          // 파싱 실패 시 기본값 사용
        }
      }
      
      return ProcessedText(
        mode: _parseTextModeFromString(processedData['mode']),
        displayMode: _parseDisplayModeFromString(processedData['displayMode']),
        fullOriginalText: processedData['fullOriginalText']?.toString() ?? '',
        fullTranslatedText: processedData['fullTranslatedText']?.toString() ?? '',
        units: units,
        sourceLanguage: processedData['sourceLanguage']?.toString() ?? page.sourceLanguage,
        targetLanguage: processedData['targetLanguage']?.toString() ?? page.targetLanguage,
        streamingStatus: streamingStatus,
        completedUnits: processedData['completedUnits'] as int? ?? 0,
        progress: (processedData['progress'] as num?)?.toDouble() ?? 0.0,
      );
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ processedText 파싱 실패: $e');
      }
      return null;
    }
  }
  
  /// Page 객체에서 ProcessedText 생성 (호환성 모드)
  Future<ProcessedText?> _createProcessedTextFromPage(page_model.Page page) async {
    if (page.translatedText == null || page.translatedText!.isEmpty) {
      return null;
    }
    
    List<TextUnit> units = [];
    
    if (page.processedText != null && 
        page.processedText!['units'] != null &&
        (page.processedText!['units'] as List).isNotEmpty) {
      // processedText에서 개별 세그먼트 복원
      units = (page.processedText!['units'] as List)
          .map((unitData) => TextUnit.fromJson(Map<String, dynamic>.from(unitData)))
          .toList();
    } else {
      // 단일 유닛으로 fallback
      units = [
        TextUnit(
          originalText: page.originalText ?? '',
          translatedText: page.translatedText ?? '',
          pinyin: page.pinyin ?? '',
          sourceLanguage: page.sourceLanguage,
          targetLanguage: page.targetLanguage,
        ),
      ];
    }
    
    // 사용자 설정에 따른 모드 적용
    final userPrefs = await _preferencesService.getPreferences();
    final mode = userPrefs.useSegmentMode ? TextProcessingMode.segment : TextProcessingMode.paragraph;
    
    return ProcessedText(
      mode: mode,
      displayMode: TextDisplayMode.full,
      fullOriginalText: page.originalText ?? '',
      fullTranslatedText: page.translatedText ?? '',
      units: units,
      sourceLanguage: page.sourceLanguage,
      targetLanguage: page.targetLanguage,
      streamingStatus: StreamingStatus.completed, // 호환성 모드는 완성된 상태
    );
  }
  
  // === Utility Methods ===
  
  /// ProcessedText 변경 감지
  bool _hasProcessedTextChanged(ProcessedText? previous, ProcessedText current) {
    if (previous == null) return true;
    
    // 핵심 필드 비교
    if (previous.fullOriginalText != current.fullOriginalText ||
        previous.fullTranslatedText != current.fullTranslatedText ||
        previous.units.length != current.units.length ||
        previous.streamingStatus != current.streamingStatus ||
        previous.progress != current.progress) {
      
      if (kDebugMode) {
        debugPrint('📝 [변경감지] ProcessedText 변경됨:');
        debugPrint('   유닛 수: ${previous.units.length} → ${current.units.length}');
        debugPrint('   스트리밍: ${previous.streamingStatus.name} → ${current.streamingStatus.name}');
        debugPrint('   진행률: ${(previous.progress * 100).toInt()}% → ${(current.progress * 100).toInt()}%');
      }
      return true;
    }
    
    return false;
  }
  
  /// 문자열에서 TextProcessingMode 파싱
  TextProcessingMode _parseTextModeFromString(dynamic modeString) {
    if (modeString == null) return TextProcessingMode.segment;
    
    try {
      return TextProcessingMode.values.firstWhere(
        (e) => e.toString() == modeString.toString()
      );
    } catch (e) {
      return TextProcessingMode.segment;
    }
  }
  
  /// 문자열에서 TextDisplayMode 파싱
  TextDisplayMode _parseDisplayModeFromString(dynamic displayModeString) {
    if (displayModeString == null) return TextDisplayMode.full;
    
    try {
      return TextDisplayMode.values.firstWhere(
        (e) => e.toString() == displayModeString.toString()
      );
    } catch (e) {
      return TextDisplayMode.full;
    }
  }
} 