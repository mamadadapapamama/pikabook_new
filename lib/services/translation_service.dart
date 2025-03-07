import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
// 순환 참조 제거
// import 'google_cloud_service.dart';

class TranslationService {
  // 싱글톤 패턴 구현
  static final TranslationService _instance = TranslationService._internal();
  factory TranslationService() => _instance;
  TranslationService._internal() {
    debugPrint('TranslationService 생성됨');
  }

  // 번역 함수
  Future<String> translateText(String text,
      {String sourceLanguage = 'auto', String? targetLanguage = 'ko'}) async {
    if (text.isEmpty) {
      return '';
    }

    try {
      // 직접 Google Cloud Translation API 호출
      final apiKey = 'YOUR_API_KEY'; // 실제 API 키로 대체해야 함
      final url = Uri.parse(
          'https://translation.googleapis.com/language/translate/v2?key=$apiKey');

      final response = await http.post(
        url,
        body: jsonEncode({
          'q': text,
          'source': sourceLanguage == 'auto' ? '' : sourceLanguage,
          'target': targetLanguage ?? 'ko',
          'format': 'text',
        }),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final translations = data['data']['translations'] as List;
        if (translations.isNotEmpty) {
          return translations[0]['translatedText'];
        }
      }

      // API 호출 실패 시 원본 텍스트 반환
      debugPrint('번역 API 호출 실패: ${response.statusCode}');
      return text;
    } catch (e) {
      debugPrint('번역 중 오류 발생: $e');
      return text; // 오류 발생 시 원본 텍스트 반환
    }
  }

  // 지원되는 언어 목록 가져오기
  Future<List<Map<String, String>>> getSupportedLanguages() async {
    // MVP에서는 한국어와 영어만 지원
    return [
      {'code': 'ko', 'name': '한국어'},
      {'code': 'en', 'name': 'English'},
    ];
  }
}
