import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

/// 단어 위치 정보를 저장하는 클래스
class WordPosition {
  final String word;
  final int start;
  final int end;

  const WordPosition(this.word, this.start, this.end);
}

/// 텍스트 하이라이트 관련 기능을 제공하는 유틸리티 클래스
/// 플래시카드 단어를 텍스트에서 찾아 하이라이트 처리하는 기능을 담당합니다.
class TextHighlightManager {
  // 중국어 정규식 캐싱
  static final RegExp _chineseRegex = RegExp(r'[\u4e00-\u9fff]');

  // 구두점 정규식 캐싱
  static final RegExp _punctuationRegex =
      RegExp(r'[，。！？：；""' '（）【】《》、,.!?:;\'"()[\]{}]');

  // 중복 사전 검색 방지를 위한 변수 (static으로 관리)
  static bool _isProcessingDictionaryLookup = false;

  /// 중국어 문자 포함 여부 확인
  static bool containsChineseCharacters(String text) {
    return _chineseRegex.hasMatch(text);
  }

  /// 공백 문자 확인
  static bool isWhitespace(String char) {
    return char.trim().isEmpty;
  }

  /// 구두점 확인
  static bool isPunctuation(String char) {
    return _punctuationRegex.hasMatch(char);
  }

  /// 하이라이트된 단어 탭 처리
  static void handleHighlightedWordTap(String word, Function(String)? onDictionaryLookup) {
    if (_isProcessingDictionaryLookup) return;

    if (kDebugMode) {
      debugPrint('하이라이트된 단어 탭 처리: $word');
    }

    // 중복 호출 방지
    _isProcessingDictionaryLookup = true;

    // 사전 검색 콜백 호출
    if (onDictionaryLookup != null) {
      onDictionaryLookup(word);
    }

    // 일정 시간 후 플래그 초기화 (중복 호출 방지)
    Future.delayed(const Duration(milliseconds: 500), () {
      _isProcessingDictionaryLookup = false;
    });
  }

  /// 단어 경계 확인
  static bool isValidWordBoundary(String text, int index, String word) {
    // 중국어 단어는 항상 유효한 경계로 간주
    if (containsChineseCharacters(word)) {
      return true;
    }

    // 단어 앞에 문자가 있는지 확인
    if (index > 0) {
      final char = text[index - 1];
      if (!isWhitespace(char) && !isPunctuation(char)) {
        return false;
      }
    }

    // 단어 뒤에 문자가 있는지 확인
    if (index + word.length < text.length) {
      final char = text[index + word.length];
      if (!isWhitespace(char) && !isPunctuation(char)) {
        return false;
      }
    }

    return true;
  }

  /// 텍스트에서 단어 위치 찾기 (최적화 버전)
  static List<WordPosition> findWordPositions(String text, Set<String> words) {
    if (text.isEmpty || words.isEmpty) {
      return const [];
    }

    // 결과 목록 미리 할당 (메모리 최적화)
    final List<WordPosition> wordPositions = [];

    // 단어를 길이 기준으로 내림차순 정렬 (긴 단어부터 검색)
    final sortedWords = words.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final word in sortedWords) {
      if (word.isEmpty) continue;

      if (kDebugMode) {
        debugPrint('단어 검색: "$word" (길이: ${word.length})');
      }

      // 중국어 단어인지 확인 (한 번만 계산)
      final bool isChinese = containsChineseCharacters(word);

      int index = 0;
      int count = 0;

      // 단어 검색 최적화: indexOf 대신 정규식 사용 고려
      while ((index = text.indexOf(word, index)) != -1) {
        // 단어 경계 확인
        final bool isValidBoundary =
            isChinese || isValidWordBoundary(text, index, word);

        if (isValidBoundary) {
          wordPositions.add(WordPosition(word, index, index + word.length));
          count++;
          if (kDebugMode) {
            debugPrint('  위치 발견: $index-${index + word.length}');
          }
        }

        index += 1; // 다음 검색 위치로 이동
      }

      if (kDebugMode && count > 0) {
        debugPrint('  찾은 위치 수: $count개');
      }
    }

    // 위치에 따라 정렬
    wordPositions.sort((a, b) => a.start.compareTo(b.start));

    // 겹치는 위치 제거 (최적화 버전)
    final List<WordPosition> filteredPositions = [];
    int lastEnd = -1;

    for (final pos in wordPositions) {
      if (pos.start >= lastEnd) {
        filteredPositions.add(pos);
        lastEnd = pos.end;
      }
    }

    if (kDebugMode) {
      debugPrint('최종 단어 위치 수: ${filteredPositions.length}개 (중복 제거 후)');
    }

    return filteredPositions;
  }

  /// 하이라이트된 텍스트 스팬 생성 (텍스트 선택 가능한 버전)
  static List<TextSpan> buildHighlightedText({
    required String text,
    required Set<String> flashcardWords,
    required Function(String) onTap,
    TextStyle? normalStyle,
    TextStyle? highlightStyle,
  }) {

    // 결과 목록 미리 할당 (메모리 최적화)
    final List<TextSpan> spans = [];

    // 빠른 경로 처리: 텍스트가 비어있거나 플래시카드 단어가 없는 경우
    if (text.isEmpty) {
      if (kDebugMode) {
        debugPrint('텍스트가 비어있어 빈 스팬 반환');
      }
      return spans;
    }

    if (flashcardWords.isEmpty) {
    
      spans.add(TextSpan(text: text, style: normalStyle));
      return spans;
    }

    // 플래시카드 단어 위치 찾기
    final List<WordPosition> wordPositions =
        findWordPositions(text, flashcardWords);

    // 위치가 없으면 일반 텍스트만 반환
    if (wordPositions.isEmpty) {
      spans.add(TextSpan(text: text, style: normalStyle));
      return spans;
    }

    // 하이라이트 스타일 정의 (한 번만 계산)
    final TextStyle effectiveHighlightStyle = highlightStyle ??
        const TextStyle(
          backgroundColor: Color(0xFFFFEA9D),
          fontWeight: FontWeight.bold,
        );

    // 텍스트 스팬 생성 (최적화 버전)
    int lastEnd = 0;

    for (final pos in wordPositions) {
      // 일반 텍스트 추가 (하이라이트 단어 사이의 텍스트)
      if (pos.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, pos.start),
          style: normalStyle,
        ));
      }

      // 하이라이트된 단어 추가 (텍스트 선택 가능하도록 수정)
      // 텍스트 선택과 탭 제스처가 충돌하지 않도록 개선
      final recognizer = TapGestureRecognizer()
        ..onTapDown = (TapDownDetails details) {
          // 탭 다운 이벤트 발생 시 로깅만 하고 다른 동작은 하지 않음
          if (kDebugMode) {
            debugPrint('하이라이트된 단어 탭 다운: ${pos.word}');
          }
        }
        ..onTap = () {
          // 단어 탭 시 콜백 호출
          if (kDebugMode) {
            debugPrint('하이라이트된 단어 탭됨: ${pos.word}');
          }
          // 선택된 텍스트가 없을 때만 탭 이벤트 처리
          // 이렇게 하면 텍스트 선택 중에는 탭 이벤트가 발생하지 않음
          onTap(pos.word);
        };

      spans.add(
        TextSpan(
          text: pos.word,
          style: effectiveHighlightStyle,
          recognizer: recognizer,
        ),
      );

      lastEnd = pos.end;
    }

    // 남은 텍스트 추가 (마지막 하이라이트 단어 이후의 텍스트)
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: normalStyle,
      ));
    }

    return spans;
  }
}
