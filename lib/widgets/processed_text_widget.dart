import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../models/processed_text.dart';
import '../models/text_segment.dart';
import '../models/flash_card.dart';
import 'text_segment_widget.dart';
import 'segmented_text_widget.dart';
import '../services/chinese_segmenter_service.dart';

/// 처리된 텍스트 표시 위젯
/// 전체 텍스트와 세그먼트별 표시를 전환할 수 있습니다.
class ProcessedTextWidget extends StatefulWidget {
  /// 처리된 텍스트 데이터
  final ProcessedText processedText;

  /// TTS 버튼 클릭 시 콜백
  final Function(String)? onTts;

  /// 사전 검색 시 콜백
  final Function(String)? onDictionaryLookup;

  /// 플래시카드 생성 시 콜백
  final Function(String, String, {String? pinyin})? onCreateFlashCard;

  /// 플래시카드 목록 (하이라이트 표시용)
  final List<FlashCard>? flashCards;

  /// 노트 ID
  final String? noteId;

  const ProcessedTextWidget({
    Key? key,
    required this.processedText,
    this.onTts,
    this.onDictionaryLookup,
    this.onCreateFlashCard,
    this.flashCards,
    this.noteId,
  }) : super(key: key);

  @override
  State<ProcessedTextWidget> createState() => _ProcessedTextWidgetState();
}

class _ProcessedTextWidgetState extends State<ProcessedTextWidget> {
  /// 현재 표시 모드 (전체 텍스트 또는 세그먼트별)
  late bool _showFullText;

  /// 플래시카드에 추가된 단어 목록
  Set<String> _flashcardWords = {};

  // 선택된 텍스트와 위치 저장을 위한 변수 추가
  String _selectedText = '';
  TextSelection? _selectionOffset;

  @override
  void initState() {
    super.initState();
    _showFullText = widget.processedText.showFullText;
    _extractFlashcardWords();
  }

  @override
  void didUpdateWidget(ProcessedTextWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.processedText != widget.processedText ||
        oldWidget.flashCards != widget.flashCards) {
      _showFullText = widget.processedText.showFullText;
      _extractFlashcardWords();
    }
  }

  /// 플래시카드에 추가된 단어 추출
  void _extractFlashcardWords() {
    _flashcardWords = {};
    if (widget.flashCards != null && widget.flashCards!.isNotEmpty) {
      for (final card in widget.flashCards!) {
        _flashcardWords.add(card.front);
      }
    }
  }

  /// 텍스트에서 플래시카드 단어 하이라이트 표시
  Widget _buildHighlightedText(String text,
      {double fontSize = 16, double height = 1.5}) {
    if (_flashcardWords.isEmpty) {
      return SelectableText(
        text,
        style: TextStyle(fontSize: fontSize, height: height),
        contextMenuBuilder: _buildCustomContextMenu,
      );
    }

    // 텍스트 스팬 목록 생성
    final List<TextSpan> spans = [];

    // 현재 처리 중인 위치
    int currentPosition = 0;

    // 텍스트 전체 길이
    final int textLength = text.length;

    // 플래시카드 단어 검색 및 하이라이트 처리
    while (currentPosition < textLength) {
      int nextHighlightPos = textLength;
      String? wordToHighlight;

      // 가장 가까운 플래시카드 단어 찾기
      for (final word in _flashcardWords) {
        final int pos = text.indexOf(word, currentPosition);
        if (pos != -1 && pos < nextHighlightPos) {
          nextHighlightPos = pos;
          wordToHighlight = word;
        }
      }

      // 일반 텍스트 추가 (하이라이트 전까지)
      if (nextHighlightPos > currentPosition) {
        spans.add(TextSpan(
          text: text.substring(currentPosition, nextHighlightPos),
          style: TextStyle(fontSize: fontSize, height: height),
        ));
      }

      // 하이라이트 텍스트 추가
      if (wordToHighlight != null) {
        spans.add(TextSpan(
          text: wordToHighlight,
          style: TextStyle(
            fontSize: fontSize,
            height: height,
            backgroundColor: Colors.yellow.shade200,
            fontWeight: FontWeight.bold,
          ),
        ));
        currentPosition = nextHighlightPos + wordToHighlight.length;
      } else {
        // 더 이상 하이라이트할 단어가 없으면 종료
        break;
      }
    }

    // 남은 텍스트 추가
    if (currentPosition < textLength) {
      spans.add(TextSpan(
        text: text.substring(currentPosition),
        style: TextStyle(fontSize: fontSize, height: height),
      ));
    }

    return SelectableText.rich(
      TextSpan(children: spans),
      contextMenuBuilder: _buildCustomContextMenu,
    );
  }

  // 통일된 사용자 정의 컨텍스트 메뉴 빌더
  Widget _buildCustomContextMenu(
      BuildContext context, EditableTextState editableTextState) {
    final TextEditingValue value = editableTextState.textEditingValue;
    final String selectedText = value.selection.textInside(value.text);

    if (selectedText.isEmpty) {
      return Container();
    }

    // 기본 메뉴 항목 가져오기
    final List<ContextMenuButtonItem> buttonItems = [];

    // 복사 버튼 추가
    buttonItems.add(
      ContextMenuButtonItem(
        onPressed: () {
          editableTextState.copySelection(SelectionChangedCause.toolbar);
          editableTextState.hideToolbar();
        },
        label: '복사',
      ),
    );

    // 사전 검색 버튼 추가
    buttonItems.add(
      ContextMenuButtonItem(
        onPressed: () {
          editableTextState.hideToolbar();
          if (widget.onDictionaryLookup != null) {
            widget.onDictionaryLookup!(selectedText);
          }
        },
        label: '사전 검색',
      ),
    );

    // 플래시카드 추가 버튼 생성
    buttonItems.add(
      ContextMenuButtonItem(
        onPressed: () {
          // 컨텍스트 메뉴 닫기
          editableTextState.hideToolbar();

          // 원문에서 선택한 경우, 해당 세그먼트의 번역 찾기
          String meaning = '';
          String? pinyin;

          if (widget.processedText.segments != null) {
            for (final segment in widget.processedText.segments!) {
              if (segment.originalText.contains(selectedText)) {
                meaning = segment.translatedText ?? '';
                pinyin = segment.pinyin;
                break;
              }
            }
          }

          // 의미가 없으면 빈 문자열로 설정
          if (meaning.isEmpty) {
            meaning = '직접 의미 입력 필요';
          }

          // 플래시카드 바로 추가
          if (widget.onCreateFlashCard != null) {
            widget.onCreateFlashCard!(
              selectedText,
              meaning,
              pinyin: pinyin,
            );
          }

          // 추가 완료 메시지 표시
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

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.processedText.fullOriginalText.isEmpty) {
      return const Center(child: Text('텍스트가 없습니다.'));
    }

    // 문장별 번역 모드일 때 처리
    if (widget.processedText.segments != null &&
        widget.processedText.segments!.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widget.processedText.segments!.map((sentence) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 원문 텍스트에 GestureDetector 추가
              GestureDetector(
                onLongPress: (sentence.originalText.isNotEmpty)
                    ? () => _showCustomMenu(context, sentence.originalText)
                    : null,
                child: SelectableText.rich(
                  TextSpan(
                    text: sentence.originalText,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  onSelectionChanged: (selection, cause) {
                    if (selection.baseOffset != selection.extentOffset) {
                      setState(() {
                        _selectedText = sentence.originalText.substring(
                            selection.baseOffset, selection.extentOffset);
                        _selectionOffset = selection;
                      });
                    }
                  },
                  // 기본 컨텍스트 메뉴 비활성화
                  contextMenuBuilder: null,
                ),
              ),
              if (sentence.translatedText != null &&
                  sentence.translatedText!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, bottom: 12.0),
                  child: Text(
                    sentence.translatedText!,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[700],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          );
        }).toList(),
      );
    }

    // 전체 텍스트 번역 모드
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 원문 텍스트
        GestureDetector(
          onLongPress: () {
            _showCustomMenu(context, widget.processedText.fullOriginalText);
          },
          child: SelectableText.rich(
            TextSpan(
              text: widget.processedText.fullOriginalText,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.normal,
              ),
            ),
            onSelectionChanged: (selection, cause) {
              if (selection.baseOffset != selection.extentOffset) {
                setState(() {
                  _selectedText = widget.processedText.fullOriginalText
                      .substring(selection.baseOffset, selection.extentOffset);
                  _selectionOffset = selection;
                });
              }
            },
            // 기본 컨텍스트 메뉴 비활성화
            contextMenuBuilder: null,
          ),
        ),
        const SizedBox(height: 16),
        // 번역 텍스트
        if (widget.processedText.fullTranslatedText != null &&
            widget.processedText.fullTranslatedText!.isNotEmpty)
          Text(
            widget.processedText.fullTranslatedText!,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[700],
              fontStyle: FontStyle.italic,
            ),
          ),
      ],
    );
  }

  // 커스텀 컨텍스트 메뉴 표시 메서드
  void _showCustomMenu(BuildContext context, String text) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + renderBox.size.width,
        position.dy + renderBox.size.height,
      ),
      items: [
        PopupMenuItem(
          child: Text('복사'),
          onTap: () {
            Clipboard.setData(ClipboardData(
                text: _selectedText.isNotEmpty ? _selectedText : text));
          },
        ),
        PopupMenuItem(
          child: Text('사전 찾기'),
          onTap: () {
            if (_selectedText.isNotEmpty && widget.onDictionaryLookup != null) {
              widget.onDictionaryLookup!(_selectedText);
            }
          },
        ),
        PopupMenuItem(
          child: Text('플래시카드 추가'),
          onTap: () {
            if (_selectedText.isNotEmpty && widget.onCreateFlashCard != null) {
              widget.onCreateFlashCard!(
                _selectedText,
                '',
                pinyin: null,
              );
            }
          },
        ),
      ],
    );
  }
}
