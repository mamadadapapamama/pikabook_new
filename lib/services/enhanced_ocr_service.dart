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
import '../models/processed_text.dart';
import '../models/text_segment.dart';
import 'translation_service.dart';
import 'chinese_segmenter_service.dart';
import 'text_cleaner_service.dart';
import 'pinyin_creation_service.dart';

/// 개선된 OCR 서비스 : OCR 처리 후 모드에 따라 다른 처리를 수행합니다.
/// 전문 서적 모드 : 핀인 제거 후 전체 텍스트 번역
/// 언어 학습 모드:  문장별 분리, 번역 후 핀인 처리

class EnhancedOcrService {
  // 싱글톤 패턴 구현
  static final EnhancedOcrService _instance = EnhancedOcrService._internal();
  factory EnhancedOcrService() => _instance;
  EnhancedOcrService._internal();

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
  final ChineseSegmenterService _segmenterService = ChineseSegmenterService();

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
  ) async {
    try {
      // 이미지에서 텍스트 추출
      final extractedText = await extractText(imageFile);
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
  Future<ProcessedText> processText(
    String text,
    String mode,
  ) async {
    if (text.isEmpty) {
      return ProcessedText(fullOriginalText: '');
    }

    try {
      // 언어 학습 모드 처리 (항상 사용)
      return await _processLanguageLearning(text);
    } catch (e) {
      debugPrint('텍스트 처리 오류: $e');
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

      // 전체 번역
      final fullTranslatedText = await _translationService
          .translateText(cleanedText, targetLanguage: 'ko');

      // 문장을 병렬로 처리
      final segments = await _processTextSegmentsInParallel(cleanedText);

      return ProcessedText(
        fullOriginalText: cleanedText,
        fullTranslatedText: fullTranslatedText,
        segments: segments,
        showFullText: false, // 세그먼트별 표시
      );
    } catch (e) {
      debugPrint('언어 학습 모드 처리 오류: $e');
      return ProcessedText(fullOriginalText: fullText);
    }
  }

  /// 전문 서적 모드 텍스트 처리 - 사용하지 않지만 호환성을 위해 유지
  Future<ProcessedText> _processProfessionalReading(String fullText) async {
    try {
      // 단순히 원본 텍스트만 반환
      return ProcessedText(
        fullOriginalText: fullText,
      );
    } catch (e) {
      debugPrint('전문 서적 모드 처리 오류: $e');
      return ProcessedText(fullOriginalText: fullText);
    }
  }

  /// 문장을 병렬로 처리
  Future<List<TextSegment>> _processTextSegmentsInParallel(String text) async {
    // 문장 분리
    final sentences = await _segmenterService.splitIntoSentences(text);
    debugPrint('분리된 문장 수: ${sentences.length}');

    if (sentences.isEmpty) {
      return [];
    }

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

      // 배치 처리 후 잠시 대기하여 UI 스레드 차단 방지
      if (end < sentences.length) {
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

      // 번역
      final translated = await _translationService.translateText(
        sentence,
        targetLanguage: 'ko',
      );

      return TextSegment(
        originalText: sentence,
        pinyin: pinyin,
        translatedText: translated,
      );
    } catch (e) {
      debugPrint('문장 처리 중 오류 발생: $e');
      // 오류가 발생해도 기본 세그먼트 반환
      return TextSegment(
        originalText: sentence,
        pinyin: '',
        translatedText: '번역 오류',
      );
    }
  }

  /// 문장에서 중국어 문자만 추출하여 핀인 생성
  Future<String> _generatePinyinForSentence(String sentence) async {
    try {
      // 중국어 문자만 추출
      final chineseCharsOnly =
          _textCleanerService.extractChineseChars(sentence);
      if (chineseCharsOnly.isEmpty) {
        return '';
      }

      // 핀인 생성
      return await _pinyinService.generatePinyin(chineseCharsOnly);
    } catch (e) {
      debugPrint('핀인 생성 중 오류 발생: $e');
      return '';
    }
  }

  /// 이미지에서 텍스트 추출 (OCR)
  Future<String> extractText(File imageFile) async {
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
}
