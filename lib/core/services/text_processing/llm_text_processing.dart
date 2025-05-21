import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../models/text_unit.dart';
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
    
    // LLM 처리
    final result = await _processWithLLM(text, {
      'sourceLanguage': sourceLanguage,
      'targetLanguage': targetLanguage,
      'needPinyin': needPinyin,
    });
    
    return result;
  }
    
  /// LLM API 호출
  Future<ProcessedText> _processWithLLM(String text, Map<String, dynamic> options) async {
    if (_apiKey == null) {
      throw Exception('API 키가 설정되지 않았습니다.');
    }
    
    try {
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
              'content': 'You are a helpful assistant that translates Chinese text to Korean and provides pinyin when requested.',
            },
            {
              'role': 'user',
              'content': 'Translate the following Chinese text to Korean${options['needPinyin'] ? ' and provide pinyin' : ''}: $text',
            },
          ],
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['choices'][0]['message']['content'];
        
        // 응답 파싱
        final translatedText = content.split('\n')[0]; // 첫 번째 줄은 번역
        final pinyin = options['needPinyin'] ? content.split('\n')[1] : ''; // 두 번째 줄은 병음
        
        return ProcessedText(
          mode: TextProcessingMode.segment,
          displayMode: TextDisplayMode.full,
          fullOriginalText: text,
          fullTranslatedText: translatedText,
          units: [
            TextUnit(
              originalText: text,
              pinyin: pinyin,
              translatedText: translatedText,
              sourceLanguage: options['sourceLanguage'],
              targetLanguage: options['targetLanguage'],
            ),
          ],
          sourceLanguage: options['sourceLanguage'],
          targetLanguage: options['targetLanguage'],
        );
      } else {
        throw Exception('API 호출 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('LLM API 호출 중 오류 발생: $e');
      rethrow;
    }
  }
  
  /// TTS 생성
  Future<String> generateTTS(String text, String language) async {
    await ensureInitialized();
    
    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/audio/speech'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'tts-1',
          'input': text,
          'voice': 'alloy',
          'language': language,
        }),
      );
      
      if (response.statusCode == 200) {
        // 임시 파일로 저장
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        return filePath;
      } else {
        throw Exception('TTS API 호출 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('TTS 생성 중 오류 발생: $e');
      rethrow;
    }
  }
  
  /// 단어 캐시 데이터 가져오기
  Map<String, String>? getWordCacheData(String word) {
    // 단어 캐시 구현
    return null;
  }
}
