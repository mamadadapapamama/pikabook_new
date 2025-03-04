import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:googleapis/vision/v1.dart' as vision;
import 'package:googleapis/translate/v3.dart' as translate;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class GoogleCloudService {
  static final GoogleCloudService _instance = GoogleCloudService._internal();
  factory GoogleCloudService() => _instance;
  GoogleCloudService._internal();

  // 서비스 계정 인증 정보
  static const String _credentialsPath =
      'assets/credentials/service-account.json';

  // 서비스 계정 인증 정보를 로드하는 메서드
  Future<Map<String, dynamic>> _loadCredentials() async {
    try {
      final String jsonString = await rootBundle.loadString(_credentialsPath);
      return json.decode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('서비스 계정 인증 정보를 로드하는데 실패했습니다: $e');
    }
  }

  // 서비스 계정으로 인증하는 메서드
  Future<AutoRefreshingAuthClient> _getAuthClient(List<String> scopes) async {
    try {
      final credentialsJson = await _loadCredentials();
      final credentials = ServiceAccountCredentials.fromJson(credentialsJson);
      return await clientViaServiceAccount(credentials, scopes);
    } catch (e) {
      throw Exception('인증 클라이언트 생성에 실패했습니다: $e');
    }
  }

  // 이미지에서 텍스트 추출 (OCR)
  Future<String> extractTextFromImage(File imageFile) async {
    try {
      // Vision API 인증
      final client = await _getAuthClient([vision.VisionApi.cloudVisionScope]);
      final visionApi = vision.VisionApi(client);

      // 이미지 파일을 base64로 인코딩
      final List<int> imageBytes = await imageFile.readAsBytes();
      final String base64Image = base64Encode(imageBytes);

      // OCR 요청 생성
      final request = vision.AnnotateImageRequest()
        ..image = (vision.Image()..content = base64Image)
        ..features = [
          vision.Feature()
            ..type = 'TEXT_DETECTION'
            ..maxResults = 1
        ]
        ..imageContext = (vision.ImageContext()
          ..languageHints = ['zh-Hans', 'zh-Hant']); // 중국어 간체 및 번체 지정

      // API 요청 실행
      final response = await visionApi.images.annotate(
        vision.BatchAnnotateImagesRequest()..requests = [request],
      );

      // 응답에서 텍스트 추출
      final textAnnotation = response.responses?.first.fullTextAnnotation;
      if (textAnnotation == null || textAnnotation.text == null) {
        return '';
      }

      return textAnnotation.text!;
    } catch (e) {
      throw Exception('이미지에서 텍스트 추출에 실패했습니다: $e');
    }
  }

  // 텍스트 번역 (중국어 -> 한국어)
  Future<String> translateText(String text,
      {String sourceLanguage = 'zh', String targetLanguage = 'ko'}) async {
    try {
      // Translation API 인증
      final client =
          await _getAuthClient([translate.TranslateApi.cloudTranslationScope]);
      final translateApi = translate.TranslateApi(client);

      // 프로젝트 ID 가져오기
      final credentials = await _loadCredentials();
      final projectId = credentials['project_id'] as String;

      // 번역 요청 생성
      final request = translate.TranslateTextRequest()
        ..contents = [text]
        ..sourceLanguageCode = sourceLanguage
        ..targetLanguageCode = targetLanguage
        ..mimeType = 'text/plain';

      // API 요청 실행
      final response = await translateApi.projects.translateText(
        request,
        'projects/$projectId',
      );

      // 응답에서 번역된 텍스트 추출
      if (response.translations == null || response.translations!.isEmpty) {
        return '';
      }

      return response.translations!.first.translatedText ?? '';
    } catch (e) {
      throw Exception('텍스트 번역에 실패했습니다: $e');
    }
  }
}
