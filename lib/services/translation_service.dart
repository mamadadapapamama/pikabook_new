import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/translate/v3.dart' as translate;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import '../models/text_segment.dart';
import '../utils/language_constants.dart';
import 'usage_limit_service.dart';
// 순환 참조 제거
// import 'google_cloud_service.dart';

/// 번역 서비스
/// 다국어 지원을 위한 확장 포인트가 포함되어 있습니다.
/// MARK: 다국어 지원을 위한 확장 포인트

class TranslationService {
  // 싱글톤 패턴 구현
  static final TranslationService _instance = TranslationService._internal();
  factory TranslationService() => _instance;

  // API 클라이언트
  http.Client? _httpClient;
  String? _projectId;
  bool _isInitializing = false;

  // 사용량 추적 서비스
  final UsageLimitService _usageLimitService = UsageLimitService();

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
      {String sourceLanguage = 'auto', String? targetLanguage}) async {
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
      // 타겟 언어 기본값 설정
      final target = targetLanguage ?? TargetLanguage.DEFAULT;
      final source = sourceLanguage == 'auto' ? null : sourceLanguage;
      final parent = 'projects/$_projectId/locations/global';

      debugPrint('번역 요청: ${text.length}자, 소스: $source, 타겟: $target');

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

      String translatedText = text; // 기본값은 원본 텍스트

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final translations = data['translations'] as List<dynamic>?;

        if (translations != null && translations.isNotEmpty) {
          final translatedResult =
              translations.first['translatedText'] as String?;
          if (translatedResult != null && translatedResult.isNotEmpty) {
            debugPrint('번역 완료: ${translatedResult.length}자');
            translatedText = translatedResult;
          }
        }
      } else {
        debugPrint('번역 API 호출 실패: ${response.statusCode}, ${response.body}');
      }

      // 번역된 글자 수 기록 (제한 없이 사용량만 추적)
      await _usageLimitService.addTranslatedChars(text.length);

      return translatedText;
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
    // MARK: 다국어 지원을 위한 확장 포인트
    // 현재는 MVP 대상 언어만 반환
    return [
      {'code': TargetLanguage.KOREAN, 'name': TargetLanguage.getName(TargetLanguage.KOREAN)},
      {'code': TargetLanguage.ENGLISH, 'name': TargetLanguage.getName(TargetLanguage.ENGLISH)},
      {'code': SourceLanguage.CHINESE, 'name': SourceLanguage.getName(SourceLanguage.CHINESE)},
      {'code': SourceLanguage.CHINESE_TRADITIONAL, 'name': SourceLanguage.getName(SourceLanguage.CHINESE_TRADITIONAL)},
      {'code': SourceLanguage.JAPANESE, 'name': SourceLanguage.getName(SourceLanguage.JAPANESE)},
    ];
  }

  /// 번역 캐싱
  Future<void> cacheTranslation(
      String originalText, String translatedText, String targetLanguage) async {
    // 이 메서드는 UnifiedCacheService를 통해 구현되어야 합니다.
    // 현재는 임시 구현으로 로그만 출력합니다.
    debugPrint(
        '번역 캐싱: 원본 텍스트 ${originalText.length}자, 번역 텍스트 ${translatedText.length}자');
  }

  /// 캐시된 번역 가져오기
  Future<String?> getTranslation(
      String originalText, String targetLanguage) async {
    // 이 메서드는 UnifiedCacheService를 통해 구현되어야 합니다.
    // 현재는 임시 구현으로 null을 반환합니다.
    debugPrint('캐시된 번역 조회: 원본 텍스트 ${originalText.length}자');
    return null;
  }

  /// 원본 문장과 번역 문장을 최대한 매핑하는 함수
  List<TextSegment> mapOriginalAndTranslatedSentences(
      List<String> originalSentences, List<String> translatedSentences, {String? sourceLanguage}) {
    final segments = <TextSegment>[];
    final int originalCount = originalSentences.length;
    final int translatedCount = translatedSentences.length;

    debugPrint('원본 문장 수: $originalCount, 번역 문장 수: $translatedCount');

    // 문장 수가 같으면 1:1 매핑
    if (originalCount == translatedCount) {
      for (int i = 0; i < originalCount; i++) {
        segments.add(TextSegment(
          originalText: originalSentences[i],
          translatedText: translatedSentences[i],
          pinyin: '',
          // 소스 언어 정보 추가
          sourceLanguage: sourceLanguage ?? SourceLanguage.DEFAULT,
        ));
      }
      return segments;
    }

    // 문장 수가 다른 경우 최대한 매핑 시도
    // 1. 원본 문장 수가 더 많은 경우: 번역 문장을 비율에 맞게 분배
    if (originalCount > translatedCount) {
      final double ratio = originalCount / translatedCount;
      for (int i = 0; i < originalCount; i++) {
        final int translatedIndex = (i / ratio).floor();
        final String translatedText = translatedIndex < translatedCount
            ? translatedSentences[translatedIndex]
            : '';
        
        segments.add(TextSegment(
          originalText: originalSentences[i],
          translatedText: translatedText,
          pinyin: '',
          // 소스 언어 정보 추가
          sourceLanguage: sourceLanguage ?? SourceLanguage.DEFAULT,
        ));
      }
      return segments;
    }

    // 2. 번역 문장 수가 더 많은 경우: 원본 문장을 비율에 맞게 분배
    final double ratio = translatedCount / originalCount;
    for (int i = 0; i < translatedCount; i++) {
      final int originalIndex = (i / ratio).floor();
      final String originalText = originalIndex < originalCount
          ? originalSentences[originalIndex]
          : '';
      
      segments.add(TextSegment(
        originalText: originalText,
        translatedText: translatedSentences[i],
        pinyin: '',
        // 소스 언어 정보 추가
        sourceLanguage: sourceLanguage ?? SourceLanguage.DEFAULT,
      ));
    }
    return segments;
  }
}
