import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../models/chinese_text.dart';
import '../authentication/user_preferences_service.dart';

// 모델 임포트

/// LLM만 사용하는 간소화된 텍스트 처리 서비스
/// OCR → LLM 처리(세그먼테이션, 번역, 병음)
class UnifiedTextProcessingService {
  // 싱글톤 패턴
  static final UnifiedTextProcessingService _instance = UnifiedTextProcessingService._internal();
  factory UnifiedTextProcessingService() => _instance;
  
  // 세그먼테이션 설정
  static bool _segmentationEnabled = true;
  static bool get isSegmentationEnabled => _segmentationEnabled;
  
  // API 키 및 엔드포인트 설정
  String? _apiKey;
  final String _defaultModel = 'gpt-3.5-turbo';
  
  // 캐시 저장소 (메모리 캐시)
  final Map<String, String> _cache = {};
  
  // 사용자 설정 서비스
  final UserPreferencesService _preferencesService = UserPreferencesService();
  
  Future<void>? _initFuture;
  
  UnifiedTextProcessingService._internal() {
    _initFuture = _initialize();
  }
  
  Future<void> ensureInitialized() async {
    if (_initFuture != null) {
      await _initFuture;
    }
  }
  
  /// 세그먼테이션 활성화 설정
  void setSegmentationEnabled(bool enabled) {
    _segmentationEnabled = enabled;
    debugPrint('UnifiedTextProcessingService: 세그먼테이션 ${enabled ? "활성화" : "비활성화"}');
  }
  
  /// 서비스 초기화
  Future<void> _initialize() async {
    try {
      // 서비스 계정 JSON 파일 로드
      final String credentialsPath = 'assets/credentials/api_keys.json';
      
      try {
        final credentialsString = await rootBundle.loadString(credentialsPath);
        final credentialsJson = jsonDecode(credentialsString);
        _apiKey = credentialsJson['openai_api_key'];
        
        if (_apiKey == null || _apiKey!.isEmpty) {
          debugPrint('API 키가 비어 있거나 null입니다.');
        } else {
          debugPrint('UnifiedTextProcessingService: API 키 로드 완료');
        }        
      } catch (e) {
        debugPrint('API 키 로드 실패: $e');
      }
    } catch (e) {
      debugPrint('UnifiedTextProcessingService 초기화 오류: $e');
    }
  }
  
  /// LLM을 통한 통합 텍스트 처리 (세그먼테이션, 번역, 병음 생성)
  Future<ChineseText> processWithLLM(String text, {String sourceLanguage = 'zh'}) async {
    debugPrint('🔍 LLM 처리 시작: 텍스트 길이=${text.length}, 언어=$sourceLanguage');
    if (text.isEmpty) {
      debugPrint('⚠️ [LLM] 입력 텍스트가 비어있음');
      return ChineseText.empty();
    }
    await ensureInitialized();
    
    // 번역 모드는 항상 세그먼트 모드 사용 (true로 강제 설정)
    bool useSegmentMode = true;
    
    // 세그먼테이션 설정 적용
    if (!_segmentationEnabled) {
      useSegmentMode = false;
    }
    
    String translationMode = useSegmentMode ? 'segment' : 'full';
    debugPrint('🔄 LLM 처리: 번역 모드 = $translationMode (세그먼트 모드: $useSegmentMode)');
    
    // 캐시 확인 (간단한 메모리 캐싱) - 번역 모드를 캐시 키에 추가
    final cacheKey = 'v3-$translationMode-$sourceLanguage:$text';
    if (_cache.containsKey(cacheKey)) {
      try {
        final cachedData = _cache[cacheKey]!;
        debugPrint('💾 캐시에서 LLM 처리 결과 로드 시도: $cacheKey');
        final List<dynamic> parsedData = jsonDecode(cachedData);
        final List<ChineseSentence> sentences = parsedData.map<ChineseSentence>((data) =>
          ChineseSentence(
            original: data['chinese'] ?? '',
            translation: data['korean'] ?? '',
            pinyin: data['pinyin'] ?? '',
          )
        ).toList();
        if (kDebugMode) {
          debugPrint('✅ 캐시에서 LLM 처리 결과 로드 성공: ${sentences.length}개 문장');
        }
        return ChineseText(
          originalText: text,
          sentences: sentences,
        );
      } catch (e) {
        debugPrint('❌ 캐시된 데이터 파싱 중 오류: $e');
      }
    }
    
    // API 키 확인
    if (_apiKey == null || _apiKey!.isEmpty) {
      debugPrint('❌ API 키가 설정되지 않았습니다.');
      throw Exception('API 키가 설정되지 않았습니다.');
    }
    
    try {
      final Stopwatch stopwatch = Stopwatch()..start();
      
      if (useSegmentMode) {
        // 세그먼트 모드 (기존 처리 방식) - 문장별 분리 및 번역, 병음 생성
        debugPrint('🔄 세그먼트 모드 처리 시작');
        return await _processSegmentMode(text, sourceLanguage, cacheKey);
      } else {
        // 전체 번역 모드 - 문단 전체 번역, 병음 생략
        debugPrint('🔄 전체 번역 모드 처리 시작');
        return await _processFullMode(text, sourceLanguage, cacheKey);
      }
    } catch (e) {
      debugPrint('❌ LLM 처리 중 오류: $e');
      throw Exception('LLM 처리 실패: $e');
    }
  }
  
  /// 세그먼트 모드 처리 - 문장별 분리 및 번역, 병음 생성
  Future<ChineseText> _processSegmentMode(String text, String sourceLanguage, String cacheKey) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    debugPrint('📝 세그먼트 모드: 입력 텍스트 = $text');
    
    // 1. GPT-4o로 원문+번역만 요청
    final prompt = '''
You are a Primary school Chinese teacher for Korean students. Split the following Chinese text. For each sentence, return a JSON object with:
- the original Chinese,
- a natural Korean translation

Respond in a valid UTF-8 encoded JSON array, with each item:
{
  "chinese": "...",
  "korean": "..."
}
DO NOT include any explanations, comments, or formatting such as code blocks.
Chinese text:
$text
Output:
''';

    debugPrint('🤖 OpenAI API 요청 시작');
    debugPrint('🤖 OpenAI API 요청 URL: https://api.openai.com/v1/chat/completions');
    debugPrint('🤖 OpenAI API 요청 헤더: ${jsonEncode({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${_apiKey?.substring(0, 10)}...',
    })}');
    debugPrint('🤖 OpenAI API 요청 본문: ${jsonEncode({
      'model': 'gpt-4o',
      'messages': [
        {
          'role': 'user',
          'content': prompt,
        }
      ],
      'temperature': 0,
      'max_tokens': 2000,
    })}');
    
    // LLM API 호출
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'model': 'gpt-4o',
        'messages': [
          {
            'role': 'user',
            'content': prompt,
          }
        ],
        'temperature': 0,
        'max_tokens': 2000,
      }),
    );

    debugPrint('📡 OpenAI API 응답 상태 코드: ${response.statusCode}');
    debugPrint('📡 OpenAI API 응답 헤더: ${response.headers}');
    debugPrint('📡 OpenAI API 응답 본문: ${response.body}');

    if (response.statusCode == 200) {
      final decodedBody = utf8.decode(response.bodyBytes);
      final responseData = jsonDecode(decodedBody);
      debugPrint('✅ OpenAI API 디코딩된 응답: $responseData');
      
      final content = responseData['choices'][0]['message']['content'] as String;
      debugPrint('✅ OpenAI API 추출된 content: $content');
      
      // robust JSON 파싱
      final jsonString = extractJsonArray(content);
      debugPrint('🔄 JSON 배열 추출: $jsonString');
      
      final List<dynamic> parsedData = jsonDecode(jsonString);
      debugPrint('✅ JSON 파싱 완료: ${parsedData.length}개 항목');
      
      // 2. chinese 문장 리스트 추출
      final List<String> chineseList = parsedData.map<String>((e) => e['chinese'] ?? '').toList();
      debugPrint('📝 중국어 문장 추출: ${chineseList.length}개');
      
      // 3. 병음 요청 (gpt-3.5-turbo)
      debugPrint('🔄 병음 처리 시작');
      final List<String> pinyinList = await processPinyinWithLLM(chineseList);
      debugPrint('✅ 병음 처리 완료: ${pinyinList.length}개');
      
      // 4. 최종 합치기
      final List<ChineseSentence> sentences = [];
      for (int i = 0; i < parsedData.length; i++) {
        sentences.add(ChineseSentence(
          original: parsedData[i]['chinese'] ?? '',
          translation: parsedData[i]['korean'] ?? '',
          pinyin: i < pinyinList.length ? pinyinList[i] : '',
        ));
      }
      
      // 결과 메모리 캐싱
      _cache[cacheKey] = jsonEncode(sentences.map((s) => {
        'chinese': s.original,
        'korean': s.translation,
        'pinyin': s.pinyin,
      }).toList());
      
      if (kDebugMode) {
        debugPrint('✅ LLM 세그먼트 모드 처리 완료 (${stopwatch.elapsedMilliseconds}ms): ${sentences.length}개 문장');
      }
      
      return ChineseText(
        originalText: text,
        sentences: sentences,
      );
    } else {
      debugPrint('❌ LLM API 오류: ${response.statusCode} - ${response.body}');
      throw Exception('LLM API 오류: ${response.statusCode} - ${response.body}');
    }
  }
  
  /// 전체 번역 모드 처리 - 문단 전체 번역, 병음 생략
  Future<ChineseText> _processFullMode(String text, String sourceLanguage, String cacheKey) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    
    // 1. GPT-4o로 전체 텍스트 번역 요청
    final prompt = '''
You are a professional translator. Translate the following Chinese text into Korean NATURALLY.
You should preserve paragraph breaks.
Respond with ONLY the Korean translation, without explanations or formatting.

Chinese text:
$text
Output:
''';

    // LLM API 호출
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'model': 'gpt-4o',
        'messages': [
          {
            'role': 'user',
            'content': prompt,
          }
        ],
        'temperature': 0,
        'max_tokens': 2000,
      }),
    );

    if (response.statusCode == 200) {
      final decodedBody = utf8.decode(response.bodyBytes);
      final responseData = jsonDecode(decodedBody);
      final fullTranslation = responseData['choices'][0]['message']['content'] as String;
      
      // 전체 텍스트를 단일 문장으로 처리 (병음 생략)
      final List<ChineseSentence> sentences = [
        ChineseSentence(
          original: text,
          translation: fullTranslation,
          pinyin: '', // 병음 생략
        )
      ];
      
      // 결과 메모리 캐싱
      _cache[cacheKey] = jsonEncode(sentences.map((s) => {
        'chinese': s.original,
        'korean': s.translation,
        'pinyin': s.pinyin,
      }).toList());
      
      if (kDebugMode) {
        debugPrint('LLM 전체 번역 모드 처리 완료 (${stopwatch.elapsedMilliseconds}ms): 원문 ${text.length}자, 번역 ${fullTranslation.length}자');
      }
      
      return ChineseText(
        originalText: text,
        sentences: sentences,
      );
    } else {
      throw Exception('LLM API 오류: ${response.statusCode} - ${response.body}');
    }
  }
  
  /// 병음만 GPT-3.5-turbo로 요청
  Future<List<String>> processPinyinWithLLM(List<String> chineseList) async {
    await ensureInitialized();
    if (chineseList.isEmpty) return [];
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API 키가 설정되지 않았습니다.');
    }
    final prompt = '''
For each of the following Chinese sentences, return the Hanyu Pinyin (with tone marks, not numbers) in a JSON array, matching the order:
[
${chineseList.map((e) => '  "$e"').join(',\n')}
]
Respond as:
[
  "pinyin1",
  "pinyin2",
  ...
]
DO NOT include any explanations, comments, or formatting such as code blocks.
''';
    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'model': 'gpt-3.5-turbo',
        'messages': [
          {
            'role': 'user',
            'content': prompt,
          }
        ],
        'temperature': 0,
        'max_tokens': 1000,
      }),
    );
    if (response.statusCode == 200) {
      final decodedBody = utf8.decode(response.bodyBytes);
      final responseData = jsonDecode(decodedBody);
      final content = responseData['choices'][0]['message']['content'] as String;
      debugPrint('Pinyin LLM content: $content');
      final jsonString = extractJsonArray(content);
      final List<dynamic> parsedData = jsonDecode(jsonString);
      return parsedData.map<String>((e) => e.toString()).toList();
    } else {
      throw Exception('Pinyin LLM API 오류: ${response.statusCode} - ${response.body}');
    }
  }
  
  /// 캐시 관련 메서드
  void clearCache() {
    _cache.clear();
    debugPrint('모든 캐시가 삭제되었습니다.');
  }

  /// 특정 단어에 대한 캐시 데이터 확인
  Map<String, dynamic>? getWordCacheData(String word) {
    try {
      final cacheKey = 'v3-segment-zh:$word';
      if (_cache.containsKey(cacheKey)) {
        final cachedData = _cache[cacheKey]!;
        final List<dynamic> parsedData = jsonDecode(cachedData);
        if (parsedData.isNotEmpty) {
          return {
            'chinese': parsedData[0]['chinese'] ?? word,
            'korean': parsedData[0]['korean'] ?? '',
            'pinyin': parsedData[0]['pinyin'] ?? '',
          };
        }
      }
      return null;
    } catch (e) {
      debugPrint('캐시 데이터 확인 중 오류: $e');
      return null;
    }
  }

  /// 캐시에 해당 단어 존재 여부 확인
  bool hasWordInCache(String word) {
    final cacheKey = 'v3-segment-zh:$word';
    return _cache.containsKey(cacheKey);
  }

  String extractJsonArray(String raw) {
    // 1. 코드블록 제거
    raw = raw.replaceAll(RegExp(r'```(json)?', caseSensitive: false), '');

    // 2. JSON array만 추출 (가장 바깥의 [ ... ] )
    final jsonArrayMatch = RegExp(r'\[[\s\S]*\]').firstMatch(raw);
    if (jsonArrayMatch != null) {
      return jsonArrayMatch.group(0)!;
    }

    // fallback: raw 자체를 반환 (실패 시 디버깅용)
    return raw;
  }
}
