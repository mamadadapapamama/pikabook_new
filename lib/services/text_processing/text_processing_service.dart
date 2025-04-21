import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

// 서비스 임포트
import '../../services/storage/unified_cache_service.dart';
import '../../services/text_processing/translation_service.dart';
import '../../services/text_processing/enhanced_ocr_service.dart';
import '../../managers/content_manager.dart';
import '../../services/text_processing/internal_cn_segmenter_service.dart';
import '../../services/text_processing/pinyin_creation_service.dart';
import '../../services/authentication/user_preferences_service.dart';

// 모델 임포트
import '../../models/page.dart' as page_model;
import '../../models/note.dart';
import '../../models/processed_text.dart';
import '../../models/text_segment.dart';

/// 다국어 텍스트 처리를 위한 중앙 통합 워크플로우 서비스
/// 
/// 이 서비스는 다음 기능들을 통합적으로 제공:
/// 1. 텍스트 번역 (TranslationService 활용)
/// 2. 언어별 세그멘테이션
/// 3. 텍스트 발음 생성 (병음 등)
/// 4. 처리된 텍스트 캐싱 (UnifiedCacheService 활용)
///
/// 기존의 NoteDetailTextProcessor와 NoteContentManager의 기능을 통합한 
/// 단일 진입점 서비스입니다.
class TextProcessingService {
  // 싱글톤 패턴
  static final TextProcessingService _instance = TextProcessingService._internal();
  factory TextProcessingService() => _instance;
  TextProcessingService._internal();

  // 필요한 서비스들의 인스턴스
  final TranslationService _translationService = TranslationService();
  final EnhancedOcrService _ocrService = EnhancedOcrService();
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  final ContentManager _contentManager = ContentManager();
  final InternalCnSegmenterService _segmenterService = InternalCnSegmenterService();
  final UserPreferencesService _preferencesService = UserPreferencesService();

  // 언어별 처리기 맵 (확장 가능)
  final Map<String, LanguageProcessor> _languageProcessors = {
    'zh': ChineseProcessor(), // 중국어 처리기
    'ko': KoreanProcessor(),  // 한국어 처리기
    // 추후 더 많은 언어 추가 가능: 'ja': JapaneseProcessor() 등
  };

  /// 페이지 텍스트 처리 (note_detail_text_processor.dart에서 이전)
  Future<ProcessedText?> processPageText({
    required page_model.Page? page,
    required File? imageFile,
  }) async {
    if (page == null) return null;
    
    // ContentManager로 위임
    return await _contentManager.processPageText(
      page: page,
      imageFile: imageFile,
    );
  }

  /// 텍스트 처리 메인 메서드
  /// 
  /// [text]: 처리할 원본 텍스트
  /// [note]: 관련 노트 객체 (언어 정보 포함)
  /// [pageId]: 페이지 ID (캐싱용)
  /// [forceRefresh]: 캐시 무시하고 새로 처리할지 여부
  Future<ProcessedText> processText({
    required String text, 
    required Note note,
    required String pageId,
    bool forceRefresh = false,
  }) async {
    // 1. 캐시 확인 (forceRefresh가 false일 때만)
    if (!forceRefresh) {
      final cachedResult = await _cacheService.getProcessedText(pageId);
      if (cachedResult != null) {
        debugPrint('캐시된 ProcessedText 반환 (페이지ID: $pageId)');
        return cachedResult;
      }
    }

    try {
      debugPrint('새로운 텍스트 처리 시작 (소스언어: ${note.sourceLanguage}, 타겟언어: ${note.targetLanguage})');
      
      // 2. 언어 처리기 가져오기
      final processor = _getProcessorForLanguage(note.sourceLanguage);
      
      // 3. 텍스트 세그멘테이션 수행
      final segments = await processor.segmentText(text);
      
      // 4. 발음 생성 (병음 등)
      final pronunciation = await processor.generatePronunciation(text);
      
      // 5. 번역 수행
      String translatedText = '';
      if (text.isNotEmpty) {
        translatedText = await _translationService.translateText(
          text,
          sourceLanguage: note.sourceLanguage,
          targetLanguage: note.targetLanguage,
        );
      }
      
      // 6. TextSegment 리스트 생성
      final List<TextSegment> textSegments = [];
      for (var segment in segments) {
        final originalText = segment['text'] as String;
        String segmentPinyin = '';
        
        // 6-1. 개별 세그먼트에 대한 발음 추가
        if (note.sourceLanguage.startsWith('zh')) {
          // 중국어인 경우 해당 세그먼트의 병음 찾기
          segmentPinyin = pronunciation[originalText] ?? '';
          
          // 병음이 없고 세그먼트가 한 글자 이상인 경우 개별 처리 시도
          if (segmentPinyin.isEmpty && originalText.length > 1) {
            final processor = ChineseProcessor();
            final segmentPronunciation = await processor.generatePronunciation(originalText);
            segmentPinyin = segmentPronunciation[originalText] ?? '';
          }
        }
        
        textSegments.add(TextSegment(
          originalText: originalText,
          pinyin: segmentPinyin,
          translatedText: '', // 개별 번역은 향후 구현
          sourceLanguage: note.sourceLanguage,
          targetLanguage: note.targetLanguage,
        ));
      }
      
      // 7. ProcessedText 객체 생성
      final processedText = ProcessedText(
        fullOriginalText: text,
        fullTranslatedText: translatedText,
        segments: textSegments,
        showFullText: false,
        showPinyin: true,
        showTranslation: true,
      );
      
      // 8. 결과 캐싱
      await _cacheService.setProcessedText(pageId, processedText);
      
      return processedText;
    } catch (e) {
      debugPrint('텍스트 처리 중 오류 발생: $e');
      // 오류 발생 시 기본 ProcessedText 반환
      return ProcessedText(
        fullOriginalText: text,
        fullTranslatedText: '',
        segments: [],
        showFullText: false,
        showPinyin: true,
        showTranslation: true,
      );
    }
  }

  /// 이미지에서 텍스트 추출 후 처리
  Future<ProcessedText> processImageText({
    required File imageFile,
    required Note note,
    required String pageId,
    bool forceRefresh = false,
  }) async {
    try {
      // 1. OCR로 텍스트 추출
      final extractedText = await _ocrService.extractText(
        imageFile,
        skipUsageCount: false,
      );
      
      // 2. 추출된 텍스트 처리
      return await processText(
        text: extractedText, 
        note: note,
        pageId: pageId,
        forceRefresh: forceRefresh,
      );
    } catch (e) {
      debugPrint('이미지 텍스트 처리 중 오류: $e');
      return ProcessedText(
        fullOriginalText: '',
        fullTranslatedText: '',
        segments: [],
        showFullText: false,
        showPinyin: true,
        showTranslation: true,
      );
    }
  }

  /// 번역 데이터 확인 및 로드 (note_detail_text_processor.dart에서 이전)
  Future<ProcessedText?> checkAndLoadTranslationData({
    required Note note,
    required page_model.Page? page,
    required File? imageFile,
    required ProcessedText? currentProcessedText,
  }) async {
    if (page == null || page.id == null) return currentProcessedText;
    
    // 이미 번역 데이터가 있으면 그대로 반환
    if (currentProcessedText != null && 
        currentProcessedText.fullTranslatedText != null && 
        currentProcessedText.fullTranslatedText!.isNotEmpty) {
      debugPrint('TextProcessingService: 이미 번역 데이터가 있습니다.');
      return currentProcessedText;
    }
    
    // 원본 텍스트가 없으면 처리할 수 없음
    if (page.originalText.isEmpty && imageFile == null) {
      debugPrint('TextProcessingService: 원본 텍스트와 이미지가 모두 없습니다.');
      return currentProcessedText;
    }
    
    debugPrint('TextProcessingService: 번역 데이터 로드 시작');
    
    try {
      // 기존 ProcessedText가 없는 경우 새로 생성
      if (currentProcessedText == null) {
        return await processPageText(
          page: page, 
          imageFile: imageFile,
        );
      }
      
      // ProcessedText는 있지만 번역 데이터가 없는 경우 번역만 추가
      final String originalText = currentProcessedText.fullOriginalText;
      if (originalText.isEmpty) {
        debugPrint('TextProcessingService: 원본 텍스트가 비어 있습니다.');
        return currentProcessedText;
      }
      
      // 번역 실행
      debugPrint('TextProcessingService: 번역 실행');
      final translatedText = await _translationService.translateText(
        originalText,
        sourceLanguage: note.sourceLanguage,
        targetLanguage: note.targetLanguage,
      );
      
      // 번역 결과 적용하여 새 ProcessedText 반환
      return currentProcessedText.copyWith(
        fullTranslatedText: translatedText,
      );
    } catch (e) {
      debugPrint('TextProcessingService: 번역 데이터 로드 중 오류 발생 - $e');
      return currentProcessedText;
    }
  }

  /// 표시 설정 변경 메서드들 (note_detail_text_processor.dart에서 이전)
  ProcessedText toggleDisplayMode(ProcessedText processedText) {
    return processedText.toggleDisplayMode();
  }

  /// 캐시 관련 메서드들 (note_detail_text_processor.dart에서 이전)
  Future<ProcessedText?> getProcessedText(String? pageId) async {
    if (pageId == null) return null;
    return await _cacheService.getProcessedText(pageId);
  }
  
  Future<void> setProcessedText(String? pageId, ProcessedText processedText) async {
    if (pageId == null) return;
    await _cacheService.setProcessedText(pageId, processedText);
    
    // 페이지 캐시도 함께 업데이트
    await _contentManager.updatePageCache(
      pageId, 
      processedText,
      "languageLearning"
    );
  }
  
  Future<void> clearProcessedTextCache(String? pageId) async {
    if (pageId == null) return;
    await _cacheService.removeProcessedText(pageId);
  }

  /// 언어 코드에 맞는 처리기 반환
  LanguageProcessor _getProcessorForLanguage(String language) {
    // 언어 코드에서 기본 언어 추출 (예: zh-CN → zh)
    final baseLanguage = language.split('-')[0].toLowerCase();
    
    // 해당 언어 처리기 반환 (없으면 기본 처리기)
    return _languageProcessors[baseLanguage] ?? GenericProcessor();
  }

  // 사용자 선호 설정에 따른 모드 로드 메서드 추가
  Future<bool> loadAndApplyUserPreferences(String? pageId) async {
    try {
      // pageId가 null이면 기본값 반환
      if (pageId == null) {
        return true; // 기본값은 세그먼트 모드
      }
      
      // 사용자가 선택한 모드 가져오기
      final useSegmentMode = await _preferencesService.getUseSegmentMode();
      
      // 페이지에 현재 저장된 ProcessedText 확인
      final currentProcessedText = await getProcessedText(pageId);
      if (currentProcessedText != null) {
        // 사용자 선호에 맞게 ProcessedText 업데이트
        final updatedText = currentProcessedText.copyWith(
          showFullText: !useSegmentMode, // 세그먼트 모드가 true면 showFullText는 false
        );
        
        // 업데이트된 설정 저장
        await setProcessedText(pageId, updatedText);
      }
      
      return useSegmentMode;
    } catch (e) {
      debugPrint('사용자 기본 설정 로드 중 오류 발생: $e');
      // 오류 발생 시 기본 모드 사용
      return true; // 기본값은 세그먼트 모드
    }
  }

  // 페이지 처리 및 번역 통합 메서드
  Future<ProcessedText?> processAndPreparePageContent({
    required page_model.Page page, 
    required File? imageFile,
    required Note note
  }) async {
    try {
      // 1. 텍스트 처리 (캐시에 없는 경우)
      final processedText = await processPageText(
        page: page,
        imageFile: imageFile,
      );
      
      if (processedText != null && page.id != null) {
        // 2. 기본 표시 설정 지정
        final useSegmentMode = await _preferencesService.getUseSegmentMode();
        final updatedProcessedText = processedText.copyWith(
          showFullText: !useSegmentMode, // 현재 선택된 모드 적용
          showPinyin: true,              // 병음 표시는 기본적으로 활성화
          showTranslation: true,         // 번역은 항상 표시
        );
        
        // 3. 업데이트된 텍스트 캐싱
        await setProcessedText(page.id!, updatedProcessedText);
        
        // 4. 필요한 번역 데이터 확인 및 로드
        final finalProcessedText = await checkAndLoadTranslationData(
          note: note,
          page: page,
          imageFile: imageFile,
          currentProcessedText: updatedProcessedText,
        );
        
        return finalProcessedText ?? updatedProcessedText;
      }
      return processedText;
    } catch (e) {
      debugPrint('페이지 컨텐츠 처리 중 오류: $e');
      return null;
    }
  }

  // 텍스트 표시 모드 토글 (통합 메서드)
  Future<ProcessedText?> toggleDisplayModeForPage(String? pageId) async {
    // pageId가 null이면 null 반환
    if (pageId == null) {
      debugPrint('toggleDisplayModeForPage: 페이지 ID가 null입니다');
      return null;
    }
    
    // 현재 처리된 텍스트 가져오기
    final processedText = await getProcessedText(pageId);
    if (processedText == null) {
      debugPrint('toggleDisplayModeForPage: 페이지 ID $pageId의 처리된 텍스트를 찾을 수 없습니다');
      return null;
    }
    
    // 원래 모드 토글
    final updatedText = toggleDisplayMode(processedText);
    
    // 업데이트된 상태 저장
    await setProcessedText(pageId, updatedText);
    
    return updatedText;
  }
}

/// 언어별 텍스트 처리 인터페이스
abstract class LanguageProcessor {
  /// 텍스트 세그멘테이션 (단어/구 단위 분리)
  Future<List<Map<String, dynamic>>> segmentText(String text);
  
  /// 발음 생성 (병음, 후리가나 등)
  Future<Map<String, String>> generatePronunciation(String text);
}

/// 중국어 처리기
class ChineseProcessor implements LanguageProcessor {
  // 필요한 서비스 인스턴스들
  final InternalCnSegmenterService _segmenterService = InternalCnSegmenterService();
  final PinyinCreationService _pinyinService = PinyinCreationService();
  
  @override
  Future<List<Map<String, dynamic>>> segmentText(String text) async {
    // 문장 단위로 분리
    final sentences = _segmenterService.splitIntoSentences(text);
    List<Map<String, dynamic>> result = [];
    
    // 각 문장을 세그먼트로 변환
    int currentIndex = 0;
    for (final sentence in sentences) {
      if (sentence.isEmpty) continue;
      
      result.add({
        'text': sentence,
        'index': currentIndex,
        'isSegmentStart': true,
      });
      
      currentIndex += sentence.length;
    }
    
    // 빈 리스트인 경우, 문자별로 분리 (폴백 처리)
    if (result.isEmpty) {
      final chars = text.split('');
      
      for (int i = 0; i < chars.length; i++) {
        result.add({
          'text': chars[i],
          'index': i,
          'isSegmentStart': true,
        });
      }
    }
    
    return result;
  }
  
  @override
  Future<Map<String, String>> generatePronunciation(String text) async {
    // 중국어 병음 생성 서비스 사용
    Map<String, String> result = {};
    
    try {
      // 전체 텍스트에 대한 병음 생성
      final wholePinyin = await _pinyinService.generatePinyin(text);
      result[text] = wholePinyin;
      
      // 세그먼트 단위로 병음 생성 (문장별)
      final sentences = _segmenterService.splitIntoSentences(text);
      for (final sentence in sentences) {
        if (sentence.isEmpty) continue;
        
        final sentencePinyin = await _pinyinService.generatePinyin(sentence);
        result[sentence] = sentencePinyin;
      }
      
      // 단어 단위로 병음 생성 (최대 2-4자 중국어 단어)
      if (text.length <= 4) {
        for (int i = 0; i < text.length; i++) {
          for (int j = i + 1; j <= i + 4 && j <= text.length; j++) {
            final word = text.substring(i, j);
            if (word.length <= 1) continue; // 1글자는 이미 개별 글자로 처리됨
            
            final wordPinyin = await _pinyinService.generatePinyin(word);
            result[word] = wordPinyin;
          }
        }
      }
      
      // 개별 글자에 대한 병음도 생성
      for (int i = 0; i < text.length; i++) {
        final char = text[i];
        final charPinyin = await _pinyinService.generatePinyin(char);
        result[char] = charPinyin;
      }
      
      return result;
    } catch (e) {
      debugPrint('병음 생성 중 오류 발생: $e');
      return {}; // 오류 시 빈 맵 반환
    }
  }
}

/// 한국어 처리기
class KoreanProcessor implements LanguageProcessor {
  @override
  Future<List<Map<String, dynamic>>> segmentText(String text) async {
    // 한국어 세그멘테이션 로직 (공백 기준 분리)
    List<Map<String, dynamic>> result = [];
    final words = text.split(' ');
    
    int currentIndex = 0;
    for (final word in words) {
      if (word.isEmpty) continue;
      
      result.add({
        'text': word,
        'index': currentIndex,
        'isSegmentStart': true,
      });
      currentIndex += word.length + 1; // 공백 포함
    }
    
    return result;
  }
  
  @override
  Future<Map<String, String>> generatePronunciation(String text) async {
    // 한국어는 발음 생성이 필요 없지만, 로마자 변환 등이 필요하면 여기 구현
    return {};
  }
}

/// 기본 언어 처리기 (언어 특화 처리기가 없을 때 사용)
class GenericProcessor implements LanguageProcessor {
  @override
  Future<List<Map<String, dynamic>>> segmentText(String text) async {
    // 간단한 공백 기반 분리
    List<Map<String, dynamic>> result = [];
    final words = text.split(' ');
    
    int currentIndex = 0;
    for (final word in words) {
      if (word.isNotEmpty) {
        result.add({
          'text': word,
          'index': currentIndex,
          'isSegmentStart': true,
        });
      }
      currentIndex += word.length + 1; // 공백 포함
    }
    
    return result;
  }
  
  @override
  Future<Map<String, String>> generatePronunciation(String text) async {
    // 기본 처리기는 발음 생성 없음
    return {};
  }
} 