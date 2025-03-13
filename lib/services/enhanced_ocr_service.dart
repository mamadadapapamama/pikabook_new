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
import '../models/text_processing_mode.dart';
import '../models/processed_text.dart';
import '../models/text_segment.dart';
import 'language_detection_service.dart';
import 'translation_service.dart';
import 'chinese_segmenter_service.dart';

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
  final LanguageDetectionService _languageDetectionService =
      LanguageDetectionService();

  // 번역 서비스
  final TranslationService _translationService = TranslationService();

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
  /// 모드에 따라 다른 처리를 수행합니다.
  Future<ProcessedText> processImage(
      File imageFile, TextProcessingMode mode) async {
    try {
      await initialize();

      if (_visionApi == null) {
        throw Exception('Vision API가 초기화되지 않았습니다.');
      }

      // 이미지 파일을 base64로 인코딩
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      // API 요청 생성
      final request = vision.AnnotateImageRequest()
        ..image = (vision.Image()..content = base64Image)
        ..features = [
          vision.Feature()
            ..type = 'TEXT_DETECTION'
            ..maxResults = 50
        ]
        ..imageContext =
            (vision.ImageContext()..languageHints = [_targetLanguage, 'en']);

      // API 호출
      final response = await _visionApi!.images.annotate(
        vision.BatchAnnotateImagesRequest()..requests = [request],
      );

      // 결과 처리
      final annotations = response.responses?[0];
      if (annotations?.textAnnotations != null &&
          annotations!.textAnnotations!.isNotEmpty) {
        // 전체 텍스트 (첫 번째 항목)
        final fullText = annotations.textAnnotations![0].description ?? '';
        debugPrint('감지된 전체 텍스트: $fullText');

        // 모드에 따라 다른 처리 수행
        if (mode == TextProcessingMode.professionalReading) {
          // 전문 서적 모드: 핀인 제거 후 전체 텍스트 처리
          return await _processProfessionalReading(fullText);
        } else {
          // 언어 학습 모드: 문장별 처리
          return await _processLanguageLearning(fullText);
        }
      }

      // 텍스트가 감지되지 않은 경우
      return ProcessedText(
        fullOriginalText: '텍스트가 감지되지 않았습니다.',
        fullTranslatedText: '텍스트가 감지되지 않았습니다.',
      );
    } catch (e) {
      debugPrint('OCR 텍스트 추출 중 오류 발생: $e');
      throw Exception('이미지에서 텍스트를 추출할 수 없습니다: $e');
    }
  }

  /// 전문 서적 모드 처리
  /// 핀인 제거 후 전체 텍스트 번역
  Future<ProcessedText> _processProfessionalReading(String fullText) async {
    // 핀인 줄 제거
    final cleanedText = _languageDetectionService.removePinyinLines(fullText);

    // 번역
    final translatedText = await _translationService.translateText(cleanedText,
        targetLanguage: 'ko');

    return ProcessedText(
      fullOriginalText: cleanedText,
      fullTranslatedText: translatedText,
      segments: null, // 세그먼트 없음
      showFullText: true, // 전체 텍스트 표시
    );
  }

  /// 언어 학습 모드 처리
  /// 문장별로 분리하여 번역 및 핀인 처리
  Future<ProcessedText> _processLanguageLearning(String fullText) async {
    // 핀인 줄 제거한 전체 텍스트
    final cleanedText = _languageDetectionService.removePinyinLines(fullText);

    // 전체 번역
    final fullTranslatedText = await _translationService
        .translateText(cleanedText, targetLanguage: 'ko');

    // 문장 분리
    final segments = await _segmentText(fullText);

    return ProcessedText(
      fullOriginalText: cleanedText,
      fullTranslatedText: fullTranslatedText,
      segments: segments,
      showFullText: false, // 세그먼트별 표시
    );
  }

  /// 텍스트를 문장으로 분리하고 각 문장에 대해 번역 및 핀인 처리
  Future<List<TextSegment>> _segmentText(String text) async {
    // 줄 단위로 분리
    final lines = text.split('\n');
    final segments = <TextSegment>[];

    // 중국어 문장과 핀인 줄 매칭
    String? currentPinyin;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // 빈 줄 건너뛰기
      if (line.trim().isEmpty) continue;

      // 핀인 줄인지 확인
      if (_languageDetectionService.isPinyinLine(line)) {
        currentPinyin = line;
        continue;
      }

      // 중국어 문장이 있는 경우
      if (_languageDetectionService.containsChinese(line)) {
        // 번역
        final translatedText =
            await _translationService.translateText(line, targetLanguage: 'ko');

        // 핀인이 없는 경우 자동 생성 시도
        if (currentPinyin == null) {
          try {
            currentPinyin =
                await _languageDetectionService.generatePinyin(line);
            debugPrint('핀인 자동 생성: $currentPinyin');
          } catch (e) {
            debugPrint('핀인 자동 생성 실패: $e');
            // 핀인 생성 실패 시 기본 핀인 제공 (예시)
            currentPinyin = _generateSimplePinyin(line);
          }
        }

        // 세그먼트 추가
        segments.add(TextSegment(
          originalText: line,
          pinyin: currentPinyin,
          translatedText: translatedText,
        ));

        // 핀인 초기화 (다음 문장을 위해)
        currentPinyin = null;
      }
    }

    return segments;
  }

  /// 간단한 핀인 생성 (pinyin 패키지 사용)
  String _generateSimplePinyin(String chineseText) {
    try {
      // 문장 전체에 대한 핀인 생성
      return PinyinHelper.getPinyin(chineseText,
          format: PinyinFormat.WITH_TONE_MARK);
    } catch (e) {
      debugPrint('간단한 핀인 생성 중 오류 발생: $e');
      return '(pinyin for: ${chineseText.substring(0, min(10, chineseText.length))}...)';
    }
  }

  /// 텍스트 처리 (OCR 없이 기존 텍스트 처리)
  Future<ProcessedText> processText(String originalText, String translatedText,
      TextProcessingMode mode) async {
    if (originalText.isEmpty) {
      throw Exception('원본 텍스트가 비어 있습니다.');
    }

    // 전문 서적 모드: 전체 텍스트 표시
    if (mode == TextProcessingMode.professionalReading) {
      return ProcessedText(
        fullOriginalText: originalText,
        fullTranslatedText: translatedText,
        showFullText: true,
      );
    }

    // 언어 학습 모드: 문장별 처리
    final languageDetectionService = LanguageDetectionService();
    final translationService = TranslationService();
    final segmenterService = ChineseSegmenterService();

    // 문장 단위로 분리
    final originalSentences = segmenterService.splitIntoSentences(originalText);
    debugPrint('분리된 문장 수: ${originalSentences.length}개');

    // 번역된 텍스트가 있으면 문장 단위로 분리
    List<String> translatedSentences = [];
    if (translatedText.isNotEmpty) {
      translatedSentences = segmenterService.splitIntoSentences(translatedText);
      debugPrint('분리된 번역 문장 수: ${translatedSentences.length}개');
    }

    // 각 문장별로 번역 수행
    final segments = <TextSegment>[];
    final StringBuffer combinedTranslation = StringBuffer();

    // 문장 수가 일치하면 1:1 매핑
    if (originalSentences.length == translatedSentences.length) {
      for (int i = 0; i < originalSentences.length; i++) {
        final originalSentence = originalSentences[i];
        final translatedSentence = translatedSentences[i];
        String pinyin = '';

        // 중국어가 포함된 문장에 대해서만 핀인 생성
        if (languageDetectionService.containsChinese(originalSentence)) {
          try {
            // 문장에서 중국어 문자만 추출하여 핀인 생성
            final chineseCharsOnly = languageDetectionService.extractChineseChars(originalSentence);
            if (chineseCharsOnly.isNotEmpty) {
              pinyin = await languageDetectionService.generatePinyin(chineseCharsOnly);
            }
          } catch (e) {
            debugPrint('핀인 생성 실패: $e');
          }
        }

        segments.add(TextSegment(
          originalText: originalSentence,
          translatedText: translatedSentence,
          pinyin: pinyin,
        ));

        // 전체 번역 텍스트 구성
        if (combinedTranslation.isNotEmpty) {
          combinedTranslation.write('\n');
        }
        combinedTranslation.write(translatedSentence);
      }
    } 
    // 문장 수가 불일치하면 매핑 시도
    else if (translatedSentences.isNotEmpty) {
      final mappedSegments = translationService.mapOriginalAndTranslatedSentences(
          originalSentences, translatedSentences);

      for (final segment in mappedSegments) {
        String pinyin = '';
        if (languageDetectionService.containsChinese(segment.originalText)) {
          try {
            final chineseCharsOnly = languageDetectionService.extractChineseChars(segment.originalText);
            if (chineseCharsOnly.isNotEmpty) {
              pinyin = await languageDetectionService.generatePinyin(chineseCharsOnly);
            }
          } catch (e) {
            debugPrint('핀인 생성 실패: $e');
          }
        }

        segments.add(TextSegment(
          originalText: segment.originalText,
          translatedText: segment.translatedText ?? '',
          pinyin: pinyin,
        ));

        // 전체 번역 텍스트 구성
        if (combinedTranslation.isNotEmpty) {
          combinedTranslation.write('\n');
        }
        combinedTranslation.write(segment.translatedText ?? '');
      }
    }
    // 번역 텍스트가 없으면 새로 번역
    else {
      for (final originalSentence in originalSentences) {
        String pinyin = '';
        String sentenceTranslation = '';

        // 중국어가 포함된 문장에 대해서만 핀인 생성 및 번역
        if (languageDetectionService.containsChinese(originalSentence)) {
          try {
            // 핀인 생성
            final chineseCharsOnly = languageDetectionService.extractChineseChars(originalSentence);
            if (chineseCharsOnly.isNotEmpty) {
              pinyin = await languageDetectionService.generatePinyin(chineseCharsOnly);
            }

            // 번역 수행
            sentenceTranslation = await translationService.translateText(
                originalSentence, targetLanguage: 'ko');
          } catch (e) {
            debugPrint('핀인 생성 또는 번역 실패: $e');
          }
        } else {
          // 중국어가 없는 문장 처리
          try {
            sentenceTranslation = await translationService.translateText(
                originalSentence, targetLanguage: 'ko');
          } catch (e) {
            sentenceTranslation = originalSentence; // 번역 실패 시 원본 사용
          }
        }

        segments.add(TextSegment(
          originalText: originalSentence,
          translatedText: sentenceTranslation,
          pinyin: pinyin,
        ));

        // 번역 결과 추가
        if (combinedTranslation.isNotEmpty) {
          combinedTranslation.write('\n');
        }
        combinedTranslation.write(sentenceTranslation);
      }
    }

    return ProcessedText(
      fullOriginalText: originalText,
      fullTranslatedText: combinedTranslation.toString(),
      segments: segments,
      showFullText: false, // 문장별 모드로 시작
    );
  }
}
