import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../models/processed_text.dart';
import '../models/text_segment.dart';
import '../models/flash_card.dart';
import 'text_segment_widget.dart';
import 'segmented_text_widget.dart';

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 표시 모드 전환 버튼
        _buildDisplayModeToggle(context),

        const SizedBox(height: 16),

        // 텍스트 표시
        _showFullText
            ? _buildFullTextView(context)
            : _buildSegmentedView(context),
      ],
    );
  }

  /// 표시 모드 전환 버튼
  Widget _buildDisplayModeToggle(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          _showFullText ? '전체 텍스트 모드' : '문장별 모드',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          value: _showFullText,
          onChanged: (value) {
            setState(() {
              _showFullText = value;
            });
          },
          activeColor: Theme.of(context).primaryColor,
        ),
      ],
    );
  }

  /// 전체 텍스트 표시
  Widget _buildFullTextView(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 원문 텍스트
        Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '원문',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (widget.onTts != null)
                      IconButton(
                        icon: const Icon(Icons.volume_up),
                        onPressed: () => widget.onTts
                            ?.call(widget.processedText.fullOriginalText),
                        tooltip: '읽기',
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // 원문에 SegmentedTextWidget 적용
                SegmentedTextWidget(
                  text: widget.processedText.fullOriginalText,
                  noteId: widget.noteId,
                ),
              ],
            ),
          ),
        ),

        // 번역 텍스트
        if (widget.processedText.fullTranslatedText != null)
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '번역',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 번역 텍스트는 일반 SelectableText 사용
                  SelectableText(
                    widget.processedText.fullTranslatedText!,
                    style: const TextStyle(fontSize: 16),
                    contextMenuBuilder: _buildCustomContextMenu,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 세그먼트별 표시
  Widget _buildSegmentedView(BuildContext context) {
    // 세그먼트가 없는 경우
    if (widget.processedText.segments == null ||
        widget.processedText.segments!.isEmpty) {
      debugPrint('세그먼트 데이터가 없습니다.');
      return const Center(
        child: Text('문장별 데이터가 없습니다. 전체 텍스트 모드를 사용해주세요.'),
      );
    }

    debugPrint('세그먼트 표시: ${widget.processedText.segments!.length}개');

    // 세그먼트 위젯 목록 생성
    final segmentWidgets =
        widget.processedText.segments!.asMap().entries.map((entry) {
      final index = entry.key;
      final segment = entry.value;
      debugPrint(
          '세그먼트 $index: ${segment.originalText.substring(0, segment.originalText.length > 10 ? 10 : segment.originalText.length)}...');

      return _buildSegmentWidget(context, segment, index);
    }).toList();

    // 세그먼트 목록 표시
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '문장별 표시 (${widget.processedText.segments!.length}개)',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 16),
        // 세그먼트 위젯 목록을 ListView로 표시
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: segmentWidgets.length,
          itemBuilder: (context, index) => segmentWidgets[index],
        ),
      ],
    );
  }

  /// 세그먼트 위젯 구성 (문장별 모드)
  Widget _buildSegmentWidget(
      BuildContext context, TextSegment segment, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 원문
            _buildHighlightedText(
              segment.originalText,
              fontSize: 18,
            ),

            // 핀인이 있으면 표시
            if (segment.pinyin != null && segment.pinyin!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                segment.pinyin!,
                style: const TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: Colors.blue,
                ),
              ),
            ],

            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),

            // 번역 (null 체크 추가)
            Text(
              segment.translatedText ?? '',
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),

            const SizedBox(height: 12),

            // 하단 액션 버튼 (플래시카드 추가 버튼 제거)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // TTS 버튼 (null 체크 추가)
                IconButton(
                  icon: const Icon(Icons.volume_up),
                  tooltip: '읽기',
                  onPressed: () => widget.onTts?.call(segment.originalText),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
