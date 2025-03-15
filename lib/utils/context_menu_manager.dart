import 'package:flutter/material.dart';
import 'context_menu_helper.dart';

/// 텍스트 컨텍스트 메뉴 관련 기능을 제공하는 유틸리티 클래스
/// 텍스트 선택 시 표시되는 컨텍스트 메뉴를 관리합니다.
class ContextMenuManager {
  /// 컨텍스트 메뉴 빌더 메서드
  static Widget buildContextMenu({
    required BuildContext context,
    required EditableTextState editableTextState,
    required Set<String> flashcardWords,
    required String selectedText,
    required Function(String) onSelectionChanged,
    required Function(String)? onDictionaryLookup,
    required Function(String, String, {String? pinyin})? onCreateFlashCard,
  }) {
    debugPrint('buildContextMenu 호출됨');

    // 범위 체크 추가 - 방향에 관계없이 작동하도록 수정
    final TextSelection selection =
        editableTextState.textEditingValue.selection;
    final int start = selection.start;
    final int end = selection.end;

    debugPrint('선택 범위: $start-$end');

    if (start < 0 ||
        end < 0 ||
        start >= editableTextState.textEditingValue.text.length ||
        end > editableTextState.textEditingValue.text.length) {
      debugPrint('선택 범위가 유효하지 않음');
      return AdaptiveTextSelectionToolbar.editableText(
        editableTextState: editableTextState,
      );
    }

    String newSelectedText = '';
    String fullText = editableTextState.textEditingValue.text;
    try {
      newSelectedText = selection.textInside(fullText);
      debugPrint('선택된 텍스트: "$newSelectedText"');
    } catch (e) {
      debugPrint('텍스트 선택 오류: $e');
      return AdaptiveTextSelectionToolbar.editableText(
        editableTextState: editableTextState,
      );
    }

    if (newSelectedText.isEmpty) {
      debugPrint('선택된 텍스트가 비어있음');
      return AdaptiveTextSelectionToolbar.editableText(
        editableTextState: editableTextState,
      );
    }

    // 플래시카드 단어와 정확히 일치하는 경우에는 사전 검색 실행
    bool isExactFlashcardWord = flashcardWords.contains(newSelectedText);
    if (isExactFlashcardWord) {
      debugPrint('플래시카드 단어와 정확히 일치: $newSelectedText - 사전 검색 실행');
      // 사전 검색 실행
      if (onDictionaryLookup != null) {
        onDictionaryLookup(newSelectedText);
      }
      return const SizedBox.shrink();
    }

    // 선택된 텍스트 업데이트
    onSelectionChanged(newSelectedText);
    debugPrint('커스텀 컨텍스트 메뉴 표시');

    // 선택한 단어가 플래시카드에 없는 경우 → 커스텀 컨텍스트 메뉴 표시
    return ContextMenuHelper.buildCustomContextMenu(
      context: context,
      editableTextState: editableTextState,
      selectedText: newSelectedText,
      flashcardWords: flashcardWords,
      onLookupDictionary: (String text) {
        if (newSelectedText.isNotEmpty && onDictionaryLookup != null) {
          onDictionaryLookup(newSelectedText);
        }
      },
      onAddToFlashcard: (String text) {
        if (newSelectedText.isNotEmpty && onCreateFlashCard != null) {
          onCreateFlashCard(newSelectedText, '', pinyin: null);
          // 플래시카드 단어 목록에 추가는 호출자가 처리해야 함
        }
      },
    );
  }
}
