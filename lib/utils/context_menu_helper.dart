import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/chinese_segmenter_service.dart';
// SegmentedWord 클래스는 chinese_segmenter_service.dart 파일에 정의되어 있으므로 별도 import 필요 없음

/// 컨텍스트 메뉴 관련 공통 기능을 제공하는 유틸리티 클래스
class ContextMenuHelper {
  /// 커스텀 컨텍스트 메뉴를 생성합니다.
  static Widget buildCustomContextMenu({
    required BuildContext context,
    required EditableTextState editableTextState,
    required String selectedText,
    required Set<String>? flashcardWords,
    Function()? onLookupDictionary,
    Function()? onAddToFlashcard,
  }) {
    // 디버그 로그 추가
    debugPrint('ContextMenuHelper: 커스텀 메뉴 생성 - 선택된 텍스트: "$selectedText"');
    debugPrint('ContextMenuHelper: 플래시카드 단어 수: ${flashcardWords?.length ?? 0}');

    // ✅ 선택한 단어가 플래시카드에 포함된 경우 => 기본 컨텍스트 메뉴 없이 "탭 하면 뜻이 바로 표시됨"
    if (flashcardWords != null && flashcardWords.contains(selectedText)) {
      debugPrint('ContextMenuHelper: 플래시카드에 포함된 단어 - 컨텍스트 메뉴 표시하지 않음');
      return const SizedBox.shrink(); // 기본 컨텍스트 메뉴를 띄우지 않음
    }

    // ✅ 선택한 단어가 플래시카드에 포함되지 않은 경우, 커스텀 메뉴 제공
    debugPrint('ContextMenuHelper: 커스텀 컨텍스트 메뉴 표시');

    final List<ContextMenuButtonItem> buttonItems = [];

    // 복사 버튼
    buttonItems.add(
      ContextMenuButtonItem(
        onPressed: () {
          Clipboard.setData(ClipboardData(text: selectedText));
          editableTextState.hideToolbar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('복사되었습니다'), duration: Duration(seconds: 1)),
          );
        },
        label: '복사',
      ),
    );

    // 전체 선택 버튼
    buttonItems.add(
      ContextMenuButtonItem(
        onPressed: () {
          editableTextState.selectAll(SelectionChangedCause.toolbar);
        },
        label: '전체 선택',
      ),
    );

    // 사전 검색 버튼
    if (onLookupDictionary != null) {
      buttonItems.add(
        ContextMenuButtonItem(
          onPressed: () {
            editableTextState.hideToolbar();
            onLookupDictionary();
          },
          label: '사전 검색',
        ),
      );
    }

    // 플래시카드 추가 버튼
    if (onAddToFlashcard != null) {
      buttonItems.add(
        ContextMenuButtonItem(
          onPressed: () {
            editableTextState.hideToolbar();
            onAddToFlashcard();
          },
          label: '플래시카드 추가',
        ),
      );
    }

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  /// 선택된 텍스트가 중국어 문자를 포함하는지 확인합니다.
  static bool containsChineseCharacters(String text) {
    // 디버그 로그 추가
    debugPrint('중국어 문자 감지 검사: "$text"');

    // 중국어 문자 범위 (CJK Unified Ideographs)
    final bool hasChinese = RegExp(r'[\u4e00-\u9fff]').hasMatch(text);

    // 결과 로깅
    debugPrint('중국어 문자 감지 결과: $hasChinese');

    return hasChinese;
  }

  /// 선택된 텍스트가 사전에 있는지 확인합니다.
  static bool isWordInDictionary(String text) {
    final segmenterService = ChineseSegmenterService();
    return segmenterService.isWordInDictionary(text);
  }

  /// 컨텍스트 메뉴를 직접 표시합니다 (SelectableText 외부에서 사용)
  static void showContextMenu(
      BuildContext context, String selectedText, Offset position,
      {Set<String>? flashcardWords,
      Function()? onLookupDictionary,
      Function()? onAddToFlashcard}) {
    // 선택한 단어가 플래시카드에 포함된 경우 확인
    bool isInFlashcard =
        flashcardWords != null && flashcardWords.contains(selectedText);

    // 플래시카드에 이미 있는 단어는 컨텍스트 메뉴를 표시하지 않음
    if (isInFlashcard) {
      debugPrint('ContextMenuHelper: 플래시카드에 포함된 단어 - 팝업 메뉴 표시하지 않음');
      return;
    }

    final List<PopupMenuEntry<String>> menuItems = [];

    // 복사 항목
    menuItems.add(
      PopupMenuItem(
        value: 'copy',
        child: const Text('복사'),
        onTap: () {
          Clipboard.setData(ClipboardData(text: selectedText));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('복사되었습니다')),
          );
        },
      ),
    );

    // 사전 검색 항목
    if (onLookupDictionary != null) {
      menuItems.add(
        PopupMenuItem(
          value: 'dictionary',
          child: const Text('사전 검색'),
          onTap: onLookupDictionary,
        ),
      );
    }

    // 플래시카드 추가 항목
    if (onAddToFlashcard != null) {
      menuItems.add(
        PopupMenuItem(
          value: 'flashcard',
          child: const Text('플래시카드 추가'),
          onTap: onAddToFlashcard,
        ),
      );
    }

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 100, // 임의의 너비
        position.dy + 100, // 임의의 높이
      ),
      items: menuItems,
    );
  }
}
