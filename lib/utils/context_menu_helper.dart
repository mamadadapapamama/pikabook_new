import 'package:flutter/material.dart';
import 'context_menu_manager.dart';

/// **컨텍스트 메뉴 관련 공통 기능을 제공하는 유틸리티 클래스**
/// - 플래시카드가 추가된 단어: 기본 컨텍스트 메뉴 없이 바로 뜻을 표시
/// - 플래시카드가 없는 단어: 롱 프레스 시 커스텀 컨텍스트 메뉴 제공
///
/// @deprecated 이 클래스는 이전 코드와의 호환성을 위해 유지됩니다. 새로운 코드에서는 ContextMenuManager를 사용하세요.
class ContextMenuHelper {
  /// **커스텍스트 메뉴를 생성하는 메서드**
  /// - `flashcardWords`에 포함된 단어는 기본 메뉴 없이 바로 뜻을 표시
  /// - 그 외 단어들은 커스텀 메뉴를 제공
  ///
  /// @deprecated 이 메서드는 이전 코드와의 호환성을 위해 유지됩니다. 새로운 코드에서는 ContextMenuManager.buildContextMenu를 사용하세요.
  static Widget buildCustomContextMenu({
    required BuildContext context,
    required EditableTextState editableTextState,
    required String selectedText,
    required Set<String>? flashcardWords,
    Function(String)? onLookupDictionary,
    Function(String)? onAddToFlashcard,
  }) {
    debugPrint(
        '==== ContextMenuHelper.buildCustomContextMenu 호출됨 (deprecated) ====');

    // ContextMenuManager로 위임
    return ContextMenuManager.buildContextMenu(
      context: context,
      editableTextState: editableTextState,
      flashcardWords: flashcardWords ?? {},
      selectedText: selectedText,
      onSelectionChanged: (_) {}, // 선택 변경 콜백은 사용하지 않음
      onDictionaryLookup: onLookupDictionary ?? (_) {},
      onCreateFlashCard: (word, _, {String? pinyin}) {
        if (onAddToFlashcard != null) {
          onAddToFlashcard(word);
        }
      },
    );
  }

  /// **기본 컨텍스트 메뉴 제공**
  /// - `enableCustomMenu`가 `false`이면 Flutter 기본 컨텍스트 메뉴를 반환
  ///
  /// @deprecated 이 메서드는 이전 코드와의 호환성을 위해 유지됩니다. 새로운 코드에서는 ContextMenuManager를 사용하세요.
  static Widget buildDefaultContextMenu({
    required BuildContext context,
    required EditableTextState editableTextState,
    bool enableCustomMenu = true,
  }) {
    if (!enableCustomMenu) {
      return AdaptiveTextSelectionToolbar.editableText(
        editableTextState: editableTextState,
      );
    }
    return buildCustomContextMenu(
      context: context,
      editableTextState: editableTextState,
      selectedText: '',
      flashcardWords: null,
    );
  }
}
