import 'package:flutter/material.dart';
import 'context_menu_helper.dart';

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
  }) {
    return SelectableText(
      text,
      style: style,
      contextMenuBuilder: (context, editableTextState) {
        return _buildContextMenu(
          context: context,
          editableTextState: editableTextState,
          onDictionaryLookup: onDictionaryLookup,
          onCreateFlashCard: onCreateFlashCard,
          translatedText: translatedText,
          flashcardWords: flashcardWords,
        );
      },
      enableInteractiveSelection: true,
      selectionControls: MaterialTextSelectionControls(),
      showCursor: true,
      cursorWidth: 2.0,
      cursorColor: Colors.blue,
    );
  }

  /// 컨텍스트 메뉴 빌더 메서드
  static Widget _buildContextMenu({
    required BuildContext context,
    required EditableTextState editableTextState,
    required Function(String) onDictionaryLookup,
    required Function(String, String, {String? pinyin}) onCreateFlashCard,
    required String translatedText,
    Set<String>? flashcardWords,
  }) {
    // 범위 체크 추가 - 방향에 관계없이 작동하도록 수정
    final TextSelection selection =
        editableTextState.textEditingValue.selection;
    final int start = selection.start;
    final int end = selection.end;

    if (start < 0 ||
        end < 0 ||
        start >= editableTextState.textEditingValue.text.length ||
        end > editableTextState.textEditingValue.text.length) {
      return const SizedBox.shrink();
    }

    String selectedText = '';
    try {
      selectedText =
          selection.textInside(editableTextState.textEditingValue.text);
    } catch (e) {
      debugPrint('텍스트 선택 오류: $e');
      return const SizedBox.shrink();
    }

    if (selectedText.isEmpty) {
      return const SizedBox.shrink();
    }

    // 선택한 단어가 플래시카드에 포함된 경우에도 커스텀 컨텍스트 메뉴 표시
    return ContextMenuHelper.buildCustomContextMenu(
      context: context,
      editableTextState: editableTextState,
      selectedText: selectedText,
      flashcardWords: flashcardWords,
      onLookupDictionary: onDictionaryLookup,
      onAddToFlashcard: (text) => onCreateFlashCard(text, translatedText),
    );
  }
}
