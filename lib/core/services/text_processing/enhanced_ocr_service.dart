// MARK: 다국어 지원을 위한 확장 포인트
// 이 서비스는 향후 다국어 지원을 위해 확장될 예정입니다.
// 현재는 중국어 텍스트 추출에 초점이 맞춰져 있습니다.
// 향후 각 언어별 최적화된 OCR 처리가 추가될 예정입니다.

import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/vision/v1.dart' as vision;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pinyin/pinyin.dart';
import '../../models/processed_text.dart';
import '../../models/text_segment.dart';
import 'translation_service.dart';
import 'internal_cn_segmenter_service.dart';
import 'text_cleaner_service.dart';
import 'pinyin_creation_service.dart';
import '../authentication/user_preferences_service.dart';
import 'package:crypto/crypto.dart';
import '../../../features/note_detail/managers/content_manager.dart'; // ContentManager 임포트

/// 개선된 OCR 서비스 : OCR 처리 후 모드에 따라 다른 처리를 수행합니다.
/// 전문 서적 모드 : 핀인 제거 후 전체 텍스트 번역
/// 언어 학습 모드:  문장별 분리, 번역 후 핀인 처리

class EnhancedOcrService {
  // 싱글톤 패턴 구현
  static final EnhancedOcrService _instance = EnhancedOcrService._internal();
  factory EnhancedOcrService() => _instance;
  EnhancedOcrService._internal() {
    debugPrint('🤖 EnhancedOcrService: 생성자 호출됨');
  }

  // Google Cloud Vision API 클라이언트
  vision.VisionApi? _visionApi;

  // 감지할 언어 설정 (MVP에서는 중국어만 지원)
  final String _targetLanguage = 'zh-CN'; // 중국어

  // 언어 감지 서비스

  // 텍스트 정리 서비스
  final TextCleanerService _textCleanerService = TextCleanerService();

  // 핀인 생성 서비스
  final PinyinCreationService _pinyinService = PinyinCreationService();

  // 번역 서비스
  final TranslationService _translationService = TranslationService();

  // 중국어 분할 서비스
  final InternalCnSegmenterService _segmenterService = InternalCnSegmenterService();

  // 사용자 설정 서비스 추가
  final UserPreferencesService _preferencesService = UserPreferencesService();

  // API 초기화
  Future<void> initialize() async {
    if (_visionApi != null) return;

    try {
      // 서비스 계정 키 파일 로드
      final credentialsFile = await _loadCredentialsFile();

      // 인증 클라이언트 생성
      final client = await clientViaServiceAccount(
        ServiceAccountCredentials.fromJson(credentialsFile),
        [vision.VisionApi.cloudVisionScope],
      );

      // Vision API 클라이언트 생성
      _visionApi = vision.VisionApi(client);

      debugPrint('Google Cloud Vision API 초기화 완료');
    } catch (e) {
      debugPrint('Google Cloud Vision API 초기화 중 오류 발생: $e');
      throw Exception('OCR 서비스를 초기화할 수 없습니다: $e');
    }
  }

  // 서비스 계정 키 파일 로드
  Future<Map<String, dynamic>> _loadCredentialsFile() async {
    try {
      // 먼저 앱 문서 디렉토리에서 키 파일 확인
      final directory = await getApplicationDocumentsDirectory();
      final credentialsPath = '${directory.path}/google_cloud_credentials.json';
      final file = File(credentialsPath);

      if (await file.exists()) {
        final contents = await file.readAsString();
        return json.decode(contents) as Map<String, dynamic>;
      } else {
        // 앱 문서 디렉토리에 파일이 없으면 assets에서 로드하여 복사
        try {
          // assets에서 키 파일 로드 (service-account.json으로 변경)
          final String jsonString = await rootBundle
              .loadString('assets/credentials/service-account.json');

          // 앱 문서 디렉토리에 파일 저장
          await file.create(recursive: true);
          await file.writeAsString(jsonString);

          return json.decode(jsonString) as Map<String, dynamic>;
        } catch (assetError) {
          debugPrint('assets에서 서비스 계정 키 파일 로드 중 오류 발생: $assetError');
          throw Exception('서비스 계정 키 파일을 찾을 수 없습니다.');
        }
      }
    } catch (e) {
      debugPrint('서비스 계정 키 파일 로드 중 오류 발생: $e');
      throw Exception('서비스 계정 키 파일을 로드할 수 없습니다: $e');
    }
  }

  /// 이미지에서 텍스트 추출 및 처리
  Future<ProcessedText> processImage(
    File imageFile,
    String mode,
    {bool skipUsageCount = false}
  ) async {
    try {
      // 이미지에서 텍스트 추출
      final extractedText = await extractText(imageFile, skipUsageCount: skipUsageCount);
      if (extractedText.isEmpty) {
        return ProcessedText(fullOriginalText: '');
      }

      // 추출된 텍스트 처리
      return await processText(extractedText, mode);
    } catch (e) {
      debugPrint('OCR 이미지 처리 오류: $e');
      return ProcessedText(fullOriginalText: '');
    }
  }

  /// 텍스트 처리 (모드에 따라 다르게 처리)
  Future<ProcessedText> processText(String text, String mode) async {
    try {
      // 입력 텍스트 확인
      if (text.isEmpty) {
        debugPrint('OCR processText: 빈 텍스트 입력');
        return ProcessedText(fullOriginalText: '');
      }
      
      // 특수 처리 중 문자열인 경우 처리 없이 반환
      if (text == '___PROCESSING___' || text == 'processing' || text.contains('텍스트 처리 중')) {
        debugPrint('OCR processText: 특수 처리 중 문자열 감지("$text"), 처리 생략');
        return ProcessedText(
          fullOriginalText: text,
          fullTranslatedText: '',
          segments: [], // 빈 세그먼트 목록 제공
          showFullText: false,
          showPinyin: true,
          showTranslation: true,
        );
      }
      
      // 모드 선택
      switch (mode) {
        case "languageLearning":
          return await _processLanguageLearning(text);
        default:
          debugPrint('알 수 없는 모드: $mode, 기본값(languageLearning) 사용');
          return await _processLanguageLearning(text);
      }
    } catch (e) {
      debugPrint('OCR 처리 중 오류 발생: $e');
      return ProcessedText(fullOriginalText: text);
    }
  }

  /// **언어 학습 모드 텍스트 처리**
  Future<ProcessedText> _processLanguageLearning(String fullText) async {
    try {
      if (fullText.isEmpty) {
        return ProcessedText(fullOriginalText: '');
      }

      // 핀인 줄 제거한 전체 텍스트
      final cleanedText = _textCleanerService.removePinyinLines(fullText);
      debugPrint('OCR _processLanguageLearning: 정리된 텍스트 ${cleanedText.length}자');

      // 사용자 세그먼트 모드 설정을 가져옴
      final useSegmentMode = await _preferencesService.getUseSegmentMode();
      debugPrint('OCR _processLanguageLearning: 사용자 세그먼트 모드: $useSegmentMode');

      String? fullTranslatedText;
      List<TextSegment>? segments;

      // 세그먼트 모드가 아닌 경우에만 전체 번역 수행
      if (!useSegmentMode) {
        debugPrint('OCR _processLanguageLearning: 전체 번역 모드 - 전체 텍스트 번역 시작...');
        // 중국어에서 한국어로 명시적으로 언어 코드 설정
        fullTranslatedText = await _translationService.translateText(
          cleanedText, 
          sourceLanguage: 'zh-CN',  // 명시적으로 중국어 소스 언어 설정 
          targetLanguage: 'ko'      // 명시적으로 한국어 타겟 언어 설정
        );
        
        // 번역 결과 검증 로그
        bool isTranslationSuccessful = fullTranslatedText != cleanedText;
        
        if (!isTranslationSuccessful) {
          debugPrint('OCR _processLanguageLearning: 심각한 경고! 번역 결과가 원문과 동일함');
          debugPrint('OCR _processLanguageLearning: 원본 샘플: "${cleanedText.length > 30 ? cleanedText.substring(0, 30) + '...' : cleanedText}"');
          debugPrint('OCR _processLanguageLearning: 번역 샘플: "${fullTranslatedText.length > 30 ? fullTranslatedText.substring(0, 30) + '...' : fullTranslatedText}"');
        } else {
          debugPrint('OCR _processLanguageLearning: 번역 성공! 번역 결과 ${fullTranslatedText.length}자');
          debugPrint('OCR _processLanguageLearning: 번역 결과 샘플: "${fullTranslatedText.length > 30 ? fullTranslatedText.substring(0, 30) + '...' : fullTranslatedText}"');
        }
      } else {
        debugPrint('OCR _processLanguageLearning: 세그먼트 모드 - 전체 텍스트 번역 건너뜀');
      }

      // 세그먼트 모드인 경우에만 개별 문장 번역 수행
      if (useSegmentMode) {
        debugPrint('OCR _processLanguageLearning: 세그먼트 모드 - 문장별 번역 시작...');
        
        // 문장을 병렬로 처리 - 이 부분을 바로 실행
        segments = await _processTextSegmentsInParallel(cleanedText);
        
        // 세그먼트가 있는 경우 세그먼트 번역 상태 확인
        if (segments.isNotEmpty) {
          int untranslatedCount = 0;
          for (var segment in segments) {
            if (segment.translatedText == segment.originalText) {
              untranslatedCount++;
            }
          }
          if (untranslatedCount > 0) {
            debugPrint('OCR _processLanguageLearning: 경고! $untranslatedCount/${segments.length} 세그먼트의 번역이 원문과 동일함');
          }
        }
      } else {
        debugPrint('OCR _processLanguageLearning: 전체 번역 모드 - 문장별 번역 건너뜀');
      }
      
      // 최종 검증 로그
      debugPrint('OCR _processLanguageLearning: 처리 완료. 원문: ${cleanedText.length}자, '
          '번역: ${fullTranslatedText?.length ?? "없음"}자, '
          '세그먼트: ${segments?.length ?? 0}개');

      return ProcessedText(
        fullOriginalText: cleanedText,
        fullTranslatedText: fullTranslatedText,
        segments: segments,
        showFullText: !useSegmentMode, // 사용자 선택에 따라 초기 표시 모드 설정
      );
    } catch (e) {
      debugPrint('언어 학습 모드 처리 오류: $e');
      return ProcessedText(fullOriginalText: fullText);
    }
  }


  /// 문장을 병렬로 처리
  Future<List<TextSegment>> _processTextSegmentsInParallel(String text) async {
    try {
      if (text.isEmpty) {
        return [];
      }

      // 중국어 문장 분리
      final sentences = _segmenterService.splitIntoSentences(text);
      debugPrint('추출된 문장 수: ${sentences.length}');

      // 빈 문장 필터링
      final filteredSentences = sentences
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      
      debugPrint('필터링 후 문장 수: ${filteredSentences.length}');

      // 항상 순차 처리 방식 사용 - Isolate 병렬 처리 문제 방지
      return _processTextSegmentsSequentially(filteredSentences);
    } catch (e) {
      debugPrint('문장 병렬 처리 중 오류 발생: $e');
      return [];
    }
  }
  
  // 문장을 순차적으로 처리
  Future<List<TextSegment>> _processTextSegmentsSequentially(List<String> sentences) async {
    debugPrint('순차적 문장 처리 시작: ${sentences.length}개');
    
    // 병렬 처리를 위한 배치 크기 설정
    const int batchSize = 5;
    final List<TextSegment> allSegments = [];

    // 배치 단위로 처리하여 메모리 사용량 최적화
    for (int i = 0; i < sentences.length; i += batchSize) {
      final end =
          (i + batchSize < sentences.length) ? i + batchSize : sentences.length;
      final batch = sentences.sublist(i, end);

      // 배치 내 문장들을 병렬로 처리
      final batchResults = await Future.wait(
        batch.map((sentence) => _processTextSegment(sentence)),
      );

      allSegments.addAll(batchResults);

      // UI 스레드 차단 방지 (필요한 경우만)
      if (end < sentences.length && allSegments.length > 10) {
        await Future.delayed(Duration(milliseconds: 1));
      }
    }

    return allSegments;
  }

  /// 개별 문장 처리
  Future<TextSegment> _processTextSegment(String sentence) async {
    try {
      // 핀인 생성
      final pinyin = await _generatePinyinForSentence(sentence);

      // 번역 시 언어 코드 명시적 설정
      debugPrint('_processTextSegment: 문장 번역 시작 (${sentence.length}자)');
      final translated = await _translationService.translateText(
        sentence,
        sourceLanguage: 'zh-CN',  // 중국어 소스 언어 명시
        targetLanguage: 'ko',     // 한국어 타겟 언어 명시
      );
      
      // 번역 결과 검증
      if (translated == sentence) {
        debugPrint('_processTextSegment: 경고 - 문장 번역 결과가 원문과 동일함');
      } else {
        debugPrint('_processTextSegment: 문장 번역 성공 (${translated.length}자)');
      }

      return TextSegment(
        originalText: sentence,
        pinyin: pinyin,
        translatedText: translated,
        sourceLanguage: 'zh-CN',  // 중국어 소스 언어 명시
        targetLanguage: 'ko',     // 한국어 타겟 언어 명시
      );
    } catch (e) {
      debugPrint('문장 처리 중 오류 발생: $e');
      // 오류가 발생해도 기본 세그먼트 반환
      return TextSegment(
        originalText: sentence,
        pinyin: '',
        translatedText: '번역 오류',
        sourceLanguage: 'zh-CN',
        targetLanguage: 'ko',
      );
    }
  }

  /// 문장에서 중국어 문자만 추출하여 핀인 생성 (Isolate 사용)
  Future<String> _generatePinyinForSentence(String sentence) async {
    try {
      // 중국어 문자만 추출
      final chineseCharsOnly =
          _textCleanerService.extractChineseChars(sentence);
      if (chineseCharsOnly.isEmpty) {
        return '';
      }

      // PinyinCreationService의 Isolate 처리 메서드 호출
      // 텍스트 클리닝은 메인 Isolate에서 수행하고, 실제 핀인 생성만 Isolate로 보냄
      return await _pinyinService.generatePinyinIsolate(chineseCharsOnly); 
    } catch (e) {
      debugPrint('핀인 생성 중 오류 발생: $e');
      return '';
    }
  }

  /// 이미지에서 텍스트 추출 (OCR)
  Future<String> extractText(File imageFile, {bool skipUsageCount = false}) async {
    try {
      await initialize();

      if (_visionApi == null) {
        throw Exception('Vision API가 초기화되지 않았습니다.');
      }

      // 이미지 파일을 base64로 인코딩
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Vision API 요청 생성
      final request = vision.AnnotateImageRequest();
      request.image = vision.Image()..content = base64Image;
      request.features = [
        vision.Feature()
          ..type = 'TEXT_DETECTION'
          ..maxResults = 1
      ];

      // 언어 힌트 추가 (중국어 우선)
      request.imageContext = vision.ImageContext()
        ..languageHints = ['zh-CN', 'zh-TW', 'ja', 'ko', 'en'];

      // API 요청 전송
      final batchRequest = vision.BatchAnnotateImagesRequest()
        ..requests = [request];
      final response = await _visionApi!.images.annotate(batchRequest);

      // 응답 처리
      if (response.responses == null || response.responses!.isEmpty) {
        return '';
      }

      final textAnnotation = response.responses![0].fullTextAnnotation;
      if (textAnnotation == null) {
        return '';
      }

      String extractedText = textAnnotation.text ?? '';

      // TextCleanerService를 사용하여 불필요한 텍스트 제거
      extractedText = _textCleanerService.cleanText(extractedText);

      return extractedText;
    } catch (e) {
      debugPrint('텍스트 추출 중 오류 발생: $e');
      return '';
    }
  }

  // 텍스트에 대한 해시 생성 (세그먼트 캐싱용)
  String _computeTextHash(String text) {
    var bytes = utf8.encode(text);
    var digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16); // 16자리로 제한
  }
}
