import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import '../models/processed_text.dart';
import '../models/flash_card.dart';
import '../utils/context_menu_helper.dart';
import '../utils/text_selection_helper.dart';
import '../services/text_reader_service.dart';
import '../utils/text_highlight_manager.dart';
import '../utils/context_menu_manager.dart';

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
  final TextReaderService _textReaderService = TextReaderService();
  int? _playingSegmentIndex;

  // 선택된 텍스트 상태 관리를 위한 ValueNotifier
  final ValueNotifier<String> _selectedTextNotifier = ValueNotifier<String>('');

  @override
  void initState() {
    super.initState();
    _flashcardWords = {};
    _extractFlashcardWords();
    _initTextReader();
  }

  void _initTextReader() async {
    await _textReaderService.init();

    // TTS 상태 변경 콜백 설정
    _textReaderService.setOnPlayingStateChanged((segmentIndex) {
      if (mounted) {
        setState(() {
          _playingSegmentIndex = segmentIndex;
        });
      }
    });

    // TTS 재생 완료 콜백 설정
    _textReaderService.setOnPlayingCompleted(() {
      if (mounted) {
        setState(() {
          _playingSegmentIndex = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _textReaderService.dispose();
    _selectedTextNotifier.dispose(); // ValueNotifier 정리
    super.dispose();
  }

  @override
  void didUpdateWidget(ProcessedTextWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 플래시카드 목록이 변경된 경우
    if (oldWidget.flashCards != widget.flashCards) {
      if (kDebugMode) {
        debugPrint('플래시카드 목록 변경 감지: didUpdateWidget');
      }
      _extractFlashcardWords();
    }

    // 처리된 텍스트가 변경된 경우
    if (oldWidget.processedText != widget.processedText) {
      if (kDebugMode) {
        debugPrint('처리된 텍스트 변경 감지: didUpdateWidget');
      }
      // 선택된 텍스트 초기화
      setState(() {
        _selectedText = '';
        _selectedTextNotifier.value = '';
      });
    }
  }

  /// **플래시카드 단어 목록 추출**
  void _extractFlashcardWords() {
    final Set<String> newFlashcardWords = {};

    if (kDebugMode) {
      debugPrint('_extractFlashcardWords 호출');
    }

    if (widget.flashCards != null) {
      if (kDebugMode) {
        debugPrint('플래시카드 목록 수: ${widget.flashCards!.length}개');
      }

      for (final card in widget.flashCards!) {
        if (card.front.isNotEmpty) {
          newFlashcardWords.add(card.front);
        }
      }

      if (widget.flashCards!.isNotEmpty && kDebugMode) {
        debugPrint(
            '첫 5개 플래시카드: ${widget.flashCards!.take(5).map((card) => card.front).join(', ')}');
      }
    } else if (kDebugMode) {
      debugPrint('플래시카드 목록이 null임');
    }

    // 변경 사항이 있는 경우에만 setState 호출
    if (_flashcardWords.length != newFlashcardWords.length ||
        !_flashcardWords.containsAll(newFlashcardWords) ||
        !newFlashcardWords.containsAll(_flashcardWords)) {
      if (kDebugMode) {
        debugPrint('플래시카드 단어 목록 변경 감지:');
        debugPrint('  이전: ${_flashcardWords.length}개');
        debugPrint('  새로운: ${newFlashcardWords.length}개');
      }

      setState(() {
        _flashcardWords = newFlashcardWords;
      });

      if (kDebugMode) {
        debugPrint('플래시카드 단어 목록 업데이트 완료: ${_flashcardWords.length}개');
        if (_flashcardWords.isNotEmpty) {
          debugPrint('첫 5개 단어: ${_flashcardWords.take(5).join(', ')}');
        }
      }
    } else if (kDebugMode) {
      debugPrint('플래시카드 단어 목록 변경 없음: ${_flashcardWords.length}개');
    }
  }

  /// **선택 가능한 텍스트 위젯 생성**
  Widget _buildSelectableText(String text) {
    // 텍스트가 비어있으면 빈 컨테이너 반환
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    if (kDebugMode) {
      debugPrint('_buildSelectableText 호출: 텍스트 길이=${text.length}');
    }

    // 하이라이트된 텍스트 스팬 생성
    final textSpans = TextHighlightManager.buildHighlightedText(
      text: text,
      flashcardWords: _flashcardWords,
      onTap: (word) {
        if (kDebugMode) {
          debugPrint('하이라이트된 단어 탭됨: $word');
        }
        // 선택된 텍스트 초기화 - 빌드 후에 실행되도록 Future.microtask 사용
        Future.microtask(() {
          if (mounted) {
            setState(() {
              _selectedText = '';
              _selectedTextNotifier.value = '';
            });
          }
        });

        // 사전 검색 실행
        if (widget.onDictionaryLookup != null) {
          widget.onDictionaryLookup!(word);
        }
      },
      normalStyle: const TextStyle(fontSize: 16),
    );

    // 클래스 멤버 ValueNotifier 사용
    _selectedTextNotifier.value = _selectedText;

    return ValueListenableBuilder<String>(
      valueListenable: _selectedTextNotifier,
      builder: (context, selectedText, child) {
        return SelectableText.rich(
          TextSpan(
            children: textSpans,
            style: const TextStyle(fontSize: 16),
          ),
          contextMenuBuilder: (context, editableTextState) {
            return ContextMenuManager.buildContextMenu(
              context: context,
              editableTextState: editableTextState,
              flashcardWords: _flashcardWords,
              selectedText: selectedText,
              onSelectionChanged: (text) {
                // 상태 변경을 ValueNotifier를 통해 처리하고, 빌드 후에 setState 호출
                _selectedTextNotifier.value = text;
                Future.microtask(() {
                  if (mounted) {
                    setState(() {
                      _selectedText = text;
                    });
                  }
                });
              },
              onDictionaryLookup: widget.onDictionaryLookup,
              onCreateFlashCard: (word, meaning, {String? pinyin}) {
                if (widget.onCreateFlashCard != null) {
                  widget.onCreateFlashCard!(word, meaning, pinyin: pinyin);
                  // 빌드 후에 setState 호출
                  Future.microtask(() {
                    if (mounted) {
                      setState(() {
                        _flashcardWords.add(word);
                      });
                    }
                  });
                }
              },
            );
          },
          enableInteractiveSelection: true,
          showCursor: true,
          cursorWidth: 2.0,
          cursorColor: Colors.blue,
        );
      },
    );
  }

  /// **TTS 재생 메서드**
  void _playTts(String text, {int? segmentIndex}) {
    if (text.isEmpty) return;

    if (_playingSegmentIndex == segmentIndex) {
      // 이미 재생 중인 세그먼트를 다시 클릭한 경우 중지
      _textReaderService.stop();
    } else {
      // 새로운 세그먼트 재생
      if (segmentIndex != null) {
        _textReaderService.readSegment(text, segmentIndex);
      } else {
        _textReaderService.readText(text);
      }
    }
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
            child:
                _buildSelectableText(widget.processedText.fullTranslatedText!),
          ),
      ],
    );
  }

  /// **세그먼트별 텍스트 표시 위젯**
  Widget _buildSegmentedView() {
    // 세그먼트가 없으면 빈 컨테이너 반환
    if (widget.processedText.segments == null ||
        widget.processedText.segments!.isEmpty) {
      if (kDebugMode) {
        debugPrint('세그먼트가 없습니다.');
      }

      // 세그먼트가 없으면 전체 텍스트 표시
      return _buildFullTextView();
    }

    if (kDebugMode) {
      debugPrint('세그먼트 수: ${widget.processedText.segments!.length}');
    }

    // 세그먼트 목록을 위젯 목록으로 변환
    List<Widget> segmentWidgets = [];

    for (int i = 0; i < widget.processedText.segments!.length; i++) {
      final segment = widget.processedText.segments![i];

      // 디버깅 정보 출력
      if (kDebugMode) {
        debugPrint('세그먼트 $i 원본 텍스트: "${segment.originalText}"');
        debugPrint('세그먼트 $i 번역 텍스트: "${segment.translatedText}"');
        debugPrint('세그먼트 $i 핀인: "${segment.pinyin}"');
      }

      // 원본 텍스트가 비어있으면 건너뜀
      if (segment.originalText.isEmpty) {
        if (kDebugMode) {
          debugPrint('세그먼트 $i 원본 텍스트가 비어있어 건너뜁니다.');
        }
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
              // TTS 버튼 추가
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(
                      _playingSegmentIndex == i
                          ? Icons.stop_circle
                          : Icons.play_circle,
                      color:
                          _playingSegmentIndex == i ? Colors.red : Colors.blue,
                    ),
                    onPressed: () {
                      _playTts(segment.originalText, segmentIndex: i);
                    },
                    tooltip: _playingSegmentIndex == i ? '중지' : '읽기',
                    iconSize: 24,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
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
                  child: _buildSelectableText(segment.translatedText!),
                ),
            ],
          ),
        ),
      );
    }

    // 세그먼트 위젯이 없으면 전체 텍스트 표시
    if (segmentWidgets.isEmpty) {
      if (kDebugMode) {
        debugPrint('세그먼트 위젯이 없어 전체 텍스트를 표시합니다.');
      }
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
    if (kDebugMode) {
      debugPrint('ProcessedTextWidget.build 호출');
      debugPrint('showFullText: ${widget.processedText.showFullText}');
      debugPrint('segments 존재 여부: ${widget.processedText.segments != null}');
      if (widget.processedText.segments != null) {
        debugPrint('segments 개수: ${widget.processedText.segments!.length}');
      }
      debugPrint(
          'fullOriginalText: "${widget.processedText.fullOriginalText}"');
      debugPrint(
          'fullTranslatedText: "${widget.processedText.fullTranslatedText}"');
    }

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

          // 하단 컨트롤 바 추가
          _buildBottomControlBar(),
        ],
      ),
    );
  }

  /// **하단 컨트롤 바 위젯**
  Widget _buildBottomControlBar() {
    return Container(
      margin: const EdgeInsets.only(top: 16.0),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 모드 표시
          Text(
            widget.processedText.segments != null &&
                    !widget.processedText.showFullText
                ? '세그먼트 모드'
                : '전체 텍스트 모드',
            style: const TextStyle(
              fontSize: 12.0,
              color: Colors.grey,
            ),
          ),

          // 전체 TTS 재생 버튼
          ElevatedButton.icon(
            onPressed: _playingSegmentIndex != null
                ? () {
                    // 재생 중이면 중지
                    _textReaderService.stop();
                  }
                : () {
                    // 전체 텍스트 읽기
                    _textReaderService.readAllSegments(widget.processedText);
                  },
            icon: Icon(
              _playingSegmentIndex != null ? Icons.stop : Icons.play_arrow,
              size: 18,
            ),
            label: Text(
              _playingSegmentIndex != null ? '중지' : '전체 읽기',
              style: const TextStyle(fontSize: 12),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 0),
            ),
          ),
        ],
      ),
    );
  }
}
