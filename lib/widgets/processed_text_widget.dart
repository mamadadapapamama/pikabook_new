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
  final Function(String)? onDictionaryLookup;
  final Function(String, String, {String? pinyin})? onCreateFlashCard;
  final List<FlashCard>? flashCards;
  final Function(int)? onDeleteSegment;

  const ProcessedTextWidget({
    Key? key,
    required this.processedText,
    this.onDictionaryLookup,
    this.onCreateFlashCard,
    this.flashCards,
    this.onDeleteSegment,
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

  // 중복 사전 검색 방지를 위한 변수
  bool _isProcessingDictionaryLookup = false;

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
      debugPrint('플래시카드 목록 변경 감지: didUpdateWidget');
      _extractFlashcardWords();
    }

    // ProcessedText 변경 감지
    if (oldWidget.processedText != widget.processedText) {
      debugPrint('처리된 텍스트 변경 감지: didUpdateWidget');
      
      // 선택된 텍스트 초기화
      setState(() {
        _selectedText = '';
        _selectedTextNotifier.value = '';
      });
    }
    
    // 표시 설정 변경 감지 - 개별 속성 확인
    if (oldWidget.processedText.showFullText != widget.processedText.showFullText) {
      debugPrint('전체 텍스트 모드 변경 감지: ${oldWidget.processedText.showFullText} -> ${widget.processedText.showFullText}');
      setState(() {});
    }
    
    if (oldWidget.processedText.showPinyin != widget.processedText.showPinyin) {
      debugPrint('병음 표시 설정 변경 감지: ${oldWidget.processedText.showPinyin} -> ${widget.processedText.showPinyin}');
      setState(() {});
    }
    
    if (oldWidget.processedText.showTranslation != widget.processedText.showTranslation) {
      debugPrint('번역 표시 설정 변경 감지: ${oldWidget.processedText.showTranslation} -> ${widget.processedText.showTranslation}');
      setState(() {});
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

  /// 하이라이트된 단어 탭 처리
  void _handleHighlightedWordTap(String word) {
    if (_isProcessingDictionaryLookup) return;

    if (kDebugMode) {
      debugPrint('하이라이트된 단어 탭 처리: $word');
    }

    // 중복 호출 방지
    _isProcessingDictionaryLookup = true;

    // 사전 검색 콜백 호출
    if (widget.onDictionaryLookup != null) {
      widget.onDictionaryLookup!(word);
    }

    // 일정 시간 후 플래그 초기화 (중복 호출 방지)
    Future.delayed(const Duration(milliseconds: 500), () {
      _isProcessingDictionaryLookup = false;
    });
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
        // 텍스트가 선택되어 있지 않을 때만 하이라이트된 단어 탭 처리
        if (_selectedText.isEmpty) {
          _handleHighlightedWordTap(word);
        } else if (kDebugMode) {
          debugPrint('텍스트 선택 중에는 하이라이트된 단어 탭 무시: $word');
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
              _selectedTextNotifier.value = '';
              Future.microtask(() {
                if (mounted) {
                  setState(() {
                    _selectedText = '';
                  });
                }
              });
            } else {
              // 텍스트가 선택된 경우, 선택된 텍스트 추출
              try {
                final selectedText =
                    text.substring(selection.start, selection.end);
                if (selectedText.isNotEmpty && selectedText != _selectedText) {
                  if (kDebugMode) {
                    debugPrint('새로운 텍스트 선택됨: "$selectedText"');
                  }
                  // 선택된 텍스트 업데이트
                  _selectedTextNotifier.value = selectedText;
                  Future.microtask(() {
                    if (mounted) {
                      setState(() {
                        _selectedText = selectedText;
                      });
                    }
                  });
                }
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('텍스트 선택 오류: $e');
                }
              }
            }
          },
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

        // 번역 텍스트 표시 (번역이 있고 showTranslation이 true인 경우)
        if (widget.processedText.fullTranslatedText != null && 
            widget.processedText.showTranslation)
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
      return _buildFullTextView();
    }

    // 현재 표시 상태 정보 출력
    debugPrint('세그먼트 뷰 빌드 정보:');
    debugPrint(' - 병음 표시: ${widget.processedText.showPinyin}');
    debugPrint(' - 번역 표시: ${widget.processedText.showTranslation}');
    debugPrint(' - 전체 텍스트 모드: ${widget.processedText.showFullText}');
    debugPrint(' - 위젯 hashCode: ${widget.hashCode}');
    debugPrint(' - ProcessedText hashCode: ${widget.processedText.hashCode}');

    // 세그먼트 목록을 위젯 목록으로 변환
    List<Widget> segmentWidgets = [];

    for (int i = 0; i < widget.processedText.segments!.length; i++) {
      final segment = widget.processedText.segments![i];

      // 원본 텍스트가 비어있으면 건너뜀
      if (segment.originalText.isEmpty) {
        continue;
      }

      // 세그먼트 컨테이너
      Widget segmentContainer = Container(
        margin: const EdgeInsets.only(bottom: 16.0),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.withOpacity(0.2)),
          borderRadius: BorderRadius.circular(8.0),
        ),
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단 컨트롤 바 (TTS 재생 버튼 등)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 드래그 핸들 아이콘 (좌측)
                const Icon(Icons.drag_handle, size: 16, color: Colors.grey),
                
                // TTS 재생 버튼 (우측)
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

            // 원본 텍스트 표시 (항상 표시)
            _buildSelectableText(segment.originalText),

            // 병음 표시 - 직접 processedText의 showPinyin 값 사용
            if (segment.pinyin != null && 
                segment.pinyin!.isNotEmpty && 
                widget.processedText.showPinyin) // 직접 값 참조
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

            // 번역 표시 (번역 표시 조건 명확하게 수정)
            if (segment.translatedText != null &&
                segment.translatedText!.isNotEmpty &&
                widget.processedText.showTranslation)
              Padding(
                padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
                child: _buildSelectableText(segment.translatedText!),
              ),
          ],
        ),
      );
      
      // 삭제 가능 조건: 세그먼트 모드(showFullText=false)이고 onDeleteSegment 콜백이 있을 때만
      if (widget.onDeleteSegment != null && !widget.processedText.showFullText) {
        segmentContainer = Dismissible(
          key: ValueKey('segment_$i'),
          direction: DismissDirection.endToStart, // 오른쪽에서 왼쪽으로 스와이프
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20.0),
            color: Colors.red,
            child: const Icon(
              Icons.delete,
              color: Colors.white,
            ),
          ),
          confirmDismiss: (direction) async {
            // 사용자 확인 다이얼로그 표시
            final bool? confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('세그먼트 삭제'),
                content: const Text('이 세그먼트를 삭제하시겠습니까?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('취소'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('삭제'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ],
              ),
            );
            
            if (confirmed == true) {
              // 세그먼트 삭제 콜백 호출
              widget.onDeleteSegment!(i);
              return true;
            }
            
            return false;
          },
          child: segmentContainer,
        );
      }

      segmentWidgets.add(segmentContainer);
    }

    // 세그먼트 위젯이 없으면 전체 텍스트 표시
    if (segmentWidgets.isEmpty) {
      return _buildFullTextView();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: segmentWidgets,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 텍스트 출력 전에 상태 확인 로그
          Text(
            'ProcessedText 표시: 원본 텍스트 ${widget.processedText.fullOriginalText.length}자, '
            '번역 텍스트 ${widget.processedText.fullTranslatedText?.length ?? 0}자, '
            'segments ${widget.processedText.segments?.length ?? 0}개',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
          
          // 모드에 따라 다른 위젯 표시 (키 추가)
          // 모드나 설정이 변경될 때 항상 새 위젯을 생성하도록 고유 키 사용
          KeyedSubtree(
            key: ValueKey('processed_text_${widget.processedText.showFullText}_'
                '${widget.processedText.showPinyin}_'
                '${widget.processedText.showTranslation}_'
                '${widget.processedText.hashCode}'),
            child: widget.processedText.segments != null &&
                !widget.processedText.showFullText
                ? _buildSegmentedView()
                : _buildFullTextView(),
          ),
        ],
      ),
    );
  }
}
