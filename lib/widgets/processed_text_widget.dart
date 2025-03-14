import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../models/processed_text.dart';
import '../models/flash_card.dart';
import '../utils/context_menu_helper.dart';
import '../utils/text_selection_helper.dart';

/// 페이지의 텍스트 프로세싱(OCR, 번역, pinyin, highlight)이 완료되면, 텍스트 처리 결과를 표시하는 위젯

class ProcessedTextWidget extends StatefulWidget {
  final ProcessedText processedText;
  final bool showTranslation;
  final Function(String)? onDictionaryLookup;
  final Function(String, String, {String? pinyin})? onCreateFlashCard;
  final List<FlashCard>? flashCards;

  const ProcessedTextWidget({
    Key? key,
    required this.processedText,
    this.showTranslation = true,
    this.onDictionaryLookup,
    this.onCreateFlashCard,
    this.flashCards,
  }) : super(key: key);

  @override
  State<ProcessedTextWidget> createState() => _ProcessedTextWidgetState();
}

class _ProcessedTextWidgetState extends State<ProcessedTextWidget> {
  String _selectedText = '';
  late Set<String> _flashcardWords;

  @override
  void initState() {
    super.initState();
    _flashcardWords = {};
    _extractFlashcardWords();
  }

  @override
  void didUpdateWidget(ProcessedTextWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flashCards != widget.flashCards) {
      _extractFlashcardWords();
    }
  }

  /// **플래시카드 단어 목록 추출**
  void _extractFlashcardWords() {
    final Set<String> newFlashcardWords = {};
    if (widget.flashCards != null) {
      for (final card in widget.flashCards!) {
        if (card.front.isNotEmpty) {
          newFlashcardWords.add(card.front);
        }
      }
    }
    setState(() {
      _flashcardWords = newFlashcardWords;
    });

    // 플래시카드 목록이 변경되면 화면을 강제로 다시 그림
    if (mounted) {
      setState(() {});
    }
  }

  /// **문장에서 플래시카드 단어를 하이라이트하여 표시**
  List<TextSpan> _buildHighlightedText(String text) {
    List<TextSpan> spans = [];
    int currentIndex = 0;

    // 플래시카드 단어가 없으면 일반 텍스트만 반환
    if (_flashcardWords.isEmpty) {
      spans.add(TextSpan(text: text));
      return spans;
    }

    // 플래시카드 단어 위치 찾기
    List<_WordPosition> wordPositions = [];
    for (final word in _flashcardWords) {
      if (word.isEmpty) continue;

      int index = 0;
      while ((index = text.indexOf(word, index)) != -1) {
        wordPositions.add(_WordPosition(word, index, index + word.length));
        index += word.length;
      }
    }

    // 위치에 따라 정렬
    wordPositions.sort((a, b) => a.start.compareTo(b.start));

    // 겹치는 위치 제거
    List<_WordPosition> filteredPositions = [];
    for (var pos in wordPositions) {
      bool overlaps = false;
      for (var existing in filteredPositions) {
        if (pos.start < existing.end && pos.end > existing.start) {
          overlaps = true;
          break;
        }
      }
      if (!overlaps) {
        filteredPositions.add(pos);
      }
    }

    // 텍스트 스팬 생성
    int lastEnd = 0;
    for (var pos in filteredPositions) {
      // 일반 텍스트 추가
      if (pos.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, pos.start)));
      }

      // 하이라이트된 단어 추가 - 선택 가능하도록 수정
      spans.add(
        TextSpan(
          text: pos.word,
          style: const TextStyle(
            backgroundColor: Colors.yellow,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

      lastEnd = pos.end;
    }

    // 남은 텍스트 추가
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return spans;
  }

  /// **선택 가능한 텍스트 위젯 생성**
  Widget _buildSelectableText(String text) {
    return SelectableText.rich(
      TextSpan(
        children: _buildHighlightedText(text),
        style: const TextStyle(fontSize: 16),
      ),
      onSelectionChanged: (selection, cause) {
        _handleSelectionChanged(selection, text);
      },
      contextMenuBuilder: _buildContextMenu,
      enableInteractiveSelection: true,
      showCursor: true,
      cursorWidth: 2.0,
      cursorColor: Colors.blue,
    );
  }

  /// **텍스트 선택 변경 처리 메서드**
  void _handleSelectionChanged(TextSelection selection, String text) {
    if (selection.baseOffset != selection.extentOffset) {
      // 범위 체크 추가 - 방향에 관계없이 작동하도록 수정
      final int start = selection.start;
      final int end = selection.end;

      if (start >= 0 && end >= 0 && start < text.length && end <= text.length) {
        setState(() {
          _selectedText = text.substring(start, end);
        });

        // 선택한 텍스트가 플래시카드 단어인지 확인
        if (_flashcardWords.contains(_selectedText)) {
          // 플래시카드 단어인 경우 사전 검색 실행
          widget.onDictionaryLookup?.call(_selectedText);
        }
      }
    }
  }

  /// **컨텍스트 메뉴 빌더 메서드**
  Widget _buildContextMenu(
      BuildContext context, EditableTextState editableTextState) {
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

    _selectedText = selectedText;

    // 선택한 단어가 플래시카드에 포함된 경우 → 컨텍스트 메뉴만 표시
    if (_flashcardWords.contains(_selectedText)) {
      // 컨텍스트 메뉴 표시
      return ContextMenuHelper.buildCustomContextMenu(
        context: context,
        editableTextState: editableTextState,
        selectedText: _selectedText,
        flashcardWords: _flashcardWords,
        onLookupDictionary: (String text) {
          widget.onDictionaryLookup?.call(text);
        },
        onAddToFlashcard: (String text) {
          // 이미 플래시카드에 있으므로 추가 기능은 제공하지 않음
        },
      );
    }

    // 선택한 단어가 플래시카드에 없는 경우 → 커스텀 컨텍스트 메뉴 표시
    return ContextMenuHelper.buildCustomContextMenu(
      context: context,
      editableTextState: editableTextState,
      selectedText: _selectedText,
      flashcardWords: _flashcardWords,
      onLookupDictionary: (String text) {
        if (_selectedText.isNotEmpty) {
          widget.onDictionaryLookup?.call(_selectedText);
        }
      },
      onAddToFlashcard: (String text) {
        if (_selectedText.isNotEmpty) {
          widget.onCreateFlashCard?.call(_selectedText, '', pinyin: null);
          setState(() {
            _flashcardWords.add(_selectedText);
          });
        }
      },
    );
  }

  /// **전체 텍스트 표시 위젯**
  Widget _buildFullTextView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 원본 텍스트 표시
        _buildSelectableText(widget.processedText.fullOriginalText),

        // 번역 텍스트 표시 (showTranslation이 true이고 번역 텍스트가 있는 경우)
        if (widget.showTranslation &&
            widget.processedText.fullTranslatedText != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              widget.processedText.fullTranslatedText!,
              style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
            ),
          ),
      ],
    );
  }

  /// **세그먼트별 텍스트 표시 위젯**
  Widget _buildSegmentedView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.processedText.segments!.map((segment) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 원본 텍스트 표시
            _buildSelectableText(segment.originalText),

            // 핀인 표시
            if (segment.pinyin != null && segment.pinyin!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
                child: Text(
                  segment.pinyin!,
                  style: const TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                  ),
                ),
              ),

            // 번역 텍스트 표시
            if (widget.showTranslation && segment.translatedText != null)
              Padding(
                padding: const EdgeInsets.only(top: 4.0, bottom: 12.0),
                child: Text(
                  segment.translatedText!,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.blue,
                  ),
                ),
              ),

            const SizedBox(height: 8),
          ],
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 문장 바깥 탭 시 선택 취소를 위한 GestureDetector 추가
    return GestureDetector(
      onTap: () {
        // 문장 바깥을 탭하면 선택 취소
        setState(() {
          _selectedText = '';
        });
      },
      behavior: HitTestBehavior.translucent,
      child: widget.processedText.segments != null &&
              !widget.processedText.showFullText
          ? _buildSegmentedView()
          : _buildFullTextView(),
    );
  }
}

/// **단어 위치 정보를 저장하는 클래스**
class _WordPosition {
  final String word;
  final int start;
  final int end;

  _WordPosition(this.word, this.start, this.end);
}
