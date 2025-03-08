import 'package:flutter/material.dart';
import '../models/processed_text.dart';
import '../models/text_segment.dart';
import 'text_segment_widget.dart';

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

  const ProcessedTextWidget({
    Key? key,
    required this.processedText,
    this.onTts,
    this.onDictionaryLookup,
    this.onCreateFlashCard,
  }) : super(key: key);

  @override
  State<ProcessedTextWidget> createState() => _ProcessedTextWidgetState();
}

class _ProcessedTextWidgetState extends State<ProcessedTextWidget> {
  /// 현재 표시 모드 (전체 텍스트 또는 세그먼트별)
  late bool _showFullText;

  @override
  void initState() {
    super.initState();
    _showFullText = widget.processedText.showFullText;
  }

  @override
  void didUpdateWidget(ProcessedTextWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.processedText != widget.processedText) {
      _showFullText = widget.processedText.showFullText;
    }
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
                SelectableText(
                  widget.processedText.fullOriginalText,
                  style: const TextStyle(fontSize: 16),
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
                  SelectableText(
                    widget.processedText.fullTranslatedText!,
                    style: const TextStyle(fontSize: 16),
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

  // 컨텍스트 메뉴 수정 및 플래시카드 생성 기능 추가
  Widget _buildTextSection(
      BuildContext context, String title, String text, bool isOriginal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 8),
        SelectableText(
          text,
          style: TextStyle(
            fontSize: isOriginal ? 18 : 16,
            height: 1.5,
          ),
          contextMenuBuilder: (context, editableTextState) {
            final TextEditingValue value = editableTextState.textEditingValue;
            final selectedText = value.selection.textInside(value.text);

            // 선택된 텍스트가 없으면 기본 메뉴 표시
            if (selectedText.isEmpty) {
              return AdaptiveTextSelectionToolbar.editableText(
                editableTextState: editableTextState,
              );
            }

            return AdaptiveTextSelectionToolbar(
              anchors: editableTextState.contextMenuAnchors,
              children: [
                // 사전 검색 옵션
                _buildContextMenuItem(
                  context,
                  '사전 검색',
                  Icons.search,
                  () {
                    // 컨텍스트 메뉴 닫기
                    editableTextState.hideToolbar();
                    // 사전 검색 실행 (null 체크 추가)
                    widget.onDictionaryLookup?.call(selectedText);
                  },
                ),

                // 플래시카드 추가 옵션
                _buildContextMenuItem(
                  context,
                  '플래시카드 추가',
                  Icons.flash_on,
                  () {
                    // 컨텍스트 메뉴 닫기
                    editableTextState.hideToolbar();
                    // 플래시카드 추가 대화상자 표시
                    _showAddFlashcardDialog(context, selectedText);
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  // 컨텍스트 메뉴 아이템 위젯
  Widget _buildContextMenuItem(BuildContext context, String label,
      IconData icon, VoidCallback onPressed) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }

  // 플래시카드 추가 대화상자
  void _showAddFlashcardDialog(BuildContext context, String selectedText) {
    // 선택된 텍스트가 원문인지 번역인지 확인
    final bool isOriginalText =
        widget.processedText.fullOriginalText.contains(selectedText);

    // 원문이면 번역을 찾고, 번역이면 원문을 찾기
    String meaning = '';
    String? pinyin;

    if (isOriginalText) {
      // 원문에서 선택한 경우, 해당 세그먼트의 번역 찾기
      if (widget.processedText.segments != null) {
        for (final segment in widget.processedText.segments!) {
          if (segment.originalText.contains(selectedText)) {
            // String? 타입을 String으로 변환 (null 체크 추가)
            meaning = segment.translatedText ?? '';
            pinyin = segment.pinyin;
            break;
          }
        }
      }
    } else {
      // 번역에서 선택한 경우, 해당 세그먼트의 원문 찾기
      if (widget.processedText.segments != null) {
        for (final segment in widget.processedText.segments!) {
          // null 체크 추가
          if (segment.translatedText?.contains(selectedText) == true) {
            // 번역에서 선택했으므로 원문이 단어가 됨
            meaning = selectedText;
            selectedText = segment.originalText;
            pinyin = segment.pinyin;
            break;
          }
        }
      }
    }

    // 의미가 없으면 빈 문자열로 설정
    if (meaning.isEmpty) {
      meaning = '직접 의미 입력 필요';
    }

    // 텍스트 컨트롤러 초기화
    final TextEditingController wordController =
        TextEditingController(text: selectedText);
    final TextEditingController meaningController =
        TextEditingController(text: meaning);
    final TextEditingController pinyinController =
        TextEditingController(text: pinyin ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('플래시카드 추가'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: wordController,
                  decoration: const InputDecoration(
                    labelText: '단어',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: pinyinController,
                  decoration: const InputDecoration(
                    labelText: '핀인',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: meaningController,
                  decoration: const InputDecoration(
                    labelText: '의미',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () {
                // 플래시카드 추가 (null 체크 추가)
                widget.onCreateFlashCard?.call(
                  wordController.text,
                  meaningController.text,
                  pinyin: pinyinController.text.isNotEmpty
                      ? pinyinController.text
                      : null,
                );
                Navigator.of(context).pop();

                // 추가 완료 메시지 표시
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('플래시카드가 추가되었습니다.'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: const Text('추가'),
            ),
          ],
        );
      },
    );
  }

  // 세그먼트 위젯 구성 (문장별 모드)
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
            SelectableText(
              segment.originalText,
              style: const TextStyle(fontSize: 18, height: 1.5),
              contextMenuBuilder: (context, editableTextState) {
                final TextEditingValue value =
                    editableTextState.textEditingValue;
                final selectedText = value.selection.textInside(value.text);

                // 선택된 텍스트가 없으면 기본 메뉴 표시
                if (selectedText.isEmpty) {
                  return AdaptiveTextSelectionToolbar.editableText(
                    editableTextState: editableTextState,
                  );
                }

                return AdaptiveTextSelectionToolbar(
                  anchors: editableTextState.contextMenuAnchors,
                  children: [
                    // 사전 검색 옵션
                    _buildContextMenuItem(
                      context,
                      '사전 검색',
                      Icons.search,
                      () {
                        // 컨텍스트 메뉴 닫기
                        editableTextState.hideToolbar();
                        // 사전 검색 실행 (null 체크 추가)
                        widget.onDictionaryLookup?.call(selectedText);
                      },
                    ),

                    // 플래시카드 추가 옵션
                    _buildContextMenuItem(
                      context,
                      '플래시카드 추가',
                      Icons.flash_on,
                      () {
                        // 컨텍스트 메뉴 닫기
                        editableTextState.hideToolbar();
                        // 플래시카드 추가 대화상자 표시
                        _showAddFlashcardDialog(context, selectedText);
                      },
                    ),
                  ],
                );
              },
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
            SelectableText(
              segment.translatedText ?? '',
              style: const TextStyle(fontSize: 16, height: 1.5),
              contextMenuBuilder: (context, editableTextState) {
                final TextEditingValue value =
                    editableTextState.textEditingValue;
                final selectedText = value.selection.textInside(value.text);

                // 선택된 텍스트가 없으면 기본 메뉴 표시
                if (selectedText.isEmpty) {
                  return AdaptiveTextSelectionToolbar.editableText(
                    editableTextState: editableTextState,
                  );
                }

                return AdaptiveTextSelectionToolbar(
                  anchors: editableTextState.contextMenuAnchors,
                  children: [
                    // 사전 검색 옵션
                    _buildContextMenuItem(
                      context,
                      '사전 검색',
                      Icons.search,
                      () {
                        // 컨텍스트 메뉴 닫기
                        editableTextState.hideToolbar();
                        // 사전 검색 실행 (null 체크 추가)
                        widget.onDictionaryLookup?.call(selectedText);
                      },
                    ),

                    // 플래시카드 추가 옵션
                    _buildContextMenuItem(
                      context,
                      '플래시카드 추가',
                      Icons.flash_on,
                      () {
                        // 컨텍스트 메뉴 닫기
                        editableTextState.hideToolbar();
                        // 플래시카드 추가 대화상자 표시
                        _showAddFlashcardDialog(context, selectedText);
                      },
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 12),

            // 하단 액션 버튼
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // TTS 버튼 (null 체크 추가)
                IconButton(
                  icon: const Icon(Icons.volume_up),
                  tooltip: '읽기',
                  onPressed: () => widget.onTts?.call(segment.originalText),
                ),

                // 플래시카드 추가 버튼 (null 체크 추가)
                IconButton(
                  icon: const Icon(Icons.flash_on),
                  tooltip: '플래시카드 추가',
                  onPressed: () {
                    widget.onCreateFlashCard?.call(
                      segment.originalText,
                      segment.translatedText ?? '',
                      pinyin: segment.pinyin,
                    );

                    // 추가 완료 메시지 표시
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('플래시카드가 추가되었습니다.'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
