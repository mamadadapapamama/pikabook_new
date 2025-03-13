import 'dart:async';
import 'package:flutter/material.dart';
import 'chinese_dictionary_service.dart';
import 'dictionary_service.dart';
import 'package:pinyin/pinyin.dart';

class ChineseSegmenterService {
  static final ChineseSegmenterService _instance =
      ChineseSegmenterService._internal();

  factory ChineseSegmenterService() {
    return _instance;
  }

  ChineseSegmenterService._internal() {
    // 사전 업데이트 리스너 등록
    _fallbackDictionaryService
        .addDictionaryUpdateListener(_onDictionaryUpdated);
  }

  final ChineseDictionaryService _dictionaryService =
      ChineseDictionaryService();

  final DictionaryService _fallbackDictionaryService = DictionaryService();

  // 세그멘테이션 활성화 여부 플래그 추가
  static bool isSegmentationEnabled = false; // MVP에서는 비활성화

  bool _isInitialized = false;

  // 사전 업데이트 감지 시 호출되는 콜백
  void _onDictionaryUpdated() {
    debugPrint('ChineseSegmenterService: 사전 업데이트 감지됨');
    // 필요한 경우 캐시 초기화 등의 작업 수행
  }

  Future<void> initialize() async {
    if (!_isInitialized) {
      debugPrint('ChineseSegmenterService 초기화 시작...');
      await _dictionaryService.loadDictionary();
      debugPrint('ChineseSegmenterService 초기화 완료: 사전 로드됨');
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
          pinyin: fallbackEntry.pinyin.isEmpty
              ? await _generatePinyin(word)
              : fallbackEntry.pinyin,
          source: fallbackEntry.source ?? 'external',
        );
      } else {
        // 3. 사전에 없는 경우 - 외부 사전 서비스 필요
        // 핀인 생성 시도
        String pinyin = '';
        try {
          pinyin = await _generatePinyin(word);
        } catch (e) {
          debugPrint('핀인 생성 중 오류 발생: $e');
        }

        return SegmentedWord(
          text: word,
          meaning: '사전에 없는 단어',
          pinyin: pinyin,
        );
      }
    }
  }

  // 핀인 생성 메서드
  Future<String> _generatePinyin(String text) async {
    try {
      // pinyin 패키지 사용
      return PinyinHelper.getPinyin(text, separator: ' ');
    } catch (e) {
      debugPrint('핀인 생성 중 오류 발생: $e');
      return '';
    }
  }

  /// 텍스트를 문장 단위로 분리
  List<String> splitIntoSentences(String text) {
    if (text.isEmpty) return [];

    // 줄바꿈 문자를 기준으로 먼저 분리
    final paragraphs = text.split('\n');
    debugPrint('줄바꿈으로 분리된 단락 수: ${paragraphs.length}');

    // 각 단락을 개별적으로 처리
    List<String> allSentences = [];

    for (final paragraph in paragraphs) {
      if (paragraph.trim().isEmpty) continue;

      // 특정 패턴 감지 (예: '제 N과', 챕터 제목 등) - 정규식 패턴 개선
      final patterns = <String, String>{};
      // 다양한 형태의 챕터 제목 패턴 감지 (제 13과, 第 1 课, 13과, 第13课, 第十三课 등)
      final chapterPattern = RegExp(
          r'(第\s*\d+\s*[课課]|第\s*[一二三四五六七八九十百千]+\s*[课課]|제\s*\d+\s*과|\d+\s*[课課과])');
      final titlePlaceholder = "###TITLE###";

      // 챕터 패턴 찾기
      String tempText = paragraph;
      final chapterMatches = chapterPattern.allMatches(paragraph).toList();
      debugPrint('단락에서 찾은 챕터 패턴 수: ${chapterMatches.length}');

      // 챕터 제목 패턴이 있는지 확인
      bool isChapterParagraph = false;
      if (chapterMatches.isNotEmpty) {
        final match = chapterMatches.first;
        final chapterText = match.group(0)!;
        debugPrint('찾은 챕터 텍스트: $chapterText');

        // 챕터 텍스트가 단락의 시작 부분에 있는지 확인
        final startIndex = match.start;
        if (startIndex == 0 || startIndex <= 2) {
          // 시작 부분에 약간의 공백이 있을 수 있음
          isChapterParagraph = true;
          // 전체 단락을 챕터 제목으로 처리
          allSentences.add(paragraph.trim());
          debugPrint('챕터 제목으로 처리: ${paragraph.trim()}');
        }
      }

      // 챕터 제목이 아닌 경우 일반 문장 처리
      if (!isChapterParagraph) {
        // 다양한 형태의 따옴표 패턴 감지 (중국어, 영어, 한국어 등)
        final quotes = <String>[];
        // 영어 따옴표 "...", 중국어 따옴표 "...", 한국어 따옴표 "..." 등을 모두 포함
        final quotePattern =
            RegExp(r'[""].*?[""]|[""].*?[""]|[""].*?[""]|[""].*?[""]');
        final quotePlaceholder = "###QUOTE###";

        // 따옴표 패턴 찾기
        final matches = quotePattern.allMatches(tempText).toList();
        for (final match in matches) {
          final quotedText = match.group(0)!;
          quotes.add(quotedText);
          tempText = tempText.replaceFirst(
              quotedText, quotePlaceholder + quotes.length.toString());
        }

        // 열거 쉼표(、)를 임시 플레이스홀더로 대체하여 보호
        final enumerationCommas = <String>[];
        final enumerationPattern = RegExp(r'、');
        final enumerationPlaceholder = "###ENUM###";

        enumerationPattern.allMatches(tempText).forEach((match) {
          enumerationCommas.add(match.group(0)!);
          tempText = tempText.replaceFirst(match.group(0)!,
              enumerationPlaceholder + enumerationCommas.length.toString());
        });

        // 문장 구분 기호로 분리
        final sentencePattern = RegExp(r'([。！？；…]+)');
        final parts = tempText.split(sentencePattern);

        final sentences = <String>[];
        for (int i = 0; i < parts.length - 1; i += 2) {
          if (i + 1 < parts.length) {
            final sentence = parts[i] + parts[i + 1];
            if (sentence.trim().isNotEmpty) {
              sentences.add(sentence.trim());
            }
          } else if (parts[i].trim().isNotEmpty) {
            sentences.add(parts[i].trim());
          }
        }

        // 마지막 부분이 남아있고 구분자가 없는 경우 추가
        if (parts.length % 2 == 1 && parts.last.trim().isNotEmpty) {
          sentences.add(parts.last.trim());
        }

        // 쉼표(，)를 포함한 긴 문장은 보조적으로 분리
        // 단, 따옴표가 포함된 문장은 분리하지 않음
        final finalSentences = <String>[];
        for (final sentence in sentences) {
          if (sentence.contains("，") &&
              sentence.length > 10 &&
              !sentence.contains(quotePlaceholder)) {
            final subSentences = sentence.split("，");
            for (final subSentence in subSentences) {
              if (subSentence.trim().isNotEmpty) {
                // 임시적으로 마침표 추가
                finalSentences.add("${subSentence.trim()}。");
              }
            }
          } else {
            finalSentences.add(sentence);
          }
        }

        // 열거 쉼표(、) 복원
        List<String> restoredEnumSentences = finalSentences.map((sentence) {
          String result = sentence;
          for (int i = 0; i < enumerationCommas.length; i++) {
            final placeholder = enumerationPlaceholder + (i + 1).toString();
            if (result.contains(placeholder)) {
              result = result.replaceAll(placeholder, enumerationCommas[i]);
            }
          }
          return result;
        }).toList();

        // 따옴표 복원
        List<String> restoredQuoteSentences =
            restoredEnumSentences.map((sentence) {
          String result = sentence;
          for (int i = 0; i < quotes.length; i++) {
            final placeholder = quotePlaceholder + (i + 1).toString();
            if (result.contains(placeholder)) {
              result = result.replaceAll(placeholder, quotes[i]);
            }
          }
          return result;
        }).toList();

        // 최종 문장 추가
        allSentences.addAll(restoredQuoteSentences);
      }
    }

    // 디버그 출력 추가
    debugPrint('최종 문장 수: ${allSentences.length}');
    for (int i = 0; i < allSentences.length; i++) {
      debugPrint('문장 $i: ${allSentences[i]}');
    }

    // 빈 문장 제거 및 정리
    return allSentences
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
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
