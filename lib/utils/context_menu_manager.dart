import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
    if (kDebugMode) {
      debugPrint('buildContextMenu 호출됨');
    }

    // 범위 체크 추가 - 방향에 관계없이 작동하도록 수정
    final TextSelection selection =
        editableTextState.textEditingValue.selection;

    // 선택 범위 정규화 (시작과 끝 위치를 올바르게 정렬)
    int start = selection.start;
    int end = selection.end;

    // 선택 방향 확인 및 로깅
    final bool isReversed = selection.baseOffset > selection.extentOffset;
    if (kDebugMode) {
      debugPrint('선택 방향: ${isReversed ? '우-좌' : '좌-우'}');
    }

    // 선택 범위가 -1인 경우 처리 (하이라이트된 텍스트에서 발생하는 문제)
    if (start == -1 || end == -1) {
      if (kDebugMode) {
        debugPrint('유효하지 않은 선택 범위 감지: $start-$end, 빈 메뉴 표시');
      }
      // 기본 메뉴 대신 빈 컨테이너 반환
      return const SizedBox.shrink();
    }

    // 선택 범위 정규화 (시작이 끝보다 큰 경우 교환)
    if (start > end) {
      final temp = start;
      start = end;
      end = temp;
      if (kDebugMode) {
        debugPrint('선택 범위 정규화: $start-$end');
      }
    }

    if (kDebugMode) {
      debugPrint('선택 범위: $start-$end');
    }

    // 텍스트 길이 확인
    final int textLength = editableTextState.textEditingValue.text.length;

    // 범위 유효성 검사 (더 엄격하게)
    if (start < 0 ||
        end < 0 ||
        start >= textLength ||
        end > textLength ||
        start == end) {
      if (kDebugMode) {
        debugPrint('선택 범위가 유효하지 않음: $start-$end (텍스트 길이: $textLength)');
      }
      // 기본 메뉴 대신 빈 컨테이너 반환
      return const SizedBox.shrink();
    }

    String newSelectedText = '';
    String fullText = editableTextState.textEditingValue.text;
    try {
      // 정규화된 범위로 텍스트 추출
      newSelectedText = fullText.substring(start, end);
      if (kDebugMode) {
        debugPrint('선택된 텍스트: "$newSelectedText"');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('텍스트 선택 오류: $e');
      }
      // 기본 메뉴 대신 빈 컨테이너 반환
      return const SizedBox.shrink();
    }

    if (newSelectedText.isEmpty) {
      if (kDebugMode) {
        debugPrint('선택된 텍스트가 비어있음');
      }
      // 기본 메뉴 대신 빈 컨테이너 반환
      return const SizedBox.shrink();
    }

    // 플래시카드 단어와 정확히 일치하는 경우에는 사전 검색 실행
    bool isExactFlashcardWord = flashcardWords.contains(newSelectedText);
    if (isExactFlashcardWord) {
      if (kDebugMode) {
        debugPrint('플래시카드 단어와 정확히 일치: $newSelectedText - 사전 검색 실행');
      }
      // 사전 검색 실행
      if (onDictionaryLookup != null) {
        // 빌드 후에 실행되도록 Future.microtask 사용
        Future.microtask(() => onDictionaryLookup(newSelectedText));
      }
      return const SizedBox.shrink();
    }

    // 선택된 텍스트 업데이트 - 빌드 후에 실행되도록 Future.microtask 사용
    if (newSelectedText != selectedText) {
      Future.microtask(() => onSelectionChanged(newSelectedText));
    }

    if (kDebugMode) {
      debugPrint('커스텀 컨텍스트 메뉴 표시');
    }

    // 선택한 단어가 플래시카드에 없는 경우 → 커스텀 컨텍스트 메뉴 표시
    final List<ContextMenuButtonItem> buttonItems = [];

    // 사전 검색 버튼
    buttonItems.add(
      ContextMenuButtonItem(
        onPressed: () {
          editableTextState.hideToolbar();
          if (onDictionaryLookup != null) {
            onDictionaryLookup(newSelectedText);
          }
        },
        label: '사전 검색',
      ),
    );

    // 플래시카드 추가 버튼 (이미 추가된 경우에는 표시하지 않음)
    if (!isExactFlashcardWord) {
      buttonItems.add(
        ContextMenuButtonItem(
          onPressed: () {
            editableTextState.hideToolbar();
            if (onCreateFlashCard != null) {
              onCreateFlashCard(newSelectedText, '', pinyin: null);
            }
          },
          label: '플래시카드 추가',
        ),
      );
    }

    // 버튼이 없는 경우 빈 컨테이너 반환
    if (buttonItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }
}
