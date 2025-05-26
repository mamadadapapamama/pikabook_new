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
          originalText: segment,
          translatedText: result['translation'] ?? '',
          pinyin: result['pinyin'] ?? '',
          sourceLanguage: sourceLanguage,
          targetLanguage: targetLanguage,
        ));

        fullOriginalText += segment;
        fullTranslatedText += result['translation'] ?? '';

        if (kDebugMode) {
          debugPrint('✅ 조각 ${i+1} 완료: "${result['translation']?.substring(0, 20) ?? ''}..."');
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

  /// 프롬프트 생성 (중복 제거)
  Map<String, String> _generatePrompts(String text, bool needPinyin) {
    if (needPinyin) {
      return {
        'userPrompt': '다음 중국어 텍스트를 한국어로 번역하고 병음도 제공해주세요. JSON 배열 형식으로 [병음, 번역] 순서로 반환해주세요:\n\n"$text"',
        'systemPrompt': '당신은 중국어를 가르치는 선생님입니다. 중국어 텍스트를 한국어로 번역하고 병음을 제공합니다. 응답은 반드시 JSON 배열 형식으로 [병음, 번역] 순서로 반환하세요. 예: ["Hémǎ yéyé", "하마 할아버지"]',
      };
    } else {
      return {
        'userPrompt': '다음 중국어 텍스트를 한국어로 번역해주세요. 번역 결과만 반환하고 다른 설명은 하지 마세요:\n\n"$text"',
        'systemPrompt': '당신은 중국어를 가르치는 선생님입니다. 중국어 텍스트를 한국어로 정확하게 번역합니다.',
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

  /// LLM 응답 파싱
  Map<String, String> _parseResponse(String content, bool needPinyin) {
    String translation = '';
    String pinyin = '';

    try {
      // JSON 배열 형태인지 확인
      if (content.trim().startsWith('[') && content.trim().endsWith(']')) {
        final List<dynamic> jsonArray = jsonDecode(content.trim());
        
        if (jsonArray.isNotEmpty) {
          if (needPinyin && jsonArray.length >= 2) {
            // 첫 번째 요소: 병음, 두 번째 요소: 번역
            pinyin = jsonArray[0].toString().trim();
            translation = jsonArray[1].toString().trim();
          } else {
            // 병음이 필요하지 않거나 요소가 하나인 경우
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
        } else if (needPinyin && lines.length >= 2) {
          // 병음이 필요한 경우: 번역과 병음을 분리
          final int separatorIndex = _findTranslationPinyinSeparator(lines);
          
          if (separatorIndex > 0) {
            translation = lines.sublist(0, separatorIndex).join(' ');
            pinyin = lines.sublist(separatorIndex).join(' ');
          } else {
            // 분리점을 찾지 못한 경우 첫 번째 줄은 병음, 두 번째 줄은 번역
            pinyin = lines[0];
            translation = lines[1];
          }
        } else {
          // 병음이 필요하지 않거나 줄이 하나인 경우
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
      } else if (needPinyin && lines.length >= 2) {
        pinyin = lines[0];
        translation = lines[1];
      } else {
        translation = lines.join(' ');
      }
    }

    // 번역이 원문과 동일한 경우 오류 처리
    if (translation.isEmpty) {
      translation = '[번역 결과가 비어있습니다]';
    }

    // 따옴표 제거
    if (translation.startsWith('"') && translation.endsWith('"')) {
      translation = translation.substring(1, translation.length - 1);
    }
    if (translation.startsWith("'") && translation.endsWith("'")) {
      translation = translation.substring(1, translation.length - 1);
    }
    
    if (pinyin.startsWith('"') && pinyin.endsWith('"')) {
      pinyin = pinyin.substring(1, pinyin.length - 1);
    }
    if (pinyin.startsWith("'") && pinyin.endsWith("'")) {
      pinyin = pinyin.substring(1, pinyin.length - 1);
    }

    return {
      'translation': translation,
      'pinyin': pinyin,
    };
  }

  /// 번역과 병음의 분리점 찾기
  int _findTranslationPinyinSeparator(List<String> lines) {
    for (int i = 1; i < lines.length; i++) {
      // 병음은 주로 로마자와 숫자로 구성됨
      if (_isPinyinLine(lines[i]) && !_isPinyinLine(lines[i-1])) {
        return i;
      }
    }
    return -1; // 분리점을 찾지 못함
  }

  /// 텍스트가 병음인지 판단
  bool _isPinyinLine(String line) {
    if (line.trim().isEmpty) return false;

    // 로마자와 숫자 비율 계산
    final romanChars = RegExp(r'[a-zA-Z0-9\s]');
    final romanMatches = romanChars.allMatches(line).length;
    
    // 한글/한자 비율 계산
    final koreanOrChineseChars = RegExp(r'[\p{Script=Hangul}\p{Script=Han}]', unicode: true);
    final koreanOrChineseMatches = koreanOrChineseChars.allMatches(line).length;
    
    final totalLength = line.length;
    final romanRatio = romanMatches / totalLength;
    final koreanOrChineseRatio = koreanOrChineseMatches / totalLength;
    
    // 로마자 비율이 높고 한글/한자 비율이 낮으면 병음으로 판단
    return romanRatio > 0.6 && koreanOrChineseRatio < 0.3;
  }
}
