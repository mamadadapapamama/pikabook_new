import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:xml/xml.dart';
import 'dart:math' show min;

class DictionaryEntry {
  final String word;
  final String pinyin;
  final String meaning;
  final List<String> examples;
  final String? source; // 사전 출처 (JSON, 시스템 사전, 외부 사전 등)

  DictionaryEntry({
    required this.word,
    required this.pinyin,
    required this.meaning,
    this.examples = const [],
    this.source,
  });
}

class DictionaryService {
  // 싱글톤 패턴 구현
  static final DictionaryService _instance = DictionaryService._internal();
  factory DictionaryService() => _instance;
  DictionaryService._internal() {
    // 초기화 시 API 키 로드
    loadApiKeys();
  }

  // API 키 저장 변수
  String? _krDictApiKey;

  // API 키 로드 메서드
  Future<void> loadApiKeys() async {
    try {
      final String jsonString =
          await rootBundle.loadString('assets/credentials/api_keys.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);
      _krDictApiKey = jsonData['krdict_api_key'];
      debugPrint('API 키 로드 완료: $_krDictApiKey');
    } catch (e) {
      debugPrint('API 키 로드 오류: $e');
      _krDictApiKey = null;
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
  Future<DictionaryEntry?> lookupWordWithFallback(String word) async {
    try {
      // API 키가 로드되지 않았으면 로드
      if (_krDictApiKey == null) {
        await loadApiKeys();
      }

      // 1. 앱 내 JSON 단어장에서 검색
      final jsonResult = _dictionary[word];
      if (jsonResult != null) {
        return jsonResult;
      }

      // 2. 시스템 사전 기능 활용 (iOS/Android)
      final systemDictResult = await _lookupInSystemDictionary(word);
      if (systemDictResult != null) {
        return systemDictResult;
      }

      // 3. 국립국어원 오픈 API 사용
      final apiResult = await _lookupInKrDictApi(word);
      if (apiResult != null) {
        return apiResult;
      }

      // 4. 외부 사전 서비스 URL 생성 (실제 검색은 사용자가 URL을 통해 수행)
      return DictionaryEntry(
        word: word,
        pinyin: '',
        meaning: '사전에서 찾을 수 없습니다. 외부 사전에서 검색하려면 탭하세요.',
        examples: [],
        source: 'external',
      );
    } catch (e) {
      debugPrint('단어 검색 중 오류 발생: $e');
      return null;
    }
  }

  // 국립국어원 오픈 API를 사용하여 단어 검색
  Future<DictionaryEntry?> _lookupInKrDictApi(String word) async {
    try {
      // API 키가 없으면 검색 불가
      if (_krDictApiKey == null || _krDictApiKey == 'YOUR_API_KEY_HERE') {
        debugPrint('유효한 API 키가 없습니다.');
        return null;
      }

      debugPrint('국립국어원 API 검색 시작: "$word"');

      // 국립국어원 중국어 사전 API URL
      // 파라미터 설명:
      // - key: API 키
      // - q: 검색어
      // - advanced: 고급 검색 여부 (y)
      // - target: 찾을 대상 (4: 원어)
      // - lang: 언어 (31: 중국어)
      // - method: 검색 방식 (exact: 정확히 일치하는 단어)
      // - translated: 다국어 번역 여부 (y)
      // - trans_lang: 번역 언어 (1: 한국어)
      final url = Uri.parse(
          'https://krdict.korean.go.kr/api/search?key=$_krDictApiKey&q=${Uri.encodeComponent(word)}&advanced=y&target=4&lang=31&method=exact&translated=y&trans_lang=1');

      debugPrint('API 요청 URL: $url');

      // API 요청 시작 시간 기록
      final startTime = DateTime.now();
      final response = await http.get(url);
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      debugPrint('API 응답 시간: ${duration.inMilliseconds}ms');
      debugPrint('API 응답 상태 코드: ${response.statusCode}');

      if (response.statusCode == 200) {
        // 응답 내용 로깅 (처음 200자만)
        final responsePreview = response.body.length > 200
            ? '${response.body.substring(0, 200)}...'
            : response.body;
        debugPrint('API 응답 내용 미리보기: $responsePreview');

        // XML 응답 파싱
        final document = XmlDocument.parse(response.body);

        // 에러 코드 확인
        final errorElements = document.findAllElements('error');
        if (errorElements.isNotEmpty) {
          final errorCode = errorElements.first
              .findElements('error_code')
              .firstOrNull
              ?.innerText;
          final errorMessage = errorElements.first
              .findElements('message')
              .firstOrNull
              ?.innerText;
          debugPrint('API 에러: $errorCode - $errorMessage');
          return null;
        }

        // 검색 결과 총 개수 확인
        final totalElement = document.findAllElements('total').firstOrNull;
        final totalCount = totalElement != null
            ? int.tryParse(totalElement.innerText) ?? 0
            : 0;
        debugPrint('검색 결과 총 개수: $totalCount');

        // item 요소 찾기
        final items = document.findAllElements('item');
        debugPrint('검색 결과 항목 수: ${items.length}');

        if (items.isNotEmpty) {
          // 첫 번째 결과 사용
          final item = items.first;
          debugPrint('첫 번째 검색 결과 처리 중...');

          // 단어 정보 요소 찾기
          final wordInfo = item.findElements('word_info').firstOrNull;
          if (wordInfo == null) {
            debugPrint('word_info 요소를 찾을 수 없습니다.');
            return null;
          }

          // 의미와 발음 추출
          String definition = '';
          final senseInfo = wordInfo.findElements('sense_info').firstOrNull;
          if (senseInfo != null) {
            definition =
                senseInfo.findElements('definition').firstOrNull?.innerText ??
                    '의미를 찾을 수 없습니다';
          } else {
            debugPrint('sense_info 요소를 찾을 수 없습니다.');
          }

          final pronunciation =
              wordInfo.findElements('pronunciation').firstOrNull?.innerText ??
                  '';
          debugPrint('추출된 발음: $pronunciation');
          debugPrint('추출된 의미: $definition');

          // 원어 정보 추출 (중국어 원어)
          String originalLanguage = '';
          final originalLanguageInfo =
              wordInfo.findElements('original_language_info').firstOrNull;
          if (originalLanguageInfo != null) {
            originalLanguage = originalLanguageInfo
                    .findElements('original_language')
                    .firstOrNull
                    ?.innerText ??
                '';
            debugPrint('추출된 원어: $originalLanguage');
          } else {
            debugPrint('original_language_info 요소를 찾을 수 없습니다.');
          }

          // 예문 추출
          final examples = <String>[];
          final exampleInfos = senseInfo?.findElements('example_info') ?? [];
          for (var exampleInfo in exampleInfos) {
            final example =
                exampleInfo.findElements('example').firstOrNull?.innerText;
            if (example != null && example.isNotEmpty) {
              examples.add(example);
            }
          }
          debugPrint('추출된 예문 수: ${examples.length}');

          return DictionaryEntry(
            word: word,
            pinyin: pronunciation,
            meaning: definition,
            examples: examples,
            source: 'krdict',
          );
        } else {
          debugPrint('검색 결과가 없습니다.');
        }
      } else {
        debugPrint('API 요청 실패: ${response.statusCode}');
        debugPrint('응답 내용: ${response.body}');
      }

      return null;
    } catch (e, stackTrace) {
      debugPrint('국립국어원 API 검색 중 오류 발생: $e');
      debugPrint('스택 트레이스: $stackTrace');
      return null;
    }
  }

  // 국립국어원 API 테스트 메서드 - 다양한 파라미터 조합으로 API 호출 테스트
  Future<void> testKrDictApi(String word) async {
    debugPrint('===== 국립국어원 API 테스트 시작: "$word" =====');

    // 테스트할 파라미터 조합 목록
    final paramCombinations = [
      {
        'description': '기본 검색 (target=1, 표제어)',
        'params':
            'key=$_krDictApiKey&q=${Uri.encodeComponent(word)}&translated=y&trans_lang=1'
      },
      {
        'description': '원어 검색 (target=4, lang=31, 중국어)',
        'params':
            'key=$_krDictApiKey&q=${Uri.encodeComponent(word)}&advanced=y&target=4&lang=31&translated=y&trans_lang=1'
      },
      {
        'description': '정확한 검색 (method=exact)',
        'params':
            'key=$_krDictApiKey&q=${Uri.encodeComponent(word)}&advanced=y&target=4&lang=31&method=exact&translated=y&trans_lang=1'
      },
      {
        'description': '시작 검색 (method=start)',
        'params':
            'key=$_krDictApiKey&q=${Uri.encodeComponent(word)}&advanced=y&target=4&lang=31&method=start&translated=y&trans_lang=1'
      },
      {
        'description': '포함 검색 (method=include)',
        'params':
            'key=$_krDictApiKey&q=${Uri.encodeComponent(word)}&advanced=y&target=4&lang=31&method=include&translated=y&trans_lang=1'
      },
      {
        'description': '유사 검색 (method=similar)',
        'params':
            'key=$_krDictApiKey&q=${Uri.encodeComponent(word)}&advanced=y&target=4&lang=31&method=similar&translated=y&trans_lang=1'
      },
    ];

    // 각 파라미터 조합으로 API 호출 테스트
    for (var combination in paramCombinations) {
      final description = combination['description'];
      final params = combination['params'];

      debugPrint('\n----- 테스트: $description -----');

      try {
        final url = Uri.parse('https://krdict.korean.go.kr/api/search?$params');
        debugPrint('요청 URL: $url');

        final response = await http.get(url);
        debugPrint('응답 상태 코드: ${response.statusCode}');

        if (response.statusCode == 200) {
          // XML 응답 파싱
          final document = XmlDocument.parse(response.body);

          // 에러 확인
          final errorElements = document.findAllElements('error');
          if (errorElements.isNotEmpty) {
            final errorCode = errorElements.first
                .findElements('error_code')
                .firstOrNull
                ?.innerText;
            final errorMessage = errorElements.first
                .findElements('message')
                .firstOrNull
                ?.innerText;
            debugPrint('API 에러: $errorCode - $errorMessage');
            continue;
          }

          // 검색 결과 개수 확인
          final totalElement = document.findAllElements('total').firstOrNull;
          final totalCount = totalElement != null
              ? int.tryParse(totalElement.innerText) ?? 0
              : 0;
          debugPrint('검색 결과 개수: $totalCount');

          // 결과가 있으면 첫 번째 항목 정보 출력
          final items = document.findAllElements('item');
          if (items.isNotEmpty) {
            debugPrint('첫 번째 결과 정보:');
            final item = items.first;

            // 단어 정보 출력
            final wordInfo = item.findElements('word_info').firstOrNull;
            if (wordInfo != null) {
              final word = wordInfo.findElements('word').firstOrNull?.innerText;
              debugPrint('- 단어: $word');

              // 발음 정보
              final pronunciationInfo =
                  wordInfo.findElements('pronunciation_info').firstOrNull;
              if (pronunciationInfo != null) {
                final pronunciation = pronunciationInfo
                    .findElements('pronunciation')
                    .firstOrNull
                    ?.innerText;
                debugPrint('- 발음: $pronunciation');
              }

              // 원어 정보
              final originalLanguageInfo =
                  wordInfo.findElements('original_language_info').firstOrNull;
              if (originalLanguageInfo != null) {
                final originalLanguage = originalLanguageInfo
                    .findElements('original_language')
                    .firstOrNull
                    ?.innerText;
                debugPrint('- 원어: $originalLanguage');
              }

              // 의미 정보
              final senseInfo = wordInfo.findElements('sense_info').firstOrNull;
              if (senseInfo != null) {
                final definition =
                    senseInfo.findElements('definition').firstOrNull?.innerText;
                debugPrint('- 의미: $definition');
              }
            } else {
              debugPrint('word_info 요소를 찾을 수 없습니다.');
            }
          } else {
            debugPrint('검색 결과가 없습니다.');
          }
        } else {
          debugPrint('API 요청 실패: ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('테스트 중 오류 발생: $e');
      }
    }

    debugPrint('\n===== 국립국어원 API 테스트 완료 =====');
  }

  // 기존 단어 검색 메서드 (하위 호환성 유지)
  DictionaryEntry? lookupWord(String word) {
    try {
      return _dictionary[word];
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
