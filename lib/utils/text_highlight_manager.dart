import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

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

  /// 하이라이트된 텍스트 스팬 생성 (최적화 버전)
  /// GestureRecognizer를 사용하지 않고 단순히 스타일만 적용하여 하이라이트 효과를 줍니다.
  static List<TextSpan> buildHighlightedText({
    required String text,
    required Set<String> flashcardWords,
    required Function(String) onTap, // 이 매개변수는 호환성을 위해 유지하지만 사용하지 않습니다.
    TextStyle? normalStyle,
    TextStyle? highlightStyle,
  }) {
    // 결과 목록 미리 할당 (메모리 최적화)
    final List<TextSpan> spans = [];

    if (kDebugMode) {
      debugPrint(
          'buildHighlightedText 호출: 텍스트 길이=${text.length}, 플래시카드 단어 수=${flashcardWords.length}');
      if (flashcardWords.isNotEmpty) {
        debugPrint('플래시카드 단어 목록: ${flashcardWords.take(5).join(', ')}');
      }
    }

    // 텍스트가 비어있으면 빈 스팬 반환
    if (text.isEmpty) {
      if (kDebugMode) {
        debugPrint('텍스트가 비어있어 빈 스팬 반환');
      }
      return spans;
    }

    // 플래시카드 단어가 없으면 일반 텍스트만 반환
    if (flashcardWords.isEmpty) {
      if (kDebugMode) {
        debugPrint('플래시카드 단어가 없어 일반 텍스트만 반환');
      }
      spans.add(TextSpan(text: text, style: normalStyle));
      return spans;
    }

    // 플래시카드 단어 위치 찾기
    final List<WordPosition> wordPositions =
        findWordPositions(text, flashcardWords);

    // 위치가 없으면 일반 텍스트만 반환 (최적화)
    if (wordPositions.isEmpty) {
      spans.add(TextSpan(text: text, style: normalStyle));
      return spans;
    }

    // 하이라이트 스타일 미리 정의 (재사용)
    final TextStyle highlightTextStyle = highlightStyle ??
        const TextStyle(
          backgroundColor: Colors.yellow,
          fontWeight: FontWeight.bold,
        );

    // 텍스트 스팬 생성
    int lastEnd = 0;
    for (final pos in wordPositions) {
      // 일반 텍스트 추가
      if (pos.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, pos.start),
          style: normalStyle,
        ));
      }

      // 하이라이트된 단어 추가 - 제스처 인식기 없이 스타일만 적용
      spans.add(
        TextSpan(
          text: pos.word,
          style: highlightTextStyle,
        ),
      );

      lastEnd = pos.end;
    }

    // 남은 텍스트 추가
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: normalStyle,
      ));
    }

    return spans;
  }
}
