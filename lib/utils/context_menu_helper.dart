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
    Function()? onLookupDictionary,
    Function()? onAddToFlashcard,
  }) {
    // 기본 메뉴 항목 가져오기
    final defaultButtonItems = editableTextState.contextMenuButtonItems;
    final List<ContextMenuButtonItem> buttonItems =
        List.from(defaultButtonItems);

    // 사전 검색 버튼 추가 (콜백이 제공된 경우)
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

    // 플래시카드 추가 버튼 (콜백이 제공된 경우)
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
    return RegExp(r'[\u4e00-\u9fa5]').hasMatch(text);
  }

  /// 선택된 텍스트가 사전에 있는지 확인합니다.
  static bool isWordInDictionary(String text) {
    final segmenterService = ChineseSegmenterService();
    return segmenterService.isWordInDictionary(text);
  }

  /// 컨텍스트 메뉴를 직접 표시합니다 (SelectableText 외부에서 사용)
  static void showContextMenu(
      BuildContext context, String selectedText, Offset position,
      {Function()? onLookupDictionary, Function()? onAddToFlashcard}) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 100, // 임의의 너비
        position.dy + 100, // 임의의 높이
      ),
      items: [
        PopupMenuItem(
          child: const Text('복사'),
          onTap: () {
            Clipboard.setData(ClipboardData(text: selectedText));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('복사되었습니다')),
            );
          },
        ),
        if (onLookupDictionary != null)
          PopupMenuItem(
            child: const Text('사전 검색'),
            onTap: onLookupDictionary,
          ),
        if (onAddToFlashcard != null)
          PopupMenuItem(
            child: const Text('플래시카드 추가'),
            onTap: onAddToFlashcard,
          ),
      ],
    );
  }
}
