import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/models/processed_text.dart';
import '../../../core/models/text_unit.dart';
import '../../../core/models/processing_status.dart';
import '../../../core/models/page.dart' as page_model;
import '../cache/cache_manager.dart';
import '../authentication/user_preferences_service.dart';

/// 텍스트 처리 통합 서비스
/// 캐시 관리와 실시간 리스너 관리를 담당
class TextProcessingService {
  // 싱글톤 패턴
  static final TextProcessingService _instance = TextProcessingService._internal();
  factory TextProcessingService() => _instance;
  TextProcessingService._internal();
  
  // 기존 서비스들
  final CacheManager _cacheManager = CacheManager();
  final UserPreferencesService _preferencesService = UserPreferencesService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // 실시간 리스너 관리
  final Map<String, StreamSubscription<DocumentSnapshot>> _pageListeners = {};
  
  /// 페이지의 처리된 텍스트 가져오기
  /// 캐시 → Firestore 순으로 확인
  Future<ProcessedText?> getProcessedText(String pageId) async {
    if (pageId.isEmpty) return null;
    
    try {
      // 1. 캐시에서 먼저 확인
      final cachedText = await _getFromCache(pageId);
      if (cachedText != null) {
        if (kDebugMode) {
          debugPrint('✅ 캐시에서 텍스트 로드: $pageId');
        }
        return cachedText;
      }
      
      // 2. Firestore에서 확인
      final firestoreText = await _getFromFirestore(pageId);
      if (firestoreText != null) {
        // 캐시에 저장
        await _saveToCache(pageId, firestoreText);
        if (kDebugMode) {
          debugPrint('✅ Firestore에서 텍스트 로드: $pageId');
        }
        return firestoreText;
      }
      
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 텍스트 로드 실패: $pageId, $e');
      }
      return null;
    }
  }
  
  /// 페이지 텍스트 처리 상태 확인
  Future<ProcessingStatus> getProcessingStatus(String pageId) async {
    if (pageId.isEmpty) return ProcessingStatus.created;
    
    try {
      final doc = await _firestore.collection('pages').doc(pageId).get();
      if (!doc.exists) return ProcessingStatus.created;
      
      final page = page_model.Page.fromFirestore(doc);
      
      // 번역 텍스트가 있으면 완료
      if (page.translatedText != null && page.translatedText!.isNotEmpty) {
        return ProcessingStatus.completed;
      }
      
      // 원본 텍스트가 있으면 추출 완료
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
  
  /// 텍스트 모드 변경
  Future<ProcessedText?> changeTextMode(String pageId, TextProcessingMode newMode) async {
    if (pageId.isEmpty) return null;
    
    try {
      // 1. 기존 텍스트 로드
      final existing = await getProcessedText(pageId);
      if (existing == null) {
        return null;
      }
      
      // 2. 모드가 같으면 그대로 반환
      if (existing.mode == newMode) {
        return existing;
      }
      
      // 3. 모드 변경된 새 객체 생성
      final updatedText = existing.copyWith(mode: newMode);
      
      // 4. 캐시 업데이트
      await _saveToCache(pageId, updatedText);
      
      if (kDebugMode) {
        debugPrint('✅ 텍스트 모드 변경: $pageId, ${existing.mode} → $newMode');
      }
      
      return updatedText;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 텍스트 모드 변경 실패: $pageId, $e');
      }
      return null;
    }
  }
  
  /// 페이지 변경 실시간 리스너 설정
  StreamSubscription<DocumentSnapshot>? listenToPageChanges(
    String pageId,
    Function(ProcessedText?) onTextChanged,
  ) {
    if (pageId.isEmpty) return null;
    
    if (kDebugMode) {
      debugPrint('🔔 실시간 리스너 설정: $pageId');
    }
    
    // 기존 리스너 정리
    _pageListeners[pageId]?.cancel();
    
    // 이전 데이터 추적을 위한 변수
    ProcessedText? previousProcessedText;
    
    final listener = _firestore
        .collection('pages')
        .doc(pageId)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists) {
        if (kDebugMode) {
          debugPrint('📄 페이지 문서가 존재하지 않음: $pageId');
        }
        return;
      }
      
      if (kDebugMode) {
        debugPrint('🔔 Firestore 변경 감지: $pageId');
      }
      
      try {
        final page = page_model.Page.fromFirestore(snapshot);
        
        if (kDebugMode) {
          debugPrint('📊 페이지 데이터 분석: $pageId');
          debugPrint('   processedText 필드: ${page.processedText != null ? "있음" : "없음"}');
          debugPrint('   translatedText: ${page.translatedText?.isNotEmpty == true ? "있음 (${page.translatedText!.length}자)" : "없음"}');
        }
        
        // processedText 필드가 있으면 ProcessedText 생성 (번역 여부와 관계없이)
        if (page.processedText != null && page.processedText!.isNotEmpty) {
          // 이미 파싱된 ProcessedText인지 확인
          final processedData = page.processedText!;
          
          // 서버에서 완전히 처리된 데이터인지 확인 (units와 번역이 모두 있는 경우)
          final hasCompleteData = processedData['units'] != null && 
                                  processedData['units'] is List &&
                                  (processedData['units'] as List).isNotEmpty &&
                                  processedData['fullTranslatedText'] != null &&
                                  processedData['fullTranslatedText'].toString().isNotEmpty;
          
          if (hasCompleteData) {
            if (kDebugMode) {
              debugPrint('✅ 서버에서 완전히 처리된 데이터 감지: $pageId (중복 파싱 스킵)');
            }
            
            final processedText = await _createProcessedTextFromPageData(page);
            
            if (processedText != null && _hasProcessedTextChanged(previousProcessedText, processedText)) {
              if (kDebugMode) {
                debugPrint('🔄 완전한 ProcessedText 변경 감지됨: $pageId');
                debugPrint('   유닛 개수: ${processedText.units.length}');
                debugPrint('   번역 완료: ${processedText.fullTranslatedText.isNotEmpty}');
              }
              
              await _saveToCache(pageId, processedText);
              onTextChanged(processedText);
              previousProcessedText = processedText;
            }
          } else {
            // 1차 처리된 데이터 (원문만 있는 경우)
            if (kDebugMode) {
              debugPrint('🔍 1차 처리된 데이터 파싱 시작: $pageId');
            }
            
            final processedText = await _createProcessedTextFromPageData(page);
            
            if (processedText != null && _hasProcessedTextChanged(previousProcessedText, processedText)) {
              if (kDebugMode) {
                debugPrint('✅ 1차 ProcessedText 파싱 성공: $pageId');
                debugPrint('   유닛 개수: ${processedText.units.length}');
                debugPrint('   스트리밍 상태: ${processedText.streamingStatus}');
              }
              
              // 1차 데이터는 캐싱하지 않음 (스트리밍 진행 중)
              onTextChanged(processedText);
              previousProcessedText = processedText;
            }
          }
        }
        // 번역 텍스트만 있고 processedText가 없는 경우 (기존 호환성)
        else if (page.translatedText != null && page.translatedText!.isNotEmpty) {
          if (kDebugMode) {
            debugPrint('🔍 호환성 모드: translatedText에서 데이터 생성 시작: $pageId');
          }
          
          final processedText = await _createProcessedTextFromPage(page);
          
          if (processedText != null) {
            if (_hasProcessedTextChanged(previousProcessedText, processedText)) {
              await _saveToCache(pageId, processedText);
              
              if (kDebugMode) {
                debugPrint('📞 호환성 모드 UI 콜백 호출: $pageId');
              }
              
              onTextChanged(processedText);
              
              if (kDebugMode) {
                debugPrint('🔔 페이지 텍스트 변경 감지 (호환성): $pageId');
              }
              
              previousProcessedText = processedText;
            }
          }
        } else {
          if (kDebugMode) {
            debugPrint('ℹ️ 처리할 텍스트 데이터 없음: $pageId');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ 페이지 리스너 처리 실패: $pageId, $e');
        }
        onTextChanged(null);
      }
    });
    
    _pageListeners[pageId] = listener;
    
    if (kDebugMode) {
      debugPrint('✅ 실시간 리스너 설정 완료: $pageId');
    }
    
    return listener;
  }
  
  /// ProcessedText 객체가 실제로 변경되었는지 확인
  bool _hasProcessedTextChanged(ProcessedText? previous, ProcessedText current) {
    if (previous == null) return true;
    
    // StreamingStatus와 진행률 포함한 상세 비교
    if (previous.fullOriginalText != current.fullOriginalText ||
        previous.fullTranslatedText != current.fullTranslatedText ||
        previous.mode != current.mode ||
        previous.displayMode != current.displayMode ||
        previous.units.length != current.units.length ||
        previous.streamingStatus != current.streamingStatus) {
      if (kDebugMode) {
        debugPrint('📝 ProcessedText 변경 감지:');
        debugPrint('   원문 길이: ${previous.fullOriginalText.length} → ${current.fullOriginalText.length}');
        debugPrint('   번역 길이: ${previous.fullTranslatedText.length} → ${current.fullTranslatedText.length}');
        debugPrint('   유닛 수: ${previous.units.length} → ${current.units.length}');
        debugPrint('   스트리밍 상태: ${previous.streamingStatus} → ${current.streamingStatus}');
      }
      return true;
    }
    
    // 개별 유닛 비교 (번역 완료 상태 포함)
    for (int i = 0; i < previous.units.length; i++) {
      final prevUnit = previous.units[i];
      final currUnit = current.units[i];
      
      if (prevUnit.originalText != currUnit.originalText ||
          prevUnit.translatedText != currUnit.translatedText ||
          prevUnit.pinyin != currUnit.pinyin) {
        if (kDebugMode) {
          debugPrint('📝 유닛 $i 변경 감지:');
          debugPrint('   원문: "${prevUnit.originalText}" → "${currUnit.originalText}"');
          debugPrint('   번역: "${prevUnit.translatedText}" → "${currUnit.translatedText}"');
          debugPrint('   병음: "${prevUnit.pinyin}" → "${currUnit.pinyin}"');
        }
        return true;
      }
    }
    
    if (kDebugMode) {
      debugPrint('✅ ProcessedText 변경 없음 (동일한 데이터)');
    }
    return false;
  }
  
  /// 리스너 정리
  void cancelPageListener(String pageId) {
    _pageListeners[pageId]?.cancel();
    _pageListeners.remove(pageId);
  }
  
  /// 모든 리스너 정리
  void cancelAllListeners() {
    for (final listener in _pageListeners.values) {
      listener.cancel();
    }
    _pageListeners.clear();
  }
  
  // === Private Methods ===
  
  /// 캐시에서 텍스트 가져오기
  Future<ProcessedText?> _getFromCache(String pageId) async {
    try {
      // 페이지 정보에서 noteId 추출 필요
      final pageDoc = await _firestore.collection('pages').doc(pageId).get();
      if (!pageDoc.exists) return null;
      
      final noteId = pageDoc.data()?['noteId'] as String?;
      if (noteId == null) return null;
      
      // 캐시에서 세그먼트 데이터 조회
      final cachedData = await _cacheManager.getNoteContent(
        noteId: noteId,
        pageId: pageId,
        dataMode: 'segment',
        type: 'processed_text',
      );
      
      if (cachedData == null || cachedData['segments'] == null) return null;
      
      final segments = cachedData['segments'] as List;
      if (segments.isEmpty) return null;
      
      final units = segments.map((segment) => TextUnit(
        originalText: segment['original'] ?? '',
        translatedText: segment['translated'] ?? '',
        pinyin: segment['pinyin'] ?? '',
        sourceLanguage: segment['sourceLanguage'] ?? 'zh-CN',
        targetLanguage: segment['targetLanguage'] ?? 'ko',
      )).toList();
      
      final fullOriginalText = units.map((u) => u.originalText).join('');
      final fullTranslatedText = units.map((u) => u.translatedText ?? '').join('');
      
      return ProcessedText(
        mode: TextProcessingMode.segment,
        displayMode: TextDisplayMode.full,
        fullOriginalText: fullOriginalText,
        fullTranslatedText: fullTranslatedText,
        units: units,
        sourceLanguage: 'zh-CN',
        targetLanguage: 'ko',
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 캐시에서 텍스트 로드 실패: $pageId, $e');
      }
      return null;
    }
  }
  
  /// Firestore에서 텍스트 가져오기
  Future<ProcessedText?> _getFromFirestore(String pageId) async {
    try {
      final doc = await _firestore.collection('pages').doc(pageId).get();
      if (!doc.exists) return null;
      
      final page = page_model.Page.fromFirestore(doc);
      return await _createProcessedTextFromPage(page);
    } catch (e) {
      return null;
    }
  }
  
  /// Page 객체에서 ProcessedText 생성
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
    );
  }
  
  /// Page의 processedText 필드에서 직접 ProcessedText 생성 (번역 여부와 관계없이)
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
      
      // 모드 파싱
      TextProcessingMode mode = TextProcessingMode.segment;
      if (processedData['mode'] != null) {
        try {
          mode = TextProcessingMode.values.firstWhere(
            (e) => e.toString() == processedData['mode']
          );
        } catch (e) {
          // 파싱 실패 시 기본값 사용
        }
      }
      
      // 표시 모드 파싱
      TextDisplayMode displayMode = TextDisplayMode.full;
      if (processedData['displayMode'] != null) {
        try {
          displayMode = TextDisplayMode.values.firstWhere(
            (e) => e.toString() == processedData['displayMode']
          );
        } catch (e) {
          // 파싱 실패 시 기본값 사용
        }
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
        mode: mode,
        displayMode: displayMode,
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
  
  /// 캐시에 텍스트 저장
  Future<void> _saveToCache(String pageId, ProcessedText processedText) async {
    try {
      // 완성된 ProcessedText만 캐싱 (타이프라이터 효과용 1차 데이터는 캐싱하지 않음)
      if (processedText.streamingStatus != StreamingStatus.completed) {
        if (kDebugMode) {
          debugPrint('⚠️ 미완성 ProcessedText는 캐싱하지 않음: $pageId (상태: ${processedText.streamingStatus})');
        }
        return;
      }

      // 페이지 정보에서 noteId 추출
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
      
      // CacheManager의 cacheNoteContent 사용
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
        debugPrint('✅ 완성된 ProcessedText 캐싱 완료: $pageId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 캐시 저장 실패: $pageId, $e');
      }
    }
  }
} 