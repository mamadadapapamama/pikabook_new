import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

// 서비스 임포트
import '../storage/unified_cache_service.dart';
import '../text_processing/translation_service.dart';
import '../text_processing/enhanced_ocr_service.dart';
// ContentManager 의존성 제거
// import '../../../features/note_detail/managers/content_manager.dart';
import '../text_processing/internal_cn_segmenter_service.dart';
import '../text_processing/pinyin_creation_service.dart';
import '../authentication/user_preferences_service.dart';

// 모델 임포트
import '../../models/page.dart' as page_model;
import '../../models/note.dart';
import '../../models/processed_text.dart';
import '../../models/text_segment.dart';

/// 텍스트 처리를 위한 중앙 통합 워크플로우
/// 
/// 다음 기능들을 통합적으로 제공:
/// 1. 텍스트 번역 (TranslationService 활용)
/// 2. 언어별 세그멘테이션 (현재는 internal_cn_segmenter_service.dart 사용)
/// 3. 텍스트 발음 생성 (병음 등)
/// 4. 처리된 텍스트 캐싱 (UnifiedCacheService 활용)
///
/// 독립적인 텍스트 처리 책임만 담당하여 UI와 분리된 순수 워크플로우 역할을 합니다.
class TextProcessingWorkflow {
  // 싱글톤 패턴
  static final TextProcessingWorkflow _instance = TextProcessingWorkflow._internal();
  factory TextProcessingWorkflow() => _instance;
  TextProcessingWorkflow._internal() {
    debugPrint('✨ TextProcessingWorkflow: 생성자 호출됨');
  }

  // 필요한 서비스들의 인스턴스
  final TranslationService _translationService = TranslationService();
  final EnhancedOcrService _ocrService = EnhancedOcrService();
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  // ContentManager 의존성 제거
  // final ContentManager _contentManager = ContentManager();
  final InternalCnSegmenterService _segmenterService = InternalCnSegmenterService();
  final UserPreferencesService _preferencesService = UserPreferencesService();

  // 언어별 처리기 맵 (확장 가능)
  final Map<String, LanguageProcessor> _languageProcessors = {
    'zh': ChineseProcessor(), // 중국어 처리기
    'ko': KoreanProcessor(),  // 한국어 처리기
    // 추후 더 많은 언어 추가 가능: 'ja': JapaneseProcessor() 등
  };

  /// 페이지 텍스트 처리 - ContentManager 의존성 제거하고 직접 구현
  Future<ProcessedText?> processPageText({
    required page_model.Page? page,
    required File? imageFile,
  }) async {
    if (page == null) return null;
    if (page.id == null) return null;
    
    // 1. 캐시에서 처리된 텍스트 확인
    final pageId = page.id!;
    try {
      final cachedText = await _cacheService.getProcessedText(pageId);
      if (cachedText != null) {
        debugPrint('캐시에서 처리된 텍스트 로드: 페이지 ID=$pageId');
        return cachedText;
      }
    } catch (e) {
      debugPrint('캐시 확인 중 오류 (무시됨): $e');
    }
    
    // 2. 텍스트 처리 로직
    final originalText = page.originalText;
    final translatedText = page.translatedText ?? '';
    
    // 3. 이미지 파일이 있고 텍스트가 없는 경우 OCR 처리
    if (imageFile != null && (originalText.isEmpty || translatedText.isEmpty)) {
      try {
        final extractedText = await _ocrService.extractText(
          imageFile,
          skipUsageCount: false,
        );
        
        final note = Note(
          id: null,
          userId: '',
          originalText: '',
          translatedText: '',
          extractedText: extractedText,
          sourceLanguage: 'zh-CN', // 기본값, 향후 개선 필요
          targetLanguage: 'ko',
        );
        
        final processedText = await processText(
          text: extractedText,
          note: note,
          pageId: pageId,
        );
        
        return processedText;
      } catch (e) {
        debugPrint('이미지 처리 중 오류: $e');
        return ProcessedText(
          fullOriginalText: originalText.isNotEmpty ? originalText : "이미지 처리 중 오류가 발생했습니다.",
          fullTranslatedText: translatedText,
          segments: [],
          showFullText: true,
        );
      }
    }
    
    // 4. 텍스트 처리
    if (originalText.isNotEmpty) {
      try {
        final note = Note(
          id: null,
          userId: '',
          originalText: '',
          translatedText: '',
          extractedText: originalText,
          sourceLanguage: 'zh-CN', // 기본값, 향후 개선 필요
          targetLanguage: 'ko',
        );
        
        ProcessedText processedText = await processText(
          text: originalText,
          note: note,
          pageId: pageId,
        );
        
        // 번역 텍스트가 있는 경우 설정
        if (translatedText.isNotEmpty && 
            (processedText.fullTranslatedText == null || processedText.fullTranslatedText!.isEmpty)) {
          processedText = processedText.copyWith(fullTranslatedText: translatedText);
        }
        
        return processedText;
      } catch (e) {
        debugPrint('텍스트 처리 중 오류: $e');
        return ProcessedText(
          fullOriginalText: originalText,
          fullTranslatedText: translatedText,
          segments: [],
          showFullText: true,
        );
      }
    }
    
    return null;
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
      
      // 5. 사용자 선호도 확인
      final useSegmentMode = await _preferencesService.getUseSegmentMode();
      final hasCompletedOnboarding = await _preferencesService.getOnboardingCompleted();
      
      // onboarding을 완료하지 않았으면 세그먼트 모드로 간주
      final effectiveSegmentMode = hasCompletedOnboarding ? useSegmentMode : true;
      
      // 6. 사용자 선호도에 따라 필요한 번역만 수행
      String translatedText = '';
      List<String> segmentTranslations = List.filled(segments.length, '');
      
      if (text.isNotEmpty) {
        if (!effectiveSegmentMode) {
          // 전체 텍스트 모드: 전체 텍스트만 번역
          debugPrint('전체 텍스트 모드로 번역 수행');
          translatedText = await _translationService.translateText(
            text,
            sourceLanguage: note.sourceLanguage,
            targetLanguage: note.targetLanguage,
          );
        } else {
          // 세그먼트 모드: 각 세그먼트만 번역
          debugPrint('세그먼트 모드로 번역 수행');
          
          if (segments.isNotEmpty) {
            for (var i = 0; i < segments.length; i++) {
              final segment = segments[i];
              final originalText = segment['text'] as String;
              if (originalText.trim().isEmpty) continue;
              
              final segmentTranslation = await _translationService.translateText(
                originalText,
                sourceLanguage: note.sourceLanguage,
                targetLanguage: note.targetLanguage,
              );
              
              segmentTranslations[i] = segmentTranslation;
            }
            
            // 세그먼트 번역 결과를 합쳐서 전체 번역 텍스트로 설정
            // 이렇게 하면 전체 텍스트 모드로 변경해도 번역이 있음
            translatedText = segmentTranslations.join(' ');
          }
        }
      }
      
      // 7. TextSegment 리스트 생성
      final List<TextSegment> textSegments = [];
      for (int i = 0; i < segments.length; i++) {
        final originalText = segments[i]['text'] as String;
        String segmentPinyin = '';
        
        // 7-1. 개별 세그먼트에 대한 발음 추가
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
        
        // 세그먼트별 번역 적용
        final segmentTranslation = effectiveSegmentMode ? segmentTranslations[i] : '';
        
        textSegments.add(TextSegment(
          originalText: originalText,
          pinyin: segmentPinyin,
          translatedText: segmentTranslation,
          sourceLanguage: note.sourceLanguage,
          targetLanguage: note.targetLanguage,
        ));
      }
      
      // 8. ProcessedText 객체 생성
      final processedText = ProcessedText(
        fullOriginalText: text,
        fullTranslatedText: translatedText,
        segments: textSegments,
        showFullText: !effectiveSegmentMode,
        showPinyin: true,
        showTranslation: true,
      );
      
      // 9. 결과 캐싱
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

  /// 번역 데이터 확인 및 로드
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
      debugPrint('TextProcessingWorkflow: 이미 번역 데이터가 있습니다.');
      return currentProcessedText;
    }
    
    // 원본 텍스트가 없으면 처리할 수 없음
    if (page.originalText.isEmpty && imageFile == null) {
      debugPrint('TextProcessingWorkflow: 원본 텍스트와 이미지가 모두 없습니다.');
      return currentProcessedText;
    }
    
    debugPrint('TextProcessingWorkflow: 번역 데이터 로드 시작');
    
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
        debugPrint('TextProcessingWorkflow: 원본 텍스트가 비어 있습니다.');
        return currentProcessedText;
      }
      
      // 번역 실행
      debugPrint('TextProcessingWorkflow: 번역 실행');
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
      debugPrint('TextProcessingWorkflow: 번역 데이터 로드 중 오류 발생 - $e');
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
    
    // 페이지 캐시도 함께 업데이트 (ContentManager 의존성 제거)
    // await _contentManager.updatePageCache(
    //   pageId, 
    //   processedText,
    //   "languageLearning"
    // );
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
      // 1. 사용자 선호도 확인
      final useSegmentMode = await _preferencesService.getUseSegmentMode();
      final hasCompletedOnboarding = await _preferencesService.getOnboardingCompleted();
      
      // onboarding을 완료하지 않았으면 세그먼트 모드로 간주
      final effectiveSegmentMode = hasCompletedOnboarding ? useSegmentMode : true;
      
      // 2. 텍스트 처리 (캐시에 없는 경우)
      ProcessedText? processedText = await getProcessedText(page.id!);
      
      if (processedText == null) {
        // 새로 처리 필요
        processedText = await processPageText(
          page: page,
          imageFile: imageFile,
        );
      }
      
      if (processedText != null) {
        // 3. 기본 표시 설정 지정
        ProcessedText updatedProcessedText = processedText.copyWith(
          showFullText: !effectiveSegmentMode, // 현재 선택된 모드 적용
          showPinyin: true,                   // 병음 표시는 기본적으로 활성화
          showTranslation: true,              // 번역은 항상 표시
        );
        
        // 4. 번역 데이터 확인 - 필요한 경우에만 번역 수행
        if (effectiveSegmentMode) {
          // 세그먼트 모드: 각 세그먼트 번역이 필요한지 확인
          if (updatedProcessedText.segments != null) {
            bool needsSegmentTranslation = false;
            
            for (var segment in updatedProcessedText.segments!) {
              if ((segment.translatedText == null || segment.translatedText!.isEmpty) && 
                  segment.originalText.isNotEmpty) {
                needsSegmentTranslation = true;
                break;
              }
            }
            
            if (needsSegmentTranslation) {
              // 세그먼트 번역 필요
              debugPrint('세그먼트 모드: 일부 세그먼트 번역 필요');
              
              // 세그먼트별 번역 수행
              final updatedSegments = <TextSegment>[];
              
              for (var segment in updatedProcessedText.segments!) {
                if ((segment.translatedText == null || segment.translatedText!.isEmpty) && 
                    segment.originalText.isNotEmpty) {
                  // 세그먼트 번역 수행
                  final translatedText = await _translationService.translateText(
                    segment.originalText,
                    sourceLanguage: segment.sourceLanguage,
                    targetLanguage: segment.targetLanguage,
                  );
                  
                  // 업데이트된 세그먼트 추가
                  updatedSegments.add(TextSegment(
                    originalText: segment.originalText,
                    translatedText: translatedText,
                    pinyin: segment.pinyin ?? '',
                    sourceLanguage: segment.sourceLanguage,
                    targetLanguage: segment.targetLanguage,
                  ));
                } else {
                  updatedSegments.add(segment);
                }
              }
              
              // 세그먼트 번역 결과를 합쳐서 전체 번역 텍스트로 설정
              final combinedTranslation = updatedSegments
                  .map((s) => s.translatedText)
                  .where((t) => t != null && t.isNotEmpty)
                  .join(' ');
              
              updatedProcessedText = updatedProcessedText.copyWith(
                segments: updatedSegments,
                fullTranslatedText: combinedTranslation,
              );
            }
          }
        } else {
          // 전체 텍스트 모드: 전체 번역이 필요한지 확인
          if ((updatedProcessedText.fullTranslatedText == null || updatedProcessedText.fullTranslatedText!.isEmpty) &&
              updatedProcessedText.fullOriginalText.isNotEmpty) {
            debugPrint('전체 텍스트 모드: 전체 번역 필요');
            
            // 전체 텍스트 번역 수행
            final translatedText = await _translationService.translateText(
              updatedProcessedText.fullOriginalText,
              sourceLanguage: note.sourceLanguage,
              targetLanguage: note.targetLanguage,
            );
            
            updatedProcessedText = updatedProcessedText.copyWith(
              fullTranslatedText: translatedText,
            );
          }
        }
        
        // 5. 업데이트된 텍스트 캐싱
        if (page.id != null) {
          await setProcessedText(page.id!, updatedProcessedText);
        }
        
        return updatedProcessedText;
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
    
    // 현재 모드 확인
    final isCurrentlyFullText = processedText.showFullText;
    final willBeSegmentMode = isCurrentlyFullText; // 토글되므로 현재 값의 반대가 될 것임
    
    // 세그먼트 모드로 전환하는데 세그먼트별 번역이 없는 경우
    if (willBeSegmentMode && processedText.segments != null) {
      bool needsSegmentTranslation = false;
      
      for (var segment in processedText.segments!) {
        if ((segment.translatedText == null || segment.translatedText!.isEmpty) && 
            segment.originalText.isNotEmpty) {
          needsSegmentTranslation = true;
          break;
        }
      }
      
      if (needsSegmentTranslation) {
        debugPrint('세그먼트 모드로 전환하는데 일부 세그먼트 번역이 없어 번역 수행');
        
        // 새 세그먼트 리스트 생성
        final updatedSegments = <TextSegment>[];
        
        for (var segment in processedText.segments!) {
          if ((segment.translatedText == null || segment.translatedText!.isEmpty) && 
              segment.originalText.isNotEmpty) {
            // 세그먼트 번역 수행
            final translatedText = await _translationService.translateText(
              segment.originalText,
              sourceLanguage: segment.sourceLanguage,
              targetLanguage: segment.targetLanguage,
            );
            
            // 업데이트된 세그먼트 추가
            updatedSegments.add(TextSegment(
              originalText: segment.originalText,
              translatedText: translatedText,
              pinyin: segment.pinyin ?? '',
              sourceLanguage: segment.sourceLanguage,
              targetLanguage: segment.targetLanguage,
            ));
          } else {
            updatedSegments.add(segment);
          }
        }
        
        // 업데이트된 ProcessedText 생성
        final updatedText = processedText.copyWith(
          showFullText: !isCurrentlyFullText,
          segments: updatedSegments
        );
        
        // 업데이트된 상태 저장
        await setProcessedText(pageId, updatedText);
        return updatedText;
      }
    }
    
    // 전체 텍스트 모드로 전환하는데 전체 번역이 없는 경우
    if (!willBeSegmentMode && (processedText.fullTranslatedText == null || processedText.fullTranslatedText!.isEmpty) &&
        processedText.fullOriginalText.isNotEmpty) {
      debugPrint('전체 텍스트로 전환하는데 전체 번역이 없어 번역 수행');
      
      // 기본 소스 및 타겟 언어 설정
      String sourceLanguage = 'zh-CN';
      String targetLanguage = 'ko';
      
      // 세그먼트에서 언어 정보 추출 시도
      if (processedText.segments != null && processedText.segments!.isNotEmpty) {
        final firstSegment = processedText.segments!.first;
        sourceLanguage = firstSegment.sourceLanguage;
        targetLanguage = firstSegment.targetLanguage;
      }
      
      // 전체 텍스트 번역 수행
      final translatedText = await _translationService.translateText(
        processedText.fullOriginalText,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      );
      
      // 번역 결과 적용
      final updatedText = processedText.copyWith(
        showFullText: !isCurrentlyFullText,
        fullTranslatedText: translatedText
      );
      
      // 업데이트된 상태 저장
      await setProcessedText(pageId, updatedText);
      return updatedText;
    }
    
    // 기존 번역이 모두 있는 경우 모드만 토글
    final updatedText = processedText.copyWith(
      showFullText: !isCurrentlyFullText
    );
    
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