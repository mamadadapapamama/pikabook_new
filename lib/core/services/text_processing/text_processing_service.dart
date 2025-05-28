import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/models/processed_text.dart';
import '../../../core/models/text_unit.dart';
import '../../../core/models/processing_status.dart';
import '../../../core/models/page.dart' as page_model;
import '../cache/unified_cache_service.dart';
import '../authentication/user_preferences_service.dart';

/// 텍스트 처리 통합 서비스
/// 캐시 관리와 실시간 리스너 관리를 담당
class TextProcessingService {
  // 싱글톤 패턴
  static final TextProcessingService _instance = TextProcessingService._internal();
  factory TextProcessingService() => _instance;
  TextProcessingService._internal();
  
  // 기존 서비스들
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  final UserPreferencesService _preferencesService = UserPreferencesService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // 실시간 리스너 관리
  final Map<String, StreamSubscription<DocumentSnapshot>> _pageListeners = {};
  
  // 스트리밍 컨트롤러 관리
  final Map<String, StreamController<ProcessedText>> _streamControllers = {};

  /// 스트리밍 방식으로 텍스트 처리 시작
  /// 원문을 먼저 보여주고 번역 결과를 점진적으로 업데이트
  Stream<ProcessedText> startStreamingProcessing({
    required String pageId,
    required List<String> originalSegments,
    required TextProcessingMode mode,
    required String sourceLanguage,
    required String targetLanguage,
  }) {
    if (kDebugMode) {
      debugPrint('🎬 스트리밍 처리 시작: $pageId (${originalSegments.length}개 세그먼트)');
    }

    // 기존 스트림 정리
    _streamControllers[pageId]?.close();
    
    // 새 스트림 컨트롤러 생성
    final controller = StreamController<ProcessedText>.broadcast();
    _streamControllers[pageId] = controller;

    // 즉시 원문만 있는 ProcessedText 전송
    final initialProcessedText = ProcessedText.withOriginalOnly(
      mode: mode,
      originalSegments: originalSegments,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
    
    controller.add(initialProcessedText);
    
    if (kDebugMode) {
      debugPrint('📤 초기 원문 전송 완료: ${originalSegments.length}개 세그먼트');
    }

    // 백그라운드에서 번역 처리 시작
    _processTranslationInBackground(
      pageId: pageId,
      processedText: initialProcessedText,
      controller: controller,
    );

    return controller.stream;
  }

  /// 백그라운드에서 번역 처리 및 점진적 업데이트
  Future<void> _processTranslationInBackground({
    required String pageId,
    required ProcessedText processedText,
    required StreamController<ProcessedText> controller,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 백그라운드 번역 처리 시작: $pageId');
      }

      var currentProcessedText = processedText;

      // 각 세그먼트를 순차적으로 처리
      for (int i = 0; i < processedText.units.length; i++) {
        if (controller.isClosed) break;

        final unit = processedText.units[i];
        
        if (kDebugMode) {
          debugPrint('🔤 세그먼트 ${i + 1}/${processedText.units.length} 번역 중: "${unit.originalText.substring(0, unit.originalText.length > 20 ? 20 : unit.originalText.length)}..."');
        }

        try {
          // 개별 세그먼트 번역 (실제 LLM 호출)
          final translatedUnit = await _translateSingleSegment(unit);
          
          // ProcessedText 업데이트
          currentProcessedText = currentProcessedText.updateUnit(i, translatedUnit);
          
          // 스트림으로 업데이트된 결과 전송
          if (!controller.isClosed) {
            controller.add(currentProcessedText);
            
            if (kDebugMode) {
              debugPrint('📤 세그먼트 ${i + 1} 번역 완료 전송: "${translatedUnit.translatedText?.substring(0, translatedUnit.translatedText!.length > 20 ? 20 : translatedUnit.translatedText!.length)}..."');
            }
          }

          // 부드러운 애니메이션을 위한 짧은 지연
          await Future.delayed(const Duration(milliseconds: 300));

        } catch (e) {
          if (kDebugMode) {
            debugPrint('❌ 세그먼트 ${i + 1} 번역 실패: $e');
          }
          
          // 실패한 경우 원본만 유지
          final failedUnit = unit.copyWith(
            translatedText: '', // 빈 번역
            pinyin: '', // 빈 병음
          );
          
          currentProcessedText = currentProcessedText.updateUnit(i, failedUnit);
          
          if (!controller.isClosed) {
            controller.add(currentProcessedText);
          }
        }
      }

      // 최종 완료 상태로 업데이트
      final finalProcessedText = currentProcessedText.copyWith(
        streamingStatus: StreamingStatus.completed,
      );
      
      if (!controller.isClosed) {
        controller.add(finalProcessedText);
      }

      // 캐시에 저장
      await _saveToCache(pageId, finalProcessedText);

      if (kDebugMode) {
        debugPrint('✅ 스트리밍 처리 완료: $pageId');
      }

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 백그라운드 번역 처리 실패: $pageId, $e');
      }
      
      // 실패 상태로 업데이트
      final failedProcessedText = processedText.copyWith(
        streamingStatus: StreamingStatus.failed,
      );
      
      if (!controller.isClosed) {
        controller.add(failedProcessedText);
      }
    } finally {
      // 스트림 정리
      if (!controller.isClosed) {
        controller.close();
      }
      _streamControllers.remove(pageId);
    }
  }

  /// 단일 세그먼트 번역 (실제 LLM 호출)
  Future<TextUnit> _translateSingleSegment(TextUnit unit) async {
    // 여기서 실제 LLM API 호출
    // 임시로 시뮬레이션 (실제로는 LLMTextProcessing 서비스 사용)
    
    await Future.delayed(Duration(milliseconds: 500 + (unit.originalText.length * 50)));
    
    // 실제 구현에서는 LLM API 호출
    return unit.copyWith(
      translatedText: '${unit.originalText}의 번역', // 임시 번역
      pinyin: '${unit.originalText}의 병음', // 임시 병음
    );
  }

  /// 스트림 정리
  void cancelStreamingProcessing(String pageId) {
    _streamControllers[pageId]?.close();
    _streamControllers.remove(pageId);
  }

  /// 모든 스트림 정리
  void cancelAllStreamingProcessing() {
    for (final controller in _streamControllers.values) {
      controller.close();
    }
    _streamControllers.clear();
  }
  
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
    
    // 기존 리스너 정리
    _pageListeners[pageId]?.cancel();
    
    // 이전 데이터 추적을 위한 변수
    ProcessedText? previousProcessedText;
    
    final listener = _firestore
        .collection('pages')
        .doc(pageId)
        .snapshots()
        .listen((snapshot) async {
      if (!snapshot.exists) return;
      
      try {
        final page = page_model.Page.fromFirestore(snapshot);
        
        // 번역 텍스트가 업데이트된 경우
        if (page.translatedText != null && page.translatedText!.isNotEmpty) {
          final processedText = await _createProcessedTextFromPage(page);
          
          // processedText가 null이 아닌 경우에만 처리
          if (processedText != null) {
            // 이전 데이터와 비교하여 실제 변경이 있는지 확인
            if (_hasProcessedTextChanged(previousProcessedText, processedText)) {
              // 캐시 업데이트
              await _saveToCache(pageId, processedText);
              
              // 콜백 호출
              onTextChanged(processedText);
              
              if (kDebugMode) {
                debugPrint('🔔 페이지 텍스트 변경 감지: $pageId');
              }
              
              // 현재 데이터를 이전 데이터로 저장
              previousProcessedText = processedText;
            } else {
              if (kDebugMode) {
                debugPrint('⏭️ 페이지 텍스트 변경 없음 (스킵): $pageId');
              }
            }
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
    return listener;
  }
  
  /// ProcessedText 객체가 실제로 변경되었는지 확인
  bool _hasProcessedTextChanged(ProcessedText? previous, ProcessedText current) {
    if (previous == null) return true;
    
    // 기본 속성 비교
    if (previous.fullOriginalText != current.fullOriginalText ||
        previous.fullTranslatedText != current.fullTranslatedText ||
        previous.mode != current.mode ||
        previous.units.length != current.units.length) {
      return true;
    }
    
    // 개별 유닛 비교
    for (int i = 0; i < previous.units.length; i++) {
      final prevUnit = previous.units[i];
      final currUnit = current.units[i];
      
      if (prevUnit.originalText != currUnit.originalText ||
          prevUnit.translatedText != currUnit.translatedText ||
          prevUnit.pinyin != currUnit.pinyin) {
        return true;
      }
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
    
    // 스트림도 정리
    cancelAllStreamingProcessing();
  }
  
  // === Private Methods ===
  
  /// 캐시에서 텍스트 가져오기
  Future<ProcessedText?> _getFromCache(String pageId) async {
    try {
      final segments = await _cacheService.getSegments(pageId, TextProcessingMode.segment);
      if (segments == null || segments.isEmpty) return null;
      
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
  
  /// 캐시에 텍스트 저장
  Future<void> _saveToCache(String pageId, ProcessedText processedText) async {
    try {
      final segments = processedText.units.map((unit) => {
        'original': unit.originalText,
        'translated': unit.translatedText ?? '',
        'pinyin': unit.pinyin ?? '',
        'sourceLanguage': unit.sourceLanguage,
        'targetLanguage': unit.targetLanguage,
      }).toList();
      
      await _cacheService.cacheSegments(pageId, processedText.mode, segments);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 캐시 저장 실패: $pageId, $e');
      }
    }
  }
} 