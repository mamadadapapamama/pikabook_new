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
import '../../models/processed_text.dart';
import 'text_cleaner_service.dart';
import '../authentication/user_preferences_service.dart';
import '../common/usage_limit_service.dart'; // 사용량 제한 서비스 추가
import 'package:crypto/crypto.dart';

/// 개선된 OCR 서비스 : 이미지에서 텍스트 추출 기능 제공

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

  // 텍스트 정리 서비스
  final TextCleanerService _textCleanerService = TextCleanerService();

  // 사용자 설정 서비스 추가
  final UserPreferencesService _preferencesService = UserPreferencesService();
  
  // 사용량 제한 서비스 추가
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

  /// 이미지에서 텍스트 추출만 수행 (처리 로직 제거)
  Future<ProcessedText> processImage(
    File imageFile,
    String mode,
    {bool skipUsageCount = false}
  ) async {
    try {
      // 이미지에서 텍스트 추출
      final extractedText = await extractText(imageFile, skipUsageCount: skipUsageCount);
      if (extractedText.isEmpty) {
        return ProcessedText(
          mode: TextProcessingMode.segment,
          fullOriginalText: ''
        );
      }

      // 추출된 텍스트만 반환 (추가 처리 없음)
      return ProcessedText(
        mode: TextProcessingMode.segment,
        fullOriginalText: extractedText
      );
    } catch (e) {
      debugPrint('OCR 이미지 처리 오류: $e');
      return ProcessedText(
        mode: TextProcessingMode.segment,
        fullOriginalText: ''
      );
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
      
      // OCR 사용량 증가 (skipUsageCount가 false인 경우에만)
      if (!skipUsageCount) {
        try {
          debugPrint('OCR 사용량 카운트 증가 시작');
          // 이미지당 1페이지로 계산하여 OCR 사용량 증가
          await _usageLimitService.incrementOcrPageCount(1, allowOverLimit: true);
          debugPrint('OCR 사용량 카운트 증가 완료');
        } catch (e) {
          debugPrint('OCR 사용량 증가 중 오류 발생: $e');
          // 사용량 증가 실패해도 OCR 결과는 반환
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

  // 텍스트에 대한 해시 생성 (세그먼트 캐싱용)
  String _computeTextHash(String text) {
    var bytes = utf8.encode(text);
    var digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16); // 16자리로 제한
  }
}
