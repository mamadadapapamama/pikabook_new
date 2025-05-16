import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../core/models/processed_text.dart';
import '../../../core/models/text_segment.dart';
import '../../../core/models/dictionary.dart';
import '../../../core/services/content/page_service.dart';
import '../../../core/services/media/tts_service.dart';
import '../../../core/services/dictionary/dictionary_service.dart';
import '../../../core/services/storage/unified_cache_service.dart';
import '../../../core/services/common/usage_limit_service.dart';
import '../../../LLM test/llm_text_processing.dart';
import 'dart:async';

/// 세그먼트(문장)와 관련된 모든 기능을 중앙화하는 매니저
/// - 페이지 캐시(processed text, LLM 처리 결과를 저장 조회 삭제)
/// - 사전 검색 (내부/외부 API 통합)
/// - 세그먼트 삭제/수정/처리
/// - TTS 서비스 연동 (세그먼트 + 전체 텍스트)
/// - TTS 사용량 제한 확인 및 관리

class SegmentManager {
  static final SegmentManager _instance = () {
    if (kDebugMode) debugPrint('🏭 SegmentManager: 싱글톤 인스턴스 생성 시작');
    final instance = SegmentManager._internal();
    if (kDebugMode) debugPrint('🏭 SegmentManager: 싱글톤 인스턴스 생성 완료');
    return instance;
  }();
  
  factory SegmentManager() {
    if (kDebugMode) debugPrint('🏭 SegmentManager: 팩토리 생성자 호출됨 (싱글톤 반환)');
    return _instance;
  }
  
  // 필요한 서비스들
  late final PageService _pageService = PageService();
  late final TtsService _ttsService = TtsService();
  late final DictionaryService _dictionaryService = DictionaryService();
  late final UnifiedCacheService _cacheService = UnifiedCacheService();
  late final UsageLimitService _usageLimitService = UsageLimitService();
  
  // TTS 상태 관련 변수
  int? _currentPlayingSegmentIndex;
  bool _isTtsInitialized = false;
  Timer? _ttsTimeoutTimer;
  
  // TTS 콜백 (UI 상태 관리용)
  Function(int?)? _onTtsStateChanged;
  Function()? _onTtsCompleted;
  
  // TTS 제한 관련 변수
  bool _isCheckingTtsLimit = false;
  Map<String, dynamic>? _ttsLimitStatus;
  Map<String, double>? _ttsUsagePercentages;
  
  // getter
  TtsService get ttsService => _ttsService;
  int? get currentPlayingSegmentIndex => _currentPlayingSegmentIndex;
  bool get isTtsInitialized => _isTtsInitialized;

  SegmentManager._internal() {
    _initTts();
  }
  
  // TTS 초기화
  Future<void> _initTts() async {
    if (_isTtsInitialized) return;
    
    try {
      await _ttsService.init();
      
      // TTS 상태 변경 리스너
      _ttsService.setOnPlayingStateChanged((segmentIndex) {
        _currentPlayingSegmentIndex = segmentIndex;
        if (_onTtsStateChanged != null) {
          _onTtsStateChanged!(segmentIndex);
        }
        debugPrint('TTS 상태 변경: 세그먼트 인덱스 = $segmentIndex');
      });
      
      // TTS 재생 완료 리스너
      _ttsService.setOnPlayingCompleted(() {
        _currentPlayingSegmentIndex = null;
        if (_onTtsCompleted != null) {
          _onTtsCompleted!();
        }
        debugPrint('TTS 재생 완료');
      });
      
      _isTtsInitialized = true;
      debugPrint('✅ TTS 서비스 초기화 완료');
    } catch (e) {
      debugPrint('❌ TTS 서비스 초기화 오류: $e');
    }
  }
  
  // TTS 상태 변경 콜백 설정
  void setOnTtsStateChanged(Function(int?) callback) {
    _onTtsStateChanged = callback;
  }
  
  // TTS 재생 완료 콜백 설정
  void setOnTtsCompleted(Function() callback) {
    _onTtsCompleted = callback;
  }
  
  // TTS 제한 확인
  Future<Map<String, dynamic>> checkTtsLimit() async {
    if (_isCheckingTtsLimit) {
      return {'ttsLimitReached': false, 'message': '이미 확인중'};
    }
    
    _isCheckingTtsLimit = true;
    
    try {
      _ttsLimitStatus = await _usageLimitService.checkFreeLimits();
      _ttsUsagePercentages = await _usageLimitService.getUsagePercentages();
      
      _isCheckingTtsLimit = false;
      
      return {
        'ttsLimitReached': _ttsLimitStatus?['ttsLimitReached'] == true,
        'limitStatus': _ttsLimitStatus,
        'usagePercentages': _ttsUsagePercentages,
      };
    } catch (e) {
      debugPrint('TTS 제한 확인 중 오류: $e');
      _isCheckingTtsLimit = false;
      return {'ttsLimitReached': false, 'error': e.toString()};
    }
  }

  // TTS 텍스트 재생 (세그먼트 인덱스 포함)
  Future<bool> playTts(String text, {int? segmentIndex}) async {
    if (!_isTtsInitialized) {
      await _initTts();
    }
    
    if (text.isEmpty) {
      debugPrint('⚠️ TTS: 재생할 텍스트가 비어있습니다');
      return false;
    }
    
    try {
      // 현재 재생 중인 세그먼트를 다시 클릭한 경우 중지
      if (_currentPlayingSegmentIndex == segmentIndex) {
        await stopSpeaking();
        return true;
      }
      
      // TTS 제한 확인
      final limitCheck = await checkTtsLimit();
      if (limitCheck['ttsLimitReached'] == true) {
        debugPrint('⚠️ TTS: 사용 제한에 도달했습니다');
        return false;
      }
      
      // 타임아웃 타이머 설정 (안전장치)
      _setupTtsTimeoutTimer(segmentIndex);
      
      // 상태 업데이트 (UI 변경 즉시 반영 위해)
      _currentPlayingSegmentIndex = segmentIndex;
      if (_onTtsStateChanged != null) {
        _onTtsStateChanged!(segmentIndex);
      }
      
      // 세그먼트 인덱스에 따라 처리
      if (segmentIndex != null) {
        await _ttsService.speak(text);
      } else {
        await _ttsService.speak(text);
      }
      
      debugPrint('✅ TTS 재생 시작: ${text.length > 20 ? text.substring(0, 20) + '...' : text}');
      return true;
    } catch (e) {
      debugPrint('❌ TTS 재생 중 오류: $e');
      
      // 오류 발생 시 상태 리셋
      _currentPlayingSegmentIndex = null;
      if (_onTtsStateChanged != null) {
        _onTtsStateChanged!(null);
      }
      
      return false;
    }
  }
  
  // TTS 타임아웃 타이머 설정 (장시간 재생 시 상태가 막히는 것을 방지)
  void _setupTtsTimeoutTimer(int? segmentIndex) {
    _ttsTimeoutTimer?.cancel();
    
    _ttsTimeoutTimer = Timer(const Duration(seconds: 30), () {
      if (_currentPlayingSegmentIndex == segmentIndex) {
        debugPrint('⚠️ TTS 타임아웃: 상태 리셋');
        _currentPlayingSegmentIndex = null;
        if (_onTtsStateChanged != null) {
          _onTtsStateChanged!(null);
        }
      }
    });
  }
  
  // TTS 중지
  Future<void> stopSpeaking() async {
    await _ttsService.stop();
    
    // 상태 리셋
    _currentPlayingSegmentIndex = null;
    if (_onTtsStateChanged != null) {
      _onTtsStateChanged!(null);
    }
    
    debugPrint('🛑 TTS 중지됨');
  }
  
  // 일반 텍스트 재생 (이전 메서드와 통합)
  Future<void> speakText(String text) async {
    await playTts(text);
  }

  // ProcessedText 캐시 메서드들
  Future<bool> hasProcessedText(String pageId) async {
    final processedText = await _cacheService.getProcessedText(pageId);
    return processedText != null;
  }
  
  Future<ProcessedText?> getProcessedText(String pageId) async {
    try {
      return await _cacheService.getProcessedText(pageId);
    } catch (e) {
      if (kDebugMode) debugPrint('처리된 텍스트 조회 중 오류: $e');
      return null;
    }
  }
  
  Future<void> setProcessedText(String pageId, ProcessedText processedText) async {
    try {
      await _cacheService.setProcessedText(pageId, processedText);
    } catch (e) {
      if (kDebugMode) debugPrint('ProcessedText 캐싱 중 오류: $e');
    }
  }
  
  Future<void> removeProcessedText(String pageId) async {
    try {
      await _cacheService.removeProcessedText(pageId);
    } catch (e) {
      if (kDebugMode) debugPrint('ProcessedText 캐시 제거 중 오류: $e');
    }
  }
  
  Future<void> clearProcessedTextCache() async {
    try {
      _cacheService.clearCache();
    } catch (e) {
      if (kDebugMode) debugPrint('전체 캐시 초기화 중 오류: $e');
    }
  }
  
  // 사전 검색 (내부 + 외부 API 통합)
  Future<DictionaryEntry?> lookupWord(String word) async {
    if (word.isEmpty) {
      debugPrint('⚠️ 사전: 검색할 단어가 비어있습니다');
      return null;
    }
    
    debugPrint('🔍 사전 검색 시작: "$word"');
    
    try {
      // 1. 먼저 내부 사전에서 검색
      final result = await _dictionaryService.lookupWord(word);
      
      if (result['success'] == true && result['entry'] != null) {
        debugPrint('✅ 내부 사전에서 단어 찾음: $word');
        return result['entry'] as DictionaryEntry;
      }
      
      // 2. 내부 사전에서 찾지 못한 경우, 외부 API로 검색
      debugPrint('⚠️ 내부 사전에서 단어를 찾지 못해 외부 API 사용을 시도합니다');
      final externalResult = await _dictionaryService.lookupWord(word);
      
      if (externalResult['success'] == true && externalResult['entry'] != null) {
        debugPrint('✅ 외부 API에서 단어 찾음: $word');
        return externalResult['entry'] as DictionaryEntry;
      }
      
      // 3. 모든 검색에서 실패한 경우
      debugPrint('❌ 모든 사전에서 단어를 찾지 못했습니다: $word');
      return null;
    } catch (e) {
      debugPrint('❌ 사전 검색 중 오류 발생: $e');
      return null;
    }
  }
  
  // 세그먼트 삭제 처리 (기존 메서드 확장)
  Future<page_model.Page?> deleteSegment({
    required String noteId,
    required page_model.Page page,
    required int segmentIndex,
  }) async {
    if (page.id == null) return null;
    
    debugPrint('🗑️ 세그먼트 삭제 시작: 페이지 ${page.id}의 세그먼트 $segmentIndex');
    
    try {
      // 1. ProcessedText 캐시에서 가져오기
      if (!(await hasProcessedText(page.id!))) {
        debugPrint('⚠️ ProcessedText가 없어 세그먼트를 삭제할 수 없습니다');
        return null;
      }
      
      final processedText = await getProcessedText(page.id!);
      if (processedText == null || 
          processedText.segments == null || 
          segmentIndex >= processedText.segments!.length) {
        debugPrint('⚠️ 유효하지 않은 ProcessedText 또는 세그먼트 인덱스');
        return null;
      }
      
      // 2. 전체 텍스트 모드에서는 세그먼트 삭제 불가
      if (processedText.showFullText) {
        debugPrint('⚠️ 전체 텍스트 모드에서는 세그먼트 삭제가 불가능합니다');
        return null;
      }
      
      // 3. 세그먼트 삭제 및 전체 텍스트 업데이트
      final updatedSegments = List<TextSegment>.from(processedText.segments!);
      updatedSegments.removeAt(segmentIndex);
      
      // 4. 전체 텍스트 다시 조합
      String updatedFullOriginalText = '';
      String updatedFullTranslatedText = '';
      
      for (final segment in updatedSegments) {
        updatedFullOriginalText += segment.originalText;
        if (segment.translatedText != null) {
          updatedFullTranslatedText += segment.translatedText!;
        }
      }
      
      // 5. 업데이트된 ProcessedText 생성
      final updatedProcessedText = processedText.copyWith(
        segments: updatedSegments,
        fullOriginalText: updatedFullOriginalText,
        fullTranslatedText: updatedFullTranslatedText,
        showFullText: processedText.showFullText,
        showPinyin: processedText.showPinyin,
        showTranslation: processedText.showTranslation,
      );
      
      // 6. 캐시 업데이트
      await setProcessedText(page.id!, updatedProcessedText);
      await updatePageCache(page.id!, updatedProcessedText, "languageLearning");
      
      // 7. Firestore DB 업데이트
      try {
        final updatedPageResult = await _pageService.updatePageContent(
          page.id!,
          updatedFullOriginalText,
          updatedFullTranslatedText,
        );
        
        if (updatedPageResult == null) {
          debugPrint('⚠️ Firestore 페이지 업데이트 실패');
          return null;
        }
        
        // 8. 페이지 캐시 업데이트
        await _cacheService.cachePage(noteId, updatedPageResult);
        
        debugPrint('✅ 세그먼트 삭제 후 업데이트 완료');
        return updatedPageResult;
      } catch (e) {
        debugPrint('❌ 세그먼트 삭제 후 페이지 업데이트 중 오류 발생: $e');
        return null;
      }
    } catch (e) {
      debugPrint('❌ 세그먼트 삭제 중 예외 발생: $e');
      return null;
    }
  }
  
  // 텍스트 표시 모드 업데이트
  Future<void> updateTextDisplayMode({
    required String pageId,
    required bool showFullText,
    required bool showPinyin,
    required bool showTranslation,
  }) async {
    if (!(await hasProcessedText(pageId))) return;
    
    final processedText = await getProcessedText(pageId);
    if (processedText == null) return;
    
    final updatedProcessedText = processedText.copyWith(
      showFullText: showFullText,
      showPinyin: showPinyin,
      showTranslation: showTranslation,
    );
    
    await setProcessedText(pageId, updatedProcessedText);
  }
  
  // 페이지 캐시 업데이트
  Future<void> updatePageCache(
    String pageId,
    ProcessedText processedText,
    String textProcessingMode,
  ) async {
    try {
      await setProcessedText(pageId, processedText);
      await _pageService.cacheProcessedText(
        pageId,
        processedText,
        textProcessingMode,
      );
    } catch (e) {
      debugPrint('❌ 페이지 캐시 업데이트 중 오류 발생: $e');
    }
  }
  
  // LLM 기반 세그먼트 처리용 processPageText 메서드
  Future<ProcessedText?> processPageText({
    required page_model.Page page,
    File? imageFile,
  }) async {
    debugPrint('🔄 페이지 텍스트 처리 시작: ${page.id}');
    
    // 페이지 ID가 없는 경우 처리 불가
    if (page.id == null) {
      debugPrint('⚠️ 페이지 ID가 null이어서 처리할 수 없습니다');
      return null;
    }
    
    try {
      // 이미 처리된 텍스트가 있는지 확인 (캐시)
      final cachedText = await getProcessedText(page.id!);
      if (cachedText != null) {
        debugPrint('✅ 캐시에서 이미 처리된 텍스트를 찾았습니다');
        return cachedText;
      }
      
      // 여기서는 실제 텍스트 처리가 LLM에서 이루어졌다고 가정하고,
      // 단순히 캐시에서 반환만 합니다.
      // 실제 LLM 처리 로직을 추가하려면 이 부분을 확장해야 합니다.
      debugPrint('⚠️ 처리된 텍스트가 없습니다');
      return null;
    } catch (e) {
      debugPrint('❌ 페이지 텍스트 처리 중 오류 발생: $e');
      return null;
    }
  }
  
  // 자원 정리
  void dispose() {
    _ttsTimeoutTimer?.cancel();
    _ttsService.dispose();
    _onTtsStateChanged = null;
    _onTtsCompleted = null;
  }
}
