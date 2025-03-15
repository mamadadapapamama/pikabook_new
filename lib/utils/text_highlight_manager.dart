import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

/// 단어 위치 정보를 저장하는 클래스
class WordPosition {
  final String word;
  final int start;
  final int end;

  WordPosition(this.word, this.start, this.end);
}

/// 텍스트 하이라이트 관련 기능을 제공하는 유틸리티 클래스
/// 플래시카드 단어를 텍스트에서 찾아 하이라이트 처리하는 기능을 담당합니다.
class TextHighlightManager {
  /// 중국어 문자 포함 여부 확인
  static bool containsChineseCharacters(String text) {
    final RegExp chineseRegex = RegExp(r'[\u4e00-\u9fff]');
    return chineseRegex.hasMatch(text);
  }

  /// 공백 문자 확인
  static bool isWhitespace(String char) {
    return char.trim().isEmpty;
  }

  /// 구두점 확인
  static bool isPunctuation(String char) {
    final RegExp punctuationRegex =
        RegExp(r'[，。！？：；""' '（）【】《》、,.!?:;\'"()[\]{}]');
    return punctuationRegex.hasMatch(char);
  }

  /// 단어 경계 확인
  static bool isValidWordBoundary(String text, int index, String word) {
    bool isValidWordBoundary = true;
    bool isChinese = containsChineseCharacters(word);

    if (!isChinese) {
      // 단어 앞에 문자가 있는지 확인
      if (index > 0) {
        final char = text[index - 1];
        if (!isWhitespace(char) && !isPunctuation(char)) {
          isValidWordBoundary = false;
        }
      }

      // 단어 뒤에 문자가 있는지 확인
      if (isValidWordBoundary && index + word.length < text.length) {
        final char = text[index + word.length];
        if (!isWhitespace(char) && !isPunctuation(char)) {
          isValidWordBoundary = false;
        }
      }
    }

    return isValidWordBoundary;
  }

  /// 텍스트에서 단어 위치 찾기
  static List<WordPosition> findWordPositions(String text, Set<String> words) {
    if (text.isEmpty || words.isEmpty) {
      return [];
    }

    List<WordPosition> wordPositions = [];

    // 단어를 길이 기준으로 내림차순 정렬 (긴 단어부터 검색)
    final sortedWords = words.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final word in sortedWords) {
      if (word.isEmpty) continue;

      debugPrint('단어 검색: "$word" (길이: ${word.length})');

      // 중국어 단어인지 확인
      bool isChinese = containsChineseCharacters(word);

      int index = 0;
      int count = 0;
      while ((index = text.indexOf(word, index)) != -1) {
        // 단어 경계 확인 (중국어가 아닌 경우만)
        bool isValidBoundary = true;

        if (!isChinese) {
          // 단어 앞에 문자가 있는지 확인
          if (index > 0) {
            final char = text[index - 1];
            if (!isWhitespace(char) && !isPunctuation(char)) {
              isValidBoundary = false;
            }
          }

          // 단어 뒤에 문자가 있는지 확인
          if (isValidBoundary && index + word.length < text.length) {
            final char = text[index + word.length];
            if (!isWhitespace(char) && !isPunctuation(char)) {
              isValidBoundary = false;
            }
          }
        }

        if (isValidBoundary) {
          wordPositions.add(WordPosition(word, index, index + word.length));
          count++;
          debugPrint('  위치 발견: $index-${index + word.length}');
        }

        index += 1; // 다음 검색 위치로 이동
      }

      debugPrint('  찾은 위치 수: $count개');
    }

    // 위치에 따라 정렬
    wordPositions.sort((a, b) => a.start.compareTo(b.start));

    // 겹치는 위치 제거
    List<WordPosition> filteredPositions = [];
    for (var pos in wordPositions) {
      bool overlaps = false;
      for (var existing in filteredPositions) {
        if (pos.start < existing.end && pos.end > existing.start) {
          overlaps = true;
          break;
        }
      }
      if (!overlaps) {
        filteredPositions.add(pos);
      }
    }

    debugPrint('최종 단어 위치 수: ${filteredPositions.length}개 (중복 제거 후)');
    return filteredPositions;
  }

  /// 하이라이트된 텍스트 스팬 생성
  static List<TextSpan> buildHighlightedText({
    required String text,
    required Set<String> flashcardWords,
    required Function(String) onTap,
    TextStyle? normalStyle,
    TextStyle? highlightStyle,
  }) {
    List<TextSpan> spans = [];

    // 디버깅 정보 출력
    debugPrint(
        'buildHighlightedText 호출: 텍스트 길이=${text.length}, 플래시카드 단어 수=${flashcardWords.length}');
    if (flashcardWords.isNotEmpty) {
      debugPrint('플래시카드 단어 목록: ${flashcardWords.take(5).join(', ')}');
    }

    // 텍스트가 비어있으면 빈 스팬 반환
    if (text.isEmpty) {
      debugPrint('텍스트가 비어있어 빈 스팬 반환');
      return spans;
    }

    // 플래시카드 단어가 없으면 일반 텍스트만 반환
    if (flashcardWords.isEmpty) {
      debugPrint('플래시카드 단어가 없어 일반 텍스트만 반환');
      spans.add(TextSpan(text: text, style: normalStyle));
      return spans;
    }

    // 플래시카드 단어 위치 찾기
    List<WordPosition> wordPositions = findWordPositions(text, flashcardWords);

    // 텍스트 스팬 생성
    int lastEnd = 0;
    for (var pos in wordPositions) {
      // 일반 텍스트 추가
      if (pos.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, pos.start),
          style: normalStyle,
        ));
      }

      // 하이라이트된 단어 추가 - 탭 가능하도록 설정
      spans.add(
        TextSpan(
          text: pos.word,
          style: highlightStyle ??
              const TextStyle(
                backgroundColor: Colors.yellow,
                fontWeight: FontWeight.bold,
              ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              debugPrint('하이라이트된 단어 탭됨: ${pos.word}');
              onTap(pos.word);
            },
          // 선택 불가능하게 설정 (중요)
          mouseCursor: SystemMouseCursors.click,
          semanticsLabel: 'flashcard:${pos.word}',
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
