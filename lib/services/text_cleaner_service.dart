import 'package:flutter/foundation.dart';
import 'pinyin_creation_service.dart';

/// 텍스트 정리 서비스
/// OCR 결과에서 불필요한 텍스트를 제거하고 텍스트를 분석하는 기능을 제공합니다.


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
    'ā', 'á', 'ǎ', 'à', 'ē', 'é', 'ě', 'è',
    'ī', 'í', 'ǐ', 'ì', 'ō', 'ó', 'ǒ', 'ò',
    'ū', 'ú', 'ǔ', 'ù', 'ǖ', 'ǘ', 'ǚ', 'ǜ'
  ];

  // 핀인 패턴 (알파벳 + 성조 기호)
  static final RegExp pinyinPattern =
      RegExp(r'[a-zA-Z' + toneMarks.join('') + r']+');

  /// 불필요한 텍스트 제거
  /// - 핀인 줄 제거
  /// - 숫자만 단독으로 있는 문장 제거
  /// - 문장부호만 있는 문장 제거
  /// - 너무 짧은 줄 제거 (중국어가 아닌 경우)
  
  String cleanText(String text) {
    if (text.isEmpty) return text;
    
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
        debugPrint('숫자만 있는 줄 제거: $trimmedLine');
        continue;
      }

      // 문장부호만 있는 줄 건너뛰기
      if (_isOnlyPunctuation(trimmedLine)) {
        debugPrint('문장부호만 있는 줄 제거: $trimmedLine');
        continue;
      }

      // 너무 짧은 줄 건너뛰기 (1-2글자이면서 중국어가 아닌 경우)
      if (_isTooShort(trimmedLine)) {
        debugPrint('너무 짧은 줄 제거: $trimmedLine');
        continue;
      }

      cleanedLines.add(trimmedLine);
    }

    return cleanedLines.join('\n');
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

  /// 중국어 텍스트에서 핀인 줄 제거
  String removePinyinLines(String text) {
    final lines = text.split('\n');
    final filteredLines = lines.where((line) => !isPinyinLine(line)).toList();
    return filteredLines.join('\n');
  }

  /// 중국어 텍스트에서 핀인 줄 추출
  List<String> extractPinyinLines(String text) {
    final lines = text.split('\n');
    return lines.where((line) => isPinyinLine(line)).toList();
  }

  /// 숫자만 있는지 확인
  bool _isOnlyNumbers(String text) {
    return RegExp(r'^[0-9]+$').hasMatch(text);
  }

  /// 문장부호만 있는지 확인
  bool _isOnlyPunctuation(String text) {
    // 문장부호 목록
    const punctuations = '.,;:!?()"\'-，。！？「」『』《》【】（）';

    // 모든 문자가 문장부호인지 확인
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (!punctuations.contains(char) && !char.trim().isEmpty) {
        return false;
      }
    }

    return true;
  }

  /// 너무 짧은 줄인지 확인 (1-2글자이면서 중국어가 아닌 경우)
  bool _isTooShort(String text) {
    return text.length <= 2 && !containsChinese(text);
  }
}
