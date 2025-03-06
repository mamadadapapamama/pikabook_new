import 'package:flutter/foundation.dart';

/// 언어 감지 및 처리를 위한 서비스
class LanguageDetectionService {
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

  // 핀인 패턴 (알파벳 + 성조 기호)
  static final RegExp pinyinPattern =
      RegExp(r'[a-zA-Z' + toneMarks.join('') + r']+');

  /// 텍스트가 중국어를 포함하는지 확인
  bool containsChinese(String text) {
    return chineseCharPattern.hasMatch(text);
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

  /// 중국어 텍스트에 대한 핀인 생성 (외부 API 호출 필요)
  Future<String> generatePinyin(String chineseText) async {
    // TODO: 외부 핀인 생성 API 연동
    // MVP에서는 간단한 구현으로 대체
    return '핀인 생성 예정 (API 연동 필요)';
  }
}
