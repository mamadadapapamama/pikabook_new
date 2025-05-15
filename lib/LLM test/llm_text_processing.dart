import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../core/models/chinese_text.dart';

// 모델 임포트

/// LLM만 사용하는 간소화된 텍스트 처리 서비스
/// OCR → LLM 처리(세그먼테이션, 번역, 병음)
class UnifiedTextProcessingService {
  // 싱글톤 패턴
  static final UnifiedTextProcessingService _instance = UnifiedTextProcessingService._internal();
  factory UnifiedTextProcessingService() => _instance;
  
  // API 키 및 엔드포인트 설정
  String? _apiKey;
  final String _defaultModel = 'gpt-3.5-turbo';
  
  // 캐시 저장소 (메모리 캐시)
  final Map<String, String> _cache = {};
  
  UnifiedTextProcessingService._internal() {
    _initialize();
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
    if (text.isEmpty) {
      return ChineseText.empty();
    }
    
    // 캐시 확인 (간단한 메모리 캐싱)
    final cacheKey = 'v2-$sourceLanguage:$text';
    if (_cache.containsKey(cacheKey)) {
      try {
        final cachedData = _cache[cacheKey]!;
        final List<dynamic> parsedData = jsonDecode(cachedData);
        final List<ChineseSentence> sentences = parsedData.map<ChineseSentence>((data) =>
          ChineseSentence(
            original: data['chinese'] ?? '',
            translation: data['korean'] ?? '',
            pinyin: data['pinyin'] ?? '',
          )
        ).toList();
        if (kDebugMode) {
          debugPrint('캐시에서 LLM 처리 결과 로드: ${sentences.length}개 문장');
        }
        return ChineseText(
          originalText: text,
          sentences: sentences,
        );
      } catch (e) {
        debugPrint('캐시된 데이터 파싱 중 오류: $e');
      }
    }
    
    // API 키 확인
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API 키가 설정되지 않았습니다. assets/credentials/openai.json 파일을 확인하세요.');
    }
    
    try {
      final Stopwatch stopwatch = Stopwatch()..start();
      
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
        final content = responseData['choices'][0]['message']['content'] as String;
        
        debugPrint('LLM content: $content');
        
        // robust JSON 파싱
        final jsonString = extractJsonArray(content);
        final List<dynamic> parsedData = jsonDecode(jsonString);
        // 2. chinese 문장 리스트 추출
        final List<String> chineseList = parsedData.map<String>((e) => e['chinese'] ?? '').toList();
        // 3. 병음 요청 (gpt-3.5-turbo)
        final List<String> pinyinList = await processPinyinWithLLM(chineseList);
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
          debugPrint('LLM 처리 완료 (${stopwatch.elapsedMilliseconds}ms): ${sentences.length}개 문장');
        }
        
        return ChineseText(
          originalText: text,
          sentences: sentences,
        );
      } else {
        throw Exception('LLM API 오류: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('LLM 처리 중 오류: $e');
      throw Exception('LLM 처리 실패: $e');
    }
  }
  
  /// 병음만 GPT-3.5-turbo로 요청
  Future<List<String>> processPinyinWithLLM(List<String> chineseList) async {
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
