import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ocr_service.dart';
import 'post_ocr_processing_service.dart';
import 'text_mode_seperation_service.dart';
import '../../models/processed_text.dart';
import '../../models/processing_status.dart';
import '../../models/page_processing_data.dart';
import '../../../features/note/services/page_service.dart';

/// **텍스트 처리 오케스트레이터**
/// 
/// OCR부터 페이지 업데이트까지의 텍스트 처리 전체 흐름을 담당합니다.
/// 
/// **처리 순서:**
/// 1. OCR: 이미지에서 텍스트 추출
/// 2. 모드별 처리:
///    - Segment 모드: PostOCR 처리(정리+제목감지) + 텍스트 분리
///    - Paragraph 모드: 텍스트 정제만 (LLM에서 지능적 분리)
/// 3. PageProcessingData: 처리 결과 데이터 생성
/// 4. PageUpdate: 페이지 데이터 업데이트
/// 
/// **모드별 차이점:**
/// - **Segment 모드**: 로컬에서 문장별 분리 → LLM 번역
/// - **Paragraph 모드**: 전체 텍스트 → LLM 분리+번역 (제목, 소제목, 문제, 보기 등)
/// 
/// **사용 예시:**
/// ```dart
/// final orchestrator = TextProcessingOrchestrator();
/// final result = await orchestrator.processImageText(
///   imageFile: imageFile,
///   pageId: pageId,
///   mode: TextProcessingMode.segment, // 또는 paragraph
///   sourceLanguage: 'zh-CN',
///   targetLanguage: 'ko',
/// );
/// ```
class TextProcessingOrchestrator {
  // 싱글톤 패턴
  static final TextProcessingOrchestrator _instance = TextProcessingOrchestrator._internal();
  factory TextProcessingOrchestrator() => _instance;
  TextProcessingOrchestrator._internal();

  // 서비스 인스턴스
  final OcrService _ocrService = OcrService();
  final PostOcrProcessingService _postOcrProcessor = PostOcrProcessingService();
  final TextModeSeparationService _textSeparationService = TextModeSeparationService();
  final PageService _pageService = PageService();

  /// **이미지에서 텍스트 처리 전체 흐름**
  /// 
  /// OCR부터 페이지 업데이트까지 모든 텍스트 처리를 수행합니다.
  /// 
  /// **매개변수:**
  /// - `imageFile`: 처리할 이미지 파일
  /// - `pageId`: 페이지 ID
  /// - `mode`: 텍스트 처리 모드 (segment/paragraph)
  /// - `sourceLanguage`: 원본 언어
  /// - `targetLanguage`: 목표 언어
  /// 
  /// **반환값:**
  /// - `PageProcessingData?`: 처리된 페이지 데이터 (실패 시 null)
  Future<PageProcessingData?> processImageText({
    required File imageFile,
    required String pageId,
    required TextProcessingMode mode,
    required String sourceLanguage,
    required String targetLanguage,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 TextProcessingOrchestrator: 텍스트 처리 시작');
        debugPrint('   페이지 ID: $pageId');
        debugPrint('   모드: $mode');
      }

      // 1단계: OCR 텍스트 추출
      final rawText = await _extractTextFromImage(imageFile);
      if (rawText.isEmpty) {
        return _createEmptyPageData(pageId, mode, sourceLanguage, targetLanguage, imageFile);
      }

      // 2단계: 모드별 처리
      String processedText;
      List<String> textSegments;
      List<String> detectedTitles = [];
      String originalText = rawText;
      String cleanedText = rawText;
      String reorderedText = rawText;

      if (mode == TextProcessingMode.segment) {
        // Segment 모드: PostOCR 처리 + 텍스트 분리
        if (kDebugMode) {
          debugPrint('📝 Segment 모드: PostOCR 처리 + 텍스트 분리');
        }
        
        final ocrResult = await _processOcrText(rawText);
        processedText = ocrResult.reorderedText;
        
        // 텍스트 분리
        textSegments = _textSeparationService.separateByMode(processedText, mode);
        
        // OCR 결과 저장
        detectedTitles = ocrResult.titleCandidates.map((t) => t.text).toList();
        originalText = ocrResult.originalText;
        cleanedText = ocrResult.cleanedText;
        reorderedText = ocrResult.reorderedText;
        
        if (kDebugMode) {
          debugPrint('✅ Segment 모드 처리 완료: ${textSegments.length}개 문장');
        }
      } else {
        // Paragraph 모드: 텍스트 정제만
        if (kDebugMode) {
          debugPrint('📄 Paragraph 모드: 텍스트 정제만 수행');
        }
        
        // 간단한 텍스트 정제 (공백, 줄바꿈 정리)
        processedText = rawText.trim().replaceAll(RegExp(r'\s+'), ' ');
        textSegments = [processedText]; // 전체 텍스트를 하나의 세그먼트로
        
        if (kDebugMode) {
          debugPrint('✅ Paragraph 모드 처리 완료: 전체 텍스트 길이 ${processedText.length}자');
        }
      }

      // 3단계: PageProcessingData 생성
      final pageData = await _createPageProcessingData(
        pageId: pageId,
        imageFile: imageFile,
        textSegments: textSegments,
        mode: mode,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        detectedTitles: detectedTitles,
        originalText: originalText,
        cleanedText: cleanedText,
        reorderedText: reorderedText,
      );

      // 4단계: 페이지 업데이트
      await _updatePageWithProcessingResult(pageData);

      if (kDebugMode) {
        debugPrint('✅ TextProcessingOrchestrator: 텍스트 처리 완료');
        debugPrint('   처리된 세그먼트: ${pageData.textSegments.length}개');
        debugPrint('   감지된 제목: ${pageData.detectedTitles.length}개');
      }

      return pageData;

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ TextProcessingOrchestrator: 처리 실패 - $e');
      }
      return null;
    }
  }

  // ========== 내부 처리 메서드들 ==========

  /// 1단계: 이미지에서 텍스트 추출
  Future<String> _extractTextFromImage(File imageFile) async {
    if (kDebugMode) {
      debugPrint('🔍 1단계: OCR 텍스트 추출 시작');
    }

    final rawText = await _ocrService.extractText(imageFile, skipUsageCount: false);

    if (kDebugMode) {
      debugPrint('✅ OCR 완료: ${rawText.length}자');
      if (rawText.isNotEmpty) {
        final preview = rawText.length > 30 ? 
            '${rawText.substring(0, 30)}...' : rawText;
        debugPrint('📄 OCR 원본 텍스트: "$preview"');
      }
    }

    return rawText;
  }

  /// 2단계: OCR 텍스트 후처리
  Future<OcrProcessingResult> _processOcrText(String rawText) async {
    if (kDebugMode) {
      debugPrint('🧹 2단계: OCR 후처리 시작 (정리 + 제목 감지)');
    }

    final ocrResult = _postOcrProcessor.processOcrResult(rawText);

    if (kDebugMode) {
      debugPrint('✅ OCR 후처리 완료: ${rawText.length}자 → ${ocrResult.reorderedText.length}자');
      debugPrint('   제목 후보: ${ocrResult.titleCandidates.length}개');
      debugPrint('   본문: ${ocrResult.bodyText.length}개 문장');
      
      // 감지된 제목들 상세 로그
      for (int i = 0; i < ocrResult.titleCandidates.length; i++) {
        final title = ocrResult.titleCandidates[i];
        debugPrint('   📋 제목 ${i+1}: "${title.text}" (신뢰도: ${title.confidence.toStringAsFixed(2)})');
      }
      
      // 처리 과정 로그 출력
      for (final step in ocrResult.processingSteps) {
        debugPrint('   🔄 $step');
      }
      
      if (ocrResult.reorderedText.isNotEmpty) {
        final preview = ocrResult.reorderedText.length > 30 ? 
            '${ocrResult.reorderedText.substring(0, 30)}...' : ocrResult.reorderedText;
        debugPrint('🧹 재배열된 텍스트: "$preview"');
      }
    }

    return ocrResult;
  }

  /// 3단계: PageProcessingData 생성
  Future<PageProcessingData> _createPageProcessingData({
    required String pageId,
    required File imageFile,
    required List<String> textSegments,
    required TextProcessingMode mode,
    required String sourceLanguage,
    required String targetLanguage,
    required List<String> detectedTitles,
    required String originalText,
    required String cleanedText,
    required String reorderedText,
  }) async {
    if (kDebugMode) {
      debugPrint('📊 3단계: PageProcessingData 생성 시작');
    }

    final pageData = PageProcessingData(
      pageId: pageId,
      imageUrl: await _getImageUrl(pageId),
      textSegments: textSegments,
      mode: mode,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      imageFileSize: await _getFileSize(imageFile),
      ocrSuccess: originalText.isNotEmpty,
      detectedTitles: detectedTitles,
      originalText: originalText,
      cleanedText: cleanedText,
      reorderedText: reorderedText,
    );

    if (kDebugMode) {
      debugPrint('✅ PageProcessingData 생성 완료');
      debugPrint('   페이지 ID: ${pageData.pageId}');
      debugPrint('   텍스트 세그먼트: ${pageData.textSegments.length}개');
      debugPrint('   감지된 제목: ${pageData.detectedTitles.length}개');
      if (pageData.detectedTitles.isNotEmpty) {
        for (int i = 0; i < pageData.detectedTitles.length; i++) {
          debugPrint('     - 제목 ${i+1}: "${pageData.detectedTitles[i]}"');
        }
      }
      debugPrint('   OCR 성공: ${pageData.ocrSuccess}');
    }

    return pageData;
  }

  /// 4단계: 페이지 업데이트
  Future<void> _updatePageWithProcessingResult(PageProcessingData pageData) async {
    if (kDebugMode) {
      debugPrint('📄 4단계: 페이지 데이터 업데이트 시작');
    }

    // 1차 ProcessedText 생성 (원문만, 타이프라이터 효과용)
    final initialProcessedText = ProcessedText.withOriginalOnly(
      mode: pageData.mode,
      originalSegments: pageData.textSegments,
      sourceLanguage: pageData.sourceLanguage,
      targetLanguage: pageData.targetLanguage,
    );

    // OCR 결과 및 1차 ProcessedText 업데이트 (제목 정보 포함)
    await _pageService.updatePage(pageData.pageId, {
      'originalText': pageData.textSegments.join(' '),
      'ocrCompletedAt': FieldValue.serverTimestamp(),
      'status': ProcessingStatus.textExtracted.toString(),
      // 원문 세그먼트를 임시 저장 (LLM 처리용)
      'textSegments': pageData.textSegments,
      'processingMode': pageData.mode.toString(),
      'sourceLanguage': pageData.sourceLanguage,
      'targetLanguage': pageData.targetLanguage,
      // OCR 후처리 결과 저장
      'detectedTitles': pageData.detectedTitles,
      'ocrOriginalText': pageData.originalText,
      'ocrCleanedText': pageData.cleanedText,
      'ocrReorderedText': pageData.reorderedText,
      // 1차 ProcessedText 저장 (원문만, 타이프라이터 효과용)
      'processedText': {
        'units': initialProcessedText.units.map((unit) => unit.toJson()).toList(),
        'mode': initialProcessedText.mode.toString(),
        'displayMode': initialProcessedText.displayMode.toString(),
        'fullOriginalText': initialProcessedText.fullOriginalText,
        'fullTranslatedText': '', // 아직 번역 없음
        'sourceLanguage': pageData.sourceLanguage,
        'targetLanguage': pageData.targetLanguage,
        'streamingStatus': initialProcessedText.streamingStatus.index,
        'completedUnits': 0,
        'progress': 0.0,
      },
    });

    if (kDebugMode) {
      debugPrint('✅ 페이지 데이터 업데이트 완료: ${pageData.pageId}');
      debugPrint('   원문 세그먼트: ${pageData.textSegments.length}개');
      debugPrint('   감지된 제목: ${pageData.detectedTitles.length}개');
      debugPrint('   OCR 후처리 결과: 원본→정리→재배열 텍스트 저장됨');
      debugPrint('   1차 ProcessedText: 원문만 포함');
      debugPrint('   2차 ProcessedText는 LLM 완료 후 생성됩니다');
    }
  }

  // ========== 헬퍼 메서드들 ==========

  /// 빈 페이지 데이터 생성 (OCR 실패 시)
  Future<PageProcessingData> _createEmptyPageData(
    String pageId,
    TextProcessingMode mode,
    String sourceLanguage,
    String targetLanguage,
    File imageFile,
  ) async {
    if (kDebugMode) {
      debugPrint('⚠️ OCR 결과가 비어있어 빈 PageProcessingData 생성');
    }

    return PageProcessingData(
      pageId: pageId,
      imageUrl: await _getImageUrl(pageId),
      textSegments: [],
      mode: mode,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      imageFileSize: await _getFileSize(imageFile),
      ocrSuccess: false,
      detectedTitles: [],
      originalText: '',
      cleanedText: '',
      reorderedText: '',
    );
  }

  /// 이미지 URL 가져오기
  Future<String> _getImageUrl(String pageId) async {
    try {
      final page = await _pageService.getPage(pageId);
      return page?.imageUrl ?? '';
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 페이지에서 이미지 URL 가져오기 실패: $e');
      }
      return '';
    }
  }

  /// 파일 크기 가져오기
  Future<int> _getFileSize(File imageFile) async {
    try {
      return await imageFile.length();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 파일 크기 계산 실패: $e');
      }
      return 0;
    }
  }
}


