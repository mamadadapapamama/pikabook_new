import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../models/text_segment.dart';
import '../../models/text_full.dart';
import '../../models/processed_text.dart';
import '../authentication/user_preferences_service.dart';

/// LLM 서비스: OCR에서 정제된 중국어를 받아 번역과 병음 제공
class UnifiedTextProcessingService {
  // 싱글톤 패턴
  static final UnifiedTextProcessingService _instance = UnifiedTextProcessingService._internal();
  factory UnifiedTextProcessingService() => _instance;
  
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
  
  /// LLM을 통한 번역 및 병음 생성
  Future<ProcessedText?> processWithLLM(
    ProcessedText ocrResult,
    {required String sourceLanguage, required String targetLanguage}
  ) async {
    debugPrint('🔍 LLM 처리 시작: 텍스트 길이=${ocrResult.fullOriginalText.length}');
    
    if (ocrResult.fullOriginalText.isEmpty) {
      debugPrint('⚠️ [LLM] 입력 텍스트가 비어있음');
      return null;
    }
    
    await ensureInitialized();
    
    // API 키 확인
    if (_apiKey == null || _apiKey!.isEmpty) {
      debugPrint('❌ API 키가 설정되지 않았습니다.');
      throw Exception('API 키가 설정되지 않았습니다.');
    }
    
    try {
      final Stopwatch stopwatch = Stopwatch()..start();
      
      if (ocrResult.mode == TextProcessingMode.segment) {
        // 세그먼트 모드: 각 문장별로 번역과 병음 생성
        return await _processSegmentMode(ocrResult, sourceLanguage, targetLanguage);
      } else {
        // 전체 번역 모드: 문단별로 번역
        return await _processFullMode(ocrResult, sourceLanguage, targetLanguage);
      }
    } catch (e) {
      debugPrint('❌ LLM 처리 중 오류: $e');
      throw Exception('LLM 처리 실패: $e');
    }
  }
  
  /// 세그먼트 모드 처리 - 문장별 번역과 병음 생성
  Future<ProcessedText> _processSegmentMode(
    ProcessedText ocrResult,
    String sourceLanguage,
    String targetLanguage
  ) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    debugPrint('📝 세그먼트 모드: ${ocrResult.segments?.length ?? 0}개 문장');
    
    // 1. GPT-4로 원문+번역+병음 요청
    final prompt = '''
You are a Primary school Chinese teacher for Korean students. For each Chinese sentence, return a JSON object with:
- the original Chinese,
- a natural Korean translation,
- Hanyu Pinyin (with tone marks)

Respond in a valid UTF-8 encoded JSON array, with each item:
{
  "chinese": "...",
  "korean": "...",
  "pinyin": "..."
}

Chinese sentences:
${ocrResult.segments?.map((s) => s.originalText).join('\n')}

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
        'model': 'gpt-4',
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
      
      // JSON 파싱
      final jsonString = extractJsonArray(content);
      final List<dynamic> parsedData = jsonDecode(jsonString);
      
      // 세그먼트 업데이트
      final updatedSegments = parsedData.map<TextSegment>((data) => TextSegment(
        originalText: data['chinese'] ?? '',
        translatedText: data['korean'] ?? '',
        pinyin: data['pinyin'] ?? '',
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      )).toList();
      
      // ProcessedText 업데이트
      return ocrResult.copyWith(
        segments: updatedSegments,
        fullTranslatedText: updatedSegments.map((s) => s.translatedText).join('\n'),
      );
    } else {
      throw Exception('LLM API 오류: ${response.statusCode} - ${response.body}');
    }
  }
  
  /// 전체 번역 모드 처리 - 문단별 번역
  Future<ProcessedText> _processFullMode(
    ProcessedText ocrResult,
    String sourceLanguage,
    String targetLanguage
  ) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    
    // 1. GPT-4로 문단별 번역 요청
    final prompt = '''
You are a professional translator. Translate the following Chinese paragraphs into Korean NATURALLY.
Each paragraph should be translated separately, preserving the original paragraph structure.
Respond with a JSON array where each item contains the original and translated text:
[
  {
    "original": "첫 번째 문단 원문",
    "translated": "첫 번째 문단 번역"
  }
]

Chinese paragraphs:
${ocrResult.segments?.map((s) => s.originalText).join('\n\n')}

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
        'model': 'gpt-4',
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
      
      // JSON 파싱
      final jsonString = extractJsonArray(content);
      final List<dynamic> parsedData = jsonDecode(jsonString);
      
      // 세그먼트 업데이트
      final updatedSegments = parsedData.map<TextSegment>((data) => TextSegment(
        originalText: data['original'] ?? '',
        translatedText: data['translated'] ?? '',
        pinyin: '', // 전체 번역 모드에서는 병음 생성하지 않음
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      )).toList();
      
      // ProcessedText 업데이트
      return ocrResult.copyWith(
        segments: updatedSegments,
        fullTranslatedText: updatedSegments.map((s) => s.translatedText).join('\n\n'),
      );
    } else {
      throw Exception('LLM API 오류: ${response.statusCode} - ${response.body}');
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
