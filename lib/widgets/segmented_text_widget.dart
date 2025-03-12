import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/chinese_segmenter_service.dart';
import '../utils/context_menu_helper.dart';

class SegmentedTextWidget extends StatefulWidget {
  final String text;
  final List<SegmentedWord> segments;
  final Function(String)? onLookupDictionary;
  final Function(String)? onAddToFlashcard;
  final Set<String>? flashcardWords; // 플래시카드 단어 목록 추가

  const SegmentedTextWidget({
    Key? key,
    required this.text,
    required this.segments,
    this.onLookupDictionary,
    this.onAddToFlashcard,
    this.flashcardWords,
  }) : super(key: key);

  @override
  State<SegmentedTextWidget> createState() => _SegmentedTextWidgetState();
}

class _SegmentedTextWidgetState extends State<SegmentedTextWidget> {
  String _selectedText = '';
  Set<String> _flashcardWords = {}; // 플래시카드 단어 목록 저장

  @override
  void initState() {
    super.initState();
    _updateFlashcardWords();
  }

  @override
  void didUpdateWidget(SegmentedTextWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flashcardWords != widget.flashcardWords) {
      _updateFlashcardWords();
    }
  }

  // 플래시카드 단어 목록 업데이트
  void _updateFlashcardWords() {
    _flashcardWords = widget.flashcardWords?.toSet() ?? {};
  }

  @override
  Widget build(BuildContext context) {
    // 세그멘테이션이 비활성화된 경우 단순 텍스트 표시
    if (!ChineseSegmenterService.isSegmentationEnabled) {
      return SelectableText.rich(
        TextSpan(
          text: widget.text,
          style: const TextStyle(fontSize: 18, color: Colors.black),
        ),
        contextMenuBuilder: (context, editableTextState) {
          if (_selectedText.isEmpty) {
            return AdaptiveTextSelectionToolbar.editableText(
              editableTextState: editableTextState,
            );
          }

          // ✅ 선택한 단어가 플래시카드에 포함된 경우 => 기본 컨텍스트 메뉴 없이 "탭 하면 뜻이 바로 표시됨"
          if (_flashcardWords.contains(_selectedText)) {
            // 해당 단어의 SegmentedWord 객체 찾기
            for (var segment in widget.segments) {
              if (segment.text == _selectedText) {
                _showWordDetails(context, segment);
                return const SizedBox.shrink(); // 컨텍스트 메뉴를 띄우지 않음
              }
            }
          }

          // ✅ 선택한 단어가 플래시카드에 포함되지 않은 경우 => 커스텀 컨텍스트 메뉴 표시
          return ContextMenuHelper.buildCustomContextMenu(
            context: context,
            editableTextState: editableTextState,
            selectedText: _selectedText,
            flashcardWords: _flashcardWords,
            onLookupDictionary: () {
              if (widget.onLookupDictionary != null) {
                widget.onLookupDictionary!(_selectedText);
              }
            },
            onAddToFlashcard: () {
              if (widget.onAddToFlashcard != null) {
                widget.onAddToFlashcard!(_selectedText);
                setState(() {
                  _flashcardWords.add(_selectedText);
                });
              }
            },
          );
        },
        onSelectionChanged: (selection, cause) {
          if (selection.baseOffset != selection.extentOffset) {
            setState(() {
              _selectedText = widget.text.substring(
                selection.baseOffset,
                selection.extentOffset,
              );
            });

            // 디버그 로그 추가
            debugPrint('선택된 텍스트 (세그먼트 비활성화): "$_selectedText"');
            debugPrint(
                '중국어 문자 포함 여부: ${ContextMenuHelper.containsChineseCharacters(_selectedText)}');
          }
        },
        enableInteractiveSelection: true,
        selectionControls: MaterialTextSelectionControls(),
        showCursor: true,
        cursorWidth: 2.0,
        cursorColor: Colors.blue,
      );
    }

    // 사전 초기화 (비동기 작업이지만 UI 블로킹 방지를 위해 async/await 사용하지 않음)
    final segmenterService = ChineseSegmenterService();
    segmenterService.initialize();

    // 기존 세그멘테이션 표시 로직
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          children: widget.segments.map((segment) {
            // 단어장에 있는지 확인 (초기화 전이라면 false 반환)
            final bool isInDictionary =
                segmenterService.isWordInDictionary(segment.text);
            debugPrint(
                '세그먼트 "${segment.text}" 사전 확인: ${isInDictionary ? "있음" : "없음"}');

            // 플래시카드에 이미 추가된 단어인지 확인
            final bool isInFlashcard = _flashcardWords.contains(segment.text);

            // 단어장에 있는 단어는 InkWell로 감싸서 탭하면 바로 뜻이 표시되도록 함
            if (isInDictionary || isInFlashcard) {
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    _showWordDetails(context, segment);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                        vertical: 2.0, horizontal: 1.0),
                    padding: const EdgeInsets.symmetric(
                        vertical: 2.0, horizontal: 4.0),
                    decoration: BoxDecoration(
                      color: isInFlashcard
                          ? Colors.yellow.shade200
                          : Colors.blue.withOpacity(0.1),
                      border: Border.all(
                        color: isInFlashcard
                            ? Colors.yellow.shade400
                            : Colors.blue.withOpacity(0.3),
                        width: 1.0,
                      ),
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    child: Text(
                      segment.text,
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.black,
                        fontWeight:
                            isInFlashcard ? FontWeight.bold : FontWeight.normal,
                        decoration: isInFlashcard
                            ? TextDecoration.none
                            : TextDecoration.underline,
                        decorationColor: Colors.blue.withOpacity(0.5),
                        decorationThickness: 1.0,
                      ),
                    ),
                  ),
                ),
              );
            }
            // 단어장에 없는 단어는 GestureDetector로 감싸서 long press 시 컨텍스트 메뉴가 표시되도록 함
            else {
              return Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onTap: () {
                    _showWordDetails(context, segment);
                  },
                  onLongPress: () {
                    _showContextMenu(context, segment.text);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                        vertical: 2.0, horizontal: 1.0),
                    padding: const EdgeInsets.symmetric(
                        vertical: 2.0, horizontal: 4.0),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      border: Border.all(
                        color: Colors.grey.withOpacity(0.3),
                        width: 1.0,
                      ),
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                    child: Text(
                      segment.text,
                      style: TextStyle(fontSize: 18, color: Colors.black),
                    ),
                  ),
                ),
              );
            }
          }).toList(),
        ),
      ],
    );
  }

  // 단어 상세 정보 표시
  void _showWordDetails(BuildContext context, SegmentedWord segment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(segment.text),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (segment.pinyin.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  '발음: ${segment.pinyin}',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
            if (segment.source != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  '출처: ${segment.source}',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            Text('의미: ${segment.meaning}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text('닫기'),
          ),
          // 이미 플래시카드에 추가된 단어인지 확인하여 버튼 표시 여부 결정
          if (!_flashcardWords.contains(segment.text))
            TextButton(
              onPressed: () {
                if (widget.onAddToFlashcard != null) {
                  widget.onAddToFlashcard!(segment.text);

                  // 플래시카드 단어 목록에 추가
                  setState(() {
                    _flashcardWords.add(segment.text);
                  });

                  Navigator.of(context).pop();
                }
              },
              child: Text('플래시카드 추가'),
            ),
        ],
      ),
    );
  }

  // 컨텍스트 메뉴 표시
  void _showContextMenu(BuildContext context, String selectedText) {
    // 중국어 문자인지 확인
    bool containsChinese =
        ContextMenuHelper.containsChineseCharacters(selectedText);
    if (!containsChinese) return;

    // 이미 플래시카드에 추가된 단어인지 확인
    bool isAlreadyInFlashcard = _flashcardWords.contains(selectedText);

    // 단어장에 있는 단어인지 확인하고 해당 단어의 SegmentedWord 객체 찾기
    SegmentedWord? foundSegment;
    for (var segment in widget.segments) {
      if (segment.text == selectedText) {
        foundSegment = segment;
        break;
      }
    }

    // 플래시카드에 이미 추가된 단어이고 SegmentedWord 객체를 찾았다면 바로 상세 정보 표시
    if (isAlreadyInFlashcard && foundSegment != null) {
      _showWordDetails(context, foundSegment);
      return;
    }

    // 단어장에 있는지 확인
    final segmenterService = ChineseSegmenterService();
    segmenterService.initialize().then((_) {
      if (segmenterService.isWordInDictionary(selectedText) &&
          foundSegment != null) {
        // 단어장에 있는 단어는 바로 뜻 표시
        _showWordDetails(context, foundSegment);
        return;
      }

      // 컨텍스트 메뉴 표시
      _showPopupMenu(context, selectedText);
    });
  }

  // 팝업 메뉴 표시 (중복 코드 제거를 위한 메서드 추출)
  void _showPopupMenu(BuildContext context, String selectedText) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Offset position = renderBox.localToGlobal(Offset.zero);

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
          child: Text('사전 검색'),
          onTap: () {
            if (widget.onLookupDictionary != null) {
              widget.onLookupDictionary!(selectedText);
            }
          },
        ),
        PopupMenuItem(
          child: Text('플래시카드 추가'),
          onTap: () {
            if (widget.onAddToFlashcard != null) {
              widget.onAddToFlashcard!(selectedText);

              // 플래시카드 단어 목록에 추가
              setState(() {
                _flashcardWords.add(selectedText);
              });
            }
          },
        ),
        PopupMenuItem(
          child: Text('복사'),
          onTap: () {
            Clipboard.setData(ClipboardData(text: selectedText));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('복사되었습니다')),
            );
          },
        ),
      ],
    );
  }
}
