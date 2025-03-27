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
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/segment_utils.dart';

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
    
    // 기본 스타일 설정
    final TextStyle defaultStyle = isOriginal 
      ? TypographyTokens.body1.copyWith(
          fontSize: 18, 
          height: 1.5,
          color: ColorTokens.textPrimary,
        )
      : TypographyTokens.body2.copyWith(
          fontSize: 14,
          color: ColorTokens.textSecondary,
        );
        
    // 제공된 스타일 또는 기본 스타일 사용
    final effectiveStyle = style ?? defaultStyle;

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
        return SelectableText.rich(
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

  /// **전체 텍스트 표시**
  Widget _buildFullTextView() {
    // 전체 텍스트를 위한 Column 위젯 (전체 너비 사용)
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 원본 텍스트 표시
        if (widget.processedText.fullOriginalText.isNotEmpty)
          _buildSelectableText(
            widget.processedText.fullOriginalText,
            style: TypographyTokens.subtitle2Cn.copyWith(
              fontWeight: FontWeight.w500, 
              height: 1.5,
              color: ColorTokens.textPrimary,
            ),
            isOriginal: true,
          ),

        // 번역 텍스트 표시 - 래퍼 제거하고 직접 표시
        if (widget.processedText.showTranslation &&
            widget.processedText.fullTranslatedText != null &&
            widget.processedText.fullTranslatedText!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
            child: Text(
              widget.processedText.fullTranslatedText!,
              style: TypographyTokens.body1.copyWith(
                color: ColorTokens.textSecondary,
              ),
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
                  segment.originalText, 
                   style: TypographyTokens.subtitle2Cn.copyWith(
                    fontWeight: FontWeight.w500, 
                    color: ColorTokens.textPrimary,
                  ),
                  isOriginal: true,
                ),
              ),
              
              // TTS 재생 버튼
              GestureDetector(
                onTap: () {
                  _playTts(segment.originalText, segmentIndex: i);
                },
                child: Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(left: 8),
                  decoration: BoxDecoration(
                    color: ColorTokens.segmentButtonBackground,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Icon(
                    _playingSegmentIndex == i
                        ? Icons.stop
                        : Icons.volume_up,
                    color: ColorTokens.textSecondary,
                    size: 14,
                  ),
                ),
              ),
            ],
          ),

          // 병음 표시 - 직접 processedText의 showPinyin 값 사용
          if (segment.pinyin != null && 
              segment.pinyin!.isNotEmpty && 
              widget.processedText.showPinyin)
            Padding(
              padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
              child: Text(
                segment.pinyin!,
                style: TypographyTokens.body2En.copyWith(
                  color: ColorTokens.textGrey,
                  fontWeight:FontWeight.w400,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),

            // 번역 표시
            if (segment.translatedText != null &&
                segment.translatedText!.isNotEmpty &&
                widget.processedText.showTranslation)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                child: Text(
                  segment.translatedText!,
                  style: TypographyTokens.body1.copyWith(
                    color: ColorTokens.textSecondary,
                  ),
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
      
      // 삭제 가능 조건: 세그먼트 모드(showFullText=false)이고 onDeleteSegment 콜백이 있을 때만
      if (widget.onDeleteSegment != null && !widget.processedText.showFullText) {
        final int segmentIndex = i;
        wrappedSegmentContainer = SegmentUtils.buildDismissibleSegment(
          key: ValueKey('segment_$i'),
          direction: DismissDirection.endToStart,
          onDelete: () {
            widget.onDeleteSegment!(segmentIndex);
          },
          confirmDismiss: (direction) async {
            return await showDialog<bool>(
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
                    style: TextButton.styleFrom(foregroundColor: ColorTokens.error),
                  ),
                ],
              ),
            );
          },
          child: wrappedSegmentContainer,
        );
      }

      // 구분선을 포함한 위젯 목록에 추가
      segmentWidgets.add(wrappedSegmentContainer);
      
      // 구분선 추가 (마지막 세그먼트가 아닌 경우)
      if (i < widget.processedText.segments!.length - 1) {
        segmentWidgets.add(
          const Padding(
            padding: EdgeInsets.only(top: 16.0, bottom: 16.0),
            child: Divider(height: 1, thickness: 1, color: ColorTokens.dividerLight),
          ),
        );
      }
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
    // 로딩 확인용
    debugPrint('[${DateTime.now()}] ProcessedTextWidget build 호출');
    
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
      ),
    );
  }
}
