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
  final GlobalKey _textKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _flashcardWords = {};
    _extractFlashcardWords();
  }

  @override
  void didUpdateWidget(ProcessedTextWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 플래시카드 목록이 변경된 경우
    if (oldWidget.flashCards != widget.flashCards) {
      debugPrint('플래시카드 목록 변경 감지: didUpdateWidget');
      _extractFlashcardWords();
    }

    // 처리된 텍스트가 변경된 경우
    if (oldWidget.processedText != widget.processedText) {
      debugPrint('처리된 텍스트 변경 감지: didUpdateWidget');
      // 선택된 텍스트 초기화
      setState(() {
        _selectedText = '';
      });
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

    // 변경 사항이 있는 경우에만 setState 호출
    if (_flashcardWords.length != newFlashcardWords.length ||
        !_flashcardWords.containsAll(newFlashcardWords) ||
        !newFlashcardWords.containsAll(_flashcardWords)) {
      setState(() {
        _flashcardWords = newFlashcardWords;
      });

      debugPrint('플래시카드 단어 목록 업데이트: ${_flashcardWords.length}개');
      if (_flashcardWords.isNotEmpty) {
        debugPrint('첫 5개 단어: ${_flashcardWords.take(5).join(', ')}');
      }
    }
  }

  /// **문장에서 플래시카드 단어를 하이라이트하여 표시**
  List<TextSpan> _buildHighlightedText(String text) {
    List<TextSpan> spans = [];

    // 텍스트가 비어있으면 빈 스팬 반환
    if (text.isEmpty) {
      return spans;
    }

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
        // 단어 경계 확인 (단어 앞뒤에 중국어 문자가 없는 경우만 추가)
        bool isValidWordBoundary = true;

        // 단어 앞에 중국어 문자가 있는지 확인
        if (index > 0) {
          final char = text[index - 1];
          final RegExp chineseRegex = RegExp(r'[\u4e00-\u9fff]');
          if (chineseRegex.hasMatch(char)) {
            isValidWordBoundary = false;
          }
        }

        // 단어 뒤에 중국어 문자가 있는지 확인
        if (isValidWordBoundary && index + word.length < text.length) {
          final char = text[index + word.length];
          final RegExp chineseRegex = RegExp(r'[\u4e00-\u9fff]');
          if (chineseRegex.hasMatch(char)) {
            isValidWordBoundary = false;
          }
        }

        if (isValidWordBoundary) {
          wordPositions.add(_WordPosition(word, index, index + word.length));
        }

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

      // 하이라이트된 단어 추가 - 탭 가능하도록 수정
      spans.add(
        TextSpan(
          text: pos.word,
          style: const TextStyle(
            backgroundColor: Colors.yellow,
            fontWeight: FontWeight.bold,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              // 선택된 텍스트 초기화
              setState(() {
                _selectedText = '';
              });

              // 사전 검색 실행
              if (widget.onDictionaryLookup != null) {
                widget.onDictionaryLookup!(pos.word);
              }
            },
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
    // 텍스트가 비어있으면 빈 컨테이너 반환
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    // 선택 가능한 텍스트 위젯 생성
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
        final selectedText = text.substring(start, end);

        // 플래시카드 단어와 정확히 일치하는 경우에만 선택 취소
        bool shouldCancelSelection = false;

        for (final word in _flashcardWords) {
          // 선택된 텍스트가 플래시카드 단어와 정확히 일치하는 경우
          if (selectedText == word) {
            shouldCancelSelection = true;
            break;
          }
        }

        if (shouldCancelSelection) {
          // 선택 취소
          setState(() {
            _selectedText = '';
          });

          // 선택이 취소되었으므로 사전 검색 실행하지 않음
        } else {
          setState(() {
            _selectedText = selectedText;
          });
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

    // 플래시카드 단어와 정확히 일치하는 경우에만 컨텍스트 메뉴 숨김
    bool shouldHideContextMenu = false;

    for (final word in _flashcardWords) {
      // 선택된 텍스트가 플래시카드 단어와 정확히 일치하는 경우
      if (selectedText == word) {
        shouldHideContextMenu = true;
        break;
      }
    }

    if (shouldHideContextMenu) {
      return const SizedBox.shrink();
    }

    _selectedText = selectedText;

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
    // 세그먼트가 없으면 빈 컨테이너 반환
    if (widget.processedText.segments == null ||
        widget.processedText.segments!.isEmpty) {
      debugPrint('세그먼트가 없습니다.');

      // 세그먼트가 없으면 전체 텍스트 표시
      return _buildFullTextView();
    }

    debugPrint('세그먼트 수: ${widget.processedText.segments!.length}');

    // 세그먼트 목록을 위젯 목록으로 변환
    List<Widget> segmentWidgets = [];

    for (int i = 0; i < widget.processedText.segments!.length; i++) {
      final segment = widget.processedText.segments![i];

      // 디버깅 정보 출력
      debugPrint('세그먼트 $i 원본 텍스트: "${segment.originalText}"');
      debugPrint('세그먼트 $i 번역 텍스트: "${segment.translatedText}"');
      debugPrint('세그먼트 $i 핀인: "${segment.pinyin}"');

      // 원본 텍스트가 비어있으면 건너뜀
      if (segment.originalText.isEmpty) {
        debugPrint('세그먼트 $i 원본 텍스트가 비어있어 건너뜁니다.');
        continue;
      }

      // 세그먼트 위젯 생성
      segmentWidgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 16.0),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
            borderRadius: BorderRadius.circular(8.0),
          ),
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 세그먼트 번호 표시 (디버깅용)
              Text(
                '세그먼트 ${i + 1}',
                style: const TextStyle(
                  fontSize: 10.0,
                  color: Colors.grey,
                ),
              ),

              const SizedBox(height: 4.0),

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
                  padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
                  child: Text(
                    segment.translatedText!,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.blue,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // 세그먼트 위젯이 없으면 전체 텍스트 표시
    if (segmentWidgets.isEmpty) {
      debugPrint('세그먼트 위젯이 없어 전체 텍스트를 표시합니다.');
      return _buildFullTextView();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: segmentWidgets,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 디버깅 정보 출력
    debugPrint('ProcessedTextWidget.build 호출');
    debugPrint('showFullText: ${widget.processedText.showFullText}');
    debugPrint('segments 존재 여부: ${widget.processedText.segments != null}');
    if (widget.processedText.segments != null) {
      debugPrint('segments 개수: ${widget.processedText.segments!.length}');
    }
    debugPrint('fullOriginalText: "${widget.processedText.fullOriginalText}"');
    debugPrint(
        'fullTranslatedText: "${widget.processedText.fullTranslatedText}"');

    // 문장 바깥 탭 시 선택 취소를 위한 GestureDetector 추가
    return GestureDetector(
      onTap: () {
        // 문장 바깥을 탭하면 선택 취소
        setState(() {
          _selectedText = '';
        });
      },
      behavior: HitTestBehavior.translucent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 모드에 따라 다른 위젯 표시
          if (widget.processedText.segments != null &&
              !widget.processedText.showFullText)
            _buildSegmentedView()
          else
            _buildFullTextView(),

          // 디버깅용 모드 표시
          Container(
            margin: const EdgeInsets.only(top: 16.0),
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4.0),
            ),
            child: Text(
              widget.processedText.segments != null &&
                      !widget.processedText.showFullText
                  ? '세그먼트 모드'
                  : '전체 텍스트 모드',
              style: const TextStyle(
                fontSize: 12.0,
                color: Colors.grey,
              ),
            ),
          ),
        ],
      ),
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
