// 현재는 중국어 문장 분절만 지원합니다.
// 향후 각 언어별 분절 서비스로 분리될 예정입니다. 

import 'dart:async';
import 'package:flutter/material.dart';
import '../dictionary/internal_cn_dictionary_service.dart';

/// 중국어 텍스트를 문장 단위로 분절하는 서비스
/// 문장 분할, 문단 처리 등의 기능만 담당합니다
class InternalCnSegmenterService {
  static final InternalCnSegmenterService _instance =
      InternalCnSegmenterService._internal();

  factory InternalCnSegmenterService() {
    return _instance;
  }

  InternalCnSegmenterService._internal();

  // 단어 목록을 가져오기 위한 중국어 사전 서비스 참조
  final InternalCnDictionaryService _dictionaryService = InternalCnDictionaryService();

  // 세그멘테이션 활성화 여부 플래그 추가
  static bool isSegmentationEnabled = false; // MVP에서는 비활성화

  bool _isInitialized = false;
  bool _isInitializing = false;
  Completer<void>? _initializationCompleter;

  // 정규식 패턴 캐싱 (성능 최적화)
  static final RegExp _chapterPattern = RegExp(
      r'(第\s*\d+\s*[课課]|第\s*[一二三四五六七八九十百千]+\s*[课課]|제\s*\d+\s*과|\d+\s*[课課과])');
  static final RegExp _quotePattern =
      RegExp(r'[""].*?[""]|[""].*?[""]|[""].*?[""]|[""].*?[""]');
  static final RegExp _enumerationPattern = RegExp(r'、');
  static final RegExp _ellipsisPattern = RegExp(r'[.．。]{2,}|…{1,}');
  static final RegExp _singleDotPattern = RegExp(r'(\s\.\s|\s\.$|[^.]\.$)');
  static final RegExp _sentencePattern = RegExp(r'([。！？；]+)');
  static final RegExp _onlyDotsPattern = RegExp(r'^\s*[.．。]+\s*$');
  static final RegExp _onlyNumbersPattern = RegExp(r'^\s*\d+\s*$');
  static final RegExp _multipleEllipsisPattern = RegExp(r'…{2,}');

  // 문장 분리 결과 캐싱
  final Map<String, List<String>> _sentenceSplitCache = {};
  final int _maxCacheSize = 100; // 최대 캐시 항목 수

  // 지연 로딩 방식으로 초기화 개선
  Future<void> initialize() async {
    // 이미 초기화되었으면 바로 반환
    if (_isInitialized) return;

    // 초기화 중이면 완료될 때까지 대기
    if (_isInitializing) {
      return _initializationCompleter!.future;
    }

    // 초기화 시작
    _isInitializing = true;
    _initializationCompleter = Completer<void>();

    try {
      debugPrint('InternalCnSegmenterService 초기화 시작...');

      // 사전 로드 (단어 분절을 위해 필요한 경우에만)
      if (isSegmentationEnabled) {
        await _dictionaryService.loadDictionary();
        debugPrint('InternalCnSegmenterService 초기화 완료: 사전 로드됨');
      } else {
        debugPrint('InternalCnSegmenterService 초기화 완료: 세그멘테이션 비활성화로 사전 로드 생략');
      }

      _isInitialized = true;
      _isInitializing = false;
      _initializationCompleter!.complete();
    } catch (e) {
      debugPrint('InternalCnSegmenterService 초기화 실패: $e');
      _isInitializing = false;
      _initializationCompleter!.completeError(e);
      throw e;
    }
  }

  /// 중국어 문장 분절
  List<String> segmentText(String text) {
    // 세그멘테이션이 비활성화된 경우
    if (!isSegmentationEnabled) {
      return [text];
    }
    
    List<String> words = [];
    
    try {
      // 메서드가 존재하면 사용
      words = _dictionaryService.getWords();
    } catch (e) {
      debugPrint('단어 목록 가져오기 실패: $e');
      // 안전하게 빈 목록 사용
      words = [];
    }
    
    // 단어 목록이 비어있으면 문자별로 분리
    if (words.isEmpty) {
      return text.split('');
    }

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

  // 단어가 사전에 있는지 확인 (하위 호환성 유지)
  bool isWordInDictionary(String word) {
    // 사전이 초기화되지 않았으면 초기화
    if (!_isInitialized) {
      debugPrint('사전 확인 전 초기화 필요');
      // 비동기 함수를 동기적으로 호출할 수 없으므로, 초기화되지 않은 상태에서는 false 반환
      return false;
    }

    // lookup 메서드로 변경
    final result = _dictionaryService.lookup(word) != null;
    debugPrint('단어 "$word" 사전 확인 결과: ${result ? "있음" : "없음"}');
    return result;
  }

  /// 텍스트를 문장 단위로 분리 (최적화 버전)
  List<String> splitIntoSentences(String text) {
    if (text.isEmpty) return [];

    // 캐시 확인
    if (_sentenceSplitCache.containsKey(text)) {
      return List<String>.from(_sentenceSplitCache[text]!);
    }

    // 전처리: 연속된 마침표를 표준 말줄임표로 변환
    text = _normalizeEllipsis(text);

    // 줄바꿈 문자를 기준으로 먼저 분리
    final paragraphs = text.split('\n');

    // 각 단락을 개별적으로 처리
    List<String> allSentences = [];

    for (final paragraph in paragraphs) {
      if (paragraph.trim().isEmpty) continue;

      // 숫자만으로 구성된 단락은 건너뜀 (페이지 번호 등)
      if (_onlyNumbersPattern.hasMatch(paragraph)) {
        continue;
      }

      // 마침표만으로 구성된 단락은 말줄임표로 처리
      if (_onlyDotsPattern.hasMatch(paragraph)) {
        // 말줄임표로 변환하여 이전 문장에 추가
        if (allSentences.isNotEmpty) {
          allSentences[allSentences.length - 1] += '…';
        } else {
          allSentences.add('…');
        }
        continue;
      }

      // 특정 패턴 감지 (예: '제 N과', 챕터 제목 등)
      // 챕터 패턴 찾기
      final chapterMatches = _chapterPattern.allMatches(paragraph).toList();

      // 챕터 제목 패턴이 있는지 확인
      bool isChapterParagraph = false;
      if (chapterMatches.isNotEmpty) {
        final match = chapterMatches.first;

        // 챕터 텍스트가 단락의 시작 부분에 있는지 확인
        final startIndex = match.start;
        if (startIndex == 0 || startIndex <= 2) {
          // 시작 부분에 약간의 공백이 있을 수 있음
          isChapterParagraph = true;
          // 전체 단락을 챕터 제목으로 처리
          allSentences.add(_normalizeEllipsis(paragraph.trim()));
        }
      }

      // 챕터 제목이 아닌 경우 일반 문장 처리
      if (!isChapterParagraph) {
        // 문장 분리 로직 최적화
        final sentences = _splitParagraphIntoSentences(paragraph);
        allSentences.addAll(sentences);
      }
    }

    // 빈 문장 제거 및 정리
    final result =
        allSentences.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

    // 캐시에 저장 (캐시 크기 제한)
    if (_sentenceSplitCache.length >= _maxCacheSize) {
      // 가장 오래된 항목 제거 (간단한 FIFO 방식)
      final oldestKey = _sentenceSplitCache.keys.first;
      _sentenceSplitCache.remove(oldestKey);
    }
    _sentenceSplitCache[text] = List<String>.from(result);

    return result;
  }

  // 단락을 문장으로 분리하는 최적화된 메서드
  List<String> _splitParagraphIntoSentences(String paragraph) {
    // 따옴표 패턴 보호
    final quotes = <String>[];
    String tempText = paragraph;

    // 따옴표 패턴 찾기 및 보호
    final quoteMatches = _quotePattern.allMatches(tempText).toList();
    for (int i = quoteMatches.length - 1; i >= 0; i--) {
      final match = quoteMatches[i];
      final quotedText = match.group(0)!;
      quotes.add(quotedText);
      tempText = tempText.replaceRange(
          match.start, match.end, "###QUOTE###${quotes.length - 1}###");
    }

    // 문장 구분 기호로 분리
    List<String> sentences = [];

    // 문장 구분 기호로 분리
    final parts = tempText.split(_sentencePattern);

    for (int i = 0; i < parts.length; i++) {
      if (parts[i].trim().isNotEmpty) {
        if (i < parts.length - 1 && i % 2 == 0) {
          // 구분자가 있는 경우
          sentences.add(parts[i] + (i + 1 < parts.length ? parts[i + 1] : ''));
          i++; // 구분자 건너뛰기
        } else {
          // 구분자가 없는 마지막 부분
          sentences.add(parts[i]);
        }
      }
    }

    // 따옴표 복원
    for (int i = 0; i < sentences.length; i++) {
      String sentence = sentences[i];
      for (int j = 0; j < quotes.length; j++) {
        sentence = sentence.replaceAll("###QUOTE###$j###", quotes[j]);
      }
      sentences[i] = _normalizeEllipsis(sentence.trim());
    }

    return sentences;
  }

  /// 연속된 마침표를 표준 말줄임표로 변환 (최적화 버전)
  String _normalizeEllipsis(String text) {
    if (text.isEmpty) return text;

    // 연속된 마침표를 표준 말줄임표로 변환
    String result = text.replaceAll(_ellipsisPattern, '…');

    // 연속된 말줄임표 문자도 하나로 통일
    result = result.replaceAll(_multipleEllipsisPattern, '…');

    return result;
  }

  /// 특별 마커가 있는 문장인지 확인
  bool isChapterTitle(String sentence) {
    return sentence.startsWith("##CHAPTER##");
  }

  /// 특별 마커 제거
  String removeMarker(String sentence) {
    if (sentence.startsWith("##CHAPTER##")) {
      return sentence.substring("##CHAPTER##".length).trim();
    }
    return sentence;
  }

  // 캐시 정리
  void clearCache() {
    _sentenceSplitCache.clear();
    debugPrint('InternalCnSegmenterService: 문장 분리 캐시 정리됨');
  }
}

// 세그먼트된 문장 정보
class SegmentedSentence {
  final String text;
  final bool isChapter;
  
  SegmentedSentence({
    required this.text,
    this.isChapter = false,
  });
}
