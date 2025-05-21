import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../models/text_segment.dart';
import '../../models/text_full.dart';
import '../../models/processed_text.dart';
import '../cache/unified_cache_service.dart';
import '../authentication/user_preferences_service.dart';

/// LLM 처리 모드
enum ProcessingMode {
  /// 원본 텍스트
  original,
  
  /// 번역된 텍스트
  translated,
  
  /// 핀인
  pinyin
}

/// LLM 서비스: OCR에서 정제된 중국어를 받아 번역과 병음 제공
class LLMTextProcessing {
  // 싱글톤 패턴
  static final LLMTextProcessing _instance = LLMTextProcessing._internal();
  factory LLMTextProcessing() => _instance;
  
  // API 키 및 엔드포인트 설정
  String? _apiKey;
  final String _defaultModel = 'gpt-3.5-turbo';
  
  // 캐시 서비스
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  
  // 사용자 설정 서비스
  final UserPreferencesService _preferencesService = UserPreferencesService();
  
  Future<void>? _initFuture;
  
  LLMTextProcessing._internal() {
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
      // API 키 로드
      _apiKey = await _loadApiKey();
      debugPrint('LLM 서비스 초기화 완료');
    } catch (e) {
      debugPrint('LLM 서비스 초기화 중 오류 발생: $e');
    }
  }
  
  /// API 키 로드
  Future<String> _loadApiKey() async {
    try {
      return await rootBundle.loadString('assets/api_keys.json')
          .then((json) => jsonDecode(json)['openai_api_key']);
    } catch (e) {
      debugPrint('API 키 로드 중 오류 발생: $e');
      rethrow;
    }
  }
  
  /// 텍스트 처리 (번역 + 병음)
  Future<ProcessedText> processText(String text, {
    required String sourceLanguage,
    required String targetLanguage,
    bool needPinyin = false,
  }) async {
    await ensureInitialized();
    
    // 캐시 확인
    final cached = await _cacheService.getPageContent(text, ProcessingMode.translated);
    if (cached != null) {
      return ProcessedText.fromJson(cached);
    }
    
    // LLM 처리
    final result = await _processWithLLM(text, {
      'sourceLanguage': sourceLanguage,
      'targetLanguage': targetLanguage,
      'needPinyin': needPinyin,
    });
    
    // 캐시 저장
    await _cacheService.cachePageContent(
      text,
          originalText: text,
      translatedText: result.translated,
      pinyin: result.pinyin,
        );
    
    return result;
    }
    
  /// LLM API 호출
  Future<ProcessedText> _processWithLLM(String text, Map<String, dynamic> options) async {
    if (_apiKey == null) {
      throw Exception('API 키가 설정되지 않았습니다.');
    }
    
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
            'role': 'system',
            'content': 'You are a Chinese language expert. Translate the given text and provide pinyin if requested.',
      },
          {
            'role': 'user',
            'content': jsonEncode({
              'text': text,
              'sourceLanguage': options['sourceLanguage'],
              'targetLanguage': options['targetLanguage'],
              'needPinyin': options['needPinyin'],
            }),
          },
        ],
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('LLM API 호출 실패: ${response.body}');
    }
    
    final result = jsonDecode(response.body);
    final content = result['choices'][0]['message']['content'];
    
    return ProcessedText.fromJson(jsonDecode(content));
  }
  
  /// TTS 생성
  Future<String> generateTTS(String text, String language) async {
    await ensureInitialized();
    
    // 캐시 확인
    final cached = await _cacheService.getPageContent(text, ProcessingMode.original);
    if (cached != null && cached['ttsPath'] != null) {
      return cached['ttsPath'];
    }
    
    // TTS API 호출
    final ttsPath = await _generateTTSWithAPI(text, language);
    
    // 캐시 저장
    await _cacheService.cachePageContent(
      text,
      originalText: text,
      translatedText: '',
      ttsPath: ttsPath,
    );
    
    return ttsPath;
  }
  
  /// TTS API 호출
  Future<String> _generateTTSWithAPI(String text, String language) async {
    // TTS API 호출 로직 구현
    // 임시로 더미 파일 경로 반환
    return '/tmp/tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
  }

  /// 단어의 캐시 데이터를 가져옵니다.
  Map<String, String>? getWordCacheData(String word) {
    try {
      final cacheKey = 'word_$word';
      final cachedData = _cacheService.get(cacheKey);
      if (cachedData != null) {
        return Map<String, String>.from(cachedData);
      }
      return null;
    } catch (e) {
      debugPrint('단어 캐시 데이터 조회 중 오류 발생: $e');
      return null;
    }
  }
}
