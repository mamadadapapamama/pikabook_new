import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:googleapis_auth/auth_io.dart';

class TranslationService {
  // 싱글톤 패턴 구현
  static final TranslationService _instance = TranslationService._internal();
  factory TranslationService() => _instance;
  TranslationService._internal();

  // 기본 번역 언어 설정
  String _sourceLanguage = 'zh-CN'; // 중국어 (간체)
  String _targetLanguage = 'ko'; // 기본값: 한국어

  // Google Cloud 인증 클라이언트
  http.Client? _authClient;
  String? _projectId;

  // 언어 설정 메서드
  void setSourceLanguage(String languageCode) {
    // MVP에서는 소스 언어를 중국어로 고정
    debugPrint('소스 언어 변경 시도: $languageCode - MVP에서는 중국어만 지원합니다.');
  }

  void setTargetLanguage(String languageCode) {
    // MVP에서는 타겟 언어를 한국어 또는 영어로만 제한
    if (languageCode == 'ko' || languageCode == 'en') {
      _targetLanguage = languageCode;
      debugPrint('타겟 언어 변경: $_targetLanguage');
    } else {
      debugPrint('지원하지 않는 타겟 언어: $languageCode - MVP에서는 한국어와 영어만 지원합니다.');
    }
  }

  // 서비스 계정 인증 초기화
  Future<bool> _initializeGoogleAuth() async {
    if (_authClient != null && _projectId != null) {
      return true;
    }

    try {
      debugPrint('서비스 계정 JSON 파일에서 인증 정보 로드 시도...');
      final String jsonString = await rootBundle
          .loadString('assets/credentials/service-account.json');

      // 서비스 계정 JSON 파일의 구조 로깅 (디버깅용)
      final data = json.decode(jsonString) as Map<String, dynamic>;
      debugPrint('서비스 계정 JSON 파일 구조: ${data.keys.join(', ')}');

      // 프로젝트 ID 저장
      _projectId = data['project_id'] as String?;
      debugPrint('프로젝트 ID: $_projectId');

      if (_projectId == null) {
        debugPrint('서비스 계정 파일에서 project_id를 찾을 수 없습니다.');
        return false;
      }

      // 서비스 계정 인증 정보 생성
      final accountCredentials = ServiceAccountCredentials.fromJson(jsonString);

      // 인증 클라이언트 생성
      _authClient = await clientViaServiceAccount(accountCredentials,
          ['https://www.googleapis.com/auth/cloud-platform']);

      debugPrint('Google Cloud 인증 초기화 성공');
      return true;
    } catch (e) {
      debugPrint('Google Cloud 인증 초기화 실패: $e');
      _authClient?.close();
      _authClient = null;
      _projectId = null;
      return false;
    }
  }

  // 텍스트 번역 메서드 (Google Translate API 사용)
  Future<String> translateText(String text, {String? targetLanguage}) async {
    if (text.isEmpty) return '';

    // MVP에서는 타겟 언어를 한국어 또는 영어로만 제한
    final target = (targetLanguage == 'ko' || targetLanguage == 'en')
        ? targetLanguage!
        : _targetLanguage;

    debugPrint(
        '번역 요청: 원본 텍스트 길이=${text.length}, 소스 언어=$_sourceLanguage, 대상 언어=$target');

    try {
      // Google Cloud 인증 초기화
      final authInitialized = await _initializeGoogleAuth();

      if (authInitialized && _authClient != null && _projectId != null) {
        debugPrint(
            'Google Translate API 호출 (서비스 계정 인증): 소스=$_sourceLanguage, 대상=$target');

        try {
          // Translation API v3 엔드포인트
          final url = Uri.parse(
              'https://translation.googleapis.com/v3/projects/$_projectId:translateText');

          // 요청 본문 생성
          final requestBody = {
            'contents': [text],
            'targetLanguageCode': target,
            'sourceLanguageCode': _sourceLanguage,
          };

          // 요청 전송
          final response = await _authClient!
              .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: json.encode(requestBody),
          )
              .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              debugPrint('Google Translate API 요청 타임아웃');
              throw Exception('번역 요청 타임아웃');
            },
          );

          debugPrint('Google Translate API 응답 상태 코드: ${response.statusCode}');

          if (response.statusCode == 200) {
            final data = json.decode(response.body) as Map<String, dynamic>;

            debugPrint('Google Translate API 응답 데이터: ${data.keys.join(', ')}');

            if (data.containsKey('translations') &&
                (data['translations'] as List).isNotEmpty) {
              final translations = data['translations'] as List;
              debugPrint('Google Translate API 번역 성공');
              return translations[0]['translatedText'] as String;
            } else {
              debugPrint('Google Translate API 응답 형식 오류: $data');
              throw Exception('번역 API 응답 형식 오류');
            }
          } else {
            debugPrint(
                'Google Translate API 응답 오류: ${response.statusCode}, ${response.body}');

            // 오류 응답 본문에서 오류 메시지 추출 시도
            try {
              final errorData =
                  json.decode(response.body) as Map<String, dynamic>;
              if (errorData.containsKey('error')) {
                final error = errorData['error'];
                debugPrint('오류 코드: ${error['code']}, 메시지: ${error['message']}');
                debugPrint('오류 상태: ${error['status']}');
              }
            } catch (e) {
              debugPrint('오류 응답 파싱 실패: $e');
            }

            // 대체 서비스 사용
            debugPrint('API 오류로 대체 번역 서비스 사용 시도...');
            return await _translateWithFallbackService(text, target);
          }
        } catch (e) {
          debugPrint('Google Translate API 호출 중 오류 발생: $e');
          throw e;
        }
      } else {
        debugPrint('Google Cloud 인증 실패, 대체 번역 서비스 사용 시도...');
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

        debugPrint('대체 번역 API 응답 상태 코드: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          debugPrint('대체 번역 API 응답 데이터: ${data.keys.join(', ')}');
          return data['translatedText'] as String;
        } else {
          debugPrint(
              '대체 번역 API 응답 오류: ${response.statusCode}, ${response.body}');
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

  // 지원되는 언어 목록 가져오기 (MVP에서는 한국어와 영어만 지원)
  Future<List<Map<String, String>>> getSupportedLanguages() async {
    // MVP에서는 한국어와 영어만 지원
    return [
      {'code': 'ko', 'name': '한국어'},
      {'code': 'en', 'name': 'English'},
    ];
  }
}
