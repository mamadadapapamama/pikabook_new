import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/translate/v3.dart' as translate;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import '../../models/text_segment.dart';
import '../../utils/language_constants.dart';
import '../common/usage_limit_service.dart';
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

  // 번역 캐시 추가 (성능 개선)
  final Map<String, String> _translationCache = {};
  
  // 생성자 로그 추가
  TranslationService._internal() {
    debugPrint('🌐 TranslationService: 생성자 호출됨');
    _initializeApi();
  }

  // API 초기화
  Future<void> _initializeApi() async {
    if (_httpClient != null || _isInitializing) return;

    _isInitializing = true;
    try {
      debugPrint('TranslationService: Google Cloud Translation API 초기화 중...');

      // 서비스 계정 JSON 파일 로드
      final String serviceAccountPath = 'assets/credentials/service-account.json';
      debugPrint('TranslationService: 서비스 계정 파일 로드 시도: $serviceAccountPath');
      
      String serviceAccountJson;
      try {
        serviceAccountJson = await rootBundle.loadString(serviceAccountPath);
        debugPrint('TranslationService: 서비스 계정 JSON 파일 로드 성공 (${serviceAccountJson.length}바이트)');
      } catch (e) {
        throw Exception('서비스 계정 JSON 파일 로드 실패: $e');
      }
      
      // JSON 데이터 파싱
      Map<String, dynamic> jsonData;
      try {
        jsonData = jsonDecode(serviceAccountJson);
        debugPrint('TranslationService: 서비스 계정 JSON 파싱 성공');
      } catch (e) {
        throw Exception('서비스 계정 JSON 파싱 실패: $e');
      }

      // 프로젝트 ID 추출
      _projectId = jsonData['project_id'];
      if (_projectId == null) {
        throw Exception('서비스 계정 JSON에 project_id가 없습니다.');
      }
      debugPrint('TranslationService: 프로젝트 ID 확인: $_projectId');

      // 서비스 계정 인증 정보 생성
      final accountCredentials = ServiceAccountCredentials.fromJson(jsonData);
      
      // 스코프 설정
      final scopes = ['https://www.googleapis.com/auth/cloud-platform'];
      
      // 인증 클라이언트 생성
      debugPrint('TranslationService: 인증 클라이언트 생성 중...');
      _httpClient = await clientViaServiceAccount(accountCredentials, scopes);
      debugPrint('TranslationService: 인증 클라이언트 생성 완료');

      _isInitializing = false;
      debugPrint('TranslationService: Google Cloud Translation API 초기화 완료');
    } catch (e) {
      _isInitializing = false;
      _httpClient = null;
      _projectId = null;
      debugPrint('TranslationService: Google Cloud Translation API 초기화 실패: $e');
      if (e.toString().contains('No such file') || e.toString().contains('Unable to load asset')) {
        debugPrint('TranslationService: 서비스 계정 파일이 존재하지 않거나 접근할 수 없습니다. pubspec.yaml에 assets 정의가 있는지 확인하세요.');
      }
      // 초기화 실패 시 예외를 다시 던지지 않고, 호출자가 처리하도록 함
    }
  }

  // 번역 함수
  Future<String> translateText(String text,
      {String sourceLanguage = 'auto', String? targetLanguage, bool countCharacters = true}) async {
    if (text.isEmpty) {
      return '';
    }
    
    Stopwatch? stopwatch;
    if (kDebugMode) {
      stopwatch = Stopwatch()..start();
    }
    
    // 특수 마커 텍스트인 경우 번역하지 않고 빈 문자열 반환
    if (text == '___PROCESSING___' || text == 'processing' || text.contains('텍스트 처리 중')) {
      debugPrint('TranslationService: 특수 마커 텍스트("$text") 감지됨 - 번역 생략');
      return '';
    }

    // 언어 코드 검증 및 기본값 설정
    final effectiveTargetLanguage = targetLanguage ?? TargetLanguage.DEFAULT;
    final effectiveSourceLanguage = sourceLanguage == 'auto' ? null : sourceLanguage;
    
    // 캐시 키 생성
    final cacheKey = '${effectiveSourceLanguage ?? 'auto'}_${effectiveTargetLanguage}_$text';
    
    // 캐시에서 번역 결과 확인 (성능 개선)
    if (_translationCache.containsKey(cacheKey)) {
      final cachedResult = _translationCache[cacheKey];
      if (kDebugMode && stopwatch != null) {
        debugPrint('⚡ 캐시된 번역 반환 (${stopwatch.elapsedMilliseconds}ms)');
      }
      
      // 캐시 히트 시에도 사용량은 기록 (첫 번역 시만)
      if (countCharacters && cachedResult != text) {
        // 백그라운드로 사용량 증가 (UI 차단 방지)
        _usageLimitService.incrementTranslationCharCount(text.length, allowOverLimit: true).then((_) {
          if (kDebugMode) {
            debugPrint('사용량 증가 완료: ${text.length}자');
          }
        });
      }
      
      return cachedResult ?? text;
    }

    if (kDebugMode) {
      debugPrint('🌐 번역 시작: ${text.length}자 (소스: ${effectiveSourceLanguage ?? 'auto'}, 타겟: $effectiveTargetLanguage)');
    }

    try {
      // API가 초기화되지 않았으면 초기화
      if (_httpClient == null || _projectId == null) {
        debugPrint('TranslationService: API 초기화 시도');
        await _initializeApi();
      }

      // API가 여전히 null이면 원본 텍스트 반환
      if (_httpClient == null || _projectId == null) {
        debugPrint('TranslationService: API 초기화 실패, 원본 텍스트 반환');
        return text;
      }

      // 번역 요청
      final parent = 'projects/$_projectId/locations/global';

      // 요청 본문에 포맷 지정
      final requestBody = {
        'contents': [text],
        'targetLanguageCode': effectiveTargetLanguage,
        if (effectiveSourceLanguage != null) 'sourceLanguageCode': effectiveSourceLanguage,
        'mimeType': 'text/plain',
      };
      
      // 요청 본문 로깅 (길이가 긴 경우 일부만 출력)
      final textSample = text.length > 50 ? '${text.substring(0, 50)}...' : text;
      if (kDebugMode) {
        debugPrint('번역 요청: "$textSample"');
      }

      // API 엔드포인트 URL
      final url = Uri.parse(
          'https://translation.googleapis.com/v3/$parent:translateText');
      
      // POST 요청 전송
      final httpStopwatch = Stopwatch()..start();
      final response = await _httpClient!.post(
        url,
        body: jsonEncode(requestBody),
        headers: {'Content-Type': 'application/json'},
      );
      if (kDebugMode) {
        debugPrint('HTTP 요청 완료 (${httpStopwatch.elapsedMilliseconds}ms)');
      }

      // 응답 처리
      String translatedText = text; // 기본값은 원본 텍스트

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        
        final translations = data['translations'] as List<dynamic>?;

        if (translations != null && translations.isNotEmpty) {
          final translatedResult = translations.first['translatedText'] as String?;
              
          if (translatedResult != null && translatedResult.isNotEmpty) {
            // 번역 결과가 원본과 다른지 확인
            if (translatedResult == text) {
              // 원본과 동일한 경우 사용량을 기록하지 않음
              if (kDebugMode) {
                debugPrint('번역 결과가 원본과 동일함 (사용량 미기록)');
              }
            } else {
              // 사용량 카운팅 옵션이 활성화된 경우에만 사용량 증가
              if (countCharacters) {
                // 백그라운드로 사용량 증가 (UI 차단 방지)
                _usageLimitService.incrementTranslationCharCount(text.length, allowOverLimit: true).then((_) {
                  if (kDebugMode) {
                    debugPrint('사용량 증가 완료: ${text.length}자');
                  }
                });
              }
            }
            translatedText = translatedResult;
            
            // 캐시에 결과 저장 (성능 개선)
            _translationCache[cacheKey] = translatedText;
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint('번역 API 오류: ${response.statusCode} - ${response.body}');
        }
      }
      
      if (kDebugMode && stopwatch != null) {
        debugPrint('✅ 번역 완료 (${stopwatch.elapsedMilliseconds}ms)');
      }

      return translatedText;
    } catch (e) {
      if (kDebugMode && stopwatch != null) {
        debugPrint('❌ 번역 오류: $e (${stopwatch.elapsedMilliseconds}ms)');
      }
      // 오류 발생 시 원본 텍스트 반환
      return text;
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
