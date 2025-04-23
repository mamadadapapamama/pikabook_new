import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flip_card/flip_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/models/flash_card.dart';
import '../../core/models/note.dart';
import '../../core/models/dictionary.dart';
import '../../core/services/content/flashcard_service.dart' hide debugPrint;
import '../../core/services/media/tts_service.dart';
import '../../core/widgets/loading_experience.dart';
import '../../core/services/dictionary/external_cn_dictionary_service.dart';
import 'flashcard_ui.dart';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import '../../core/theme/tokens/spacing_tokens.dart';
import '../../core/widgets/pika_app_bar.dart';
import '../../core/services/storage/unified_cache_service.dart';
import '../../core/services/common/usage_limit_service.dart';
import '../../core/widgets/usage_dialog.dart';

/// 플래시카드 화면 전체 위젯 (플래시카드 UI 로드, app bar, bottom controls)
/// 플래시카드 UI interaction 담당 (swipe, flip, tts, delete )
/// 사전 검색 및 플래시카드 내용 추가
///
class FlashCardScreen extends StatefulWidget {
  final String? noteId; // 특정 노트의 플래시카드만 표시할 때 사용
  final List<FlashCard>? initialFlashcards; // 초기 플래시카드 목록

  const FlashCardScreen({
    super.key, 
    this.noteId,
    this.initialFlashcards,
  });

  @override
  State<FlashCardScreen> createState() => _FlashCardScreenState();
}

class _FlashCardScreenState extends State<FlashCardScreen> {
  final FlashCardService _flashCardService = FlashCardService();
  final TtsService _ttsService = TtsService();
  final ExternalCnDictionaryService _dictionaryService =
      ExternalCnDictionaryService();
  final CardSwiperController _cardController = CardSwiperController();
  final GlobalKey<FlipCardState> _flipCardKey = GlobalKey<FlipCardState>();

  List<FlashCard> _flashCards = []; // 플래시카드 목록
  bool _isLoading = true; // 로딩 상태
  int _currentIndex = 0; // 현재 보고 있는 카드 인덱스
  bool _isFlipped = false; // 카드 뒤집힘 상태
  bool _isSpeaking = false; // TTS 실행 중 상태
  String? _error; // 오류 메시지
  String? _selectedNoteId;

  @override
  void initState() {
    super.initState();
    // 초기 플래시카드가 있는 경우 바로 사용
    if (widget.initialFlashcards != null && widget.initialFlashcards!.isNotEmpty) {
      setState(() {
        _flashCards = widget.initialFlashcards!;
        _isLoading = false;
      });
      // 사용량 업데이트는 여전히 수행
      if (_flashCards.isNotEmpty) {
        _updateFlashCardReviewCount();
      }
    } else {
      // 기존 방식대로 로드
      _loadFlashCards();
    }
    _initTts(); // TTS 초기화
    // 중국어 사전은 필요할 때만 로드하도록 변경
  }

  @override
  void dispose() {
    _ttsService.dispose();
    _cardController.dispose();
    super.dispose();
  }

  /// TTS 서비스 초기화
  Future<void> _initTts() async {
    try {
      await _ttsService.init();
    } catch (e) {
      debugPrint('TTS 초기화 중 오류 발생: $e');
    }
  }

  /// 플래시카드 목록 로드
  Future<void> _loadFlashCards() async {
    try {
      // noteId가 있으면 해당 노트의 플래시카드만, 없으면 모든 플래시카드 로드
      _flashCards = widget.noteId != null
          ? await _flashCardService.getFlashCardsForNote(widget.noteId!)
          : await _flashCardService.getAllFlashCards();

      // 초기화 인덱스 설정
      _currentIndex = 0;
      _isFlipped = false;

      // 플래시카드가 있으면 첫 번째 카드의 복습 횟수 업데이트
      if (_flashCards.isNotEmpty) {
        await _updateFlashCardReviewCount();
      }
    } catch (e) {
      debugPrint('플래시카드를 불러오는 중 오류가 발생했습니다: $e');
      // 에러를 LoadingExperience에서 처리하기 위해 에러를 throw
      throw '플래시카드를 불러오는 중 오류가 발생했습니다: $e';
    }
  }

  /// 플래시카드 복습 횟수 업데이트
  Future<void> _updateFlashCardReviewCount() async {
    if (_flashCards.isEmpty || _currentIndex >= _flashCards.length) return;

    try {
      final updatedCard =
          await _flashCardService.updateFlashCard(_flashCards[_currentIndex]);

      if (mounted) {
        setState(() {
          _flashCards[_currentIndex] = updatedCard;
        });
      }
    } catch (e) {
      debugPrint('플래시카드 복습 횟수 업데이트 중 오류 발생: $e');
    }
  }

  /// 카드 뒤집기
  void _flipCard() {
    _flipCardKey.currentState?.toggleCard();
    setState(() => _isFlipped = !_isFlipped);
  }

  /// 음성 재생 기능 (TTS)
  Future<void> _speakText() async {
    if (_flashCards.isEmpty) return;
    if (_isSpeaking) {
      await _stopSpeaking();
      return;
    }

    // TTS 사용량 제한 확인
    final usageLimitService = UsageLimitService();
    final limitStatus = await usageLimitService.checkFreeLimits();
    if (limitStatus['ttsLimitReached'] == true) {
      // 제한에 도달한 경우 다이얼로그 표시
      if (mounted) {
        UsageDialog.show(
          context,
          limitStatus: limitStatus,
          usagePercentages: await usageLimitService.getUsagePercentages(),
          onContactSupport: () {
            // TODO: 지원팀 문의 기능 추가
          },
        );
      }
      return;
    }

    // 항상 중국어(front)만 읽도록 수정
    final textToSpeak = _flashCards[_currentIndex].front;

    if (textToSpeak.isEmpty) return;

    setState(() {
      _isSpeaking = true;
    });

    try {
      // 항상 중국어 발음으로 설정
      await _ttsService.setLanguage('zh-CN');
      await _ttsService.speak(textToSpeak);

      // 음성 재생이 완료되면 상태 업데이트
      // CompletionHandler에서 처리하기 위해 특별한 콜백 등록
      _ttsService.setOnPlayingCompleted(() {
        if (mounted && _isSpeaking) {
          setState(() {
            _isSpeaking = false;
          });
          debugPrint('플래시카드 TTS 재생 완료 이벤트 수신');
        }
      });
      
      // 안전장치로 타임아웃 설정 (재생 시간이 길어도 최대 10초 후 상태 리셋)
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted && _isSpeaking) {
          setState(() {
            _isSpeaking = false;
          });
          debugPrint('플래시카드 TTS 타임아웃으로 상태 리셋');
        }
      });
    } catch (e) {
      debugPrint('TTS 실행 중 오류 발생: $e');
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('음성 재생 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  /// TTS 중지
  Future<void> _stopSpeaking() async {
    if (!_isSpeaking) return;

    try {
      await _ttsService.stop();
    } catch (e) {
      debugPrint('TTS 중지 중 오류 발생: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    }
  }

  /// 카드 스와이프 처리
  bool _onSwipe(
      int? previousIndex, int? currentIndex, CardSwiperDirection direction) {
    if (_flashCards.isEmpty) return false;

    debugPrint(
        '스와이프: 이전 인덱스=$previousIndex, 현재 인덱스=$currentIndex, 방향=$direction');

    // 플래시카드가 1개일 때 특별 처리
    if (_flashCards.length == 1) {
      // 위로 스와이프: 카드 삭제
      if (direction == CardSwiperDirection.top) {
        _deleteCurrentCard();
      }
      // 다른 방향으로 스와이프: 무시
      return false; // 스와이프 취소
    }

    // 플래시카드가 2개 이상일 때 일반 처리
    // CardSwiper가 자동으로 인덱스를 업데이트하므로, 현재 인덱스를 사용
    if (currentIndex != null) {
      setState(() {
        _currentIndex = currentIndex;
        _isFlipped = false;
      });
    }

    // 위로 스와이프: 카드 삭제
    if (direction == CardSwiperDirection.top) {
      _deleteCurrentCard();
    }

    _updateFlashCardReviewCount();
    return true;
  }

  /// 현재 카드 삭제
  Future<void> _deleteCurrentCard() async {
    if (_flashCards.isEmpty || _currentIndex >= _flashCards.length) return;

    final flashCardId = _flashCards[_currentIndex].id;
    final noteId = _flashCards[_currentIndex].noteId;

    try {
      // 삭제 전 플래시카드 개수 확인
      final int cardCountBeforeDelete = _flashCards.length;
      debugPrint('카드 삭제 시작: 총 카드 수=$cardCountBeforeDelete, 현재 인덱스=$_currentIndex');

      // 플래시카드 서비스를 통해 카드 삭제
      await _flashCardService.deleteFlashCard(flashCardId, noteId: noteId);

      if (mounted) {
        // 삭제할 카드 인덱스 저장
        final int indexToRemove = _currentIndex;
        
        // 2장에서 1장으로 줄어드는 경우
        final bool willBeOneCardLeft = cardCountBeforeDelete == 2;
        
        setState(() {
          // 카드 삭제
          _flashCards.removeAt(indexToRemove);
          debugPrint('카드 삭제 후: 남은 카드 수=${_flashCards.length}');
          
          // 인덱스 조정 (카드가 하나 이상 남아있을 때만)
          if (_flashCards.isNotEmpty) {
            // 마지막 카드였다면 이전 카드로 인덱스 이동
            if (indexToRemove >= _flashCards.length) {
              _currentIndex = _flashCards.length - 1;
              debugPrint('마지막 카드였으므로 인덱스 조정: $_currentIndex');
            }
            // 그 외에는 현재 인덱스 유지 (자동으로 다음 카드가 보임)
          } else {
            // 카드가 모두 삭제된 경우 인덱스를 0으로 설정
            _currentIndex = 0;
            debugPrint('카드가 모두 삭제되어 인덱스를 0으로 리셋');
          }
        });
        
        // 2장에서 1장으로 줄어든 경우, 다음 프레임에서 처리
        if (willBeOneCardLeft && _flashCards.length == 1) {
          debugPrint('2장에서 1장으로 줄어들어 UI 재구성 예약');
          
          // 다음 프레임에서 화면을 강제로 다시 빌드
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              // UI를 완전히 재구성하기 위해 카드를 임시로 복사하고 새로 설정
              final tempCard = _flashCards.first;
              setState(() {
                _flashCards = [];
                debugPrint('카드 임시 제거: 플래시카드 배열 비움');
              });
              
              // 약간의 지연 후 카드 다시 추가
              Future.delayed(const Duration(milliseconds: 100), () {
                if (mounted) {
                  setState(() {
                    _flashCards = [tempCard];
                    _currentIndex = 0;
                    _isFlipped = false;
                    debugPrint('카드 다시 추가: 인덱스를 0으로 리셋하고 화면 갱신');
                  });
                }
              });
            }
          });
        }
        
        // 삭제 완료 메시지 표시
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('플래시카드가 삭제되었습니다.')),
        );
      }
    } catch (e) {
      debugPrint('플래시카드 삭제 중 오류 발생: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('플래시카드 삭제 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  /// 다음 카드 정보 가져오기
  String? _getNextCardInfo() {
    if (_currentIndex < _flashCards.length - 1) {
      return _flashCards[_currentIndex + 1].front;
    }
    return null;
  }

  /// 이전 카드 정보 가져오기
  String? _getPreviousCardInfo() {
    if (_currentIndex > 0) {
      return _flashCards[_currentIndex - 1].front;
    }
    return null;
  }

  /// 단어를 사전에서 검색
  void _searchWordInDictionary(String word) {
    if (word.isEmpty) return;

    setState(() => _isLoading = true);
    
    // ExternalCnDictionaryService는 lookupWord 메서드로 검색을 수행함
    _dictionaryService.lookupWord(word).then((result) {
      if (mounted) {
        setState(() => _isLoading = false);
        
        if (result['success'] == true && result['entry'] != null) {
          final entry = result['entry'] as DictionaryEntry;
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (context) {
              return DraggableScrollableSheet(
                initialChildSize: 0.4,
                minChildSize: 0.3,
                maxChildSize: 0.7,
                expand: false,
                builder: (context, scrollController) {
                  return Container(
                    padding: const EdgeInsets.all(16.0),
                    child: ListView(
                      controller: scrollController,
                      children: [
                        Card(
                          margin: const EdgeInsets.only(bottom: 8.0),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.word,
                                  style: const TextStyle(
                                    fontSize: 24.0,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4.0),
                                Text(
                                  entry.pinyin,
                                  style: const TextStyle(
                                    fontSize: 18.0,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.blue,
                                  ),
                                ),
                                const SizedBox(height: 8.0),
                                Text(
                                  entry.meaning,
                                  style: const TextStyle(fontSize: 16.0),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        } else {
          // 검색 실패 또는 결과 없음
          final message = result['message'] ?? '\'$word\'에 대한 검색 결과가 없습니다.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
          
          // 사용량 제한 초과 경우
          if (result['limitExceeded'] == true) {
            UsageDialog.show(
              context,
              limitStatus: {'dictionaryLimitReached': true},
              usagePercentages: {'dictionary': 100},
              onContactSupport: () {
                // 지원팀 문의 기능
              },
            );
          }
        }
      }
    }).catchError((e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('단어 검색 중 오류가 발생했습니다: $e')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // 화면을 나갈 때 현재 플래시카드 카운트를 전달 (onBackPressed와 동일한 형식)
        if (widget.noteId != null && mounted) {
          Navigator.of(context).pop({
            'flashcardCount': _flashCards.length,
            'success': _error == null,
            'noteId': widget.noteId,
            'flashcards': _flashCards, // 플래시카드 목록 전체 반환
          });
        }
        return false; // 이미 명시적으로 pop을 호출했으므로 false 반환
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: PikaAppBar.flashcard(
          onBackPressed: () async {
            // 뒤로가기 버튼 클릭 시 현재 플래시카드 수 반환
            // TTS 실행 중인 경우 먼저 중지
            if (_isSpeaking) {
              await _ttsService.stop();
              _isSpeaking = false;
            }
            
            // 화면전환 깜빡임 최소화를 위해 즉시 처리
            Navigator.of(context).pop({
              'flashcardCount': _flashCards.length,
              'success': _error == null,
              'noteId': widget.noteId,
              'flashcards': _flashCards, // 플래시카드 목록 전체 반환
            });
          },
          currentCardIndex: _currentIndex,
          totalCards: _flashCards.length,
        ),
        body: Stack(
          children: [
            // 메인 카드 화면
            LoadingExperience(
              loadingMessage: '플래시카드 로딩 중...',
              loadData: _loadFlashCards,
              errorWidgetBuilder: (error, retry) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline,
                        size: SpacingTokens.iconSizeXLarge, 
                        color: ColorTokens.error),
                    SizedBox(height: SpacingTokens.md),
                    Text(
                      error.toString(), 
                      textAlign: TextAlign.center,
                      style: TypographyTokens.body1.copyWith(
                        color: ColorTokens.textPrimary,
                      ),
                    ),
                    SizedBox(height: SpacingTokens.md),
                    ElevatedButton(
                      onPressed: retry,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ColorTokens.primary,
                        foregroundColor: ColorTokens.textLight,
                        padding: EdgeInsets.symmetric(
                          horizontal: SpacingTokens.md,
                          vertical: SpacingTokens.sm,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
                        ),
                      ),
                      child: Text(
                        '다시 시도',
                        style: TypographyTokens.button.copyWith(
                          color: ColorTokens.textLight,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              emptyStateWidget: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 이미지
                      Image.asset(
                        'assets/images/flashcard_zero.png',
                        width: 160,
                        height: 232,
                        fit: BoxFit.contain,
                      ),
                      SizedBox(height: SpacingTokens.lg),
                      
                      // 제목 텍스트
                      Text(
                        '잘 안외워지는 단어는,\n플래시카드로 만들어봐요!',
                        textAlign: TextAlign.center,
                        style: TypographyTokens.subtitle1.copyWith(
                          color: ColorTokens.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: SpacingTokens.sm),
                      
                      // 설명 텍스트
                      Text(
                        '스마트 노트에서 단어를 선택해\n플래시카드로 추가하세요.',
                        textAlign: TextAlign.center,
                        style: TypographyTokens.body2.copyWith(
                          color: ColorTokens.textSecondary,
                        ),
                      ),
                      SizedBox(height: SpacingTokens.xl),
                      
                      // 노트로 돌아가기 버튼
                      GestureDetector(
                        onTap: () async {
                          // TTS 실행 중인 경우 먼저 중지
                          if (_isSpeaking) {
                            await _ttsService.stop();
                            _isSpeaking = false;
                          }
                          
                          if (widget.noteId != null && mounted) {
                            // 노트 화면으로 돌아가면서 카드 개수 0 전달
                            Navigator.of(context).pop({
                              'flashcardCount': 0,
                              'success': true,
                              'noteId': widget.noteId
                            });
                          } else {
                            Navigator.of(context).pushReplacementNamed('/notes');
                          }
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: SpacingTokens.lg,
                            vertical: SpacingTokens.sm + SpacingTokens.xs
                          ),
                          decoration: BoxDecoration(
                            color: ColorTokens.primary,
                            borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
                          ),
                          child: Text(
                            '노트로 돌아가기',
                            style: TypographyTokens.button.copyWith(
                              color: ColorTokens.textLight,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              isEmptyState: () => _flashCards.isEmpty,
              contentBuilder: (context) => FutureBuilder<bool>(
                future: _ttsService.isTtsAvailable(),
                builder: (context, snapshot) {
                  final bool isTtsEnabled = snapshot.data ?? true;
                  final String ttsTooltip = _ttsService.getTtsLimitMessage();
                  
                  return Stack(
                    children: [
                      Padding(
                        padding: EdgeInsets.all(SpacingTokens.md),
                        child: CardSwiper(
                          controller: _cardController,
                          cardsCount: _flashCards.length,
                          onSwipe: _onSwipe,
                          allowedSwipeDirection: _flashCards.length == 1
                              ? const AllowedSwipeDirection.only(up: true)
                              : AllowedSwipeDirection.symmetric(
                                  horizontal: true,
                                  vertical: true,
                                ),
                          onSwipeDirectionChange: (_, __) {},
                          numberOfCardsDisplayed:
                              _flashCards.length == 1 ? 1 : 2,
                          padding: EdgeInsets.all(SpacingTokens.lg),
                          isLoop: _flashCards.length > 1,
                          cardBuilder: (context, index, horizontalThreshold,
                              verticalThreshold) {
                            debugPrint('CardSwiper가 카드 빌드: index=$index, 총 카드=${_flashCards.length}, 현재 인덱스=$_currentIndex');
                            
                            final double scale;
                            final double yOffset;

                            if (_flashCards.length == 1) {
                              scale = 1.0;
                              yOffset = 0.0;
                              debugPrint('카드 1장만 표시: 스케일=$scale, 오프셋=$yOffset');
                            } else {
                              final int indexDiff = (index - _currentIndex).abs();
                              scale = index == _currentIndex
                                  ? 1.0
                                  : 1.0 - (0.05 * indexDiff);
                              yOffset = index == _currentIndex
                                  ? 0
                                  : 20.0 * indexDiff;
                              debugPrint('여러 카드 표시: 인덱스=$index, 현재 인덱스=$_currentIndex, 스케일=$scale, 오프셋=$yOffset');
                            }

                            return FlashCardUI.buildFlashCard(
                              card: _flashCards[index],
                              index: index,
                              currentIndex: _currentIndex,
                              flipCardKey: index == _currentIndex
                                  ? _flipCardKey
                                  : null,
                              isSpeaking: _isSpeaking,
                              onFlip: () {
                                setState(() => _isFlipped = !_isFlipped);
                              },
                              onSpeak: _speakText,
                              onStopSpeaking: _stopSpeaking,
                              getNextCardInfo: _getNextCardInfo,
                              getPreviousCardInfo: _getPreviousCardInfo,
                              onWordTap: _searchWordInDictionary,
                              onDelete: _deleteCurrentCard,
                              scale: scale,
                              offset: Offset(0, yOffset),
                              isTtsEnabled: isTtsEnabled,
                              ttsTooltip: !isTtsEnabled ? ttsTooltip : null,
                            );
                          },
                        ),
                      ),
                
                      // 삭제 안내 텍스트 (상단)
                      Positioned(
                        top: SpacingTokens.xs,
                        left: 0,
                        right: 0,
                        child: Material(
                          color: ColorTokens.surface.withOpacity(0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // 삭제 버튼
                              Icon(
                                Icons.delete_outline,
                                color: ColorTokens.disabled,
                                size: SpacingTokens.iconSizeMedium,
                              ),
                              SizedBox(height: SpacingTokens.xs/2),
                              // 스와이프 안내 텍스트
                              Text(
                                '위로 스와이프 하면 삭제 됩니다.',
                                style: TypographyTokens.caption.copyWith(
                                  color: ColorTokens.disabled,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      // 이동 안내 텍스트 (하단)
                      if (_flashCards.length > 1)
                        Positioned(
                          bottom: SpacingTokens.xl,
                          left: 0,
                          right: 0,
                          child: Material(
                            color: ColorTokens.surface.withOpacity(0),
                            child: Text(
                              '좌우로 스와이프 해서 다음 카드로 이동',
                              style: TypographyTokens.caption.copyWith(
                                color: ColorTokens.disabled,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
