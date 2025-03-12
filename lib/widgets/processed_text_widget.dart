import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'dart:math' show min, max;
import '../models/processed_text.dart';
import '../models/text_segment.dart';
import '../models/flash_card.dart';
import 'segmented_text_widget.dart';
import '../services/chinese_segmenter_service.dart';
import '../services/dictionary_service.dart';
import '../utils/context_menu_helper.dart';

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

    // 디버그 로그 추가
    debugPrint('ProcessedTextWidget 초기화: noteId=${widget.noteId}');
    debugPrint('플래시카드 단어 수: ${_flashcardWords.length}');
    if (_flashcardWords.isNotEmpty) {
      debugPrint('플래시카드 단어 목록: ${_flashcardWords.join(", ")}');
    }
  }

  @override
  void didUpdateWidget(ProcessedTextWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.processedText != widget.processedText ||
        oldWidget.flashCards != widget.flashCards) {
      _showFullText = widget.processedText.showFullText;
      _extractFlashcardWords();

      // 디버그 로그 추가
      debugPrint('ProcessedTextWidget 업데이트: noteId=${widget.noteId}');
      debugPrint('플래시카드 단어 수: ${_flashcardWords.length}');
      if (_flashcardWords.isNotEmpty) {
        debugPrint('플래시카드 단어 목록: ${_flashcardWords.join(", ")}');
      }
    }
  }

  /// 플래시카드에 추가된 단어 추출
  void _extractFlashcardWords() {
    final Set<String> newFlashcardWords = {};
    if (widget.flashCards != null && widget.flashCards!.isNotEmpty) {
      for (final card in widget.flashCards!) {
        if (card.front.isNotEmpty) {
          newFlashcardWords.add(card.front);
          // 디버그 로그 추가
          debugPrint('플래시카드 단어 추가: ${card.front}');
        }
      }
    }

    // 변경 사항이 있는 경우에만 상태 업데이트
    if (_flashcardWords.length != newFlashcardWords.length ||
        !_flashcardWords.containsAll(newFlashcardWords)) {
      setState(() {
        _flashcardWords = newFlashcardWords;
      });
    }
  }

  /// 텍스트에서 플래시카드 단어 하이라이트 표시
  Widget _buildHighlightedText(String text,
      {double fontSize = 16, double height = 1.5}) {
    if (_flashcardWords.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: SelectableText(
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

              // 디버그 로그 추가
              debugPrint('선택된 텍스트: "$_selectedText"');
              debugPrint(
                  '중국어 문자 포함 여부: ${ContextMenuHelper.containsChineseCharacters(_selectedText)}');
            }
          },
          contextMenuBuilder: (context, editableTextState) {
            // 선택된 텍스트가 없으면 기본 메뉴 표시
            if (_selectedText.isEmpty) {
              debugPrint('컨텍스트 메뉴: 선택된 텍스트 없음');
              return AdaptiveTextSelectionToolbar.editableText(
                editableTextState: editableTextState,
              );
            }

            // 중국어 문자가 포함되어 있는지 확인
            bool containsChinese =
                ContextMenuHelper.containsChineseCharacters(_selectedText);
            debugPrint('컨텍스트 메뉴: 중국어 포함 = $containsChinese');

            // 중국어가 아니면 기본 메뉴 표시
            if (!containsChinese) {
              debugPrint('컨텍스트 메뉴: 중국어 아님, 기본 메뉴 표시');
              return AdaptiveTextSelectionToolbar.editableText(
                editableTextState: editableTextState,
              );
            }

            // 이미 플래시카드에 추가된 단어인지 확인
            bool isAlreadyInFlashcard = _flashcardWords.contains(_selectedText);
            debugPrint('컨텍스트 메뉴: 이미 플래시카드에 추가된 단어 = $isAlreadyInFlashcard');
            debugPrint('현재 플래시카드 단어 수: ${_flashcardWords.length}');

            // 항상 커스텀 메뉴 표시 (플래시카드 추가 여부와 관계없이)
            debugPrint('컨텍스트 메뉴: 커스텀 메뉴 표시');
            return _buildCustomContextMenu(context, editableTextState);
          },
          enableInteractiveSelection: true,
          selectionControls: MaterialTextSelectionControls(),
          showCursor: true,
          cursorWidth: 2.0,
          cursorColor: Colors.blue,
        ),
      );
    }

    // 플래시카드 단어가 있는 경우 하이라이트 처리
    final List<InlineSpan> spans = [];
    int currentPosition = 0;

    // 이미 처리된 위치를 추적하기 위한 Set
    final Set<int> processedPositions = {};

    // 플래시카드 단어 검색 및 하이라이트
    for (final word in _flashcardWords) {
      if (word.isEmpty) continue;

      int startIndex = 0;
      while (true) {
        startIndex = text.indexOf(word, startIndex);
        if (startIndex == -1) break;

        // 이미 처리된 위치인지 확인
        bool alreadyProcessed = false;
        for (int i = startIndex; i < startIndex + word.length; i++) {
          if (processedPositions.contains(i)) {
            alreadyProcessed = true;
            break;
          }
        }

        // 이미 처리된 위치면 건너뛰기
        if (alreadyProcessed) {
          startIndex += 1;
          continue;
        }

        // 처리되지 않은 텍스트 추가
        if (startIndex > currentPosition) {
          final normalText = text.substring(currentPosition, startIndex);
          spans.add(TextSpan(
            text: normalText,
            style: TextStyle(fontSize: fontSize, height: height),
          ));
        }

        // 하이라이트된 단어 추가
        final highlightedWord =
            text.substring(startIndex, startIndex + word.length);
        spans.add(TextSpan(
          text: highlightedWord,
          style: TextStyle(
            fontSize: fontSize,
            height: height,
            backgroundColor: Colors.yellow.shade200,
            fontWeight: FontWeight.bold,
          ),
        ));

        // 처리된 위치 기록
        for (int i = startIndex; i < startIndex + word.length; i++) {
          processedPositions.add(i);
        }

        // 다음 검색 위치 업데이트
        currentPosition = startIndex + word.length;
        startIndex = currentPosition;
      }
    }

    // 남은 텍스트 추가
    if (currentPosition < text.length) {
      final normalText = text.substring(currentPosition);
      spans.add(TextSpan(
        text: normalText,
        style: TextStyle(fontSize: fontSize, height: height),
      ));
    }

    // 하이라이트된 텍스트 위젯 반환
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: SelectableText.rich(
        TextSpan(children: spans),
        onSelectionChanged: (selection, cause) {
          // 선택된 텍스트가 있을 때만 처리
          if (selection.baseOffset != selection.extentOffset) {
            final selectedText =
                TextSpan(children: spans).toPlainText().substring(
                      selection.baseOffset,
                      selection.extentOffset,
                    );
            setState(() {
              _selectedText = selectedText;
              _selectionOffset = selection;
            });

            // 디버그 로그 추가
            debugPrint('선택된 텍스트 (하이라이트): "$_selectedText"');
            debugPrint(
                '중국어 문자 포함 여부: ${ContextMenuHelper.containsChineseCharacters(_selectedText)}');
          }
        },
        contextMenuBuilder: (context, editableTextState) {
          // 선택된 텍스트가 없으면 기본 메뉴 표시
          if (_selectedText.isEmpty) {
            debugPrint('컨텍스트 메뉴: 선택된 텍스트 없음');
            return AdaptiveTextSelectionToolbar.editableText(
              editableTextState: editableTextState,
            );
          }

          // 중국어 문자가 포함되어 있는지 확인
          bool containsChinese =
              ContextMenuHelper.containsChineseCharacters(_selectedText);
          debugPrint('컨텍스트 메뉴: 중국어 포함 = $containsChinese');

          // 중국어가 아니면 기본 메뉴 표시
          if (!containsChinese) {
            debugPrint('컨텍스트 메뉴: 중국어 아님, 기본 메뉴 표시');
            return AdaptiveTextSelectionToolbar.editableText(
              editableTextState: editableTextState,
            );
          }

          // 이미 플래시카드에 추가된 단어인지 확인
          bool isAlreadyInFlashcard = _flashcardWords.contains(_selectedText);
          debugPrint('컨텍스트 메뉴: 이미 플래시카드에 추가된 단어 = $isAlreadyInFlashcard');
          debugPrint('현재 플래시카드 단어 수: ${_flashcardWords.length}');

          // 항상 커스텀 메뉴 표시 (플래시카드 추가 여부와 관계없이)
          debugPrint('컨텍스트 메뉴: 커스텀 메뉴 표시');
          return _buildCustomContextMenu(context, editableTextState);
        },
        enableInteractiveSelection: true,
        selectionControls: MaterialTextSelectionControls(),
        showCursor: true,
        cursorWidth: 2.0,
        cursorColor: Colors.blue,
      ),
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
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 단어 헤더
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 단어 제목
                Text(
                  word.text,
                  style: const TextStyle(
                      fontSize: 28, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 16),

                // 발음 정보
                if (word.pinyin.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      children: [
                        const Icon(Icons.record_voice_over, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          '발음: ${word.pinyin}',
                          style: const TextStyle(
                              fontSize: 18, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),

                // 의미 정보
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.translate, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '의미: ${word.meaning}',
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ],
                  ),
                ),

                // 출처 정보
                if (word.source != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      children: [
                        const Icon(Icons.source, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          '출처: ${word.source}',
                          style:
                              const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),

                const Divider(height: 24),

                // 외부 사전 검색 섹션
                if (word.meaning == '사전에 없는 단어' ||
                    word.meaning.isEmpty ||
                    word.source == 'external')
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '외부 사전 검색:',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildExternalDictButton(word.text,
                              ExternalDictType.google, 'Google', Colors.blue),
                          _buildExternalDictButton(word.text,
                              ExternalDictType.naver, 'Naver', Colors.green),
                          _buildExternalDictButton(word.text,
                              ExternalDictType.baidu, 'Baidu', Colors.red),
                        ],
                      ),
                    ],
                  ),

                // 디버그 모드 API 테스트 버튼
                if (kDebugMode)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(),
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

                const SizedBox(height: 24),

                // 하단 버튼
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('닫기'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          _addToFlashcard(word.text, word.meaning, word.pinyin);
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: Colors.blue,
                        ),
                        child: const Text('플래시카드에 추가'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 외부 사전 버튼 위젯
  Widget _buildExternalDictButton(
      String word, ExternalDictType type, String label, Color color) {
    return ElevatedButton(
      onPressed: () => _searchExternalDictionary(word, type),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: Text(label),
    );
  }

  // 외부 사전 검색 및 결과 표시
  Future<void> _searchExternalDictionary(
      String word, ExternalDictType type) async {
    // 로딩 표시
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('외부 사전에서 검색 중...'),
        duration: Duration(seconds: 1),
      ),
    );

    // 외부 사전 검색
    final dictionaryService = DictionaryService();
    final result = await dictionaryService.searchExternalDictionary(word, type);

    // 검색 결과가 있으면 표시
    if (result != null && context.mounted) {
      // 사전에 추가된 단어를 플래시카드 단어 목록에 추가
      if (!_flashcardWords.contains(word) &&
          result.meaning.isNotEmpty &&
          result.meaning != '외부 사전 검색 결과를 가져올 수 없습니다.') {
        debugPrint('사전 검색 결과를 플래시카드 단어 목록에 추가: $word');
        setState(() {
          // 플래시카드 단어 목록에 추가
          _flashcardWords.add(word);
        });
      }

      Navigator.of(context).pop(); // 현재 바텀시트 닫기
      _showWordDetails(SegmentedWord(
        text: result.word,
        pinyin: result.pinyin,
        meaning: result.meaning,
        source: result.source,
      ));
    } else if (context.mounted) {
      // 검색 실패 시 메시지 표시
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('외부 사전 검색에 실패했습니다.'),
          duration: Duration(seconds: 2),
        ),
      );

      // 외부 브라우저로 열기
      _openExternalDictionary(word, type);
    }
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

      // 플래시카드 단어 목록에 추가 (setState 호출 없이)
      if (!_flashcardWords.contains(word)) {
        _flashcardWords.add(word);
      }
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
                        : Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8.0, vertical: 4.0),
                            child: SelectableText(
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

                                  // 디버그 로그 추가
                                  debugPrint('선택된 텍스트 (세그먼트): "$selectedText"');
                                  debugPrint(
                                      '중국어 문자 포함 여부: ${ContextMenuHelper.containsChineseCharacters(selectedText)}');
                                }
                              },
                              contextMenuBuilder: (context, editableTextState) {
                                // 선택된 텍스트가 없으면 기본 메뉴 표시
                                if (_selectedText.isEmpty) {
                                  return AdaptiveTextSelectionToolbar
                                      .editableText(
                                    editableTextState: editableTextState,
                                  );
                                }

                                // 중국어 문자가 포함되어 있는지 확인
                                bool containsChinese =
                                    ContextMenuHelper.containsChineseCharacters(
                                        _selectedText);
                                debugPrint(
                                    '컨텍스트 메뉴 빌더 (세그먼트): 중국어 포함 = $containsChinese');

                                // 중국어가 아니면 기본 메뉴 표시
                                if (!containsChinese) {
                                  return AdaptiveTextSelectionToolbar
                                      .editableText(
                                    editableTextState: editableTextState,
                                  );
                                }

                                // 이미 플래시카드에 추가된 단어인지 확인
                                bool isAlreadyInFlashcard =
                                    _flashcardWords.contains(_selectedText);
                                debugPrint(
                                    '이미 플래시카드에 추가된 단어: $isAlreadyInFlashcard');

                                // 항상 커스텀 메뉴 표시
                                return _buildCustomContextMenu(
                                    context, editableTextState);
                              },
                              enableInteractiveSelection: true,
                              showCursor: true,
                              cursorWidth: 2.0,
                              cursorColor: Colors.blue,
                            ),
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
            : Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: SelectableText(
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

                      // 디버그 로그 추가
                      debugPrint('선택된 텍스트 (전체 텍스트): "$selectedText"');
                      debugPrint(
                          '중국어 문자 포함 여부: ${ContextMenuHelper.containsChineseCharacters(selectedText)}');
                    }
                  },
                  contextMenuBuilder: (context, editableTextState) {
                    // 선택된 텍스트가 없으면 기본 메뉴 표시
                    if (_selectedText.isEmpty) {
                      return AdaptiveTextSelectionToolbar.editableText(
                        editableTextState: editableTextState,
                      );
                    }

                    // 중국어 문자가 포함되어 있는지 확인
                    bool containsChinese =
                        ContextMenuHelper.containsChineseCharacters(
                            _selectedText);
                    debugPrint(
                        '컨텍스트 메뉴 빌더 (전체 텍스트): 중국어 포함 = $containsChinese');

                    // 중국어가 아니면 기본 메뉴 표시
                    if (!containsChinese) {
                      return AdaptiveTextSelectionToolbar.editableText(
                        editableTextState: editableTextState,
                      );
                    }

                    // 이미 플래시카드에 추가된 단어인지 확인
                    bool isAlreadyInFlashcard =
                        _flashcardWords.contains(_selectedText);
                    debugPrint('이미 플래시카드에 추가된 단어: $isAlreadyInFlashcard');

                    // 항상 커스텀 메뉴 표시
                    return _buildCustomContextMenu(context, editableTextState);
                  },
                  enableInteractiveSelection: true,
                  showCursor: true,
                  cursorWidth: 2.0,
                  cursorColor: Colors.blue,
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

  /// 커스텀 컨텍스트 메뉴 생성
  Widget _buildCustomContextMenu(
      BuildContext context, EditableTextState editableTextState) {
    // 디버그 로그 추가
    debugPrint('커스텀 컨텍스트 메뉴 빌더 호출: 선택된 텍스트 = "$_selectedText"');

    // 선택된 텍스트가 이미 플래시카드에 있는지 확인
    // 매번 최신 상태를 확인하기 위해 widget.flashCards에서 직접 확인
    bool isAlreadyInFlashcard = false;
    if (widget.flashCards != null) {
      for (final card in widget.flashCards!) {
        if (card.front == _selectedText) {
          isAlreadyInFlashcard = true;
          break;
        }
      }
    }

    // 로컬 변수와 비교
    bool isInLocalFlashcards = _flashcardWords.contains(_selectedText);

    debugPrint(
        '커스텀 메뉴: 플래시카드 확인 결과 - widget: $isAlreadyInFlashcard, 로컬: $isInLocalFlashcards');

    // 두 결과가 다르면 로컬 상태 업데이트
    if (isAlreadyInFlashcard != isInLocalFlashcards) {
      debugPrint('커스텀 메뉴: 플래시카드 상태 불일치 감지, 업데이트 필요');
      // 다음 프레임에서 상태 업데이트
      Future.microtask(() {
        if (mounted) {
          setState(() {
            if (isAlreadyInFlashcard &&
                !_flashcardWords.contains(_selectedText)) {
              _flashcardWords.add(_selectedText);
            }
          });
        }
      });
    }

    // 커스텀 메뉴 항목 생성
    final List<ContextMenuButtonItem> buttonItems = [];

    // 복사 버튼
    buttonItems.add(
      ContextMenuButtonItem(
        onPressed: () {
          editableTextState.copySelection(SelectionChangedCause.toolbar);
          editableTextState.hideToolbar();
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
    if (widget.onDictionaryLookup != null) {
      buttonItems.add(
        ContextMenuButtonItem(
          onPressed: () {
            editableTextState.hideToolbar();
            widget.onDictionaryLookup!(_selectedText);
          },
          label: '사전 검색',
        ),
      );
    }

    // 플래시카드 추가 버튼 (이미 추가된 경우에는 표시하지 않음)
    if (widget.onCreateFlashCard != null && !isAlreadyInFlashcard) {
      buttonItems.add(
        ContextMenuButtonItem(
          onPressed: () {
            editableTextState.hideToolbar();

            // 플래시카드 추가 기능 호출
            // 원문에서 선택한 경우, 해당 세그먼트의 번역 찾기
            String meaning = '';
            String? pinyin;

            if (widget.processedText.segments != null) {
              for (final segment in widget.processedText.segments!) {
                if (segment.originalText.contains(_selectedText)) {
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

            widget.onCreateFlashCard!(_selectedText, meaning, pinyin: pinyin);

            // 플래시카드 단어 목록에 추가하여 하이라이트 표시
            if (!_flashcardWords.contains(_selectedText)) {
              setState(() {
                _flashcardWords.add(_selectedText);
              });
            }

            // 추가 완료 메시지 표시
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('플래시카드에 추가되었습니다'),
                duration: Duration(seconds: 2),
              ),
            );
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
}
