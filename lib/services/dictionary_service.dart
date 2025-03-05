import 'package:flutter/foundation.dart';

class DictionaryEntry {
  final String word;
  final String pinyin;
  final String meaning;
  final List<String> examples;

  DictionaryEntry({
    required this.word,
    required this.pinyin,
    required this.meaning,
    this.examples = const [],
  });
}

class DictionaryService {
  // 싱글톤 패턴 구현
  static final DictionaryService _instance = DictionaryService._internal();
  factory DictionaryService() => _instance;
  DictionaryService._internal();

  // 간단한 인메모리 사전 (실제로는 데이터베이스나 API를 사용해야 함)
  final Map<String, DictionaryEntry> _dictionary = {
    '你': DictionaryEntry(
      word: '你',
      pinyin: 'nǐ',
      meaning: '너, 당신',
      examples: ['你好 (nǐ hǎo) - 안녕하세요', '谢谢你 (xiè xiè nǐ) - 감사합니다'],
    ),
    '好': DictionaryEntry(
      word: '好',
      pinyin: 'hǎo',
      meaning: '좋다, 잘',
      examples: ['你好 (nǐ hǎo) - 안녕하세요', '好的 (hǎo de) - 좋아요'],
    ),
    '我': DictionaryEntry(
      word: '我',
      pinyin: 'wǒ',
      meaning: '나, 저',
      examples: ['我是学生 (wǒ shì xué shēng) - 나는 학생이다'],
    ),
    '是': DictionaryEntry(
      word: '是',
      pinyin: 'shì',
      meaning: '~이다, ~이다',
      examples: ['我是韩国人 (wǒ shì hán guó rén) - 나는 한국인이다'],
    ),
    '中国': DictionaryEntry(
      word: '中国',
      pinyin: 'zhōng guó',
      meaning: '중국',
      examples: ['我去中国 (wǒ qù zhōng guó) - 나는 중국에 간다'],
    ),
    '学生': DictionaryEntry(
      word: '学生',
      pinyin: 'xué shēng',
      meaning: '학생',
      examples: ['我是学生 (wǒ shì xué shēng) - 나는 학생이다'],
    ),
    '谢谢': DictionaryEntry(
      word: '谢谢',
      pinyin: 'xiè xiè',
      meaning: '감사합니다',
      examples: ['谢谢你 (xiè xiè nǐ) - 감사합니다'],
    ),
    '再见': DictionaryEntry(
      word: '再见',
      pinyin: 'zài jiàn',
      meaning: '안녕히 가세요, 안녕히 계세요',
      examples: ['明天见 (míng tiān jiàn) - 내일 봐요'],
    ),
    '朋友': DictionaryEntry(
      word: '朋友',
      pinyin: 'péng yǒu',
      meaning: '친구',
      examples: ['他是我的朋友 (tā shì wǒ de péng yǒu) - 그는 내 친구이다'],
    ),
    '老师': DictionaryEntry(
      word: '老师',
      pinyin: 'lǎo shī',
      meaning: '선생님, 교사',
      examples: ['他是老师 (tā shì lǎo shī) - 그는 선생님이다'],
    ),
  };

  // 단어 검색
  DictionaryEntry? lookupWord(String word) {
    try {
      return _dictionary[word];
    } catch (e) {
      debugPrint('단어 검색 중 오류 발생: $e');
      return null;
    }
  }

  // 문장에서 알고 있는 단어 추출
  List<DictionaryEntry> extractKnownWords(String text) {
    final result = <DictionaryEntry>[];

    // 단순 구현: 사전에 있는 단어가 문장에 포함되어 있는지 확인
    _dictionary.forEach((word, entry) {
      if (text.contains(word)) {
        result.add(entry);
      }
    });

    return result;
  }

  // 더 복잡한 중국어 단어 분석 (실제로는 NLP 라이브러리 사용 필요)
  List<String> segmentChineseText(String text) {
    // 간단한 구현: 각 문자를 개별 단어로 취급
    // 실제로는 중국어 단어 분석 라이브러리를 사용해야 함
    return text.split('');
  }
}
