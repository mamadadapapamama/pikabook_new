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
        if (kDebugMode) {
          debugPrint('캐시에서 처리된 텍스트 로드: 페이지 ID=$pageId');
        }
        return cachedText;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('캐시 확인 중 오류 (무시됨): $e');
      }
    }
    
    // 2. 텍스트 처리 로직
    final originalText = page.originalText;
    final translatedText = page.translatedText ?? '';
    
    // 3. 이미지 파일이 있고 텍스트가 없는 경우 OCR 처리
    if (imageFile != null && (originalText.isEmpty || translatedText.isEmpty)) {
      try {
        if (kDebugMode) {
          debugPrint('이미지 파일에서 OCR 처리 시작');
        }
        
        final extractedText = await _ocrService.extractText(
          imageFile,
          skipUsageCount: false,
        );
        
        if (kDebugMode) {
          debugPrint('OCR 텍스트 추출 완료: ${extractedText.length}자');
        }
        
        // OCR로 추출한 텍스트로 바로 처리 (캐시 확인 불필요)
        final note = Note(
          id: null,
          userId: '',
          originalText: '',
          translatedText: '',
          extractedText: extractedText,
          sourceLanguage: 'zh-CN', // 기본값, 향후 개선 필요
          targetLanguage: 'ko',
        );
        
        return await processText(
          text: extractedText,
          note: note,
          pageId: pageId,
          forceRefresh: true, // 캐시 확인을 건너뛰기 위해 forceRefresh 설정
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('이미지 처리 중 오류: $e');
        }
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
        if (kDebugMode) {
          debugPrint('페이지 원본 텍스트 처리 시작: ${originalText.length}자');
        }
        
        final note = Note(
          id: null,
          userId: '',
          originalText: '',
          translatedText: '',
          extractedText: originalText,
          sourceLanguage: 'zh-CN', // 기본값, 향후 개선 필요
          targetLanguage: 'ko',
        );
        
        // 원본 텍스트로 처리 (이미 캐시 확인을 했으므로 forceRefresh 설정)
        ProcessedText processedText = await processText(
          text: originalText,
          note: note,
          pageId: pageId,
          forceRefresh: true, // 불필요한 캐시 확인 방지
        );
        
        // 번역 텍스트가 있는 경우 설정
        if (translatedText.isNotEmpty && 
            (processedText.fullTranslatedText == null || processedText.fullTranslatedText!.isEmpty)) {
          processedText = processedText.copyWith(fullTranslatedText: translatedText);
        }
        
        return processedText;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('텍스트 처리 중 오류: $e');
        }
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
    // 시간 측정 (성능 최적화 모니터링)
    final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;
    if (kDebugMode) {
      debugPrint('🔄 텍스트 처리 시작: ${text.length}자');
    }
    
    // 캐시 확인은 forceRefresh가 false일 때만 수행 (processPageText에서 넘어온 경우는 forceRefresh=true)
    if (!forceRefresh) {
      final cachedResult = await _cacheService.getProcessedText(pageId);
      if (cachedResult != null) {
        if (kDebugMode) {
          debugPrint('⚡ 캐시된 ProcessedText 반환 (페이지ID: $pageId)');
        }
        return cachedResult;
      }
    }

    try {
      if (kDebugMode) {
        debugPrint('새로운 텍스트 처리 시작 (소스언어: ${note.sourceLanguage}, 타겟언어: ${note.targetLanguage})');
      }
      
      // 사용자 선호도 확인
      final useSegmentMode = await _preferencesService.getUseSegmentMode();
      final hasCompletedOnboarding = await _preferencesService.getOnboardingCompleted();
      
      // onboarding을 완료하지 않았으면 세그먼트 모드로 간주
      final effectiveSegmentMode = hasCompletedOnboarding ? useSegmentMode : true;
      
      if (kDebugMode) {
        debugPrint('텍스트 처리 모드: ${effectiveSegmentMode ? "세그먼트" : "전체 텍스트"}');
      }
      
      String translatedText = '';
      List<TextSegment> textSegments = [];
      
      if (text.isNotEmpty) {
        final translationStart = kDebugMode ? (Stopwatch()..start()) : null;
        
        // 전체 텍스트 모드: 번역만 수행
        if (!effectiveSegmentMode) {
          if (kDebugMode) {
            debugPrint('전체 텍스트 모드로 번역 수행');
          }
          translatedText = await _translationService.translateText(
            text,
            sourceLanguage: note.sourceLanguage,
            targetLanguage: note.targetLanguage,
          );
          
          // 전체 텍스트 모드에서는 단일 세그먼트만 생성
          textSegments = [
            TextSegment(
              originalText: text,
              translatedText: translatedText,
              pinyin: '',
              sourceLanguage: note.sourceLanguage,
              targetLanguage: note.targetLanguage,
            )
          ];
        } 
        // 세그먼트 모드: 세그먼테이션, 발음 생성, 세그먼트별 번역 수행
        else {
          if (kDebugMode) {
            debugPrint('세그먼트 모드로 처리 시작');
          }
          
          // 1. 세그멘테이션 수행 (세그먼트 모드에서만 필요)
          final segmentationStart = kDebugMode ? (Stopwatch()..start()) : null;
          
          // 직접 InternalCnSegmenterService 사용
          final segmenterService = InternalCnSegmenterService();
          // 문장 단위로 분리
          final sentences = segmenterService.splitIntoSentences(text);
          
          // segments 구조 생성
          final segments = <Map<String, dynamic>>[];
          int currentIndex = 0;
          for (final sentence in sentences) {
            if (sentence.isEmpty) continue;
            
            segments.add({
              'text': sentence,
              'index': currentIndex,
              'isSegmentStart': true,
            });
            
            currentIndex += sentence.length;
          }
          
          if (kDebugMode && segmentationStart != null) {
            debugPrint('세그멘테이션 완료 (${segmentationStart.elapsedMilliseconds}ms): ${segments.length}개 세그먼트');
          }
          
          // 2. 발음 생성 (세그먼트 모드에서만 필요)
          final pronunciationStart = kDebugMode ? (Stopwatch()..start()) : null;
          
          // 직접 PinyinCreationService 사용
          final pinyinService = PinyinCreationService();
          final pronunciation = <String, String>{};
          
          // 전체 텍스트에 대한 병음 생성
          final wholePinyin = await pinyinService.generatePinyin(text);
          pronunciation[text] = wholePinyin;
          
          // 각 문장별 병음 생성
          for (final sentence in sentences) {
            if (sentence.isEmpty) continue;
            
            final sentencePinyin = await pinyinService.generatePinyin(sentence);
            pronunciation[sentence] = sentencePinyin;
          }
          
          // 개별 글자에 대한 병음 생성
          for (int i = 0; i < text.length; i++) {
            final char = text[i];
            final charPinyin = await pinyinService.generatePinyin(char);
            pronunciation[char] = charPinyin;
          }
          
          if (kDebugMode && pronunciationStart != null) {
            debugPrint('발음 생성 완료 (${pronunciationStart.elapsedMilliseconds}ms)');
          }
          
          // 3. 세그먼트별 번역
          if (kDebugMode) {
            debugPrint('세그먼트 번역 시작');
          }
          
          if (segments.isNotEmpty) {
            // 번역할 텍스트 수집
            final segmentsToTranslate = <int, String>{};
            for (int i = 0; i < segments.length; i++) {
              final originalText = segments[i]['text'] as String;
              if (originalText.trim().isNotEmpty) {
                segmentsToTranslate[i] = originalText;
              }
            }
            
            // 번역 결과 저장용 배열
            List<String> segmentTranslations = List.filled(segments.length, '');
            
            if (segmentsToTranslate.isNotEmpty) {
              // 세그먼트 최적화를 위한 배치 처리
              final batchSize = 15; // 한 번에 처리할 세그먼트 수
              final segmentBatches = <List<int>>[];
              final keys = segmentsToTranslate.keys.toList()..sort();
              
              // 세그먼트 인덱스를 batchSize 단위로 그룹화
              for (int i = 0; i < keys.length; i += batchSize) {
                final endIdx = (i + batchSize < keys.length) ? i + batchSize : keys.length;
                segmentBatches.add(keys.sublist(i, endIdx));
              }
              
              if (kDebugMode) {
                debugPrint('세그먼트 배치 ${segmentBatches.length}개 생성됨');
              }
              
              // 각 배치에 대해 번역 처리 수행
              for (final batch in segmentBatches) {
                final segmentTexts = batch.map((idx) => segmentsToTranslate[idx]!).toList();
                final translationResult = await _batchTranslate(
                  segmentTexts,
                  note.sourceLanguage, 
                  note.targetLanguage
                );
                
                // 번역 결과 적용
                for (int i = 0; i < batch.length; i++) {
                  if (i < translationResult.length) {
                    final segmentIdx = batch[i];
                    segmentTranslations[segmentIdx] = translationResult[i];
                  }
                }
              }
              
              // 세그먼트 번역 결과를 합쳐서 전체 번역 텍스트로 설정
              translatedText = segmentTranslations.join(' ');
            }
            
            // 4. TextSegment 리스트 생성
            textSegments = [];
            for (int i = 0; i < segments.length; i++) {
              final originalText = segments[i]['text'] as String;
              String segmentPinyin = '';
              
              // 발음 추가
              segmentPinyin = pronunciation[originalText] ?? '';
              
              // 병음이 없고 세그먼트가 한 글자 이상인 경우 개별 처리 시도
              if (segmentPinyin.isEmpty && originalText.length > 1) {
                segmentPinyin = await pinyinService.generatePinyin(originalText);
              }
              
              // 세그먼트별 번역 적용
              textSegments.add(TextSegment(
                originalText: originalText,
                pinyin: segmentPinyin,
                translatedText: segmentTranslations[i],
                sourceLanguage: note.sourceLanguage,
                targetLanguage: note.targetLanguage,
              ));
            }
          }
        }
        
        if (kDebugMode && translationStart != null) {
          debugPrint('번역/처리 완료 (${translationStart.elapsedMilliseconds}ms)');
        }
      }
      
      // ProcessedText 객체 생성
      final processedText = ProcessedText(
        fullOriginalText: text,
        fullTranslatedText: translatedText,
        segments: textSegments,
        showFullText: !effectiveSegmentMode,
        showPinyin: true,
        showTranslation: true,
      );
      
      // 결과 캐싱
      await _cacheService.setProcessedText(pageId, processedText);
      
      if (kDebugMode && stopwatch != null) {
        debugPrint('✅ 텍스트 처리 완료 (${stopwatch.elapsedMilliseconds}ms)');
      }
      
      return processedText;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 텍스트 처리 중 오류 발생: $e');
      }
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
  
  /// 여러 텍스트를 일괄 번역하는 공통 메서드 (중복 제거)
  Future<List<String>> _batchTranslate(
    List<String> texts,
    String sourceLanguage,
    String targetLanguage
  ) async {
    if (texts.isEmpty) return [];
    
    try {
      // 유니크한 마커 생성 (타임스탬프 포함)
      final uniqueMarker = '===SEG${DateTime.now().millisecondsSinceEpoch}===';
      
      // 배치 내 텍스트 결합
      final combinedText = texts.join('\n$uniqueMarker\n');
      
      // 배치 번역 수행
      final combinedTranslation = await _translationService.translateText(
        combinedText,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      );
      
      // 번역 결과 분리
      return combinedTranslation.split(uniqueMarker)
          .map((t) => t.trim())
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('텍스트 배치 번역 오류: $e');
      }
      // 오류시 원본 텍스트 반환
      return texts;
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
      final processingStart = kDebugMode ? (Stopwatch()..start()) : null;
      
      // 1. 사용자 선호도 확인
      final useSegmentMode = await _preferencesService.getUseSegmentMode();
      final hasCompletedOnboarding = await _preferencesService.getOnboardingCompleted();
      
      // onboarding을 완료하지 않았으면 세그먼트 모드로 간주
      final effectiveSegmentMode = hasCompletedOnboarding ? useSegmentMode : true;
      
      if (kDebugMode) {
        debugPrint('페이지 처리 모드: ${effectiveSegmentMode ? "세그먼트" : "전체 텍스트"}');
      }
      
      // 2. 텍스트 처리 (캐시에 없는 경우)
      ProcessedText? processedText = await getProcessedText(page.id!);
      
      if (processedText == null) {
        // 새로 처리 필요
        if (kDebugMode) {
          debugPrint('캐시된 텍스트 없음, 새로 처리 시작');
        }
        
        processedText = await processPageText(
          page: page,
          imageFile: imageFile,
        );
        
        if (kDebugMode && processingStart != null) {
          debugPrint('새 페이지 처리 완료 (${processingStart.elapsedMilliseconds}ms)');
        }
        
        return processedText;
      }
      
      if (processedText != null) {
        // 변경 필요 여부 확인 (불필요한 업데이트 방지)
        bool needsUpdate = false;
        
        // 3. 표시 설정 확인
        final needsModeSwitch = processedText.showFullText == effectiveSegmentMode;
        if (needsModeSwitch) {
          needsUpdate = true;
          if (kDebugMode) {
            debugPrint('모드 전환 필요: ${processedText.showFullText ? "전체" : "세그먼트"} → ${effectiveSegmentMode ? "세그먼트" : "전체"}');
          }
        }
        
        // 번역 데이터 확인
        final needsTranslation = effectiveSegmentMode 
          ? _needsSegmentTranslation(processedText)
          : _needsFullTranslation(processedText);
          
        if (needsTranslation) {
          needsUpdate = true;
          if (kDebugMode) {
            debugPrint('번역 데이터 추가 필요');
          }
        }
        
        // 변경이 필요한 경우에만 업데이트
        if (needsUpdate) {
          // 3. 기본 표시 설정 지정
          ProcessedText updatedProcessedText = processedText.copyWith(
            showFullText: !effectiveSegmentMode, // 현재 선택된 모드 적용
            showPinyin: true,                   // 병음 표시는 기본적으로 활성화
            showTranslation: true,              // 번역은 항상 표시
          );
          
          // 4. 번역 데이터 확인 - 필요한 경우에만 번역 수행
          if (effectiveSegmentMode && needsTranslation) {
            updatedProcessedText = await _addMissingSegmentTranslations(
              updatedProcessedText, 
              note.sourceLanguage, 
              note.targetLanguage
            );
          } else if (!effectiveSegmentMode && needsTranslation) {
            // 전체 텍스트 모드: 전체 번역 필요한 경우
            if (kDebugMode) {
              debugPrint('전체 텍스트 번역 필요');
            }
            
            // 전체 텍스트 번역 수행
            final translationStart = kDebugMode ? (Stopwatch()..start()) : null;
            final translatedText = await _translationService.translateText(
              updatedProcessedText.fullOriginalText,
              sourceLanguage: note.sourceLanguage,
              targetLanguage: note.targetLanguage,
            );
            
            if (kDebugMode && translationStart != null) {
              debugPrint('전체 텍스트 번역 완료 (${translationStart.elapsedMilliseconds}ms)');
            }
            
            updatedProcessedText = updatedProcessedText.copyWith(
              fullTranslatedText: translatedText,
            );
          }
          
          // 5. 업데이트된 텍스트 캐싱
          if (page.id != null) {
            await setProcessedText(page.id!, updatedProcessedText);
          }
          
          if (kDebugMode && processingStart != null) {
            debugPrint('페이지 컨텐츠 처리 완료 (${processingStart.elapsedMilliseconds}ms)');
          }
          
          return updatedProcessedText;
        }
        
        // 변경이 필요 없는 경우 그대로 반환
        if (kDebugMode) {
          debugPrint('텍스트 처리 불필요 (이미 최신 상태)');
        }
        return processedText;
      }
      
      return processedText;
    } catch (e) {
      debugPrint('페이지 컨텐츠 처리 중 오류: $e');
      return null;
    }
  }
  
  /// 세그먼트 번역이 필요한지 확인
  bool _needsSegmentTranslation(ProcessedText processedText) {
    if (processedText.segments == null || processedText.segments!.isEmpty) {
      return false;
    }
    
    // 번역되지 않은 세그먼트가 하나라도 있는지 확인
    return processedText.segments!.any(
      (segment) => segment.originalText.isNotEmpty && 
                  (segment.translatedText == null || segment.translatedText!.isEmpty)
    );
  }
  
  /// 전체 번역이 필요한지 확인
  bool _needsFullTranslation(ProcessedText processedText) {
    return processedText.fullOriginalText.isNotEmpty &&
           (processedText.fullTranslatedText == null || processedText.fullTranslatedText!.isEmpty);
  }
  
  /// 누락된 세그먼트 번역 추가
  Future<ProcessedText> _addMissingSegmentTranslations(
    ProcessedText processedText,
    String sourceLanguage,
    String targetLanguage
  ) async {
    if (processedText.segments == null) {
      return processedText;
    }
    
    // 번역이 필요한 세그먼트 수집
    final segmentsToTranslate = <int, String>{};
    for (int i = 0; i < processedText.segments!.length; i++) {
      var segment = processedText.segments![i];
      if ((segment.translatedText == null || segment.translatedText!.isEmpty) && 
          segment.originalText.isNotEmpty) {
        segmentsToTranslate[i] = segment.originalText;
      }
    }
    
    if (segmentsToTranslate.isEmpty) {
      return processedText;
    }
    
    if (kDebugMode) {
      debugPrint('번역 필요: ${segmentsToTranslate.length}개 세그먼트');
    }
    
    // _processBatchTranslation 메서드를 사용하여 중복 제거
    final updatedSegments = List<TextSegment>.from(processedText.segments!);
    
    try {
      // 세그먼트 최적화를 위한 배치 처리
      final batchSize = 15; // 더 큰 배치 사이즈
      final segmentBatches = <List<int>>[];
      final keys = segmentsToTranslate.keys.toList()..sort();
      
      // 세그먼트 인덱스를 batchSize 단위로 그룹화
      for (int i = 0; i < keys.length; i += batchSize) {
        final endIdx = (i + batchSize < keys.length) ? i + batchSize : keys.length;
        segmentBatches.add(keys.sublist(i, endIdx));
      }
      
      // 각 배치에 대해 번역 처리 수행
      for (final batch in segmentBatches) {
        final segmentTexts = batch.map((idx) => segmentsToTranslate[idx]!).toList();
        final translationResult = await _batchTranslate(
          segmentTexts,
          sourceLanguage, 
          targetLanguage
        );
        
        // 번역 결과 적용
        for (int i = 0; i < batch.length; i++) {
          if (i < translationResult.length) {
            final segmentIdx = batch[i];
            final translation = translationResult[i];
            
            updatedSegments[segmentIdx] = TextSegment(
              originalText: processedText.segments![segmentIdx].originalText,
              translatedText: translation,
              pinyin: processedText.segments![segmentIdx].pinyin ?? '',
              sourceLanguage: processedText.segments![segmentIdx].sourceLanguage,
              targetLanguage: processedText.segments![segmentIdx].targetLanguage,
            );
          }
        }
      }
      
      // 세그먼트 번역 결과를 합쳐서 전체 번역 텍스트로 설정
      final combinedTranslation = updatedSegments
          .map((s) => s.translatedText)
          .where((t) => t != null && t.isNotEmpty)
          .join(' ');
      
      return processedText.copyWith(
        segments: updatedSegments,
        fullTranslatedText: combinedTranslation,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('세그먼트 번역 추가 중 오류: $e');
      }
      return processedText;
    }
  }

  // 텍스트 표시 모드 토글 (통합 메서드)
  Future<ProcessedText?> toggleDisplayModeForPage(String? pageId) async {
    // 성능 측정 시작
    final toggleStart = kDebugMode ? (Stopwatch()..start()) : null;
    
    // pageId가 null이면 null 반환
    if (pageId == null) {
      if (kDebugMode) {
        debugPrint('toggleDisplayModeForPage: 페이지 ID가 null입니다');
      }
      return null;
    }
    
    // 현재 처리된 텍스트 가져오기
    final processedText = await getProcessedText(pageId);
    if (processedText == null) {
      if (kDebugMode) {
        debugPrint('toggleDisplayModeForPage: 페이지 ID $pageId의 처리된 텍스트를 찾을 수 없습니다');
      }
      return null;
    }
    
    // 현재 모드 확인
    final isCurrentlyFullText = processedText.showFullText;
    final willBeSegmentMode = isCurrentlyFullText; // 토글되므로 현재 값의 반대가 될 것임
    
    if (kDebugMode) {
      debugPrint('표시 모드 전환: ${isCurrentlyFullText ? "전체" : "세그먼트"} → ${willBeSegmentMode ? "세그먼트" : "전체"}');
    }
    
    // 우선 모드 전환만 적용한 상태로 반환할 객체 생성
    ProcessedText result = processedText.copyWith(
      showFullText: !isCurrentlyFullText
    );
    
    try {
      // 세그먼트 모드로 전환하는데 세그먼트별 번역이 없는 경우
      if (willBeSegmentMode && _needsSegmentTranslation(processedText)) {
        if (kDebugMode) {
          debugPrint('세그먼트 모드 전환: 누락된 세그먼트 번역 추가 필요');
        }
        
        // 기본 소스 및 타겟 언어 설정
        String sourceLanguage = 'zh-CN';
        String targetLanguage = 'ko';
        
        // 세그먼트에서 언어 정보 추출 시도
        if (processedText.segments != null && processedText.segments!.isNotEmpty) {
          final firstSegment = processedText.segments!.first;
          sourceLanguage = firstSegment.sourceLanguage;
          targetLanguage = firstSegment.targetLanguage;
        }
        
        // 누락된 세그먼트 번역 추가
        result = await _addMissingSegmentTranslations(
          result,
          sourceLanguage,
          targetLanguage
        );
      }
      // 전체 텍스트 모드로 전환하는데 전체 번역이 없는 경우
      else if (!willBeSegmentMode && _needsFullTranslation(processedText)) {
        if (kDebugMode) {
          debugPrint('전체 텍스트 모드 전환: 전체 번역 추가 필요');
        }
        
        // 기본 소스 및 타겟 언어 설정
        String sourceLanguage = 'zh-CN';
        String targetLanguage = 'ko';
        
        // 세그먼트에서 언어 정보 추출 시도
        if (processedText.segments != null && processedText.segments!.isNotEmpty) {
          final firstSegment = processedText.segments!.first;
          sourceLanguage = firstSegment.sourceLanguage;
          targetLanguage = firstSegment.targetLanguage;
        }
        
        // 전체 텍스트 번역 수행 (이미 번역된 세그먼트가 있으면 조합하여 사용)
        if (processedText.segments != null && 
            processedText.segments!.any((s) => s.translatedText != null && s.translatedText!.isNotEmpty)) {
          // 이미 번역된 세그먼트가 있으면 조합하여 사용 (API 호출 절약)
          final combinedTranslation = processedText.segments!
              .map((s) => s.translatedText)
              .where((t) => t != null && t.isNotEmpty)
              .join(' ');
          
          if (combinedTranslation.isNotEmpty) {
            result = result.copyWith(
              fullTranslatedText: combinedTranslation
            );
            
            if (kDebugMode) {
              debugPrint('세그먼트 번역을 조합하여 전체 번역으로 사용');
            }
          } else {
            // 세그먼트 번역이 없는 경우 전체 번역 수행
            final translatedText = await _translationService.translateText(
              processedText.fullOriginalText,
              sourceLanguage: sourceLanguage,
              targetLanguage: targetLanguage,
            );
            
            result = result.copyWith(
              fullTranslatedText: translatedText
            );
          }
        } else {
          // 번역된 세그먼트가 없는 경우 전체 번역 수행
          final translatedText = await _translationService.translateText(
            processedText.fullOriginalText,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
          );
          
          result = result.copyWith(
            fullTranslatedText: translatedText
          );
        }
      }
      
      // 업데이트된 상태 저장
      await setProcessedText(pageId, result);
      
      if (kDebugMode && toggleStart != null) {
        debugPrint('✅ 모드 전환 완료 (${toggleStart.elapsedMilliseconds}ms)');
      }
      
      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 모드 전환 중 오류: $e');
        if (toggleStart != null) {
          debugPrint('처리 시간: ${toggleStart.elapsedMilliseconds}ms');
        }
      }
      
      // 오류 발생 시에도 모드 전환은 수행
      await setProcessedText(pageId, result);
      return result;
    }
  }
}

