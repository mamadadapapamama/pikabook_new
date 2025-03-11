import 'dart:async';
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

  // 세그멘테이션 활성화 여부 플래그 추가
  static bool isSegmentationEnabled = false; // MVP에서는 비활성화

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (!_isInitialized) {
      await _dictionaryService.loadDictionary();
      // DictionaryService에 loadDictionary 메서드가 없는 경우 주석 처리
      // if (_fallbackDictionaryService != null) {
      //   await _fallbackDictionaryService.loadDictionary();
      // }
      _isInitialized = true;
    }
  }

  // 중국어 텍스트 분절 및 사전 정보 추가
  Future<List<SegmentedWord>> processText(String text) async {
    await initialize();

    // 세그멘테이션이 비활성화된 경우 전체 텍스트를 하나의 세그먼트로 반환
    if (!isSegmentationEnabled) {
      return [
        SegmentedWord(
          text: text,
          meaning: '', // 의미는 비워둠
          pinyin: '', // 병음도 비워둠
        )
      ];
    }

    // 각 단어에 사전 정보 추가
    List<SegmentedWord> result = [];

    // 비동기 처리를 위한 Future 목록
    List<Future<SegmentedWord>> futures = [];

    for (String segment in _segmentText(text)) {
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
        text: segment,
        meaning: entry.meaning,
        pinyin: entry.pinyin,
      );
    } else {
      // 2. 폴백 사전 서비스 사용 (DictionaryService)
      final fallbackEntry =
          await _fallbackDictionaryService.lookupWordWithFallback(segment);

      if (fallbackEntry != null) {
        // 폴백 사전에서 찾은 경우
        return SegmentedWord(
          text: segment,
          meaning: fallbackEntry.meaning,
          pinyin: fallbackEntry.pinyin,
          source: 'external',
        );
      } else {
        // 3. 사전에 없는 경우 - 외부 사전 서비스 필요
        return SegmentedWord(
          text: segment,
          meaning: '사전에 없는 단어',
          pinyin: '',
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

  bool isWordInDictionary(String word) {
    // lookup 메서드로 변경
    return _dictionaryService.lookup(word) != null;
  }

  // 유저가 선택한 단어 처리 메서드 추가
  Future<SegmentedWord> processSelectedWord(String word) async {
    await initialize();

    // 1. 앱 내 JSON 사전에서 검색
    final entry = _dictionaryService.lookup(word);

    if (entry != null) {
      // JSON 사전에서 찾은 경우
      return SegmentedWord(
        text: word,
        meaning: entry.meaning,
        pinyin: entry.pinyin,
      );
    } else {
      // 2. 폴백 사전 서비스 사용 (DictionaryService)
      final fallbackEntry =
          await _fallbackDictionaryService.lookupWordWithFallback(word);

      if (fallbackEntry != null) {
        // 폴백 사전에서 찾은 경우
        return SegmentedWord(
          text: word,
          meaning: fallbackEntry.meaning,
          pinyin: fallbackEntry.pinyin,
          source: 'external',
        );
      } else {
        // 3. 사전에 없는 경우 - 외부 사전 서비스 필요
        return SegmentedWord(
          text: word,
          meaning: '사전에 없는 단어',
          pinyin: '',
        );
      }
    }
  }
}

// 분절된 단어 클래스
class SegmentedWord {
  final String text;
  final String meaning;
  final String pinyin;
  final String? source;

  SegmentedWord({
    required this.text,
    required this.meaning,
    required this.pinyin,
    this.source,
  });
}
