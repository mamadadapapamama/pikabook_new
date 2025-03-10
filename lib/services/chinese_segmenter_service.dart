import 'package:flutter/material.dart';
import 'chinese_dictionary_service.dart';

class ChineseSegmenterService {
  static final ChineseSegmenterService _instance =
      ChineseSegmenterService._internal();

  factory ChineseSegmenterService() {
    return _instance;
  }

  ChineseSegmenterService._internal();

  final ChineseDictionaryService _dictionaryService =
      ChineseDictionaryService();

  // 중국어 텍스트 분절 및 사전 정보 추가
  Future<List<SegmentedWord>> processText(String text) async {
    // 사전이 로드되지 않았으면 로드
    if (!_dictionaryService.isLoaded) {
      await _dictionaryService.loadDictionary();
    }

    // 단어 분절
    final List<String> segments = _segmentText(text);

    // 각 단어에 사전 정보 추가
    List<SegmentedWord> result = [];
    for (String segment in segments) {
      final entry = _dictionaryService.lookup(segment);

      result.add(SegmentedWord(
        word: segment,
        pinyin: entry?.pinyin ?? '',
        meaning: entry?.meaning ?? '알 수 없음',
      ));
    }

    return result;
  }

  // 중국어 문장 분절
  List<String> _segmentText(String text) {
    final words = _dictionaryService.getWords();

    // 최장 일치 알고리즘 (Forward Maximum Matching)
    List<String> result = [];
    int i = 0;

    while (i < text.length) {
      // 가장 긴 일치 단어 찾기
      int maxLength = 0;
      String matchedWord = "";

      // 최대 단어 길이 (일반적으로 중국어 단어는 1-4자)
      for (int j = 4; j >= 1; j--) {
        if (i + j <= text.length) {
          String candidate = text.substring(i, i + j);
          if (words.contains(candidate) && j > maxLength) {
            maxLength = j;
            matchedWord = candidate;
          }
        }
      }

      // 일치하는 단어가 없으면 한 글자를 추가
      if (maxLength == 0) {
        result.add(text[i]);
        i++;
      } else {
        result.add(matchedWord);
        i += maxLength;
      }
    }

    return result;
  }
}

// 분절된 단어 클래스
class SegmentedWord {
  final String word;
  final String pinyin;
  final String meaning;

  SegmentedWord({
    required this.word,
    required this.pinyin,
    required this.meaning,
  });
}
