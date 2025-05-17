import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import '../../models/dictionary.dart';

/// 외부 API를 통해 중국어 사전 기능을 제공하는 서비스
/// Google Translation API를 사용하여 중국어 단어 번역 기능만 제공합니다.
class ExternalCnDictionaryService {
  // 싱글톤 패턴 구현
  static final ExternalCnDictionaryService _instance = ExternalCnDictionaryService._internal();
  factory ExternalCnDictionaryService() => _instance;
  
  ExternalCnDictionaryService._internal() {
    // 초기화 시 Google API 초기화
    _initializeApi();
  }

  // API 클라이언트
  http.Client? _httpClient;
  String? _projectId;
  bool _isInitializing = false;
  
  // 검색 결과 캐시 (메모리 캐시)
  final Map<String, DictionaryEntry> _searchResultCache = {};
  
  // 사전 업데이트 콜백 리스트
  final List<Function()> _dictionaryUpdateListeners = [];

  // API 초기화
  Future<void> _initializeApi() async {
    if (_httpClient != null || _isInitializing) return;

    _isInitializing = true;
    try {
      debugPrint('ExternalCnDictionaryService: Google Cloud Translation API 초기화 중...');

      // 서비스 계정 JSON 파일 로드
      final String serviceAccountPath = 'assets/credentials/service-account.json';
      debugPrint('ExternalCnDictionaryService: 서비스 계정 파일 로드 시도: $serviceAccountPath');
      
      String serviceAccountJson;
      try {
        serviceAccountJson = await rootBundle.loadString(serviceAccountPath);
        debugPrint('ExternalCnDictionaryService: 서비스 계정 JSON 파일 로드 성공 (${serviceAccountJson.length}바이트)');
      } catch (e) {
        throw Exception('서비스 계정 JSON 파일 로드 실패: $e');
      }
      
      // JSON 데이터 파싱
      Map<String, dynamic> jsonData;
      try {
        jsonData = jsonDecode(serviceAccountJson);
        debugPrint('ExternalCnDictionaryService: 서비스 계정 JSON 파싱 성공');
      } catch (e) {
        throw Exception('서비스 계정 JSON 파싱 실패: $e');
      }

      // 프로젝트 ID 추출
      _projectId = jsonData['project_id'];
      if (_projectId == null) {
        throw Exception('서비스 계정 JSON에 project_id가 없습니다.');
      }
      debugPrint('ExternalCnDictionaryService: 프로젝트 ID 확인: $_projectId');

      // 서비스 계정 인증 정보 생성
      final accountCredentials = ServiceAccountCredentials.fromJson(jsonData);
      
      // 스코프 설정
      final scopes = ['https://www.googleapis.com/auth/cloud-platform'];
      
      // 인증 클라이언트 생성
      debugPrint('ExternalCnDictionaryService: 인증 클라이언트 생성 중...');
      _httpClient = await clientViaServiceAccount(accountCredentials, scopes);
      debugPrint('ExternalCnDictionaryService: 인증 클라이언트 생성 완료');

      _isInitializing = false;
      debugPrint('ExternalCnDictionaryService: Google Cloud Translation API 초기화 완료');
    } catch (e) {
      _isInitializing = false;
      _httpClient = null;
      _projectId = null;
      debugPrint('ExternalCnDictionaryService: Google Cloud Translation API 초기화 실패: $e');
      if (e.toString().contains('No such file') || e.toString().contains('Unable to load asset')) {
        debugPrint('ExternalCnDictionaryService: 서비스 계정 파일이 존재하지 않거나 접근할 수 없습니다. pubspec.yaml에 assets 정의가 있는지 확인하세요.');
      }
    }
  }

  // 사전 업데이트 리스너 추가
  void addDictionaryUpdateListener(Function() listener) {
    if (!_dictionaryUpdateListeners.contains(listener)) {
      _dictionaryUpdateListeners.add(listener);
    }
  }

  // 사전 업데이트 리스너 제거
  void removeDictionaryUpdateListener(Function() listener) {
    _dictionaryUpdateListeners.remove(listener);
  }

  // 사전 업데이트 알림
  void _notifyDictionaryUpdated() {
    for (final listener in _dictionaryUpdateListeners) {
      listener();
    }
  }

  // 외부 사전을 통한 단어 검색 (Google API 사용)
  Future<Map<String, dynamic>> lookupWord(String word) async {
    try {
      // 캐시된 결과 있으면 바로 반환
      if (_searchResultCache.containsKey(word)) {
        if (kDebugMode) debugPrint('캐시에서 단어 검색 결과 반환: $word');
        return {
          'entry': _searchResultCache[word],
          'success': true,
        };
      }
      
      // API가 초기화되지 않았으면 초기화
      if (_httpClient == null || _projectId == null) {
        if (kDebugMode) debugPrint('ExternalCnDictionaryService: API 초기화 시도');
        await _initializeApi();
      }

      // API가 여전히 null이면 대체 API 사용
      if (_httpClient == null || _projectId == null) {
        if (kDebugMode) debugPrint('ExternalCnDictionaryService: API 초기화 실패, 무료 API 사용');
        var fallbackResult = await _lookupWithFallbackApi(word);
        if (fallbackResult != null) {
          // 캐시에 저장
          _searchResultCache[word] = fallbackResult;
          
          // 사전 업데이트 알림
          _notifyDictionaryUpdated();
          
          return {
            'entry': fallbackResult,
            'success': true,
          };
        }
        return {
          'success': false,
          'message': 'Google 번역에서 단어를 찾을 수 없습니다.',
        };
      }

      // Google Cloud Translation API 사용
      if (kDebugMode) debugPrint('Google API로 단어 검색 시작: $word');
      final googleResult = await _lookupWithGoogleCloud(word);
      
      if (googleResult != null) {
        // 캐시에 저장
        _searchResultCache[word] = googleResult;
        
        // 사전 업데이트 알림
        _notifyDictionaryUpdated();
        
        return {
          'entry': googleResult,
          'success': true,
        };
      }

      return {
        'success': false,
        'message': 'Google 번역에서 단어를 찾을 수 없습니다.',
      };
    } catch (e) {
      if (kDebugMode) debugPrint('Google 단어 검색 중 오류 발생: $e');
      return {
        'success': false,
        'message': '단어 검색 중 오류가 발생했습니다: $e',
      };
    }
  }

  // Google Cloud Translation API를 사용하여 단어 번역
  Future<DictionaryEntry?> _lookupWithGoogleCloud(String word) async {
    try {
      // API 클라이언트 확인
      if (_httpClient == null || _projectId == null) {
        if (kDebugMode) debugPrint('Google API 클라이언트가 초기화되지 않았습니다.');
        return null;
      }

      if (kDebugMode) debugPrint('Google Cloud Translation API 번역 시작: "$word"');

      // 요청 준비
      final parent = 'projects/$_projectId/locations/global';
      final url = Uri.parse('https://translation.googleapis.com/v3/$parent:translateText');

      // 요청 본문
      final requestBody = {
        'contents': [word],
        'sourceLanguageCode': 'zh-CN',
        'targetLanguageCode': 'ko',
        'mimeType': 'text/plain',
      };

      // API 요청
      final response = await _httpClient!.post(
        url,
        body: jsonEncode(requestBody),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5), onTimeout: () {
        if (kDebugMode) debugPrint('Google API 요청 타임아웃');
        return http.Response('{"error":"timeout"}', 408);
      });

      if (kDebugMode) {
        debugPrint('API 응답 상태 코드: ${response.statusCode}');
        debugPrint('API 응답 바디: ${response.body}');
      }

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);

        final translations = data['translations'];
        if (translations != null && translations is List && translations.isNotEmpty) {
          final translatedText = translations[0]['translatedText'];
          if (kDebugMode) debugPrint('번역 결과: $translatedText');

          // 병음은 빈 문자열로 설정 (다른 서비스에서 처리됨)
          final entry = DictionaryEntry(
            word: word,
            pinyin: '', // 병음은 내부 사전에서 처리
            meaning: translatedText,
            examples: [],
            source: 'google',
          );

          return entry;
        } else {
          if (kDebugMode) debugPrint('API 응답 데이터에 translations 필드가 없거나 비어 있습니다');
        }
      } else {
        if (kDebugMode) debugPrint('API 응답 실패: ${response.statusCode}, ${response.body}');
      }

      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('Google API 번역 중 오류 발생: $e');
      return null;
    }
  }

  // 대체 API (무료 버전 Google Translation API)
  Future<DictionaryEntry?> _lookupWithFallbackApi(String word) async {
    try {
      if (kDebugMode) debugPrint('Google 번역 API(무료) 번역 시작: "$word"');

      // 무료 번역 API 활용
      final url = Uri.parse('https://translate.googleapis.com/translate_a/single?client=gtx&sl=zh-CN&tl=ko&dt=t&q=${Uri.encodeComponent(word)}');
      
      final response = await http.get(url).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          if (kDebugMode) debugPrint('Google API 요청 타임아웃');
          return http.Response('{"error":"timeout"}', 408);
        }
      );

      if (kDebugMode) {
        debugPrint('API 응답 상태 코드: ${response.statusCode}');
        debugPrint('API 응답 바디: ${response.body}');
      }

      if (response.statusCode == 200) {
        // 응답 파싱 (무료 API는 특수한 응답 형식)
        final data = json.decode(response.body);
        if (data is List && data.isNotEmpty && data[0] is List && data[0].isNotEmpty) {
          final translatedText = data[0][0][0];
          if (kDebugMode) debugPrint('번역 결과: $translatedText');

          // 병음은 빈 문자열로 설정 (다른 서비스에서 처리됨)
          final entry = DictionaryEntry(
            word: word,
            pinyin: '', // 병음은 내부 사전에서 처리
            meaning: translatedText,
            examples: [],
            source: 'google',
          );

          return entry;
        } else {
          if (kDebugMode) debugPrint('API 응답 파싱 실패: 예상치 못한 형식');
        }
      } else {
        if (kDebugMode) debugPrint('API 응답 실패: ${response.statusCode}, ${response.body}');
      }

      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('Google API(무료) 번역 중 오류 발생: $e');
      return null;
    }
  }
  
  // 검색 캐시 초기화
  void clearCache() {
    _searchResultCache.clear();
    if (kDebugMode) debugPrint('외부 사전 검색 캐시 정리됨');
  }
} 