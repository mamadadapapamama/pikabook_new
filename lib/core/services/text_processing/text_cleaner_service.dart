import 'package:flutter/foundation.dart';
import 'pinyin_creation_service.dart';

/// 텍스트 정리 서비스
/// 
/// OCR 결과 및 일반 텍스트에 대한 정리, 분석 기능을 제공합니다.
/// 
/// ## 주요 기능
/// - 핀인 줄 제거 및 추출
/// - 중국어 문자 추출 및 분석
/// - 불필요한 텍스트 제거 (페이지 번호, 문장부호 등)
/// - 언어 감지 및 문자 분석
/// - 특수문자 제거 및 줄바꿈 정리
///
/// ## 사용 예시
/// ```dart
/// final textCleanerService = TextCleanerService();
/// 
/// // OCR 결과 정리
/// final cleanedText = textCleanerService.cleanText(ocrText);
/// 
/// // 핀인 줄 제거
/// final textWithoutPinyin = textCleanerService.removePinyinLines(text);
/// 
/// // 중국어 문자 추출
/// final chineseCharsOnly = textCleanerService.extractChineseChars(text);
/// ```
class TextCleanerService {
  // 싱글톤 패턴 구현
  static final TextCleanerService _instance = TextCleanerService._internal();
  factory TextCleanerService() => _instance;
  TextCleanerService._internal();

  // 핀인 생성 서비스
  final PinyinCreationService _pinyinService = PinyinCreationService();

  // 중국어 문자 범위 (유니코드)
  static final RegExp chineseCharPattern = RegExp(r'[\u4e00-\u9fff]');

  // 핀인 성조 기호
  static const List<String> toneMarks = [
    'ā',
    'á',
    'ǎ',
    'à',
    'ē',
    'é',
    'ě',
    'è',
    'ī',
    'í',
    'ǐ',
    'ì',
    'ō',
    'ó',
    'ǒ',
    'ò',
    'ū',
    'ú',
    'ǔ',
    'ù',
    'ǖ',
    'ǘ',
    'ǚ',
    'ǜ'
  ];

  // 정규식 패턴 캐싱 (성능 최적화)
  static final RegExp pinyinPattern =
      RegExp(r'[a-zA-Z' + toneMarks.join('') + r']+');
  static final RegExp onlyNumbersPattern = RegExp(r'^[0-9]+$');
  static final RegExp onlyPunctuationPattern =
      RegExp(r'^[\s\p{P}]+$', unicode: true);

  // 텍스트 정리 결과 캐싱
  final Map<String, String> _cleanTextCache = {};
  final int _maxCacheSize = 100;

  /// 불필요한 텍스트 제거
  /// - 핀인 줄 제거
  /// - 숫자만 단독으로 있는 문장 제거
  /// - 문장부호만 있는 문장 제거
  /// - 너무 짧은 줄 제거 (중국어가 아닌 경우)
  String cleanText(String text) {
    if (text.isEmpty) return text;

    // 캐시 확인
    if (_cleanTextCache.containsKey(text)) {
      return _cleanTextCache[text]!;
    }

    // 핀인 줄 제거
    text = removePinyinLines(text);

    // 줄 단위로 분리
    final lines = text.split('\n');
    final cleanedLines = <String>[];

    for (final line in lines) {
      final trimmedLine = line.trim();

      // 빈 줄 건너뛰기
      if (trimmedLine.isEmpty) continue;

      // 숫자만 있는 줄 건너뛰기 (페이지 번호 등)
      if (_isOnlyNumbers(trimmedLine)) {
        continue;
      }

      // 문장부호만 있는 줄 건너뛰기
      if (_isOnlyPunctuation(trimmedLine)) {
        continue;
      }

      // 너무 짧은 줄 건너뛰기 (1-2글자이면서 중국어가 아닌 경우)
      if (_isTooShort(trimmedLine)) {
        continue;
      }

      cleanedLines.add(trimmedLine);
    }

    final result = cleanedLines.join('\n');

    // 캐시에 저장 (캐시 크기 제한)
    if (_cleanTextCache.length >= _maxCacheSize) {
      // 가장 오래된 항목 제거 (간단한 FIFO 방식)
      final oldestKey = _cleanTextCache.keys.first;
      _cleanTextCache.remove(oldestKey);
    }
    _cleanTextCache[text] = result;

    return result;
  }

  /// 텍스트가 중국어를 포함하는지 확인
  bool containsChinese(String text) {
    return chineseCharPattern.hasMatch(text);
  }

  /// 텍스트에서 중국어 문자만 추출
  String extractChineseChars(String text) {
    if (text.isEmpty) return '';

    final matches = chineseCharPattern.allMatches(text);
    final buffer = StringBuffer();

    for (final match in matches) {
      buffer.write(match.group(0));
    }

    return buffer.toString();
  }

  /// 텍스트가 핀인인지 확인 (전체 줄이 핀인인 경우)
  bool isPinyinLine(String line) {
    // 중국어 문자가 없고, 핀인 패턴과 일치하는 경우
    return !containsChinese(line) &&
        pinyinPattern.allMatches(line).length > 0 &&
        line.trim().split(' ').every(
            (word) => pinyinPattern.hasMatch(word) || word.trim().isEmpty);
  }

  // 핀인 줄 캐싱
  final Map<String, String> _pinyinRemovalCache = {};

  /// 중국어 텍스트에서 핀인 줄 제거
  String removePinyinLines(String text) {
    if (text.isEmpty) return text;

    // 캐시 확인
    if (_pinyinRemovalCache.containsKey(text)) {
      return _pinyinRemovalCache[text]!;
    }

    final lines = text.split('\n');
    final filteredLines = lines.where((line) => !isPinyinLine(line)).toList();
    final result = filteredLines.join('\n');

    // 캐시에 저장 (캐시 크기 제한)
    if (_pinyinRemovalCache.length >= _maxCacheSize) {
      // 가장 오래된 항목 제거
      final oldestKey = _pinyinRemovalCache.keys.first;
      _pinyinRemovalCache.remove(oldestKey);
    }
    _pinyinRemovalCache[text] = result;

    return result;
  }

  /// 중국어 텍스트에서 핀인 줄 추출
  List<String> extractPinyinLines(String text) {
    final lines = text.split('\n');
    return lines.where((line) => isPinyinLine(line)).toList();
  }

  /// 숫자만 있는지 확인
  bool _isOnlyNumbers(String text) {
    return onlyNumbersPattern.hasMatch(text);
  }

  /// 문장부호만 있는지 확인
  bool _isOnlyPunctuation(String text) {
    return onlyPunctuationPattern.hasMatch(text);
  }

  /// 너무 짧은 줄인지 확인 (1-2글자이면서 중국어가 아닌 경우)
  bool _isTooShort(String text) {
    return text.length <= 2 && !containsChinese(text);
  }

  // 캐시 정리
  void clearCache() {
    _cleanTextCache.clear();
    _pinyinRemovalCache.clear();
    debugPrint('TextCleanerService: 캐시 정리됨');
  }
  
  /// 문장에서 중국어 문자만 추출하여 병음 생성 (EnhancedOcrService에서 이동)
  Future<String> generatePinyinForSentence(String sentence) async {
    try {
      // 중국어 문자만 추출
      final chineseCharsOnly = extractChineseChars(sentence);
      if (chineseCharsOnly.isEmpty) {
        return '';
      }

      // 핀인 생성
      return await _pinyinService.generatePinyin(chineseCharsOnly);
    } catch (e) {
      debugPrint('핀인 생성 중 오류 발생: $e');
      return '';
    }
  }
  
  /// OCR 텍스트 정리 (EnhancedOcrService에서 이동)
  /// 
  /// 특수 문자, 핀인 줄 등을 제거하고 깔끔한 텍스트로 변환합니다.
  String normalizeOcrText(String text) {
    if (text.isEmpty) return text;
    
    // 핀인 줄 제거
    final textWithoutPinyin = removePinyinLines(text);
    
    // 줄바꿈 정리 (연속된 줄바꿈을 하나로)
    final normalizedNewlines = textWithoutPinyin.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    
    // 특수문자 제거 (필요에 따라 추가)
    final cleanedText = normalizedNewlines
        .replaceAll(RegExp(r'[^\w\s\p{P}\u4e00-\u9fff]', unicode: true), '')
        .trim();
    
    return cleanedText;
  }
}
