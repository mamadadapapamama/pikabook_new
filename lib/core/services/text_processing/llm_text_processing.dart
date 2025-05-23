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
      return await rootBundle.loadString('assets/credentials/api_keys.json')
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
    
    if (kDebugMode) {
      debugPrint('LLM processText 호출됨: ${text.length}자 처리 시작');
      debugPrint('소스 언어: $sourceLanguage, 대상 언어: $targetLanguage, 병음 필요: $needPinyin');
    }
    
    // 빈 텍스트 검사 추가
    if (text.isEmpty) {
      if (kDebugMode) {
        debugPrint('LLM processText: 텍스트가 비어있어 처리 불가');
      }
      // 빈 텍스트인 경우 빈 ProcessedText 반환
      return ProcessedText(
        mode: TextProcessingMode.segment,
        displayMode: TextDisplayMode.full,
        fullOriginalText: '',
        fullTranslatedText: '',
        units: [],
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      );
    }
    
    // API 키 확인
    if (_apiKey == null || _apiKey!.isEmpty) {
      if (kDebugMode) {
        debugPrint('LLM processText: API 키가 없거나 비어 있음');
      }
      throw Exception('API 키가 설정되지 않았습니다.');
    }
    
    // LLM 처리
    if (kDebugMode) {
      debugPrint('LLM API 호출 준비 완료: 텍스트 길이=${text.length}');
    }
    
    final result = await _processWithLLM(text, {
      'sourceLanguage': sourceLanguage,
      'targetLanguage': targetLanguage,
      'needPinyin': needPinyin,
    });
    
    if (kDebugMode) {
      debugPrint('LLM 처리 완료: 원문=${result.fullOriginalText.length}자, 번역=${result.fullTranslatedText.length}자');
    }
    
    return result;
  }
    
  /// LLM API 호출
  Future<ProcessedText> _processWithLLM(String text, Map<String, dynamic> options) async {
    if (_apiKey == null) {
      if (kDebugMode) {
        debugPrint('⚠️ LLM API 호출 오류: API 키가 null입니다');
      }
      throw Exception('API 키가 설정되지 않았습니다.');
    }
    
    try {
      if (kDebugMode) {
        debugPrint('🚀 LLM API 호출 시작: OpenAI API');
        debugPrint('요청 텍스트: ${text.substring(0, text.length > 30 ? 30 : text.length)}...');
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
              'content': '당신은 중국어를 한국어로 번역하는 번역기입니다. 중국어 텍스트를 한국어로 정확하게 번역하고, 요청시 병음도 제공합니다. 응답 형식은 다음과 같습니다:\n\n첫 번째 줄: 한국어 번역\n두 번째 줄(병음 요청 시): 병음',
            },
            {
              'role': 'user',
              'content': '다음 중국어 텍스트를 한국어로 번역해주세요${options['needPinyin'] ? ' 그리고 병음도 제공해주세요' : ''}. 번역 결과만 반환하고 다른 설명은 하지 마세요: "$text"',
            },
          ],
          'temperature': 0.3, // 더 결정적인 출력을 위해 낮은 온도 설정
        }),
      );
      
      if (kDebugMode) {
        debugPrint('📡 LLM API 응답 코드: ${response.statusCode}');
      }
      
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final content = data['choices'][0]['message']['content'];
        
        if (kDebugMode) {
          debugPrint('✅ LLM API 응답 성공: ${content.length}자');
          debugPrint('응답 전체 내용: $content');
        }
        
        // 응답에서 번역과 병음 추출 (간단한 줄 기반 파싱)
        final lines = content.split('\n')
            .where((String line) => line.trim().isNotEmpty)
            .toList();
        
        // 기본값 설정
        String translatedText = '';
        String pinyin = '';
        
        // 첫 번째 의미 있는 줄은 번역으로 간주
        if (lines.isNotEmpty) {
          translatedText = lines[0].trim();
          
          // 디버그 로그 추가 - 번역이 원문과 동일한지 확인
          if (kDebugMode && translatedText == text) {
            debugPrint('⚠️ 경고: 번역 결과가 원문과 동일함. API 응답 확인 필요');
          }
          
          // 병음은 두 번째 줄부터 검색 (여러 줄일 수 있음)
          if (lines.length > 1) {
            pinyin = lines[1].trim();
          }
        } else {
          // 줄이 없으면 전체 내용 사용
          translatedText = content.trim();
        }
        
        // 번역이 여전히 원문과 동일하면 번역 실패로 처리
        if (translatedText == text) {
          if (kDebugMode) {
            debugPrint('⚠️ 번역 실패: 번역 결과가 원문과 동일함');
            debugPrint('임시 오류 메시지로 대체합니다.');
          }
          translatedText = "[번역 처리 중 오류가 발생했습니다]";
        }
        
        if (kDebugMode) {
          debugPrint('📝 최종 번역 결과: $translatedText');
          if (pinyin.isNotEmpty) {
            debugPrint('📝 최종 병음 결과: $pinyin');
          }
        }
        
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
  
  /// 단어 캐시 데이터 가져오기
  Map<String, String>? getWordCacheData(String word) {
    // 단어 캐시 구현
    return null;
  }
}
