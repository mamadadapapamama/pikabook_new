import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class TranslationService {
  // 싱글톤 패턴 구현
  static final TranslationService _instance = TranslationService._internal();
  factory TranslationService() => _instance;
  TranslationService._internal();

  // 기본 번역 언어 설정
  String _sourceLanguage = 'auto'; // 자동 감지
  String _targetLanguage = 'ko'; // 한국어

  // Google Translate API 키
  String? _apiKey;

  // 언어 설정 메서드
  void setSourceLanguage(String languageCode) {
    _sourceLanguage = languageCode;
  }

  void setTargetLanguage(String languageCode) {
    _targetLanguage = languageCode;
  }

  // API 키 로드
  Future<String?> _loadApiKey() async {
    if (_apiKey != null) return _apiKey;

    try {
      // 서비스 계정 JSON 파일에서 API 키 로드 시도
      try {
        debugPrint('서비스 계정 JSON 파일에서 API 키 로드 시도...');
        final String jsonString = await rootBundle
            .loadString('assets/credentials/service-account.json');
        final data = json.decode(jsonString) as Map<String, dynamic>;

        // 서비스 계정 JSON 파일의 구조 로깅 (디버깅용)
        debugPrint('서비스 계정 JSON 파일 구조: ${data.keys.join(', ')}');

        // API 키 필드 확인
        if (data.containsKey('api_key')) {
          debugPrint('api_key 필드를 찾았습니다.');
          _apiKey = data['api_key'] as String;
          return _apiKey;
        } else if (data.containsKey('key')) {
          debugPrint('key 필드를 찾았습니다.');
          _apiKey = data['key'] as String;
          return _apiKey;
        } else if (data.containsKey('private_key')) {
          debugPrint('private_key 필드를 찾았습니다.');
          _apiKey = data['private_key'] as String;
          return _apiKey;
        } else {
          // 서비스 계정 파일에 API 키가 없는 경우
          debugPrint('서비스 계정 파일에서 API 키를 찾을 수 없습니다. 대체 번역 서비스를 사용합니다.');
          return null;
        }
      } catch (e) {
        debugPrint('서비스 계정 JSON 파일 로드 중 오류 발생: $e');
        debugPrint('대체 번역 서비스를 사용합니다.');
        return null;
      }
    } catch (e) {
      debugPrint('API 키 로드 중 오류 발생: $e');
      return null;
    }
  }

  // 텍스트 번역 메서드 (Google Translate API 사용)
  Future<String> translateText(String text, {String? targetLanguage}) async {
    if (text.isEmpty) return '';

    final target = targetLanguage ?? _targetLanguage;

    // 중국어 번역이 아닌 경우 바로 대체 서비스 사용
    if (target != 'zh' && target != 'zh-CN' && target != 'zh-TW') {
      debugPrint('중국어 번역이 아니므로 대체 번역 서비스를 사용합니다.');
      return await _translateWithFallbackService(text, target);
    }

    try {
      // API 키 로드
      final apiKey = await _loadApiKey();

      if (apiKey == null || apiKey.isEmpty) {
        debugPrint('Google Translate API 키가 없습니다. 대체 번역 서비스 사용 시도...');
        return await _translateWithFallbackService(text, target);
      }

      // Google Translate API 호출
      final url = Uri.parse(
        'https://translation.googleapis.com/language/translate/v2?key=$apiKey',
      );

      debugPrint('Google Translate API 호출: 소스=${_sourceLanguage}, 대상=$target');

      final response = await http
          .post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'q': text,
          'source': _sourceLanguage == 'auto' ? '' : _sourceLanguage,
          'target': target,
          'format': 'text',
        }),
      )
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('Google Translate API 요청 타임아웃');
          throw Exception('번역 요청 타임아웃');
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        if (data.containsKey('data') &&
            data['data'].containsKey('translations') &&
            (data['data']['translations'] as List).isNotEmpty) {
          final translations = data['data']['translations'] as List;
          debugPrint('Google Translate API 번역 성공');
          return translations[0]['translatedText'] as String;
        } else {
          debugPrint('Google Translate API 응답 형식 오류: $data');
          throw Exception('번역 API 응답 형식 오류');
        }
      } else {
        debugPrint(
            'Google Translate API 응답 오류: ${response.statusCode}, ${response.body}');

        // 오류 코드가 API 키 관련 문제인 경우 대체 서비스 사용
        debugPrint('API 키 오류로 대체 번역 서비스 사용 시도...');
        return await _translateWithFallbackService(text, target);
      }
    } catch (e) {
      debugPrint('Google Translate API 사용 중 오류 발생: $e');

      // 오류 발생 시 대체 서비스 사용 시도
      try {
        return await _translateWithFallbackService(text, target);
      } catch (fallbackError) {
        debugPrint('대체 번역 서비스도 실패: $fallbackError');
        return '(번역 실패) $text';
      }
    }
  }

  // 대체 번역 서비스 (LibreTranslate)
  Future<String> _translateWithFallbackService(
      String text, String targetLanguage) async {
    // 번역 API 엔드포인트 목록 (여러 개의 대체 서버 제공)
    final List<String> translationEndpoints = [
      'https://translate.argosopentech.com',
      'https://translate.terraprint.co',
      'https://libretranslate.de',
    ];

    // 최대 3번 시도
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final endpoint =
            translationEndpoints[attempt % translationEndpoints.length];
        debugPrint('대체 번역 시도 #${attempt + 1} - 엔드포인트: $endpoint');

        final url = Uri.parse('$endpoint/translate');
        final response = await http
            .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'q': text,
            'source': _sourceLanguage,
            'target': targetLanguage,
            'format': 'text',
          }),
        )
            .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint('대체 번역 요청 타임아웃');
            throw Exception('번역 요청 타임아웃');
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          return data['translatedText'] as String;
        } else {
          debugPrint('대체 번역 API 응답 오류: ${response.statusCode}');
          throw Exception('번역 API 응답 오류: ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('대체 번역 중 오류 발생: $e');

        // 마지막 시도가 아니면 계속 시도
        if (attempt < 2) {
          continue;
        }
      }
    }

    // 모든 시도 실패 시 원본 텍스트 반환
    return '(번역 실패) $text';
  }

  // 지원되는 언어 목록 가져오기
  Future<List<Map<String, String>>> getSupportedLanguages() async {
    try {
      // API 키 로드
      final apiKey = await _loadApiKey();

      if (apiKey != null && apiKey.isNotEmpty) {
        // Google Translate API 사용
        final url = Uri.parse(
          'https://translation.googleapis.com/language/translate/v2/languages?key=$apiKey&target=ko',
        );

        final response = await http.get(url).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw Exception('언어 목록 요청 타임아웃');
          },
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;

          if (data.containsKey('data') &&
              data['data'].containsKey('languages')) {
            final languages = data['data']['languages'] as List;
            return languages
                .map((lang) => {
                      'code': lang['language'] as String,
                      'name':
                          lang['name'] as String? ?? lang['language'] as String,
                    })
                .toList();
          }
        }
      }

      // Google API 실패 시 대체 서비스 사용
      return await _getFallbackSupportedLanguages();
    } catch (e) {
      debugPrint('지원 언어 목록 조회 중 오류 발생: $e');
      return await _getFallbackSupportedLanguages();
    }
  }

  // 대체 서비스에서 지원 언어 목록 가져오기
  Future<List<Map<String, String>>> _getFallbackSupportedLanguages() async {
    // 번역 API 엔드포인트 목록
    final List<String> translationEndpoints = [
      'https://translate.argosopentech.com',
      'https://translate.terraprint.co',
      'https://libretranslate.de',
    ];

    // 최대 3번 시도
    for (int attempt = 0; attempt < 3; attempt++) {
      try {
        final endpoint =
            translationEndpoints[attempt % translationEndpoints.length];
        final url = Uri.parse('$endpoint/languages');
        final response = await http.get(url).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw Exception('언어 목록 요청 타임아웃');
          },
        );

        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body);
          return data
              .map((lang) => {
                    'code': lang['code'] as String,
                    'name': lang['name'] as String,
                  })
              .toList();
        }
      } catch (e) {
        debugPrint('대체 서비스 언어 목록 조회 중 오류 발생: $e');

        // 마지막 시도가 아니면 계속 시도
        if (attempt < 2) {
          continue;
        }
      }
    }

    // 기본 언어 목록 반환
    return [
      {'code': 'en', 'name': 'English'},
      {'code': 'ko', 'name': '한국어'},
      {'code': 'ja', 'name': '日本語'},
      {'code': 'zh', 'name': '中文'},
      {'code': 'zh-CN', 'name': '简体中文'},
      {'code': 'zh-TW', 'name': '繁體中文'},
      {'code': 'fr', 'name': 'Français'},
      {'code': 'de', 'name': 'Deutsch'},
      {'code': 'es', 'name': 'Español'},
    ];
  }
}
