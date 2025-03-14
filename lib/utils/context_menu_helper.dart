import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/chinese_segmenter_service.dart';
import '../services/tts_service.dart';
// SegmentedWord 클래스는 chinese_segmenter_service.dart 파일에 정의되어 있으므로 별도 import 필요 없음

/// **컨텍스트 메뉴 관련 공통 기능을 제공하는 유틸리티 클래스**
/// - 플래시카드가 추가된 단어: 기본 컨텍스트 메뉴 없이 바로 뜻을 표시
/// - 플래시카드가 없는 단어: 롱 프레스 시 커스텀 컨텍스트 메뉴 제공
class ContextMenuHelper {
  /// **커스텀 컨텍스트 메뉴를 생성하는 메서드**
  /// - `flashcardWords`에 포함된 단어는 기본 메뉴 없이 바로 뜻을 표시
  /// - 그 외 단어들은 커스텀 메뉴를 제공
  static Widget buildCustomContextMenu({
    required BuildContext context,
    required EditableTextState editableTextState,
    required String selectedText,
    required Set<String>? flashcardWords,
    Function(String)? onLookupDictionary,
    Function(String)? onAddToFlashcard,
  }) {
    debugPrint('==== ContextMenuHelper.buildCustomContextMenu 호출됨 ====');
    debugPrint('선택된 텍스트: "$selectedText"');
    debugPrint('플래시카드 단어 수: ${flashcardWords?.length ?? 0}');
    if (flashcardWords != null && flashcardWords.isNotEmpty) {
      debugPrint('플래시카드 단어 목록: ${flashcardWords.join(', ')}');
    }

    // 선택된 텍스트가 없으면 기본 메뉴 표시
    if (selectedText.isEmpty) {
      debugPrint('선택된 텍스트가 없어 기본 메뉴 표시');
      return AdaptiveTextSelectionToolbar.editableText(
        editableTextState: editableTextState,
      );
    }

    // ✅ 선택한 단어가 플래시카드에 포함된 경우 => 컨텍스트 메뉴 표시 및 사전 검색 실행
    bool isInFlashcards =
        flashcardWords != null && flashcardWords.contains(selectedText);
    debugPrint('선택된 텍스트가 플래시카드에 포함되어 있는지: $isInFlashcards');

    if (isInFlashcards) {
      debugPrint('플래시카드에 포함된 단어: $selectedText - 컨텍스트 메뉴 표시');

      // 플래시카드 단어용 컨텍스트 메뉴 표시
      final List<ContextMenuButtonItem> buttonItems = [];

      // 사전 검색 버튼
      buttonItems.add(
        ContextMenuButtonItem(
          onPressed: () {
            onLookupDictionary?.call(selectedText);
          },
          label: '사전 검색',
        ),
      );

      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: editableTextState.contextMenuAnchors,
        buttonItems: buttonItems,
      );
    }

    // ✅ 선택된 단어가 중국어인지 확인하여 추가 기능 제공
    bool containsChinese = _containsChineseCharacters(selectedText);
    debugPrint('중국어 포함 여부: $containsChinese');

    // 중국어가 아닌 경우 기본 컨텍스트 메뉴 표시
    if (!containsChinese) {
      return AdaptiveTextSelectionToolbar.editableText(
        editableTextState: editableTextState,
      );
    }

    // ✅ 커스텀 메뉴 항목 설정 (중국어인 경우만)
    final List<ContextMenuButtonItem> buttonItems = [];

    // 사전 검색 버튼
    buttonItems.add(
      ContextMenuButtonItem(
        onPressed: () {
          editableTextState.hideToolbar();
          onLookupDictionary?.call(selectedText);
        },
        label: '사전 검색',
      ),
    );

    // 플래시카드 추가 버튼 (이미 추가된 경우에는 표시하지 않음)
    if (!isInFlashcards) {
      buttonItems.add(
        ContextMenuButtonItem(
          onPressed: () {
            editableTextState.hideToolbar();
            onAddToFlashcard?.call(selectedText);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('플래시카드가 추가되었습니다.'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          label: '플래시카드 추가',
        ),
      );
    }

    debugPrint('커스텀 메뉴 항목 수: ${buttonItems.length}');
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  /// **기본 컨텍스트 메뉴 제공**
  /// - `enableCustomMenu`가 `false`이면 Flutter 기본 컨텍스트 메뉴를 반환
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

  /// **중국어 포함 여부 확인 함수**
  static bool _containsChineseCharacters(String text) {
    final RegExp chineseRegex = RegExp(r'[\u4e00-\u9fff]');
    return chineseRegex.hasMatch(text);
  }
}
