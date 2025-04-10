// MARK: 다국어 지원을 위한 확장 포인트
// 이 서비스는 향후 다국어 지원을 위해 확장될 예정입니다.
// 현재는 중국어만 지원합니다.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/dictionary_entry.dart';
import 'chinese_dictionary_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'pinyin_creation_service.dart';
import 'usage_limit_service.dart';

/// 외부 사전 서비스 (e.g papago, google translate) 를 관리하는 서비스
/// 단어 검색 결과 캐싱
/// 플래시카드 연동을 위한 단어 정보 제공

class DictionaryService {
  // 싱글톤 패턴 구현
  static final DictionaryService _instance = DictionaryService._internal();
  factory DictionaryService() => _instance;
  DictionaryService._internal() {
    // 초기화 시 API 키 로드
    loadApiKeys();
    // 중국어 사전 서비스 인스턴스 가져오기
    _chineseDictionaryService = ChineseDictionaryService();
    // 사용량 제한 서비스 초기화
    _usageLimitService = UsageLimitService();
  }

  // API 키 저장 변수
  String? _papagoClientId;
  String? _papagoClientSecret;

  // 중국어 사전 서비스 참조
  late final ChineseDictionaryService _chineseDictionaryService;
  
  // 사용량 제한 서비스
  late final UsageLimitService _usageLimitService;

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

  // 간단한 인메모리 사전 (실제로는 데이터베이스나 API를 사용해야 함)
  final Map<String, DictionaryEntry> _dictionary = {
    '你': DictionaryEntry(
      word: '你',
      pinyin: 'nǐ',
      meaning: '너, 당신',
      examples: ['你好 (nǐ hǎo) - 안녕하세요', '谢谢你 (xiè xiè nǐ) - 감사합니다'],
    ),
    '好': DictionaryEntry(
      word: '好',
      pinyin: 'hǎo',
      meaning: '좋다, 잘',
      examples: ['你好 (nǐ hǎo) - 안녕하세요', '好的 (hǎo de) - 좋아요'],
    ),
    '我': DictionaryEntry(
      word: '我',
      pinyin: 'wǒ',
      meaning: '나, 저',
      examples: ['我是学生 (wǒ shì xué shēng) - 나는 학생이다'],
    ),
    '是': DictionaryEntry(
      word: '是',
      pinyin: 'shì',
      meaning: '~이다, ~이다',
      examples: ['我是韩国人 (wǒ shì hán guó rén) - 나는 한국인이다'],
    ),
    '中国': DictionaryEntry(
      word: '中国',
      pinyin: 'zhōng guó',
      meaning: '중국',
      examples: ['我去中国 (wǒ qù zhōng guó) - 나는 중국에 간다'],
    ),
    '学生': DictionaryEntry(
      word: '学生',
      pinyin: 'xué shēng',
      meaning: '학생',
      examples: ['我是学生 (wǒ shì xué shēng) - 나는 학생이다'],
    ),
    '谢谢': DictionaryEntry(
      word: '谢谢',
      pinyin: 'xiè xiè',
      meaning: '감사합니다',
      examples: ['谢谢你 (xiè xiè nǐ) - 감사합니다'],
    ),
    '再见': DictionaryEntry(
      word: '再见',
      pinyin: 'zài jiàn',
      meaning: '안녕히 가세요, 안녕히 계세요',
      examples: ['明天见 (míng tiān jiàn) - 내일 봐요'],
    ),
    '朋友': DictionaryEntry(
      word: '朋友',
      pinyin: 'péng yǒu',
      meaning: '친구',
      examples: ['他是我的朋友 (tā shì wǒ de péng yǒu) - 그는 내 친구이다'],
    ),
    '老师': DictionaryEntry(
      word: '老师',
      pinyin: 'lǎo shī',
      meaning: '선생님, 교사',
      examples: ['他是老师 (tā shì lǎo shī) - 그는 선생님이다'],
    ),
  };

  // 단어 검색 - 단계별 폴백 구현
  Future<Map<String, dynamic>> lookupWordWithFallback(String word) async {
    try {
      // 캐시된 결과 있으면 바로 반환
      if (_searchResultCache.containsKey(word)) {
        debugPrint('캐시에서 단어 검색 결과 반환: $word');
        return {
          'entry': _searchResultCache[word],
          'success': true,
        };
      }
      
      // 사용량 제한 체크 (로컬/내장 사전은 제외)
      // 0. 먼저 내부 중국어 사전 서비스에서 검색 (사용량 제한 없음)
      await _chineseDictionaryService.loadDictionary();
      final chineseDictResult = _chineseDictionaryService.lookup(word);
      if (chineseDictResult != null) {
        // 병음이 없는 경우에도 생성
        if (chineseDictResult.pinyin.isEmpty) {
          final pinyin = await _pinyinService.generatePinyin(word);
          final entry = DictionaryEntry(
            word: chineseDictResult.word,
            pinyin: pinyin,
            meaning: chineseDictResult.meaning,
            examples: chineseDictResult.examples,
            source: chineseDictResult.source,
          );
          
          // 캐시에 저장
          _searchResultCache[word] = entry;
          
          debugPrint('내부 중국어 사전에서 단어 찾음: $word');
          return {
            'entry': entry,
            'success': true,
          };
        }
        
        // 캐시에 저장
        _searchResultCache[word] = chineseDictResult;
        
        debugPrint('내부 중국어 사전에서 단어 찾음: $word');
        return {
          'entry': chineseDictResult,
          'success': true,
        };
      }
      
      // 내부 사전에 없는 경우 사용량 제한 확인
      final canLookup = await _usageLimitService.incrementDictionaryCount();
      if (!canLookup) {
        debugPrint('사전 검색 사용량 한도 초과: $word');
        return {
          'success': false,
          'message': '무료 버전 사전 검색 한도를 초과했습니다. 관리자에게 문의해주세요.',
          'limitExceeded': true,
        };
      }

      // API 키가 로드되지 않았으면 로드
      if (_papagoClientId == null || _papagoClientSecret == null) {
        await loadApiKeys();
      }

      // 1. 앱 내 JSON 단어장에서 검색
      final jsonResult = _dictionary[word];
      if (jsonResult != null) {
        // 병음이 없는 경우에도 생성
        if (jsonResult.pinyin.isEmpty) {
          final pinyin = await _pinyinService.generatePinyin(word);
          final entry = DictionaryEntry(
            word: jsonResult.word,
            pinyin: pinyin,
            meaning: jsonResult.meaning,
            examples: jsonResult.examples,
            source: jsonResult.source,
          );
          
          // 캐시에 저장
          _searchResultCache[word] = entry;
          
          return {
            'entry': entry,
            'success': true,
          };
        }
        
        // 캐시에 저장
        _searchResultCache[word] = jsonResult;
        
        return {
          'entry': jsonResult,
          'success': true,
        };
      }

      // 2. 시스템 사전 기능 활용 (iOS/Android)
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

      // 3. Papago API 사용
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
        // 내부 중국어 사전에도 추가
        _chineseDictionaryService.addEntry(entryWithPinyin);
        
        // 캐시에 저장
        _searchResultCache[word] = entryWithPinyin;
        
        return {
          'entry': entryWithPinyin,
          'success': true,
        };
      }

      // 검색 결과가 없는 경우
      return {
        'success': false,
        'message': '사전에서 단어를 찾을 수 없습니다.',
      };
    } catch (e) {
      debugPrint('단어 검색 중 오류 발생: $e');
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
      
      // 사용량 제한 확인 (외부 API 호출 전 확인)
      final canLookup = await _usageLimitService.incrementDictionaryCount();
      if (!canLookup) {
        debugPrint('Papago API 호출 사용량 한도 초과: $word');
        return null;
      }

      // 이미 사전에 있는지 확인 (중복 API 호출 방지)
      final existingEntry = _dictionary[word];
      if (existingEntry != null) {
        debugPrint('이미 사전에 있는 단어 반환: $word');
        // 이미 사전에 있으므로 사용량을 다시 감소
        await _usageLimitService.decrementUsage('dictionaryLookups');
        return existingEntry;
      }

      debugPrint('Papago API 번역 시작: "$word"');

      // Papago API URL (최신 URL로 변경)
      final url =
          Uri.parse('https://naveropenapi.apigw.ntruss.com/nmt/v1/translation');

      // API 요청 헤더 (최신 헤더 이름으로 변경)
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

      // API 요청 시작 시간 기록
      final startTime = DateTime.now();

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

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      debugPrint('API 응답 상태 코드: ${response.statusCode}');

      if (response.statusCode == 200) {
        // JSON 응답 파싱
        final Map<String, dynamic> data = json.decode(response.body);

        if (data.containsKey('message')) {
          if (data['message'].containsKey('result')) {
            final translatedText = data['message']['result']['translatedText'];
            final srcLangType = data['message']['result']['srcLangType'];
            final tarLangType = data['message']['result']['tarLangType'];

            // 번역 결과를 DictionaryEntry로 변환
            final entry = DictionaryEntry(
              word: word,
              pinyin: '', // Papago는 발음 정보를 제공하지 않음
              meaning: translatedText,
              examples: [],
              source: 'papago',
            );

            // 사전에 추가 (메모리 사전에 영구 저장)
            _dictionary[word] = entry;

            // 사전 업데이트 알림
            _notifyDictionaryUpdated();

            return entry;
          }
        }
      }

      return null;
    } catch (e, stackTrace) {
      debugPrint('Papago API 번역 중 오류 발생: $e');
      debugPrint('스택 트레이스: $stackTrace');
      return null;
    }
  }

  // Papago API 테스트 메서드
  Future<void> testPapagoApi(String word) async {
    debugPrint('===== Papago API 테스트 시작: "$word" =====');

    try {
      // API 키가 로드되지 않았으면 로드
      if (_papagoClientId == null || _papagoClientSecret == null) {
        await loadApiKeys();
      }

      // API 키 확인
      if (_papagoClientId == null || _papagoClientSecret == null) {
        debugPrint('유효한 Papago API 키가 없습니다.');
        return;
      }

      // Papago API URL (최신 URL로 변경)
      final url =
          Uri.parse('https://naveropenapi.apigw.ntruss.com/nmt/v1/translation');

      // API 요청 헤더 (최신 헤더 이름으로 변경)
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

      debugPrint('요청 URL: $url');
      debugPrint('요청 헤더: $headers');
      debugPrint('요청 바디: $body');

      // API 요청 시작 시간 기록
      final startTime = DateTime.now();
      final response = await http.post(
        url,
        headers: headers,
        body: body,
      );
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      debugPrint('API 응답 상태 코드: ${response.statusCode}');

      if (response.statusCode == 200) {
        // 응답 내용 로깅 (전체)
        debugPrint('API 응답 내용: ${response.body}');

        // JSON 응답 파싱
        final Map<String, dynamic> data = json.decode(response.body);
        debugPrint('응답 데이터 구조: ${data.keys}');

        if (data.containsKey('message')) {
          debugPrint('message 구조: ${data['message'].keys}');

          if (data['message'].containsKey('result')) {
            debugPrint('result 구조: ${data['message']['result'].keys}');

            final translatedText = data['message']['result']['translatedText'];
            final srcLangType = data['message']['result']['srcLangType'];
            final tarLangType = data['message']['result']['tarLangType'];

            debugPrint('원본 언어: $srcLangType');
            debugPrint('번역 언어: $tarLangType');
            debugPrint('번역 결과: $translatedText');
          }
        }
      } else {
        debugPrint('API 요청 실패: ${response.statusCode}');
        debugPrint('응답 내용: ${response.body}');
      }
    } catch (e, stackTrace) {
      debugPrint('Papago API 테스트 중 오류 발생: $e');
      debugPrint('스택 트레이스: $stackTrace');
    }

    debugPrint('===== Papago API 테스트 완료 =====');
  }

  // 기존 단어 검색 메서드 (하위 호환성 유지)
  DictionaryEntry? lookupWord(String word) {
    try {
      // 사전에서 단어 검색
      final entry = _dictionary[word];

      // 디버그 로그 추가
      if (entry != null) {
        debugPrint('사전에서 단어 찾음: $word -> ${entry.meaning}');
      } else {
        debugPrint('사전에서 단어를 찾을 수 없음: $word');
      }

      return entry;
    } catch (e) {
      debugPrint('단어 검색 중 오류 발생: $e');
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
      {ExternalDictType type = ExternalDictType.google}) async {
    try {
      final Uri uri = _getExternalDictionaryUri(word, type);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('외부 사전 열기 중 오류 발생: $e');
      return false;
    }
  }

  // 외부 사전 서비스 URL 생성
  Uri _getExternalDictionaryUri(String word, ExternalDictType type) {
    switch (type) {
      case ExternalDictType.google:
        // Google Translate (중국어 -> 한국어)
        return Uri.parse(
            'https://translate.google.com/?sl=zh-CN&tl=ko&text=${Uri.encodeComponent(word)}&op=translate');

      case ExternalDictType.naver:
        // Naver 사전 (중국어)
        return Uri.parse(
            'https://dict.naver.com/dict.search?query=${Uri.encodeComponent(word)}');

      case ExternalDictType.baidu:
        // Baidu 사전
        return Uri.parse(
            'https://dict.baidu.com/s?wd=${Uri.encodeComponent(word)}');

      default:
        return Uri.parse(
            'https://translate.google.com/?sl=zh-CN&tl=ko&text=${Uri.encodeComponent(word)}&op=translate');
    }
  }

  // 외부 사전에서 단어 검색 후 결과 반환
  Future<DictionaryEntry?> searchExternalDictionary(
      String word, ExternalDictType type) async {
    try {
      // 이미 사전에 있는지 확인
      final existingEntry = _dictionary[word];
      if (existingEntry != null) {
        debugPrint('이미 사전에 있는 단어: $word');
        return existingEntry;
      }

      // 캐시 키 생성 (단어 + 타입)
      final cacheKey = '${word}_${type.toString()}';

      // 메모리 캐시 확인 (임시 캐시)
      final cachedResult = _searchResultCache[cacheKey];
      if (cachedResult != null) {
        debugPrint('캐시된 검색 결과 반환: $word');
        return cachedResult;
      }

      // Papago API 사용 (Google, Naver, Baidu 대신)
      final papagoResult = await _lookupWithPapagoApi(word);
      if (papagoResult != null) {
        // 검색 결과를 사전에 추가
        addToDictionary(papagoResult);

        // 내부 중국어 사전에도 추가
        _chineseDictionaryService.addEntry(papagoResult);

        // 캐시에 결과 저장
        _searchResultCache[cacheKey] = papagoResult;

        return papagoResult;
      }

      // API 검색 실패 시 기본 정보 반환
      final fallbackEntry = DictionaryEntry(
        word: word,
        pinyin: '',
        meaning: '외부 사전 검색 결과를 가져올 수 없습니다.',
        examples: [],
        source: type.toString().split('.').last,
      );

      // 캐시에 실패 결과도 저장 (재시도 방지)
      _searchResultCache[cacheKey] = fallbackEntry;

      return fallbackEntry;
    } catch (e) {
      debugPrint('외부 사전 검색 중 오류 발생: $e');
      return null;
    }
  }

  // 사전에 단어 추가
  void addToDictionary(DictionaryEntry entry) {
    bool isNewEntry = false;
    if (!_dictionary.containsKey(entry.word)) {
      _dictionary[entry.word] = entry;
      isNewEntry = true;
      debugPrint('사전에 단어 추가됨: ${entry.word}');
    } else if (_dictionary[entry.word]!.meaning != entry.meaning) {
      // 기존 단어의 의미가 다른 경우 업데이트
      _dictionary[entry.word] = entry;
      isNewEntry = true;
      debugPrint('사전에 단어 업데이트됨: ${entry.word}');
    }

    // 새 단어가 추가되었거나 업데이트된 경우 리스너에 알림
    if (isNewEntry) {
      _notifyDictionaryUpdated();
    }
  }

  // 문장에서 알고 있는 단어 추출
  List<DictionaryEntry> extractKnownWords(String text) {
    final result = <DictionaryEntry>[];

    // 단순 구현: 사전에 있는 단어가 문장에 포함되어 있는지 확인
    _dictionary.forEach((word, entry) {
      if (text.contains(word)) {
        result.add(entry);
      }
    });

    return result;
  }

  // 더 복잡한 중국어 단어 분석 (실제로는 NLP 라이브러리 사용 필요)
  List<String> segmentChineseText(String text) {
    // 간단한 구현: 각 문자를 개별 단어로 취급
    // 실제로는 중국어 단어 분석 라이브러리를 사용해야 함
    return text.split('');
  }

  // 단어별 의미 분석 결과를 담을 클래스
  Future<List<WordAnalysis>> analyzeText(String text) async {
    // 현재는 간단한 구현으로, 실제로는 API 호출이 필요합니다
    List<WordAnalysis> result = [];

    try {
      // 여기서 API 호출을 구현합니다
      // 예시: Google Cloud Natural Language API 또는 Baidu API 호출

      // 임시 구현: 사전에서 단어를 찾아 분석 결과 생성
      // 실제 구현에서는 API 응답을 파싱하여 결과 생성
      final words = text.split(' '); // 간단한 공백 기준 분리 (실제로는 더 복잡한 분리 필요)

      for (final word in words) {
        if (word.trim().isEmpty) continue;

        final entry = lookupWord(word.trim());
        if (entry != null) {
          result.add(WordAnalysis(
            word: entry.word,
            pinyin: entry.pinyin,
            meaning: entry.meaning,
            partOfSpeech: _guessPartOfSpeech(entry.meaning),
          ));
        } else {
          // 사전에 없는 단어는 분석 결과 없음으로 표시
          result.add(WordAnalysis(
            word: word.trim(),
            pinyin: '',
            meaning: '사전에 없는 단어',
            partOfSpeech: '알 수 없음',
          ));
        }
      }
    } catch (e) {
      debugPrint('텍스트 분석 중 오류 발생: $e');
    }

    return result;
  }

  // 간단한 품사 추측 (실제로는 API에서 제공하는 품사 정보 사용)
  String _guessPartOfSpeech(String meaning) {
    final lowerMeaning = meaning.toLowerCase();

    if (lowerMeaning.contains('동사') || lowerMeaning.contains('verb')) {
      return '동사';
    } else if (lowerMeaning.contains('명사') || lowerMeaning.contains('noun')) {
      return '명사';
    } else if (lowerMeaning.contains('형용사') ||
        lowerMeaning.contains('adjective')) {
      return '형용사';
    } else if (lowerMeaning.contains('부사') || lowerMeaning.contains('adverb')) {
      return '부사';
    } else {
      return '기타';
    }
  }

  Future<Map<String, dynamic>> _processSearchResults(List<Map<String, dynamic>> results, String query) async {
    try {
      // 전체 결과 처리 시간 측정
      // final startTime = DateTime.now();
      
      // 결과 데이터 형식 통일
      final processedResults = <Map<String, dynamic>>[];
      
      for (final result in results) {
        processedResults.add({
          'word': result['word'] ?? result['title'] ?? query,
          'pinyin': result['pinyin'] ?? result['pronunciation'] ?? '',
          'meaning': result['meaning'] ?? result['definition'] ?? (result['translations'] != null 
              ? List<String>.from(result['translations']).join(', ') 
              : ''),
          'examples': result['examples'] ?? [],
          'source': result['source'] ?? 'local',
        });
      }
      
      // 결과 필터링 및 정렬
      final filteredResults = processedResults
          .where((r) => r['word'].toString().isNotEmpty && r['meaning'].toString().isNotEmpty)
          .toList();
      
      // 정확한 일치가 있으면 상위 배치
      filteredResults.sort((a, b) {
        final aExactMatch = a['word'] == query;
        final bExactMatch = b['word'] == query;
        
        if (aExactMatch && !bExactMatch) return -1;
        if (!aExactMatch && bExactMatch) return 1;
        
        // 단어 길이로 정렬 (짧은 것이 우선)
        return a['word'].toString().length - b['word'].toString().length;
      });
      
      // 최대 10개 결과로 제한
      final limitedResults = filteredResults.take(10).toList();
      
      // 최종 결과 포맷
      final finalResponse = {
        'query': query,
        'results': limitedResults,
        'status': 'success',
        'count': limitedResults.length,
      };
      
      // 처리 시간 측정
      // final endTime = DateTime.now();
      // final processingTime = endTime.difference(startTime).inMilliseconds;
      // debugPrint('검색 결과 처리 시간: ${processingTime}ms (${limitedResults.length}개 결과)');
      
      return finalResponse;
    } catch (e) {
      debugPrint('검색 결과 처리 중 오류 발생: $e');
      return {
        'query': query,
        'results': [],
        'status': 'error',
        'count': 0,
        'error': e.toString(),
      };
    }
  }
}

// 외부 사전 유형
enum ExternalDictType {
  google, // Google Translate
  naver, // Naver 사전
  baidu, // Baidu 사전
}

// 단어 분석 결과를 담는 클래스
class WordAnalysis {
  final String word;
  final String pinyin;
  final String meaning;
  final String partOfSpeech; // 품사 정보

  WordAnalysis({
    required this.word,
    required this.pinyin,
    required this.meaning,
    required this.partOfSpeech,
  });
}
