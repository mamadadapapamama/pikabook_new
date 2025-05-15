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
    final cacheKey = '$sourceLanguage:$text';
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
        // 캐시 오류 시 API 호출로 진행
      }
    }
    
    // API 키 확인
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API 키가 설정되지 않았습니다. assets/credentials/openai.json 파일을 확인하세요.');
    }
    
    try {
      final Stopwatch stopwatch = Stopwatch()..start();
      
      // LLM 프롬프트 구성 (GPT-4o용)
      final prompt = '''
Split the following Chinese text into natural sentences and provide Korean translation and Pinyin for each. 
Return all non-ASCII characters (Chinese, Korean, Pinyin) as real text, and ensure the response is valid UTF-8 JSON.

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
          'model': _defaultModel,
          'messages': [
            {
              'role': 'user',
              'content': prompt,
            }
          ],
          'temperature': 0.1,
          'max_tokens': 2000,
        }),
      );
      
      if (response.statusCode == 200) {
        final decodedBody = utf8.decode(response.bodyBytes);
        final responseData = jsonDecode(decodedBody);
        final content = responseData['choices'][0]['message']['content'] as String;
        
        debugPrint('LLM content: $content');
        
        // JSON 파싱
        final jsonStart = content.indexOf('[');
        final jsonEnd = content.lastIndexOf(']');
        
        if (jsonStart != -1 && jsonEnd != -1) {
          final jsonString = content.substring(jsonStart, jsonEnd + 1);
          var parsedData = jsonDecode(jsonString);
          // 이중 인코딩된 경우 한 번 더 파싱
          if (parsedData.isNotEmpty && parsedData[0] is String) {
            parsedData = parsedData.map((e) => jsonDecode(e)).toList();
          }
          // ChineseSentence 리스트 생성
          final List<ChineseSentence> sentences = parsedData.map<ChineseSentence>((data) =>
            ChineseSentence(
              original: data['chinese'] ?? '',
              translation: data['korean'] ?? '',
              pinyin: data['pinyin'] ?? '',
            )
          ).toList();
          
          // 결과 메모리 캐싱
          _cache[cacheKey] = jsonString;
          
          if (kDebugMode) {
            debugPrint('LLM 처리 완료 (${stopwatch.elapsedMilliseconds}ms): ${sentences.length}개 문장');
          }
          
          return ChineseText(
            originalText: text,
            sentences: sentences,
          );
        } else {
          throw Exception('LLM 응답에서 JSON 형식을 찾을 수 없습니다: $content');
        }
      } else {
        throw Exception('LLM API 오류: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('LLM 처리 중 오류: $e');
      throw Exception('LLM 처리 실패: $e');
    }
  }
  
  /// 캐시 관련 메서드
  void clearCache() {
    _cache.clear();
    debugPrint('모든 캐시가 삭제되었습니다.');
  }
}
