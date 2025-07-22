import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../../core/models/processed_text.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';

import '../../flashcard/flashcard_view_model.dart';
import '../../../core/widgets/loading_dots_widget.dart';
import '../../../core/utils/context_menu_manager.dart';

import '../../../core/services/common/usage_limit_service.dart';
import '../../../core/widgets/simple_upgrade_modal.dart';
import '../../tts/unified_tts_button.dart';
import '../../../core/services/tts/unified_tts_service.dart';
import 'paragraph_mode_widget.dart';
import '../../../core/services/authentication/auth_service.dart';
import '../../sample/sample_tts_service.dart';
import '../../../core/widgets/dot_loading_indicator.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/services/subscription/unified_subscription_manager.dart';

/// ProcessedTextWidget은 처리된 텍스트(중국어 원문, 병음, 번역)를 표시하는 위젯입니다.

class ProcessedTextWidget extends StatefulWidget {
  final ProcessedText processedText;
  final Function(String)? onDictionaryLookup;
  final Function(String, String, {String? pinyin})? onCreateFlashCard;
  final FlashCardViewModel? flashCardViewModel;
  final Function(String, {int? segmentIndex})? onPlayTts;
  final int? playingSegmentIndex;
  final TextStyle? originalTextStyle;
  final TextStyle? pinyinTextStyle;
  final TextStyle? translatedTextStyle;
  final bool showTtsButtons;
  final bool showTypewriterEffect; // 타이프라이터 효과 여부

  const ProcessedTextWidget({
    Key? key,
    required this.processedText,
    this.onDictionaryLookup,
    this.onCreateFlashCard,
    this.flashCardViewModel,
    this.onPlayTts,
    this.playingSegmentIndex,
    this.originalTextStyle,
    this.pinyinTextStyle,
    this.translatedTextStyle,
    this.showTtsButtons = true,
    this.showTypewriterEffect = false,
  }) : super(key: key);

  @override
  State<ProcessedTextWidget> createState() => _ProcessedTextWidgetState();
}

class _ProcessedTextWidgetState extends State<ProcessedTextWidget> {
  String _selectedText = '';
  final ValueNotifier<String> _selectedTextNotifier = ValueNotifier<String>('');
  Set<String> _flashcardWords = {};

  // TTS 서비스
  final UnifiedTtsService _ttsService = UnifiedTtsService();
  final AuthService _authService = AuthService();
  final SampleTtsService _sampleTtsService = SampleTtsService();
  final UnifiedSubscriptionManager _subscriptionManager = UnifiedSubscriptionManager();
  
  // TTS 리스너 콜백 참조 저장 (dispose 시 제거용)
  Function(int?)? _stateChangedCallback;
  Function()? _completedCallback;
  
  // 기본 스타일 정의
  late TextStyle _defaultOriginalTextStyle;
  late TextStyle _defaultPinyinTextStyle;
  late TextStyle _defaultTranslatedTextStyle;
  
  @override
  void initState() {
    super.initState();
    _initializeFlashcardWords();
    _initializeStyles();
    _initTts();
  }

  /// TTS 초기화
  Future<void> _initTts() async {
    try {
      await _ttsService.init();
      await _ttsService.setLanguage('zh-CN');
      
      // TTS 상태 변경 리스너 설정 (콜백 참조 저장)
      _stateChangedCallback = (segmentIndex) {
        // 위젯이 마운트되어 있고 BuildContext가 유효한 경우에만 setState 호출
        if (mounted && context.mounted) {
          try {
            setState(() {
              // 상태 업데이트는 widget.playingSegmentIndex를 통해 부모에서 관리
            });
          } catch (e) {
            if (kDebugMode) {
              debugPrint('TTS 상태 변경 중 setState 오류: $e');
            }
          }
        }
      };
      _ttsService.setOnPlayingStateChanged(_stateChangedCallback!, mode: TtsMode.normal);
      
      // TTS 재생 완료 리스너 설정 (콜백 참조 저장)
      _completedCallback = () {
        // 위젯이 마운트되어 있고 BuildContext가 유효한 경우에만 setState 호출
        if (mounted && context.mounted) {
          try {
            setState(() {
              // 재생 완료 시 상태 리셋
            });
          } catch (e) {
            if (kDebugMode) {
              debugPrint('TTS 재생 완료 중 setState 오류: $e');
            }
          }
        }
      };
      _ttsService.setOnPlayingCompleted(_completedCallback!, mode: TtsMode.normal);
    } catch (e) {
      if (kDebugMode) {
      debugPrint('TTS 초기화 실패: $e');
      }
    }
  }

  @override
  void dispose() {
    // TTS 리스너 제거 (메모리 누수 및 setState 오류 방지)
    final stateCallback = _stateChangedCallback;
    if (stateCallback != null) {
      _ttsService.removeOnPlayingStateChanged(stateCallback, mode: TtsMode.normal);
    }
    final completedCallback = _completedCallback;
    if (completedCallback != null) {
      _ttsService.removeOnPlayingCompleted(completedCallback, mode: TtsMode.normal);
    }
    
    _selectedTextNotifier.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ProcessedTextWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 텍스트 내용 변경 확인
    final bool hasContentChanged = oldWidget.processedText.fullOriginalText != widget.processedText.fullOriginalText ||
        oldWidget.processedText.fullTranslatedText != widget.processedText.fullTranslatedText ||
        oldWidget.processedText.units.length != widget.processedText.units.length;

    // 표시 모드 변경 확인  
    final bool hasModeChanged = oldWidget.processedText.displayMode != widget.processedText.displayMode ||
        oldWidget.processedText.mode != widget.processedText.mode;

    // 내용이 변경된 경우 선택 상태 초기화
    if (hasContentChanged) {
      if (kDebugMode) {
      debugPrint('처리된 텍스트 변경 감지: didUpdateWidget');
      }
      setState(() {
        _selectedText = '';
        _selectedTextNotifier.value = '';
      });
    }
    // 모드만 변경된 경우 리빌드
    else if (hasModeChanged) {
      setState(() {});
    }

    // FlashCardViewModel 변경 시 단어 목록 업데이트
    if (oldWidget.flashCardViewModel != widget.flashCardViewModel) {
      _initializeFlashcardWords();
    }
  }

  /// TTS 재생 처리
  Future<void> _handleTtsPlay(String text, int segmentIndex) async {
    try {
      // 샘플 모드(로그아웃 상태)에서는 SampleTtsService 사용
      if (_authService.currentUser == null) {
        await _handleSampleModeTts(text, segmentIndex);
        return;
      }

      // TTS 사용량 제한 체크
      final usageService = UsageLimitService();
      final subscriptionState = await _subscriptionManager.getSubscriptionState();
      final limitStatus = await usageService.checkInitialLimitStatus(subscriptionState: subscriptionState);
      
      if (limitStatus['ttsLimitReached'] == true) {
        if (mounted) {
          // TTS 한도 도달 시 업그레이드 모달 표시
        final subscriptionState = await UnifiedSubscriptionManager().getSubscriptionState();
        final modalType = subscriptionState.hasUsedTrial 
            ? UpgradeModalType.premiumOffer 
            : UpgradeModalType.trialOffer;
        
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => SimpleUpgradeModal(type: modalType),
        );
        }
        return;
      }

      // ViewModel을 통해 TTS 처리 (중복 호출 방지)
      if (widget.onPlayTts != null) {
        widget.onPlayTts!(text, segmentIndex: segmentIndex);
      }
    } catch (e) {
      debugPrint('TTS 재생 중 오류: $e');
    }
  }

  /// 샘플 모드에서 TTS 처리 (중복 재생 방지)
  Future<void> _handleSampleModeTts(String text, int segmentIndex) async {
    try {
      // 현재 재생 중인 세그먼트와 같으면 중지
      if (widget.playingSegmentIndex == segmentIndex) {
        await _sampleTtsService.stop();
        if (widget.onPlayTts != null) {
          widget.onPlayTts!('', segmentIndex: null);
        }
      } else {
        // 먼저 상태 업데이트 (재생 시작 상태로 변경)
        if (widget.onPlayTts != null) {
          widget.onPlayTts!(text, segmentIndex: segmentIndex);
        }
        
        // 그 다음에 실제 TTS 재생 (중복 호출 방지)
        await _sampleTtsService.speak(text, context: context);
      }
    } catch (e) {
      debugPrint('샘플 모드 TTS 재생 중 오류: $e');
    }
  }

  /// 일반 TTS 버튼 위젯 생성
  Widget _buildTtsButton(String text, int segmentIndex, bool isPlaying) {
    return UnifiedTtsButton(
      text: text,
      segmentIndex: segmentIndex,
      mode: TtsMode.normal,
      size: 32.0,
      isEnabled: true,
      useCircularShape: true,
      iconColor: ColorTokens.textSecondary,
      activeBackgroundColor: ColorTokens.primary.withOpacity(0.2),
    );
  }

  /// 느린 TTS 버튼 위젯 생성
  Widget _buildSlowTtsButton(String text, int segmentIndex, bool isPlaying) {
    return UnifiedTtsButton(
      text: text,
      segmentIndex: segmentIndex,
      mode: TtsMode.slow,
      size: 24.0,
      isEnabled: true,
      useCircularShape: true,
      iconColor: ColorTokens.textSecondary,
      activeBackgroundColor: ColorTokens.primary.withOpacity(0.2),
    );
  }

  /// **문단별 텍스트 표시** (문단 모드 전용 위젯 사용)
  Widget _buildFullTextView() {
    // 문단 모드인 경우 전용 위젯 사용
    if (widget.processedText.mode == TextProcessingMode.paragraph) {
      return ParagraphModeWidget(
        processedText: widget.processedText,
        flashcardWords: _flashcardWords,
        selectedText: _selectedText,
        selectedTextNotifier: _selectedTextNotifier,
        onSelectionChanged: (selectedText) {
          setState(() {
            _selectedText = selectedText;
          });
        },
        onDictionaryLookup: widget.onDictionaryLookup,
        onCreateFlashCard: widget.onCreateFlashCard,
      );
    }
    
    // 기존 전체 텍스트 표시 (fallback)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 원문 텍스트 표시
        ContextMenuManager.buildSelectableText(
          widget.processedText.fullOriginalText,
          style: _defaultOriginalTextStyle,
          isOriginal: true,
          flashcardWords: _flashcardWords,
          selectedText: _selectedText,
          selectedTextNotifier: _selectedTextNotifier,
          onSelectionChanged: (selectedText) {
            setState(() {
              _selectedText = selectedText;
            });
          },
          onDictionaryLookup: widget.onDictionaryLookup,
          onCreateFlashCard: widget.onCreateFlashCard,
        ),
        const SizedBox(height: 16),
        
        // 번역 텍스트 표시 (스트리밍 상태 고려)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
          child: widget.processedText.fullTranslatedText != null &&
                  widget.processedText.fullTranslatedText!.isNotEmpty
              ? Text(
              widget.processedText.fullTranslatedText!,
              style: _defaultTranslatedTextStyle,
                )
              : widget.processedText.isStreaming
                  ? LoadingDotsWidget(
                      style: _defaultTranslatedTextStyle,
                      usePinyinStyle: false,
                    )
                  : const SizedBox.shrink(),
          ),
      ],
    );
  }

  /// 세그먼트 단위 표시 (타이프라이터 효과 지원)
  Widget _buildSegmentView() {
    final List<Widget> unitWidgets = [];

    if (kDebugMode) {
      debugPrint('🔧 _buildSegmentView 호출');
      debugPrint('   showTypewriterEffect: ${widget.showTypewriterEffect}');
      debugPrint('   units 개수: ${widget.processedText.units.length}');
    }

    for (int i = 0; i < widget.processedText.units.length; i++) {
      final unit = widget.processedText.units[i];
      final isPlaying = widget.playingSegmentIndex == i;
      final hasTranslation = unit.translatedText != null && unit.translatedText!.isNotEmpty;

      if (kDebugMode && i < 3) {
        debugPrint('   세그먼트 $i: "${unit.originalText.length > 20 ? unit.originalText.substring(0, 20) + "..." : unit.originalText}"');
        debugPrint('     번역: ${hasTranslation ? "있음" : "없음"}');
        debugPrint('     타이프라이터 적용: ${widget.showTypewriterEffect}');
      }

      // 세그먼트 컨테이너
      Widget segmentContainer = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 원문 표시 (일반 텍스트로 바로 표시)
          Row(
            children: [
              Expanded(
                child: ContextMenuManager.buildSelectableText(
                  unit.originalText,
                  style: _defaultOriginalTextStyle,
                  isOriginal: true,
                        flashcardWords: _flashcardWords,
                  selectedText: _selectedText,
                  selectedTextNotifier: _selectedTextNotifier,
                        onSelectionChanged: (selectedText) {
                          setState(() {
                            _selectedText = selectedText;
                          });
                        },
                  onDictionaryLookup: widget.onDictionaryLookup,
                  onCreateFlashCard: widget.onCreateFlashCard,
                ),
              ),
              if (widget.showTtsButtons) ...[
                _buildTtsButton(unit.originalText, i, isPlaying),
                const SizedBox(width: 4),
                _buildSlowTtsButton(unit.originalText, i, isPlaying),
              ],
            ],
          ),

          // 병음 표시 (스트리밍 상태 고려)
          if (widget.processedText.displayMode == TextDisplayMode.full)
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: unit.pinyin != null && unit.pinyin!.isNotEmpty
                  ? Text(
                      unit.pinyin!,
                      style: _defaultPinyinTextStyle,
                    )
                  : widget.processedText.isStreaming
                      ? LoadingDotsWidget(
                          style: _defaultPinyinTextStyle,
                          usePinyinStyle: true,
                        )
                      : const SizedBox.shrink(),
            ),

          // 번역 표시 (스트리밍 상태 고려)
          Padding(
            padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
            child: hasTranslation
                ? Text(
                    unit.translatedText!,
                    style: _defaultTranslatedTextStyle,
                  )
                : widget.processedText.isStreaming
                    ? LoadingDotsWidget(
                        style: _defaultTranslatedTextStyle,
                        usePinyinStyle: false,
                      )
                    : const SizedBox.shrink(),
          ),
        ],
      );
      
      unitWidgets.add(segmentContainer);
      
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
    final buildStartTime = DateTime.now();
    
    // 문장별 모드인지 문단별 모드인지에 따라 다른 렌더링
    final bool isParagraphMode = widget.processedText.mode == TextProcessingMode.paragraph;
    final bool hasUnits = widget.processedText.units.isNotEmpty;
    final bool hasTranslation = widget.processedText.fullTranslatedText.isNotEmpty;

    if (kDebugMode) {
      debugPrint('🎨 [UI] ProcessedTextWidget build 시작');
      debugPrint('   모드: ${widget.processedText.mode.name}, 유닛: ${widget.processedText.units.length}개');
      
      if (isParagraphMode && !hasUnits) {
        debugPrint('   문단모드: LLM 응답 대기 중 (빈 상태)');
      } else if (hasTranslation) {
        debugPrint('   번역 텍스트: ${widget.processedText.fullTranslatedText.length}자');
      } else {
        debugPrint('   번역 텍스트: 없음');
      }
    }

    // 문단모드에서 유닛이 없으면 로딩 상태 표시
    if (isParagraphMode && !hasUnits) {
      if (kDebugMode) {
        debugPrint('🎨 [UI] 문단모드 로딩 상태 반환');
      }
      return _buildLoadingState();
    }

    // 문장 바깥 탭 시 선택 취소를 위한 GestureDetector 추가
    final result = GestureDetector(
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
              child: widget.processedText.units.isNotEmpty &&
                  widget.processedText.mode == TextProcessingMode.segment
                  ? _buildSegmentView() // 문장별 표시
                  : _buildFullTextView(), // 문단별 표시
            ),
          ],
        ),
      ),
    );

    if (kDebugMode) {
      final buildEndTime = DateTime.now();
      final buildTime = buildEndTime.difference(buildStartTime).inMilliseconds;
      debugPrint('🎨 [UI] ProcessedTextWidget build 완료: ${buildTime}ms');
      if (buildTime > 100) {
        debugPrint('⚠️ [UI] 렌더링 시간이 100ms를 초과했습니다: ${buildTime}ms');
      }
    }

    return result;
  }

  /// 플래시카드 단어 목록 초기화
  void _initializeFlashcardWords() {
    if (widget.flashCardViewModel != null) {
      _flashcardWords = Set<String>.from(
        widget.flashCardViewModel!.flashCards.map((card) => card.front)
      );
    }
  }

  /// 스타일 초기화
  void _initializeStyles() {
    _defaultOriginalTextStyle = TypographyTokens.subtitle1Cn.copyWith(
      color: ColorTokens.textPrimary,
    );

    _defaultPinyinTextStyle = TypographyTokens.caption.copyWith(
      color: ColorTokens.textGrey,
      height: 1.2,
    );

    _defaultTranslatedTextStyle = TypographyTokens.body2.copyWith(
      color: ColorTokens.textSecondary,
      height: 1.5,
    );
  }

  Widget _buildLoadingState() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const SizedBox(height: 20),
          DotLoadingIndicator(
            dotSize: 12.0,
            dotColor: ColorTokens.primary,
          ),
          const SizedBox(height: 16),
          Text(
            ErrorHandler.analyzingTextMessage,
            style: TypographyTokens.caption.copyWith(
              color: ColorTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
