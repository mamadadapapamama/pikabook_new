import 'package:flutter/material.dart';
import 'chinese_dictionary_service.dart';
import 'dictionary_service.dart';

class ChineseSegmenterService {
  static final ChineseSegmenterService _instance =
      ChineseSegmenterService._internal();

  factory ChineseSegmenterService() {
    return _instance;
  }

  ChineseSegmenterService._internal();

  final ChineseDictionaryService _dictionaryService =
      ChineseDictionaryService();

  final DictionaryService _fallbackDictionaryService = DictionaryService();

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

    // 비동기 처리를 위한 Future 목록
    List<Future<SegmentedWord>> futures = [];

    for (String segment in segments) {
      futures.add(_processSegment(segment));
    }

    // 모든 비동기 작업이 완료될 때까지 대기
    result = await Future.wait(futures);

    return result;
  }

  // 개별 단어 처리 (비동기)
  Future<SegmentedWord> _processSegment(String segment) async {
    // 1. 앱 내 JSON 사전에서 검색
    final entry = _dictionaryService.lookup(segment);

    if (entry != null) {
      // JSON 사전에서 찾은 경우
      return SegmentedWord(
        word: segment,
        pinyin: entry.pinyin,
        meaning: entry.meaning,
        isInDictionary: true,
        source: 'json',
      );
    } else {
      // 2. 폴백 사전 서비스 사용 (DictionaryService)
      final fallbackEntry =
          await _fallbackDictionaryService.lookupWordWithFallback(segment);

      if (fallbackEntry != null) {
        // 폴백 사전에서 찾은 경우
        return SegmentedWord(
          word: segment,
          pinyin: fallbackEntry.pinyin,
          meaning: fallbackEntry.meaning,
          isInDictionary: true,
          source: fallbackEntry.source,
        );
      } else {
        // 3. 사전에 없는 경우 - 외부 사전 서비스 필요
        return SegmentedWord(
          word: segment,
          pinyin: '',
          meaning: '사전에 없는 단어',
          isInDictionary: false,
          source: 'none',
        );
      }
    }
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
  final bool isInDictionary; // 사전에 있는 단어인지 여부
  final String? source;

  SegmentedWord({
    required this.word,
    required this.pinyin,
    required this.meaning,
    this.isInDictionary = false,
    this.source,
  });
}
