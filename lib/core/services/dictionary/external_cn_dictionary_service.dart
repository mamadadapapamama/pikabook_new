import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:io' show Platform;
import 'package:url_launcher/url_launcher.dart';
import '../../models/dictionary.dart';
import '../common/usage_limit_service.dart';
import '../text_processing/pinyin_creation_service.dart';

/// 외부 중국어 사전 서비스 타입 (구글, 네이버, 바이두)
enum ExternalCnDictType {
  google,
  naver,
  baidu,
}

/// 외부 API를 통해 중국어 사전 기능을 제공하는 서비스
/// Papago, Google Translate 등 외부 사전 API 연동을 담당합니다.
class ExternalCnDictionaryService {
  // 싱글톤 패턴 구현
  static final ExternalCnDictionaryService _instance = ExternalCnDictionaryService._internal();
  factory ExternalCnDictionaryService() => _instance;
  
  ExternalCnDictionaryService._internal() {
    // 초기화 시 API 키 로드
    loadApiKeys();
    // 사용량 제한 서비스 초기화
  }

  // API 키 저장 변수
  String? _papagoClientId;
  String? _papagoClientSecret;
  

  // 검색 결과 캐시 (메모리 캐시)
  final Map<String, DictionaryEntry> _searchResultCache = {};
  
  // 사전 업데이트 콜백 리스트
  final List<Function()> _dictionaryUpdateListeners = [];
  
  final PinyinCreationService _pinyinService = PinyinCreationService();

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

  // API 키 로드 메서드
  Future<void> loadApiKeys() async {
    try {
      final String jsonString =
          await rootBundle.loadString('assets/credentials/api_keys.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);
      _papagoClientId = jsonData['papago_client_id'];
      _papagoClientSecret = jsonData['papago_client_secret'];
      debugPrint('Papago API 키 로드 완료');
    } catch (e) {
      debugPrint('API 키 로드 오류: $e');
      _papagoClientId = null;
      _papagoClientSecret = null;
    }
  }

  // 외부 사전을 통한 단어 검색
  Future<Map<String, dynamic>> lookupWord(String word) async {
    try {
      // 캐시된 결과 있으면 바로 반환
      if (_searchResultCache.containsKey(word)) {
        debugPrint('캐시에서 단어 검색 결과 반환: $word');
        return {
          'entry': _searchResultCache[word],
          'success': true,
        };
      }
      
      // API 키가 로드되지 않았으면 로드
      if (_papagoClientId == null || _papagoClientSecret == null) {
        await loadApiKeys();
      }

      // Papago API 사용
      final papagoResult = await _lookupWithPapagoApi(word);
      if (papagoResult != null) {
        // 파파고는 병음을 제공하지 않으므로 항상 생성
        final pinyin = await _pinyinService.generatePinyin(word);
        final entryWithPinyin = DictionaryEntry(
          word: papagoResult.word,
          pinyin: pinyin,
          meaning: papagoResult.meaning,
          examples: papagoResult.examples,
          source: papagoResult.source,
        );
        
        // 캐시에 저장
        _searchResultCache[word] = entryWithPinyin;
        
        // 사전 업데이트 알림
        _notifyDictionaryUpdated();
        
        return {
          'entry': entryWithPinyin,
          'success': true,
        };
      }

      // 시스템 사전 기능 활용 (iOS/Android)
      final systemDictResult = await _lookupInSystemDictionary(word);
      if (systemDictResult != null) {
        // 병음이 없는 경우에도 생성
        if (systemDictResult.pinyin.isEmpty) {
          final pinyin = await _pinyinService.generatePinyin(word);
          final entry = DictionaryEntry(
            word: systemDictResult.word,
            pinyin: pinyin,
            meaning: systemDictResult.meaning,
            examples: systemDictResult.examples,
            source: systemDictResult.source,
          );
          
          // 캐시에 저장
          _searchResultCache[word] = entry;
          
          return {
            'entry': entry,
            'success': true,
          };
        }
        
        // 캐시에 저장
        _searchResultCache[word] = systemDictResult;
        
        return {
          'entry': systemDictResult,
          'success': true,
        };
      }

      // 검색 결과가 없는 경우
      return {
        'success': false,
        'message': '외부 사전에서 단어를 찾을 수 없습니다.',
      };
    } catch (e) {
      debugPrint('외부 사전 단어 검색 중 오류 발생: $e');
      return {
        'success': false,
        'message': '단어 검색 중 오류가 발생했습니다: $e',
      };
    }
  }

  // Papago API를 사용하여 단어 번역
  Future<DictionaryEntry?> _lookupWithPapagoApi(String word) async {
    try {
      // API 키가 없으면 검색 불가
      if (_papagoClientId == null || _papagoClientSecret == null) {
        debugPrint('유효한 Papago API 키가 없습니다.');
        return null;
      }

      debugPrint('Papago API 번역 시작: "$word"');

      // Papago API URL
      final url =
          Uri.parse('https://naveropenapi.apigw.ntruss.com/nmt/v1/translation');

      // API 요청 헤더
      final headers = {
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'X-NCP-APIGW-API-KEY-ID': _papagoClientId!,
        'X-NCP-APIGW-API-KEY': _papagoClientSecret!,
      };

      // API 요청 바디 (중국어 -> 한국어)
      final body = {
        'source': 'zh-CN',
        'target': 'ko',
        'text': word,
      };

      // 타임아웃 설정 (5초)
      final response = await http
          .post(
        url,
        headers: headers,
        body: body,
      )
          .timeout(const Duration(seconds: 5), onTimeout: () {
        debugPrint('Papago API 요청 타임아웃');
        return http.Response('{"error":"timeout"}', 408);
      });

      debugPrint('API 응답 상태 코드: ${response.statusCode}');

      if (response.statusCode == 200) {
        // JSON 응답 파싱
        final Map<String, dynamic> data = json.decode(response.body);

        if (data.containsKey('message')) {
          if (data['message'].containsKey('result')) {
            final translatedText = data['message']['result']['translatedText'];

            // 번역 결과를 DictionaryEntry로 변환
            final entry = DictionaryEntry(
              word: word,
              pinyin: '', // Papago는 발음 정보를 제공하지 않음
              meaning: translatedText,
              examples: [],
              source: 'papago',
            );

            return entry;
          }
        }
      }

      return null;
    } catch (e) {
      debugPrint('Papago API 번역 중 오류 발생: $e');
      return null;
    }
  }

  // 시스템 사전에서 단어 검색 (iOS/Android)
  Future<DictionaryEntry?> _lookupInSystemDictionary(String word) async {
    try {
      // iOS의 경우 사전 앱 URL 스킴 사용
      if (Platform.isIOS) {
        // iOS 사전 앱은 직접적인 API가 없어 URL 스킴을 통해 열기만 가능
        // 결과를 직접 가져올 수는 없음
        return null;
      }

      // Android의 경우 시스템 사전 API 사용 (실제로는 구현 필요)
      if (Platform.isAndroid) {
        // Android에는 표준 사전 API가 없어 제조사별 구현이 다를 수 있음
        return null;
      }

      return null;
    } catch (e) {
      debugPrint('시스템 사전 검색 중 오류 발생: $e');
      return null;
    }
  }

  // 외부 사전 서비스로 연결 (Google Translate, Naver 사전 등)
  Future<bool> openExternalDictionary(String word,
      {ExternalCnDictType type = ExternalCnDictType.google}) async {
    try {
      final Uri uri = _getExternalDictionaryUri(word, type);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('외부 사전 열기 중 오류 발생: $e');
      return false;
    }
  }

  // 외부 사전 서비스 URL 생성
  Uri _getExternalDictionaryUri(String word, ExternalCnDictType type) {
    switch (type) {
      case ExternalCnDictType.google:
        // Google Translate (중국어 -> 한국어)
        return Uri.parse(
            'https://translate.google.com/?sl=zh-CN&tl=ko&text=${Uri.encodeComponent(word)}&op=translate');

      case ExternalCnDictType.naver:
        // Naver 사전 (중국어)
        return Uri.parse(
            'https://dict.naver.com/search.dict?dicQuery=${Uri.encodeComponent(word)}&query=${Uri.encodeComponent(word)}&target=dic&ie=utf8&query_utf=&isOnlyViewEE=');

      case ExternalCnDictType.baidu:
        // Baidu 사전
        return Uri.parse(
            'https://fanyi.baidu.com/#zh/ko/${Uri.encodeComponent(word)}');
    }
  }
  
  // 검색 캐시 초기화
  void clearCache() {
    _searchResultCache.clear();
    debugPrint('외부 사전 검색 캐시 정리됨');
  }
  

} 