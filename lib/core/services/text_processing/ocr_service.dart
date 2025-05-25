import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/vision/v1.dart' as vision;
import 'package:googleapis_auth/auth_io.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/models/processed_text.dart';
import '../../../core/models/text_unit.dart';
import 'text_cleaner_service.dart';
import 'text_mode_seperation_service.dart';
import '../authentication/user_preferences_service.dart';
import '../../core/services/common/usage_limit_service.dart';

/// OCR 서비스
/// 이미지에서 '중국어' 우선추출
/// 텍스트 클리닝 및 모드별 분리 담당
/// (LLM 처리는 별도 서비스에서 담당)
///  
class OcrService {
  // 싱글톤 패턴 구현
  static final OcrService _instance = OcrService._internal();
  factory OcrService() => _instance;
  OcrService._internal() {
    debugPrint('🤖 OcrService: 생성자 호출됨');
  }

  // Google Cloud Vision API 클라이언트
  vision.VisionApi? _visionApi;

  // 텍스트 정리 서비스
  final TextCleanerService _textCleanerService = TextCleanerService();

  // 텍스트 모드별 분리 서비스
  final TextModeSeparationService _separationService = TextModeSeparationService();

  // 사용자 설정 서비스
  final UserPreferencesService _preferencesService = UserPreferencesService();

  // 사용량 제한 서비스
  final UsageLimitService _usageLimitService = UsageLimitService();

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
          // assets에서 키 파일 로드
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

  /// 이미지에서 텍스트 추출 및 기본 처리
  /// 처리 순서:
  /// 1. OCR로 텍스트 추출 (Google Cloud Vision API)
  /// 2. TextCleanerService로 불필요한 텍스트 제거 (중국어만 추출)
  /// 3. 사용자 설정에 따라 문장/문단 단위로 분리
  /// (LLM 번역/병음 처리는 별도 서비스에서 담당)
  Future<ProcessedText> processImage(
    File imageFile,
    TextProcessingMode mode,
    {bool skipUsageCount = false}
  ) async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 OCR 이미지 처리 시작: 모드=$mode');
      }

      // 1. OCR로 텍스트 추출
      final extractedText = await extractText(imageFile, skipUsageCount: skipUsageCount);
      if (extractedText.isEmpty) {
        if (kDebugMode) {
          debugPrint('⚠️ OCR 결과가 비어있음');
        }
        return _createEmptyProcessedText(mode);
      }

      if (kDebugMode) {
        debugPrint('✅ OCR 추출 완료: ${extractedText.length}자');
        debugPrint('추출된 텍스트 샘플: "${extractedText.substring(0, extractedText.length > 50 ? 50 : extractedText.length)}..."');
      }

      // 2. 사용자 설정 가져오기
      final userPrefs = await _preferencesService.getPreferences();
      final sourceLanguage = userPrefs.sourceLanguage;
      final targetLanguage = userPrefs.targetLanguage;

      if (kDebugMode) {
        debugPrint('📊 사용자 설정: $sourceLanguage -> $targetLanguage');
      }

      // 3. 모드에 따라 텍스트 분리
      final textSegments = _separationService.separateByMode(extractedText, mode);

      if (kDebugMode) {
        debugPrint('📝 텍스트 분리 완료: ${textSegments.length}개 단위');
      }

      // 4. 기본 TextUnit 생성 (번역/병음은 빈 상태로)
      final units = textSegments.map((segment) => TextUnit(
        originalText: segment,
        translatedText: '', // LLM 서비스에서 채울 예정
        pinyin: '', // LLM 서비스에서 채울 예정
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      )).toList();

      // 5. 최종 ProcessedText 생성
      final result = ProcessedText(
        mode: mode,
        displayMode: TextDisplayMode.full,
        fullOriginalText: extractedText,
        fullTranslatedText: '', // LLM 서비스에서 채울 예정
        units: units,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      );

      if (kDebugMode) {
        debugPrint('🎉 OCR 처리 완료:');
        debugPrint('  모드: $mode');
        debugPrint('  원문: ${result.fullOriginalText.length}자');
        debugPrint('  분리된 단위: ${result.units.length}개');
        debugPrint('  (번역/병음은 LLM 서비스에서 처리 예정)');
      }

      return result;

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ OCR 이미지 처리 중 오류: $e');
      }
      return _createEmptyProcessedText(mode);
    }
  }

  /// 빈 ProcessedText 생성
  ProcessedText _createEmptyProcessedText(TextProcessingMode mode) {
    return ProcessedText(
      mode: mode,
      displayMode: TextDisplayMode.full,
      fullOriginalText: '',
      fullTranslatedText: '',
      units: [],
      sourceLanguage: 'zh-CN',
      targetLanguage: 'ko'
    );
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
          ..type = 'DOCUMENT_TEXT_DETECTION'
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
      
      // OCR 사용량 증가 (skipUsageCount가 false인 경우에만)
      if (!skipUsageCount) {
        try {
          debugPrint('OCR 사용량 카운트 증가 시작');
          await _usageLimitService.incrementOcrPageCount(1, allowOverLimit: true);
          debugPrint('OCR 사용량 카운트 증가 완료');
        } catch (e) {
          debugPrint('OCR 사용량 증가 중 오류 발생: $e');
        }
      } else {
        debugPrint('OCR 사용량 카운트 건너뜀 (skipUsageCount=true)');
      }

      return extractedText;
    } catch (e) {
      debugPrint('텍스트 추출 중 오류 발생: $e');
      return '';
    }
  }

  /// 이미지에서 텍스트 인식만 수행 (TextViewModel용)
  Future<String> recognizeText(File imageFile) async {
    return await extractText(imageFile, skipUsageCount: false);
  }
}
