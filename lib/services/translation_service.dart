import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/translate/v3.dart' as translate;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
// 순환 참조 제거
// import 'google_cloud_service.dart';

class TranslationService {
  // 싱글톤 패턴 구현
  static final TranslationService _instance = TranslationService._internal();
  factory TranslationService() => _instance;

  // API 클라이언트
  http.Client? _httpClient;
  String? _projectId;
  bool _isInitializing = false;

  TranslationService._internal() {
    debugPrint('TranslationService 생성됨');
    _initializeApi();
  }

  // API 초기화
  Future<void> _initializeApi() async {
    if (_httpClient != null || _isInitializing) return;

    _isInitializing = true;
    try {
      debugPrint('Google Cloud Translation API 초기화 중...');

      // 서비스 계정 JSON 파일 로드
      final serviceAccountJson = await rootBundle
          .loadString('assets/credentials/service-account.json');
      final Map<String, dynamic> jsonData = jsonDecode(serviceAccountJson);

      // 프로젝트 ID 추출
      _projectId = jsonData['project_id'];
      if (_projectId == null) {
        throw Exception('서비스 계정 JSON에 project_id가 없습니다.');
      }

      final serviceAccountCredentials =
          ServiceAccountCredentials.fromJson(serviceAccountJson);

      // 인증 클라이언트 생성
      final scopes = ['https://www.googleapis.com/auth/cloud-platform'];
      _httpClient =
          await clientViaServiceAccount(serviceAccountCredentials, scopes);

      debugPrint('Google Cloud Translation API 초기화 완료 (프로젝트 ID: $_projectId)');
    } catch (e) {
      debugPrint('Google Cloud Translation API 초기화 실패: $e');
      _projectId = null;
    } finally {
      _isInitializing = false;
    }
  }

  // 번역 함수
  Future<String> translateText(String text,
      {String sourceLanguage = 'auto', String? targetLanguage = 'ko'}) async {
    if (text.isEmpty) {
      return '';
    }

    try {
      // API가 초기화되지 않았으면 초기화
      if (_httpClient == null || _projectId == null) {
        await _initializeApi();
      }

      // API가 여전히 null이면 원본 텍스트 반환
      if (_httpClient == null || _projectId == null) {
        debugPrint('Translation API 초기화 실패로 원본 텍스트 반환');
        return text;
      }

      // 번역 요청
      final target = targetLanguage ?? 'ko';
      final source = sourceLanguage == 'auto' ? null : sourceLanguage;
      final parent = 'projects/$_projectId/locations/global';

      debugPrint('번역 요청: ${text.length}자, 소스: $source, 타겟: $target');

      // HTTP 직접 호출 방식으로 변경
      try {
        // 요청 본문 생성
        final requestBody = {
          'contents': [text],
          'targetLanguageCode': target,
          if (source != null && source != 'auto') 'sourceLanguageCode': source,
          'mimeType': 'text/plain',
        };

        // API 엔드포인트 URL
        final url = Uri.parse(
            'https://translation.googleapis.com/v3/$parent:translateText');

        // POST 요청 전송
        final response = await _httpClient!.post(
          url,
          body: jsonEncode(requestBody),
          headers: {'Content-Type': 'application/json'},
        );

        if (response.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(response.body);
          final translations = data['translations'] as List<dynamic>?;

          if (translations != null && translations.isNotEmpty) {
            final translatedText =
                translations.first['translatedText'] as String?;
            if (translatedText != null && translatedText.isNotEmpty) {
              debugPrint('번역 완료: ${translatedText.length}자');
              return translatedText;
            }
          }
        } else {
          debugPrint('번역 API 호출 실패: ${response.statusCode}, ${response.body}');
        }
      } catch (e) {
        debugPrint('번역 API 호출 중 오류 발생: $e');
      }

      debugPrint('번역 결과가 비어있어 원본 텍스트 반환');
      return text;
    } catch (e) {
      debugPrint('번역 중 오류 발생: $e');
      return text; // 오류 발생 시 원본 텍스트 반환
    }
  }

  // 지원되는 언어 목록 가져오기
  Future<List<Map<String, String>>> getSupportedLanguages() async {
    try {
      // API가 초기화되지 않았으면 초기화
      if (_httpClient == null || _projectId == null) {
        await _initializeApi();
      }

      // API가 여전히 null이면 기본 언어 목록 반환
      if (_httpClient == null || _projectId == null) {
        debugPrint('Translation API 초기화 실패로 기본 언어 목록 반환');
        return _getDefaultLanguages();
      }

      // 지원 언어 요청
      final parent = 'projects/$_projectId/locations/global';

      try {
        // API 엔드포인트 URL
        final url = Uri.parse(
            'https://translation.googleapis.com/v3/$parent/supportedLanguages?displayLanguageCode=ko');

        // GET 요청 전송
        final response = await _httpClient!.get(url);

        if (response.statusCode == 200) {
          final Map<String, dynamic> data = jsonDecode(response.body);
          final languages = data['languages'] as List<dynamic>?;

          if (languages != null && languages.isNotEmpty) {
            return languages
                .map((lang) => {
                      'code': lang['languageCode'] as String? ?? '',
                      'name': lang['displayName'] as String? ??
                          lang['languageCode'] as String? ??
                          '',
                    })
                .toList();
          }
        } else {
          debugPrint(
              '지원 언어 목록 API 호출 실패: ${response.statusCode}, ${response.body}');
        }
      } catch (e) {
        debugPrint('지원 언어 목록 API 호출 중 오류 발생: $e');
      }

      return _getDefaultLanguages();
    } catch (e) {
      debugPrint('지원 언어 목록 가져오기 중 오류 발생: $e');
      return _getDefaultLanguages();
    }
  }

  // 기본 언어 목록
  List<Map<String, String>> _getDefaultLanguages() {
    return [
      {'code': 'ko', 'name': '한국어'},
      {'code': 'en', 'name': 'English'},
      {'code': 'zh-CN', 'name': '중국어 (간체)'},
      {'code': 'zh-TW', 'name': '중국어 (번체)'},
      {'code': 'ja', 'name': '일본어'},
    ];
  }
}
