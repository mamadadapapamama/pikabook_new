import 'package:flutter/foundation.dart';
import 'package:pinyin/pinyin.dart';

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

  /// 중국어 텍스트에 대한 핀인 생성 (pinyin 패키지 사용)
  Future<String> generatePinyin(String chineseText) async {
    try {
      // 문장 내 각 한자에 대한 핀인 생성
      final List<String> pinyinWords = [];

      // 문장을 한자 단위로 처리
      for (int i = 0; i < chineseText.length; i++) {
        final char = chineseText[i];

        // 중국어 한자인 경우 핀인 생성
        if (containsChinese(char)) {
          // pinyin 패키지 사용 - 성조 표시가 있는 형식으로 변환
          final pinyin =
              PinyinHelper.getPinyin(char, format: PinyinFormat.WITH_TONE_MARK);
          pinyinWords.add(pinyin);
        }
        // 구두점이나 기타 문자는 그대로 유지
        else {
          // 공백 추가 (가독성을 위해)
          if (char == '，' || char == '。' || char == '！' || char == '？') {
            pinyinWords.add(char + ' ');
          } else {
            pinyinWords.add(char);
          }
        }
      }

      // 핀인 단어들을 공백으로 연결
      return pinyinWords.join(' ').replaceAll('  ', ' ').trim();
    } catch (e) {
      debugPrint('핀인 생성 중 오류 발생: $e');
      throw Exception('핀인을 생성할 수 없습니다: $e');
    }
  }

  /// 문자열에서 중국어 문자만 추출
  String extractChineseChars(String text) {
    final RegExp chineseRegex = RegExp(r'[\u4e00-\u9fff]+');
    final Iterable<Match> matches = chineseRegex.allMatches(text);
    final StringBuffer buffer = StringBuffer();
    for (final match in matches) {
      buffer.write(match.group(0));
    }
    return buffer.toString();
  }
}
