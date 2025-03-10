import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ChineseDictionaryService {
  static final ChineseDictionaryService _instance =
      ChineseDictionaryService._internal();

  factory ChineseDictionaryService() {
    return _instance;
  }

  ChineseDictionaryService._internal();

  Map<String, DictionaryEntry> _entries = {};
  List<String> _words = [];
  bool _isLoaded = false;

  // 사전 데이터 로드
  Future<void> loadDictionary() async {
    if (_isLoaded) return;

    try {
      final String jsonString =
          await rootBundle.loadString('assets/data/chinese_dictionary.json');
      final Map<String, dynamic> jsonData = json.decode(jsonString);

      // 사전 항목 로드
      final List<dynamic> dictionary = jsonData['dictionary'];
      for (var entry in dictionary) {
        _entries[entry['word']] = DictionaryEntry(
          word: entry['word'],
          pinyin: entry['pinyin'],
          meaning: entry['meaning'],
        );
      }

      // 분절용 단어 목록 로드
      _words = List<String>.from(jsonData['words']);

      _isLoaded = true;
      debugPrint('중국어 사전 ${_entries.length}개 항목 로드 완료');
      debugPrint('분절용 단어 ${_words.length}개 로드 완료');
    } catch (e) {
      debugPrint('사전 로드 오류: $e');
      // 기본 사전 데이터 사용
      _entries = {
        '我': DictionaryEntry(word: '我', pinyin: 'wǒ', meaning: '나, 저'),
        '非常':
            DictionaryEntry(word: '非常', pinyin: 'fēi cháng', meaning: '매우, 아주'),
        '喜欢': DictionaryEntry(word: '喜欢', pinyin: 'xǐ huān', meaning: '좋아하다'),
        '草莓': DictionaryEntry(word: '草莓', pinyin: 'cǎo méi', meaning: '딸기'),
      };
      _words = ['我', '非常', '喜欢', '草莓'];
      _isLoaded = true;
    }
  }

  // 단어 검색
  DictionaryEntry? lookup(String word) {
    if (!_isLoaded) {
      debugPrint('사전이 아직 로드되지 않았습니다.');
      return null;
    }
    return _entries[word];
  }

  // 분절용 단어 목록 가져오기
  List<String> getWords() {
    if (!_isLoaded) {
      debugPrint('사전이 아직 로드되지 않았습니다.');
      return [];
    }
    return _words;
  }

  // 사전이 로드되었는지 확인
  bool get isLoaded => _isLoaded;
}

// 사전 항목 클래스
class DictionaryEntry {
  final String word;
  final String pinyin;
  final String meaning;

  DictionaryEntry({
    required this.word,
    required this.pinyin,
    required this.meaning,
  });
}
