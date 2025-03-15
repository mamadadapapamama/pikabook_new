import 'package:flutter/material.dart';
import 'context_menu_manager.dart';
import 'text_highlight_manager.dart';

/// 텍스트 선택 관련 공통 기능을 제공하는 유틸리티 클래스
class TextSelectionHelper {
  /// 선택 가능한 텍스트 위젯 생성
  static Widget buildSelectableText({
    required String text,
    required TextStyle style,
    required Function(String) onDictionaryLookup,
    required Function(String, String, {String? pinyin}) onCreateFlashCard,
    required String translatedText,
    Set<String>? flashcardWords,
    Function(String)? onWordTap,
  }) {
    // 플래시카드 단어 목록이 null인 경우 빈 Set으로 초기화
    final Set<String> words = flashcardWords ?? {};

    // 하이라이트된 텍스트 스팬 생성
    final textSpans = TextHighlightManager.buildHighlightedText(
      text: text,
      flashcardWords: words,
      onTap: (word) {
        if (onWordTap != null) {
          onWordTap(word);
        } else {
          onDictionaryLookup(word);
        }
      },
      normalStyle: style,
    );

    // 선택된 텍스트 상태 관리를 위한 변수
    String selectedText = '';

    return SelectableText.rich(
      TextSpan(
        children: textSpans,
        style: style,
      ),
      contextMenuBuilder: (context, editableTextState) {
        return ContextMenuManager.buildContextMenu(
          context: context,
          editableTextState: editableTextState,
          flashcardWords: words,
          selectedText: selectedText,
          onSelectionChanged: (text) {
            selectedText = text;
          },
          onDictionaryLookup: onDictionaryLookup,
          onCreateFlashCard: (word, meaning, {String? pinyin}) {
            onCreateFlashCard(word, translatedText, pinyin: pinyin);
          },
        );
      },
      enableInteractiveSelection: true,
      showCursor: true,
      cursorWidth: 2.0,
      cursorColor: Colors.blue,
    );
  }
}
