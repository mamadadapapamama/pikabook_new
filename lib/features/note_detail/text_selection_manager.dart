import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../core/utils/text_highlight_manager.dart';
import '../../core/theme/tokens/color_tokens.dart';

/// 텍스트 선택과 하이라이팅을 관리하는 클래스
/// 컨텍스트 메뉴 기능을 포함하여 텍스트 선택 관련 모든 기능을 통합 관리합니다.
class TextSelectionManager {
  final Set<String> flashcardWords;
  final Function(String)? onDictionaryLookup;
  final Function(String, String, {String? pinyin})? onCreateFlashCard;
  final ValueNotifier<String> selectedTextNotifier = ValueNotifier<String>('');
  
  // 중복 사전 검색 방지를 위한 변수
  bool _isProcessingDictionaryLookup = false;

  TextSelectionManager({
    required this.flashcardWords,
    this.onDictionaryLookup,
    this.onCreateFlashCard,
  });

  /// 하이라이트된 텍스트 생성 메서드
  Widget buildSelectableText(
    String text, {
    TextStyle? style,
    bool isOriginal = false,
    BuildContext? context,
  }) {
    // 텍스트가 비어있으면 빈 컨테이너 반환
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // 스타일이 제공되지 않은 경우 경고
    if (style == null && kDebugMode) {
      debugPrint('경고: TextSelectionManager에 스타일이 제공되지 않았습니다.');
    }
    
    // 하이라이트된 텍스트 스팬 생성
    final textSpans = TextHighlightManager.buildHighlightedText(
      text: text,
      flashcardWords: flashcardWords,
      onTap: (word) {
        // 텍스트가 선택되어 있지 않을 때만 하이라이트된 단어 탭 처리
        if (selectedTextNotifier.value.isEmpty) {
          _handleHighlightedWordTap(word);
        }
      },
      normalStyle: style,
    );

    return ValueListenableBuilder<String>(
      valueListenable: selectedTextNotifier,
      builder: (context, selectedText, child) {
        return SelectableText.rich(
          TextSpan(
            children: textSpans,
            style: style,
          ),
          contextMenuBuilder: (context, editableTextState) {
            return buildContextMenu(
              context: context,
              editableTextState: editableTextState,
              selectedText: selectedText,
            );
          },
          enableInteractiveSelection: true,
          showCursor: true,
          cursorWidth: 2.0,
          cursorColor: ColorTokens.primary,
          onSelectionChanged: (selection, cause) {
            // 선택이 취소된 경우 (빈 선택)
            if (selection.isCollapsed) {
              selectedTextNotifier.value = '';
            } else {
              // 텍스트가 선택된 경우, 선택된 텍스트 추출
              try {
                final selectedText = text.substring(selection.start, selection.end);
                if (selectedText.isNotEmpty && selectedText != selectedTextNotifier.value) {
                  selectedTextNotifier.value = selectedText;
                }
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('텍스트 선택 오류: $e');
                }
              }
            }
          },
        );
      },
    );
  }

  /// 컨텍스트 메뉴 빌드 메서드
  /// 외부에서 호환성을 위해 접근 가능
  Widget buildContextMenu({
    required BuildContext context,
    required EditableTextState editableTextState,
    required String selectedText,
  }) {
    if (selectedText.isEmpty) {
      return const SizedBox.shrink();
    }

    // 플래시카드 단어와 정확히 일치하는 경우에는 사전 검색 실행
    bool isExactFlashcardWord = flashcardWords.contains(selectedText);
    if (isExactFlashcardWord && onDictionaryLookup != null) {
      // 사전 검색 콜백을 마이크로태스크로 예약
      Future.microtask(() => onDictionaryLookup!(selectedText));
      return const SizedBox.shrink();
    }

    // 커스텀 컨텍스트 메뉴 버튼 아이템
    List<ContextMenuButtonItem> buttonItems = [];

    // 사전 검색 버튼
    buttonItems.add(
      ContextMenuButtonItem(
        onPressed: () {
          editableTextState.hideToolbar();
          if (onDictionaryLookup != null) {
            onDictionaryLookup!(selectedText);
          }
        },
        label: '사전 검색',
      ),
    );

    // 플래시카드 추가 버튼 (이미 추가된 경우에는 표시하지 않음)
    if (!isExactFlashcardWord && onCreateFlashCard != null) {
      buttonItems.add(
        ContextMenuButtonItem(
          onPressed: () {
            editableTextState.hideToolbar();
            onCreateFlashCard!(selectedText, '', pinyin: null);
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

  /// 하이라이트된 단어 탭 처리
  void _handleHighlightedWordTap(String word) {
    if (_isProcessingDictionaryLookup) return;

    // 중복 호출 방지
    _isProcessingDictionaryLookup = true;

    // 사전 검색 콜백 호출
    if (onDictionaryLookup != null) {
      onDictionaryLookup!(word);
    }

    // 일정 시간 후 플래그 초기화 (중복 호출 방지)
    Future.delayed(const Duration(milliseconds: 500), () {
      _isProcessingDictionaryLookup = false;
    });
  }

  /// 선택 초기화
  void clearSelection() {
    selectedTextNotifier.value = '';
  }
  
  /// 자원 해제
  void dispose() {
    selectedTextNotifier.dispose();
  }
} 