import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import '../../core/models/processed_text.dart';
import '../../core/models/flash_card.dart';
// import '../../core/utils/context_menu_helper.dart'; // 더 이상 사용하지 않음
// import '../../core/utils/context_menu_manager.dart'; // 더 이상 사용하지 않음
import '../../core/services/text_processing/.text_reader_service.dart';
import '../../core/utils/text_highlight_manager.dart';
// import '../../core/utils/context_menu_manager.dart'; // 중복 임포트 제거
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import '../../core/utils/segment_utils.dart';
import '../../core/widgets/tts_button.dart';
import '../../core/widgets/dot_loading_indicator.dart';
import 'note_detail_state.dart';
import 'text_selection_manager.dart';
import 'text_segment_view.dart';
import 'full_text_view.dart';

/// ProcessedTextWidget은 처리된 텍스트(중국어 원문, 병음, 번역)를 표시하는 위젯입니다.
/// 
/// ## 주요 기능
/// - 세그먼트별 또는 전체 텍스트 모드로 표시
/// - 단어 선택 및 사전 검색
/// - 텍스트 선택 및 컨텍스트 메뉴
/// - 플래시카드 단어 하이라이트
/// - TTS(Text-to-Speech) 기능
/// - 세그먼트 삭제 기능
/// 
/// ## 리팩토링 개선사항
/// - TextSelectionManager로 텍스트 선택 관련 로직 분리
/// - TextSegmentView로 세그먼트 표시 로직 분리
/// - FullTextView로 전체 텍스트 표시 로직 분리

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
  final Function(ComponentState)? onStateChanged;
  final bool showLoadingUI;

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
    this.onStateChanged,
    this.showLoadingUI = false,
  }) : super(key: key);

  @override
  State<ProcessedTextWidget> createState() => _ProcessedTextWidgetState();
}

class _ProcessedTextWidgetState extends State<ProcessedTextWidget> {
  late Set<String> _flashcardWords;
  late TextSelectionManager _selectionManager;

  @override
  void initState() {
    super.initState();
    _flashcardWords = {};
    _extractFlashcardWords();
    _initSelectionManager();
    
    // 위젯 초기화 시 상태 알림
    if (widget.processedText.fullOriginalText != "___PROCESSING___") {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.onStateChanged != null) {
          widget.onStateChanged!(ComponentState.ready);
        }
      });
    }
  }

  void _initSelectionManager() {
    _selectionManager = TextSelectionManager(
      flashcardWords: _flashcardWords,
      onDictionaryLookup: widget.onDictionaryLookup,
      onCreateFlashCard: widget.onCreateFlashCard,
    );
  }

  @override
  void dispose() {
    _selectionManager.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ProcessedTextWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 플래시카드 목록이 변경된 경우
    if (oldWidget.flashCards != widget.flashCards) {
      debugPrint('플래시카드 목록 변경 감지: didUpdateWidget');
      _extractFlashcardWords();
      _initSelectionManager(); // 선택 관리자 재생성
    }

    // ProcessedText 변경 감지
    if (oldWidget.processedText != widget.processedText) {
      debugPrint('처리된 텍스트 변경 감지: didUpdateWidget');
      
      // 선택된 텍스트 초기화
      _selectionManager.clearSelection();
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

  /// **TTS 재생 메서드**
  void _playTts(String text, {int? segmentIndex}) {
    if (text.isEmpty) return;

    // 부모 위젯의 콜백 호출
    if (widget.onPlayTts != null) {
      widget.onPlayTts!(text, segmentIndex: segmentIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final processedText = widget.processedText;
    
    // 처리 중인 경우 - 상태만 보고하고 빈 컨테이너 반환
    if (processedText.fullOriginalText == "___PROCESSING___") {
      // 상태 콜백 호출 (로딩 중)
      if (widget.onStateChanged != null) {
        widget.onStateChanged!(ComponentState.loading);
      }
      
      // 로딩 UI 없이 빈 컨테이너만 반환
      return const SizedBox();
    }

    // 텍스트가 준비되었음을 알림
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.onStateChanged != null) {
        widget.onStateChanged!(ComponentState.ready);
      }
    });

    // 세그먼트 모드인지 전체 텍스트 모드인지에 따라 다른 렌더링
    final bool isFullTextMode = widget.processedText.showFullText;

    // 문장 바깥 탭 시 선택 취소를 위한 GestureDetector 추가
    return GestureDetector(
      onTap: () {
        // 문장 바깥을 탭하면 선택 취소
        _selectionManager.clearSelection();
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
                  ? TextSegmentView(
                      segments: widget.processedText.segments!,
                      processedText: widget.processedText,
                      buildSelectableText: _selectionManager.buildSelectableText,
                      onDeleteSegment: widget.onDeleteSegment,
                      originalTextStyle: widget.originalTextStyle,
                      pinyinTextStyle: widget.pinyinTextStyle,
                      translatedTextStyle: widget.translatedTextStyle,
                    )
                  : FullTextView(
                      processedText: widget.processedText,
                      buildSelectableText: _selectionManager.buildSelectableText,
                      originalTextStyle: widget.originalTextStyle,
                      translatedTextStyle: widget.translatedTextStyle,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
