import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import '../../core/models/processed_text.dart';
import '../../core/models/flash_card.dart';
import '../../core/services/tts/tts_service.dart';
import '../../core/utils/text_highlight_manager.dart';
import '../../core/utils/context_menu_manager.dart';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/utils/segment_utils.dart';
import '../../core/widgets/tts_button.dart';
import '../../core/widgets/dot_loading_indicator.dart';

/// ProcessedTextWidget은 처리된 텍스트(중국어 원문, 병음, 번역)를 표시하는 위젯입니다.
/// 
/// ## 주요 기능
/// - 병음 및 번역 표시 토글
/// - 단어 선택 및 사전 검색
/// - 텍스트 선택 및 컨텍스트 메뉴
/// - 플래시카드 단어 하이라이트
/// - TTS(Text-to-Speech) 기능



class ProcessedTextWidget extends StatefulWidget {
  final ProcessedText processedText;
  final Function(String)? onDictionaryLookup;
  final Function(String, String, {String? pinyin})? onCreateFlashCard;
  final List<FlashCard>? flashCards;
  final Function(int)? onDeleteSegment;
  final Function(String, {int? segmentIndex})? onPlayTts;
  final int? playingSegmentIndex;
  final TextStyle? originalTextStyle;
  final TextStyle? pinyinTextStyle;
  final TextStyle? translatedTextStyle;

  const ProcessedTextWidget({
    Key? key,
    required this.processedText,
    this.onDictionaryLookup,
    this.onCreateFlashCard,
    this.flashCards,
    this.onDeleteSegment,
    this.onPlayTts,
    this.playingSegmentIndex,
    this.originalTextStyle,
    this.pinyinTextStyle,
    this.translatedTextStyle,
  }) : super(key: key);

  @override
  State<ProcessedTextWidget> createState() => _ProcessedTextWidgetState();
}

class _ProcessedTextWidgetState extends State<ProcessedTextWidget> {
  String _selectedText = '';
  late Set<String> _flashcardWords;
  final GlobalKey _textKey = GlobalKey();

  // 중복 사전 검색 방지를 위한 변수
  bool _isProcessingDictionaryLookup = false;

  // 선택된 텍스트 상태 관리를 위한 ValueNotifier
  final ValueNotifier<String> _selectedTextNotifier = ValueNotifier<String>('');

  @override
  void initState() {
    super.initState();
    _flashcardWords = {};
    _extractFlashcardWords();
  }

  @override
  void dispose() {
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
    if (oldWidget.processedText.displayMode != widget.processedText.displayMode) {
      debugPrint('표시 모드 변경 감지: ${oldWidget.processedText.displayMode} -> ${widget.processedText.displayMode}');
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
  Widget _buildSelectableText(
    String text, {
    TextStyle? style,
    bool isOriginal = false,
  }) {
    // 텍스트가 비어있으면 빈 컨테이너 반환
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    if (kDebugMode) {
      debugPrint('_buildSelectableText 호출: 텍스트 길이=${text.length}');
    }
    
    // 스타일이 제공되지 않은 경우 경고
    if (style == null) {
      debugPrint('경고: ProcessedTextWidget에 스타일이 제공되지 않았습니다.');
    }
    
    // 항상 제공된 스타일 사용 (PageContentWidget에서 관리)
    final effectiveStyle = style;
    
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
      normalStyle: effectiveStyle,
    );

    // 클래스 멤버 ValueNotifier 사용
    _selectedTextNotifier.value = _selectedText;

    return ValueListenableBuilder<String>(
      valueListenable: _selectedTextNotifier,
      builder: (context, selectedText, child) {
        return TextSelectionTheme(
          data: TextSelectionThemeData(
            selectionColor: ColorTokens.primary.withOpacity(0.2),
            cursorColor: ColorTokens.primary,
            selectionHandleColor: ColorTokens.primary,
          ),
          child: SelectableText.rich(
            TextSpan(
              children: textSpans,
              style: effectiveStyle,
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
            cursorColor: ColorTokens.primary,
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
          ),
        );
      },
    );
  }

  /// **TTS 재생 메서드**
  void _playTts(String text, {int? segmentIndex}) {
    if (text.isEmpty) return;

    // 부모 위젯의 콜백 호출
    if (widget.onPlayTts != null) {
      widget.onPlayTts!(text, segmentIndex: segmentIndex);
    }
  }

  /// **전체 텍스트 표시**
  Widget _buildFullTextView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 원문 텍스트 표시
        SelectableText(
          widget.processedText.fullOriginalText,
          style: widget.originalTextStyle,
        ),
        const SizedBox(height: 16),
        
        // 번역 텍스트 표시 - 래퍼 제거하고 직접 표시
        if (widget.processedText.fullTranslatedText != null &&
            widget.processedText.fullTranslatedText!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            child: Text(
              widget.processedText.fullTranslatedText!,
              style: widget.translatedTextStyle,
            ),
          ),
      ],
    );
  }

  /// **세그먼트별 텍스트 표시 위젯**
  Widget _buildSegmentedView() {
    // 유닛이 없으면 빈 컨테이너 반환
    if (widget.processedText.units == null ||
        widget.processedText.units.isEmpty) {
      return _buildFullTextView();
    }

    // 현재 표시 상태 정보 출력
    debugPrint('세그먼트 뷰 빌드 정보:');
    debugPrint(' - 표시 모드: ${widget.processedText.displayMode}');
    debugPrint(' - 위젯 hashCode: ${widget.hashCode}');
    debugPrint(' - ProcessedText hashCode: ${widget.processedText.hashCode}');

    List<Widget> unitWidgets = [];

    for (int i = 0; i < widget.processedText.units.length; i++) {
      final unit = widget.processedText.units[i];

      // 원본 텍스트가 비어있으면 건너뜀
      if (unit.originalText.isEmpty) {
        continue;
      }

      // 세그먼트 컨테이너
      Widget segmentContainer = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 원본 텍스트와 TTS 버튼을 함께 표시하는 행
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 원본 텍스트 (확장 가능하게)
              Expanded(
                child: _buildSelectableText(
                  unit.originalText, 
                  style: widget.originalTextStyle,
                  isOriginal: true,
                ),
              ),
              
              // TTS 재생 버튼 - 세그먼트 스타일로 통일
              Padding(
                padding: const EdgeInsets.only(left: 8.0, top: 2.0),
                child: TtsButton(
                  text: unit.originalText,
                  segmentIndex: i,
                  size: TtsButton.sizeMedium, // 중간 크기로 통일
                  tooltip: '무료 TTS 사용량을 모두 사용했습니다.',
                  activeBackgroundColor: ColorTokens.primary.withOpacity(0.2), // 더 뚜렷한 활성화 색상
                ),
              ),
            ],
          ),

          // 병음 표시 - displayMode에 따라 결정
          if (unit.pinyin != null && 
              unit.pinyin!.isNotEmpty && 
              widget.processedText.displayMode == TextDisplayMode.full)
            Padding(
              padding: const EdgeInsets.only(top: 2.0, bottom: 4.0),
              child: Text(
                unit.pinyin!,
                style: widget.pinyinTextStyle,
              ),
            ),

            // 번역 표시 - 항상 표시
            if (unit.translatedText != null &&
                unit.translatedText!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                child: Text(
                  unit.translatedText!,
                  style: widget.translatedTextStyle,
                ),
              ),
        ],
      );
      
      // 세그먼트 컨테이너 래핑
      Widget wrappedSegmentContainer = Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4.0),
        ),
        child: segmentContainer,
      );
      
      // 삭제 가능 조건: 세그먼트 모드(mode=segment)이고 onDeleteSegment 콜백이 있을 때만
      if (widget.onDeleteSegment != null && widget.processedText.mode == TextProcessingMode.segment) {
        final int unitIndex = i;
        wrappedSegmentContainer = SegmentUtils.buildDismissibleSegment(
          key: ValueKey('segment_$i'),
          child: wrappedSegmentContainer,
          onDelete: () => widget.onDeleteSegment!(unitIndex),
        );
      }
      
      unitWidgets.add(wrappedSegmentContainer);
      
      // 구분선 추가 (마지막 유닛이 아닌 경우)
      if (i < widget.processedText.units.length - 1) {
        unitWidgets.add(
          const Padding(
            padding: EdgeInsets.only(top: 16.0, bottom: 16.0),
            child: Divider(height: 1, thickness: 1, color: ColorTokens.dividerLight),
          ),
        );
      }
    }

    // 세그먼트 체크
    if (widget.processedText.units != null && widget.processedText.units.isNotEmpty) {
      int untranslatedUnits = 0;
      for (final unit in widget.processedText.units) {
        if (unit.translatedText == null || unit.translatedText!.isEmpty || unit.translatedText == unit.originalText) {
          untranslatedUnits++;
        }
      }
      debugPrint('ProcessedTextWidget: 유닛 ${widget.processedText.units.length}개 중 $untranslatedUnits개 번역 누락');
    }

    // 세그먼트 위젯이 없으면 전체 텍스트 표시
    if (unitWidgets.isEmpty) {
      return _buildFullTextView();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: unitWidgets,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 특수 마커가 있는 경우 처리 중 표시
    if (widget.processedText.fullOriginalText.contains('___PROCESSING___')) {
      return const Center(
        child: DotLoadingIndicator(message: '텍스트 처리 중이에요!'),
      );
    }

    // 세그먼트 모드인지 전체 텍스트 모드인지에 따라 다른 렌더링
    final bool isFullTextMode = widget.processedText.mode == TextProcessingMode.paragraph;

    // 로딩 확인용
    // debugPrint('[${DateTime.now()}] ProcessedTextWidget build 호출');
    
    // 번역 텍스트 체크 로그 추가
    if (widget.processedText.fullTranslatedText != null && widget.processedText.fullTranslatedText!.isNotEmpty) {
      final sample = widget.processedText.fullTranslatedText!.length > 50 
          ? widget.processedText.fullTranslatedText!.substring(0, 50) + '...' 
          : widget.processedText.fullTranslatedText!;
      debugPrint('ProcessedTextWidget: 번역 텍스트 있음 (${widget.processedText.fullTranslatedText!.length}자)');
      debugPrint('ProcessedTextWidget: 번역 텍스트 샘플 - "$sample"');
    } else {
      debugPrint('ProcessedTextWidget: 번역 텍스트 없음 (null 또는 빈 문자열)');
    }
    
    // 세그먼트별 번역 체크
    if (widget.processedText.units != null && widget.processedText.units.isNotEmpty) {
      int untranslatedUnits = 0;
      for (final unit in widget.processedText.units) {
        if (unit.translatedText == null || unit.translatedText!.isEmpty || unit.translatedText == unit.originalText) {
          untranslatedUnits++;
        }
      }
      debugPrint('ProcessedTextWidget: 유닛 ${widget.processedText.units.length}개 중 $untranslatedUnits개 번역 누락');
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
      child: Container(
        color: ColorTokens.surface, // 배경색을 흰색으로 설정
        padding: const EdgeInsets.only(top: 8.0), // 첫 번째 세그먼트를 위한 상단 패딩 추가
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 모드에 따라 다른 위젯 표시 (키 추가)
            // 모드나 설정이 변경될 때 항상 새 위젯을 생성하도록 고유 키 사용
            KeyedSubtree(
              key: ValueKey('processed_text_${widget.processedText.mode}_'
                  '${widget.processedText.displayMode}_'
                  '${widget.processedText.hashCode}'),
              child: widget.processedText.units != null &&
                  widget.processedText.mode == TextProcessingMode.segment
                  ? _buildSegmentedView()
                  : _buildFullTextView(),
            ),
          ],
        ),
      ),
    );
  }
}
