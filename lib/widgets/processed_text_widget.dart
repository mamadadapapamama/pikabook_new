import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:math' show min, max;
import '../models/processed_text.dart';
import '../models/text_segment.dart';
import '../models/flash_card.dart';
import 'segmented_text_widget.dart';
import '../services/chinese_segmenter_service.dart';
import '../services/dictionary_service.dart';

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
        onSelectionChanged: (selection, cause) {
          // 선택된 텍스트가 있을 때만 처리
          if (selection.baseOffset != selection.extentOffset) {
            final selectedText =
                text.substring(selection.baseOffset, selection.extentOffset);
            setState(() {
              _selectedText = selectedText;
              _selectionOffset = selection;
            });
          }
        },
        contextMenuBuilder: (context, editableTextState) {
          return _buildCustomContextMenu(context, editableTextState);
        },
        enableInteractiveSelection: true,
        selectionControls: MaterialTextSelectionControls(),
        showCursor: true,
        cursorWidth: 2.0,
        cursorColor: Colors.blue,
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
      onSelectionChanged: (selection, cause) {
        // 선택된 텍스트가 있을 때만 처리
        if (selection.baseOffset != selection.extentOffset) {
          // 선택된 텍스트 추출 (스팬에서 선택 범위에 해당하는 텍스트 추출)
          int currentPos = 0;
          String selectedText = '';

          for (var span in spans) {
            final spanText = span.text ?? '';
            final spanStart = currentPos;
            final spanEnd = currentPos + spanText.length;

            // 선택 범위와 스팬 범위가 겹치는지 확인
            if (spanEnd > selection.baseOffset &&
                spanStart < selection.extentOffset) {
              final overlapStart = max(spanStart, selection.baseOffset);
              final overlapEnd = min(spanEnd, selection.extentOffset);

              if (overlapEnd > overlapStart) {
                final relativeStart = overlapStart - spanStart;
                final relativeEnd = overlapEnd - spanStart;
                selectedText += spanText.substring(
                    max(0, relativeStart), min(spanText.length, relativeEnd));
              }
            }

            currentPos = spanEnd;
          }

          setState(() {
            _selectedText = selectedText;
            _selectionOffset = selection;
          });
        }
      },
      contextMenuBuilder: (context, editableTextState) {
        return _buildCustomContextMenu(context, editableTextState);
      },
      enableInteractiveSelection: true,
      selectionControls: MaterialTextSelectionControls(),
      showCursor: true,
      cursorWidth: 2.0,
      cursorColor: Colors.blue,
    );
  }

  // 통일된 사용자 정의 컨텍스트 메뉴 빌더
  Widget _buildCustomContextMenu(
      BuildContext context, EditableTextState editableTextState) {
    final TextEditingValue value = editableTextState.textEditingValue;
    final String selectedText = value.selection.textInside(value.text);

    if (selectedText.isEmpty) {
      return AdaptiveTextSelectionToolbar.editableText(
        editableTextState: editableTextState,
      );
    }

    // 기본 메뉴 항목 직접 생성
    final List<ContextMenuButtonItem> buttonItems = [
      ContextMenuButtonItem(
        onPressed: () {
          Clipboard.setData(ClipboardData(
            text: selectedText,
          ));
          editableTextState.hideToolbar();
        },
        label: '복사',
      ),
      ContextMenuButtonItem(
        onPressed: () {
          editableTextState.selectAll(SelectionChangedCause.toolbar);
        },
        label: '전체 선택',
      ),
    ];

    // 중국어 문자인지 확인
    bool containsChinese = RegExp(r'[\u4e00-\u9fa5]').hasMatch(selectedText);

    // 사전 검색 버튼 추가 (중국어 문자가 포함된 경우에만)
    if (containsChinese) {
      buttonItems.add(
        ContextMenuButtonItem(
          onPressed: () async {
            editableTextState.hideToolbar();

            // 중국어 분석 서비스 사용
            final segmenterService = ChineseSegmenterService();
            final wordInfo =
                await segmenterService.processSelectedWord(selectedText);

            // 단어 정보 표시
            if (wordInfo != null && context.mounted) {
              _showWordDetails(wordInfo);
            }
          },
          label: '사전 검색',
        ),
      );
    }

    // 기존 사전 검색 버튼 (onDictionaryLookup 콜백 사용)
    if (widget.onDictionaryLookup != null) {
      buttonItems.add(
        ContextMenuButtonItem(
          onPressed: () {
            editableTextState.hideToolbar();
            widget.onDictionaryLookup!(selectedText);
          },
          label: '기존 사전 검색',
        ),
      );
    }

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

            // 플래시카드 단어 목록에 추가하여 하이라이트 표시
            setState(() {
              _flashcardWords.add(selectedText);
            });
          }
        },
        label: '플래시카드 추가',
      ),
    );

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buttonItems,
    );
  }

  // 단어 선택 시 사전 기능 호출
  Future<void> _handleWordSelection(String selectedText) async {
    if (selectedText.isEmpty) return;

    // 중국어 문자인지 확인
    bool containsChinese = RegExp(r'[\u4e00-\u9fa5]').hasMatch(selectedText);
    if (!containsChinese) return;

    // 중국어 분석 서비스 사용
    final segmenterService = ChineseSegmenterService();
    final wordInfo = await segmenterService.processSelectedWord(selectedText);

    // 단어 정보 표시
    if (wordInfo != null) {
      _showWordDetails(wordInfo);
    }
  }

  // 단어 정보 표시 다이얼로그
  void _showWordDetails(SegmentedWord word) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(word.text,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (word.pinyin.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    '발음: ${word.pinyin}',
                    style: const TextStyle(
                        fontSize: 16, fontStyle: FontStyle.italic),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  '의미: ${word.meaning}',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              if (word.source != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    '출처: ${word.source}',
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ),
              if (word.meaning == '사전에 없는 단어' ||
                  word.meaning.isEmpty ||
                  word.source == 'external')
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    const Text('외부 사전 검색:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ElevatedButton(
                          onPressed: () => _openExternalDictionary(
                              word.text, ExternalDictType.google),
                          child: const Text('Google'),
                        ),
                        ElevatedButton(
                          onPressed: () => _openExternalDictionary(
                              word.text, ExternalDictType.naver),
                          child: const Text('Naver'),
                        ),
                        ElevatedButton(
                          onPressed: () => _openExternalDictionary(
                              word.text, ExternalDictType.baidu),
                          child: const Text('Baidu'),
                        ),
                      ],
                    ),

                    // Papago API 테스트 버튼 추가 (디버그 모드에서만 표시)
                    if (kDebugMode)
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('API 테스트:',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue)),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: () {
                                // Papago API 테스트 실행
                                final dictionaryService = DictionaryService();
                                dictionaryService.testPapagoApi(word.text);

                                // 테스트 실행 알림
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                        'Papago API 테스트가 실행되었습니다. 콘솔 로그를 확인하세요.'),
                                    duration: Duration(seconds: 3),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue[700],
                              ),
                              child: const Text('Papago API 테스트'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('닫기'),
          ),
          TextButton(
            onPressed: () {
              // 플래시카드에 추가하는 기능 (이미 구현되어 있다면 호출)
              _addToFlashcard(word.text, word.meaning, word.pinyin);
              Navigator.of(context).pop();
            },
            child: const Text('플래시카드에 추가'),
          ),
        ],
      ),
    );
  }

  // 외부 사전 열기
  Future<void> _openExternalDictionary(
      String word, ExternalDictType type) async {
    final dictionaryService = DictionaryService();
    await dictionaryService.openExternalDictionary(word, type: type);
  }

  // 플래시카드에 추가
  void _addToFlashcard(String word, String meaning, String pinyin) {
    // 플래시카드 추가 로직 구현
    // 이미 구현된 플래시카드 추가 메서드가 있다면 그것을 호출
    debugPrint('플래시카드에 추가: $word ($pinyin) - $meaning');

    // 부모 위젯에 알림 (콜백이 있는 경우)
    if (widget.onCreateFlashCard != null) {
      widget.onCreateFlashCard!(word, meaning, pinyin: pinyin);
    }
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
              // 원문 텍스트에 Row 추가
              Row(
                children: [
                  Expanded(
                    child: _flashcardWords.isNotEmpty
                        ? _buildHighlightedText(
                            sentence.originalText,
                            fontSize: 18,
                            height: 1.5,
                          )
                        : SelectableText(
                            sentence.originalText,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.normal,
                              height: 1.5,
                            ),
                            onSelectionChanged: (selection, cause) {
                              if (selection.baseOffset !=
                                  selection.extentOffset) {
                                final selectedText = sentence.originalText
                                    .substring(selection.baseOffset,
                                        selection.extentOffset);
                                setState(() {
                                  _selectedText = selectedText;
                                  _selectionOffset = selection;
                                });
                              }
                            },
                            contextMenuBuilder: (context, editableTextState) {
                              return _buildCustomContextMenu(
                                  context, editableTextState);
                            },
                            enableInteractiveSelection: true,
                            selectionControls: MaterialTextSelectionControls(),
                            showCursor: true,
                            cursorWidth: 2.0,
                            cursorColor: Colors.blue,
                          ),
                  ),
                  // TTS 버튼 추가
                  if (widget.onTts != null && sentence.originalText.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.volume_up),
                      onPressed: () => widget.onTts!(sentence.originalText),
                      tooltip: '읽기',
                    ),
                ],
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
        _flashcardWords.isNotEmpty
            ? _buildHighlightedText(
                widget.processedText.fullOriginalText,
                fontSize: 18,
                height: 1.5,
              )
            : SelectableText(
                widget.processedText.fullOriginalText,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.normal,
                  height: 1.5,
                ),
                onSelectionChanged: (selection, cause) {
                  if (selection.baseOffset != selection.extentOffset) {
                    final selectedText = widget.processedText.fullOriginalText
                        .substring(
                            selection.baseOffset, selection.extentOffset);
                    setState(() {
                      _selectedText = selectedText;
                      _selectionOffset = selection;
                    });
                  }
                },
                contextMenuBuilder: (context, editableTextState) {
                  return _buildCustomContextMenu(context, editableTextState);
                },
                enableInteractiveSelection: true,
                selectionControls: MaterialTextSelectionControls(),
                showCursor: true,
                cursorWidth: 2.0,
                cursorColor: Colors.blue,
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
}
