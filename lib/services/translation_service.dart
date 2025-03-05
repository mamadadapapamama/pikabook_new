import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class TranslationService {
  // 싱글톤 패턴 구현
  static final TranslationService _instance = TranslationService._internal();
  factory TranslationService() => _instance;
  TranslationService._internal();

  // 기본 번역 언어 설정
  String _sourceLanguage = 'auto'; // 자동 감지
  String _targetLanguage = 'ko'; // 한국어

  // 언어 설정 메서드
  void setSourceLanguage(String languageCode) {
    _sourceLanguage = languageCode;
  }

  void setTargetLanguage(String languageCode) {
    _targetLanguage = languageCode;
  }

  // 텍스트 번역 메서드 (간단한 무료 API 사용)
  Future<String> translateText(String text, {String? targetLanguage}) async {
    if (text.isEmpty) return '';

    final target = targetLanguage ?? _targetLanguage;

    try {
      // 여기서는 간단한 예시로 LibreTranslate API를 사용합니다.
      // 실제 앱에서는 Google Cloud Translation API 등 더 안정적인 서비스를 사용하는 것이 좋습니다.
      final url = Uri.parse('https://libretranslate.de/translate');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'q': text,
          'source': _sourceLanguage,
          'target': target,
          'format': 'text',
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['translatedText'] as String;
      } else {
        throw Exception('번역 API 응답 오류: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('텍스트 번역 중 오류 발생: $e');

      // 오류 발생 시 원본 텍스트 반환 (실패해도 앱이 중단되지 않도록)
      return '(번역 실패) $text';
    }
  }

  // 지원되는 언어 목록 가져오기
  Future<List<Map<String, String>>> getSupportedLanguages() async {
    try {
      final url = Uri.parse('https://libretranslate.de/languages');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data
            .map((lang) => {
                  'code': lang['code'] as String,
                  'name': lang['name'] as String,
                })
            .toList();
      } else {
        throw Exception('언어 목록 API 응답 오류: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('지원 언어 목록 조회 중 오류 발생: $e');
      // 기본 언어 목록 반환
      return [
        {'code': 'en', 'name': 'English'},
        {'code': 'ko', 'name': '한국어'},
        {'code': 'ja', 'name': '日本語'},
        {'code': 'zh', 'name': '中文'},
      ];
    }
  }
}
