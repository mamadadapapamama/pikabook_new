import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../../core/models/text_unit.dart';
import '../../../core/models/processed_text.dart';

/// LLM 서비스: 분리된 텍스트 조각들을 받아 번역과 필요한경우 병음 제공
/// (모드별 분리는 TextModeSeparationService에서 이미 처리됨)

class LLMTextProcessing {
  // 싱글톤 패턴
  static final LLMTextProcessing _instance = LLMTextProcessing._internal();
  factory LLMTextProcessing() => _instance;
  
  // API 키 및 엔드포인트 설정
  String? _apiKey;
  final String _defaultModel = 'gpt-3.5-turbo';
  
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
      
      if (kDebugMode) {
        debugPrint('🤖 LLM 서비스 초기화 완료');
      }
    } catch (e) {
      debugPrint('❌ LLM 서비스 초기화 중 오류 발생: $e');
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

  /// 텍스트 조각들을 번역+병음 처리
  /// 단일 텍스트인 경우에도 리스트로 전달하여 사용
  Future<ProcessedText> processTextSegments(
    List<String> textSegments, {
    required String sourceLanguage, 
    required String targetLanguage,
    required TextProcessingMode mode,
    bool needPinyin = false,
  }) async {
    await ensureInitialized();

    if (kDebugMode) {
      debugPrint('🔄 LLM 텍스트 처리: ${textSegments.length}개 조각');
    }

    if (textSegments.isEmpty) {
      return ProcessedText(
        mode: mode,
        displayMode: TextDisplayMode.full,
        fullOriginalText: '',
        fullTranslatedText: '',
        units: [],
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
      );
    }

    // API 키 확인 (한 번만)
    await _ensureApiKeyAvailable();

    List<TextUnit> units = [];
    String fullOriginalText = '';
    String fullTranslatedText = '';

    // 각 텍스트 조각 처리
    for (int i = 0; i < textSegments.length; i++) {
      final segment = textSegments[i];
      if (segment.trim().isEmpty) continue;

      if (kDebugMode) {
        debugPrint('📝 조각 ${i+1}/${textSegments.length} 처리 중: "${segment.substring(0, segment.length > 20 ? 20 : segment.length)}..."');
      }

      try {
        final result = await _translateText(segment, sourceLanguage, targetLanguage, needPinyin);
        
        units.add(TextUnit(
          originalText: result['original'] ?? segment,
          translatedText: result['translation'] ?? '',
          pinyin: result['pinyin'] ?? '',
          sourceLanguage: sourceLanguage,
          targetLanguage: targetLanguage,
        ));

        fullOriginalText += result['original'] ?? segment;
        fullTranslatedText += result['translation'] ?? '';

        if (kDebugMode) {
          debugPrint('✅ 조각 ${i+1} 완료:');
          debugPrint('   원문: "${result['original']?.substring(0, 20) ?? ''}..."');
          debugPrint('   번역: "${result['translation']?.substring(0, 20) ?? ''}..."');
          if (needPinyin && result['pinyin']?.isNotEmpty == true) {
            debugPrint('   병음: "${result['pinyin']?.substring(0, 20) ?? ''}..."');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ 조각 ${i+1} 처리 실패: $e');
        }
        // 실패한 조각은 원본만 유지
        units.add(TextUnit(
          originalText: segment,
          translatedText: '',
          pinyin: '',
          sourceLanguage: sourceLanguage,
          targetLanguage: targetLanguage,
        ));
        fullOriginalText += segment;
      }
    }

    final result = ProcessedText(
      mode: mode,
      displayMode: TextDisplayMode.full,
      fullOriginalText: fullOriginalText,
      fullTranslatedText: fullTranslatedText,
      units: units,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );

    if (kDebugMode) {
      debugPrint('🎉 일괄 처리 완료: ${units.length}개 단위, 원문=${fullOriginalText.length}자, 번역=${fullTranslatedText.length}자');
    }

    return result;
  }

  /// API 키 사용 가능 여부 확인 (중복 제거)
  Future<void> _ensureApiKeyAvailable() async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      throw Exception('API 키가 설정되지 않았습니다.');
    }
  }

  /// 프롬프트 생성 (원문+번역+병음 모두 요청)
  Map<String, String> _generatePrompts(String text, bool needPinyin) {
    if (needPinyin) {
      return {
        'userPrompt': '''다음 텍스트를 분석하여 중국어 부분만 추출하고, 한국어로 번역하며, 병음을 제공해주세요. 
JSON 배열 형식으로 [정리된_중국어_원문, 병음, 한국어_번역] 순서로 반환해주세요:

"$text"

예시: ["你好世界", "Nǐ hǎo shìjiè", "안녕하세요 세계"]''',
        'systemPrompt': '''당신은 중국어를 가르치는 선생님입니다. 
주어진 텍스트에서 중국어 부분만 정리하여 추출하고, 한국어로 자연스럽게 번역하며, 정확한 병음을 제공합니다.
응답은 반드시 JSON 배열 형식으로 [정리된_중국어_원문, 병음, 한국어_번역] 순서로 반환하세요.
중국어가 아닌 부분(숫자, 영어, 기호 등)은 제거하고 순수한 중국어만 추출하세요.''',
      };
    } else {
      return {
        'userPrompt': '''다음 텍스트를 분석하여 중국어 부분만 추출하고, 한국어로 번역해주세요.
JSON 배열 형식으로 [정리된_중국어_원문, 한국어_번역] 순서로 반환해주세요:

"$text"

예시: ["你好世界", "안녕하세요 세계"]''',
        'systemPrompt': '''당신은 중국어를 가르치는 선생님입니다.
주어진 텍스트에서 중국어 부분만 정리하여 추출하고, 한국어로 자연스럽게 번역합니다.
응답은 반드시 JSON 배열 형식으로 [정리된_중국어_원문, 한국어_번역] 순서로 반환하세요.
중국어가 아닌 부분(숫자, 영어, 기호 등)은 제거하고 순수한 중국어만 추출하세요.''',
      };
    }
  }

  /// 단일 텍스트 조각을 번역+병음 처리
  Future<Map<String, String>> _translateText(
    String text,
    String sourceLanguage,
    String targetLanguage,
    bool needPinyin,
  ) async {
    try {
      if (kDebugMode) {
        debugPrint('🚀 LLM API 호출 시작: "${text.substring(0, text.length > 30 ? 30 : text.length)}..."');
      }

      final prompts = _generatePrompts(text, needPinyin);

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
              'content': prompts['systemPrompt'],
            },
            {
              'role': 'user',
              'content': prompts['userPrompt'],
            },
          ],
          'temperature': 0.3,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        final content = data['choices'][0]['message']['content'] as String;

        if (kDebugMode) {
          debugPrint('✅ LLM API 응답 성공: ${content.length}자');
        }

        // 응답 파싱
        final result = _parseResponse(content, needPinyin);

        if (kDebugMode) {
          debugPrint('📝 번역: "${result['translation']}"');
          if (needPinyin && result['pinyin']?.isNotEmpty == true) {
            debugPrint('📝 병음: "${result['pinyin']}"');
          }
        }

        return result;
      } else {
        if (kDebugMode) {
          debugPrint('❌ API 호출 실패: ${response.statusCode}');
          debugPrint('응답: ${response.body}');
        }
        throw Exception('API 호출 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ 번역 처리 중 오류: $e');
      rethrow;
    }
  }

  /// LLM 응답 파싱 (원문+번역+병음)
  Map<String, String> _parseResponse(String content, bool needPinyin) {
    String original = '';
    String translation = '';
    String pinyin = '';

    try {
      // JSON 배열 형태인지 확인
      if (content.trim().startsWith('[') && content.trim().endsWith(']')) {
        final List<dynamic> jsonArray = jsonDecode(content.trim());
        
        if (jsonArray.isNotEmpty) {
          if (needPinyin && jsonArray.length >= 3) {
            // [정리된_중국어_원문, 병음, 한국어_번역] 형식
            original = jsonArray[0].toString().trim();
            pinyin = jsonArray[1].toString().trim();
            translation = jsonArray[2].toString().trim();
          } else if (!needPinyin && jsonArray.length >= 2) {
            // [정리된_중국어_원문, 한국어_번역] 형식
            original = jsonArray[0].toString().trim();
            translation = jsonArray[1].toString().trim();
          } else if (jsonArray.length >= 1) {
            // 요소가 하나인 경우 번역으로 처리
            translation = jsonArray[0].toString().trim();
          }
        }
      } else {
        // 일반 텍스트 형태 파싱
        final lines = content.split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();

        if (lines.isEmpty) {
          translation = content.trim();
        } else if (needPinyin && lines.length >= 3) {
          // 3줄 형식: 원문, 병음, 번역
          original = lines[0];
          pinyin = lines[1];
          translation = lines[2];
        } else if (!needPinyin && lines.length >= 2) {
          // 2줄 형식: 원문, 번역
          original = lines[0];
          translation = lines[1];
        } else {
          // 1줄인 경우 번역으로 처리
          translation = lines.join(' ');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ JSON 파싱 실패, 일반 텍스트로 처리: $e');
      }
      
      // JSON 파싱 실패 시 일반 텍스트로 처리
      final lines = content.split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      if (lines.isEmpty) {
        translation = content.trim();
      } else if (needPinyin && lines.length >= 3) {
        original = lines[0];
        pinyin = lines[1];
        translation = lines[2];
      } else if (!needPinyin && lines.length >= 2) {
        original = lines[0];
        translation = lines[1];
      } else {
        translation = lines.join(' ');
      }
    }

    // 기본값 처리
    if (translation.isEmpty) {
      translation = '[번역 결과가 비어있습니다]';
    }
    if (original.isEmpty && translation.isNotEmpty) {
      original = '[원문을 추출할 수 없습니다]';
    }

    // 따옴표 제거
    original = _removeQuotes(original);
    translation = _removeQuotes(translation);
    pinyin = _removeQuotes(pinyin);

    return {
      'original': original,
      'translation': translation,
      'pinyin': pinyin,
    };
  }

  /// 따옴표 제거 헬퍼 메서드
  String _removeQuotes(String text) {
    if (text.startsWith('"') && text.endsWith('"')) {
      text = text.substring(1, text.length - 1);
    }
    if (text.startsWith("'") && text.endsWith("'")) {
      text = text.substring(1, text.length - 1);
    }
    return text;
  }
}
