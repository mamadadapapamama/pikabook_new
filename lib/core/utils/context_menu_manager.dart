import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import 'text_highlight_manager.dart';

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

    // 선택된 텍스트가 이미 있는 경우, 이를 사용하여 컨텍스트 메뉴 생성
    if (selectedText.isNotEmpty) {
      if (kDebugMode) {
        debugPrint('이미 선택된 텍스트 사용: "$selectedText"');
      }

      // 플래시카드 단어와 정확히 일치하는 경우에는 사전 검색 실행
      bool isExactFlashcardWord = flashcardWords.contains(selectedText);
      if (isExactFlashcardWord) {
        if (kDebugMode) {
          debugPrint('플래시카드 단어와 정확히 일치: $selectedText - 사전 검색 실행');
        }
        // 사전 검색 실행
        if (onDictionaryLookup != null) {
          // 빌드 후에 실행되도록 Future.microtask 사용
          Future.microtask(() => onDictionaryLookup(selectedText));
        }
        return const SizedBox.shrink();
      }

      // 커스텀 컨텍스트 메뉴 표시
      return _buildCustomContextMenu(
        editableTextState: editableTextState,
        selectedText: selectedText,
        isExactFlashcardWord: isExactFlashcardWord,
        onDictionaryLookup: onDictionaryLookup,
        onCreateFlashCard: onCreateFlashCard,
      );
    }

    // 선택 범위가 -1인 경우 처리 (하이라이트된 텍스트에서 발생하는 문제)
    if (start == -1 || end == -1) {
      if (kDebugMode) {
        debugPrint('유효하지 않은 선택 범위 감지: $start-$end, 빈 메뉴 표시');
      }

      // 선택된 텍스트가 있으면 그것을 사용
      if (selectedText.isNotEmpty) {
        bool isExactFlashcardWord = flashcardWords.contains(selectedText);
        return _buildCustomContextMenu(
          editableTextState: editableTextState,
          selectedText: selectedText,
          isExactFlashcardWord: isExactFlashcardWord,
          onDictionaryLookup: onDictionaryLookup,
          onCreateFlashCard: onCreateFlashCard,
        );
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

      // 선택된 텍스트가 있으면 그것을 사용
      if (selectedText.isNotEmpty) {
        bool isExactFlashcardWord = flashcardWords.contains(selectedText);
        return _buildCustomContextMenu(
          editableTextState: editableTextState,
          selectedText: selectedText,
          isExactFlashcardWord: isExactFlashcardWord,
          onDictionaryLookup: onDictionaryLookup,
          onCreateFlashCard: onCreateFlashCard,
        );
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

      // 선택된 텍스트가 있으면 그것을 사용
      if (selectedText.isNotEmpty) {
        bool isExactFlashcardWord = flashcardWords.contains(selectedText);
        return _buildCustomContextMenu(
          editableTextState: editableTextState,
          selectedText: selectedText,
          isExactFlashcardWord: isExactFlashcardWord,
          onDictionaryLookup: onDictionaryLookup,
          onCreateFlashCard: onCreateFlashCard,
        );
      }

      // 기본 메뉴 대신 빈 컨테이너 반환
      return const SizedBox.shrink();
    }

    if (newSelectedText.isEmpty) {
      if (kDebugMode) {
        debugPrint('선택된 텍스트가 비어있음');
      }

      // 선택된 텍스트가 있으면 그것을 사용
      if (selectedText.isNotEmpty) {
        bool isExactFlashcardWord = flashcardWords.contains(selectedText);
        return _buildCustomContextMenu(
          editableTextState: editableTextState,
          selectedText: selectedText,
          isExactFlashcardWord: isExactFlashcardWord,
          onDictionaryLookup: onDictionaryLookup,
          onCreateFlashCard: onCreateFlashCard,
        );
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

    // 커스텀 컨텍스트 메뉴 생성
    return _buildCustomContextMenu(
      editableTextState: editableTextState,
      selectedText: newSelectedText,
      isExactFlashcardWord: isExactFlashcardWord,
      onDictionaryLookup: onDictionaryLookup,
      onCreateFlashCard: onCreateFlashCard,
    );
  }

  /// 커스텀 컨텍스트 메뉴 생성 메서드
  static Widget _buildCustomContextMenu({
    required EditableTextState editableTextState,
    required String selectedText,
    required bool isExactFlashcardWord,
    required Function(String)? onDictionaryLookup,
    required Function(String, String, {String? pinyin})? onCreateFlashCard,
  }) {
    // 선택한 단어가 플래시카드에 없는 경우 → 커스텀 컨텍스트 메뉴 표시
    final List<ContextMenuButtonItem> buttonItems = [];

    // 사전 검색 버튼
    buttonItems.add(
      ContextMenuButtonItem(
        onPressed: () {
          editableTextState.hideToolbar();
          if (onDictionaryLookup != null) {
            onDictionaryLookup(selectedText);
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
              onCreateFlashCard(selectedText, '', pinyin: null);
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

  /// 선택 가능한 텍스트 위젯 생성
  static Widget buildSelectableText(
    String text, {
    TextStyle? style,
    bool isOriginal = false,
    required Set<String> flashcardWords,
    required String selectedText,
    required ValueNotifier<String> selectedTextNotifier,
    required Function(String) onSelectionChanged,
    required Function(String)? onDictionaryLookup,
    required Function(String, String, {String? pinyin})? onCreateFlashCard,
  }) {
    // 텍스트가 비어있으면 빈 컨테이너 반환
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    if (kDebugMode) {
      debugPrint('buildSelectableText 호출: 텍스트 길이=${text.length}');
    }
    
    // 스타일이 제공되지 않은 경우 경고
    if (style == null) {
      debugPrint('경고: ContextMenuManager에 스타일이 제공되지 않았습니다.');
    }
    
    // 항상 제공된 스타일 사용
    final effectiveStyle = style;
    
    // 하이라이트된 텍스트 스팬 생성
    final textSpans = TextHighlightManager.buildHighlightedText(
      text: text,
      flashcardWords: flashcardWords,
      onTap: (word) {
        // 텍스트가 선택되어 있지 않을 때만 하이라이트된 단어 탭 처리
        if (selectedText.isEmpty) {
          TextHighlightManager.handleHighlightedWordTap(word, onDictionaryLookup);
        } else if (kDebugMode) {
          debugPrint('텍스트 선택 중에는 하이라이트된 단어 탭 무시: $word');
        }
      },
      normalStyle: effectiveStyle,
    );

    // ValueNotifier 업데이트
    selectedTextNotifier.value = selectedText;

    return ValueListenableBuilder<String>(
      valueListenable: selectedTextNotifier,
      builder: (context, currentSelectedText, child) {
        return TextSelectionTheme(
          data: TextSelectionThemeData(
            selectionColor: ColorTokens.primary.withOpacity(0.2),
            cursorColor: ColorTokens.primary,
            selectionHandleColor: ColorTokens.primary,
          ),
          child: SelectableText.rich(
            TextSpan(
              children: textSpans,
              style: effectiveStyle,
            ),
            contextMenuBuilder: (context, editableTextState) {
              return buildContextMenu(
                context: context,
                editableTextState: editableTextState,
                flashcardWords: flashcardWords,
                selectedText: currentSelectedText,
                onSelectionChanged: (text) {
                  // 상태 변경을 ValueNotifier를 통해 처리하고, 빌드 후에 콜백 호출
                  selectedTextNotifier.value = text;
                  Future.microtask(() {
                    onSelectionChanged(text);
                  });
                },
                onDictionaryLookup: onDictionaryLookup,
                onCreateFlashCard: onCreateFlashCard,
              );
            },
            enableInteractiveSelection: true,
            showCursor: true,
            cursorWidth: 2.0,
            cursorColor: ColorTokens.primary,
            onSelectionChanged: (selection, cause) {
              // 선택 변경 시 로깅
              if (kDebugMode) {
                debugPrint(
                    '선택 변경: ${selection.start}-${selection.end}, 원인: $cause');
              }

              // 선택이 취소된 경우 (빈 선택)
              if (selection.isCollapsed) {
                if (kDebugMode) {
                  debugPrint('선택 취소됨 (빈 선택)');
                }
                // 선택된 텍스트 초기화
                selectedTextNotifier.value = '';
                Future.microtask(() {
                  onSelectionChanged('');
                });
              } else {
                // 텍스트가 선택된 경우, 선택된 텍스트 추출
                try {
                  final newSelectedText =
                      text.substring(selection.start, selection.end);
                  if (newSelectedText.isNotEmpty && newSelectedText != currentSelectedText) {
                    if (kDebugMode) {
                      debugPrint('새로운 텍스트 선택됨: "$newSelectedText"');
                    }
                    // 선택된 텍스트 업데이트
                    selectedTextNotifier.value = newSelectedText;
                    Future.microtask(() {
                      onSelectionChanged(newSelectedText);
                    });
                  }
                } catch (e) {
                  if (kDebugMode) {
                    debugPrint('텍스트 선택 오류: $e');
                  }
                }
              }
            },
          ),
        );
      },
    );
  }
}
