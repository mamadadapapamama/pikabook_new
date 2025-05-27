import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/vision/v1.dart' as vision;
import 'package:googleapis_auth/auth_io.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/services/common/usage_limit_service.dart';

/// OCR 서비스 (순수 OCR 기능만 담당)
/// 
/// **책임:**
/// - Google Cloud Vision API를 사용한 이미지 텍스트 추출
/// - OCR 사용량 카운팅
/// - 원본 텍스트 반환 (정리/분리는 다른 서비스에서 담당)
/// 
/// **사용 예시:**
/// ```dart
/// final ocrService = OcrService();
/// final rawText = await ocrService.extractText(imageFile);
/// ```
class OcrService {
  // 싱글톤 패턴 구현
  static final OcrService _instance = OcrService._internal();
  factory OcrService() => _instance;
  OcrService._internal() {
    if (kDebugMode) {
      debugPrint('🤖 OcrService: 순수 OCR 서비스 초기화');
    }
  }

  // Google Cloud Vision API 클라이언트
  vision.VisionApi? _visionApi;

  // 사용량 제한 서비스
  final UsageLimitService _usageLimitService = UsageLimitService();

  /// Google Cloud Vision API 초기화
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

      if (kDebugMode) {
        debugPrint('✅ Google Cloud Vision API 초기화 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Google Cloud Vision API 초기화 실패: $e');
      }
      throw Exception('OCR 서비스를 초기화할 수 없습니다: $e');
    }
  }

  /// 서비스 계정 키 파일 로드
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
          if (kDebugMode) {
            debugPrint('❌ assets에서 서비스 계정 키 파일 로드 실패: $assetError');
          }
          throw Exception('서비스 계정 키 파일을 찾을 수 없습니다.');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 서비스 계정 키 파일 로드 실패: $e');
      }
      throw Exception('서비스 계정 키 파일을 로드할 수 없습니다: $e');
    }
  }

  /// **메인 OCR 메서드: 이미지에서 원본 텍스트 추출**
  /// 
  /// Google Cloud Vision API를 사용하여 이미지에서 텍스트를 추출합니다.
  /// 원본 텍스트를 그대로 반환하며, 정리나 분리는 하지 않습니다.
  /// 
  /// **매개변수:**
  /// - `imageFile`: OCR을 수행할 이미지 파일
  /// - `skipUsageCount`: 사용량 카운팅 건너뛸지 여부 (기본값: false)
  /// 
  /// **반환값:**
  /// - 추출된 원본 텍스트 (정리되지 않은 상태)
  /// 
  /// **예시:**
  /// ```dart
  /// final rawText = await ocrService.extractText(imageFile);
  /// // rawText: "你好\nNǐ hǎo\npage 1\n世界\n..."
  /// ```
  Future<String> extractText(File imageFile, {bool skipUsageCount = false}) async {
    try {
      await initialize();

      if (_visionApi == null) {
        throw Exception('Vision API가 초기화되지 않았습니다.');
      }

      if (kDebugMode) {
        debugPrint('🔍 OCR 텍스트 추출 시작');
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
        if (kDebugMode) {
          debugPrint('⚠️ OCR 응답이 비어있음');
        }
        return '';
      }

      final textAnnotation = response.responses![0].fullTextAnnotation;
      if (textAnnotation == null) {
        if (kDebugMode) {
          debugPrint('⚠️ OCR 텍스트 주석이 없음');
        }
        return '';
      }

      final extractedText = textAnnotation.text ?? '';

      if (kDebugMode) {
        debugPrint('✅ OCR 추출 완료: ${extractedText.length}자');
        if (extractedText.isNotEmpty) {
          final preview = extractedText.length > 50 ? 
              '${extractedText.substring(0, 50)}...' : extractedText;
          debugPrint('📄 OCR 원본 텍스트 미리보기: "$preview"');
        }
      }
      
      // OCR 사용량 증가 (skipUsageCount가 false인 경우에만)
      if (!skipUsageCount) {
        try {
          if (kDebugMode) {
            debugPrint('📊 OCR 사용량 카운트 증가 시작');
          }
          await _usageLimitService.updateUsageAfterNoteCreation(ocrPages: 1);
          if (kDebugMode) {
            debugPrint('✅ OCR 사용량 카운트 증가 완료');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ OCR 사용량 증가 실패 (무시): $e');
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint('⏭️ OCR 사용량 카운트 건너뜀 (skipUsageCount=true)');
        }
      }

      return extractedText;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ OCR 텍스트 추출 실패: $e');
      }
      return '';
    }
  }

  /// **간편 메서드: 텍스트 인식**
  /// 
  /// extractText의 간편 버전으로, 사용량 카운팅을 포함합니다.
  /// 
  /// **매개변수:**
  /// - `imageFile`: OCR을 수행할 이미지 파일
  /// 
  /// **반환값:**
  /// - 추출된 원본 텍스트
  Future<String> recognizeText(File imageFile) async {
    return await extractText(imageFile, skipUsageCount: false);
  }
}
