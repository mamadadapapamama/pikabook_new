import 'package:flutter/material.dart';
import 'package:flip_card/flip_card.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:provider/provider.dart';
import '../../core/models/flash_card.dart';
import 'flashcard_view_model.dart';
import 'flashcard_ui.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../core/widgets/pika_app_bar.dart';

/// 플래시카드 화면 전체 위젯 (플래시카드 UI 로드, app bar, bottom controls)
/// 플래시카드 UI interaction 담당 (swipe, flip, tts, delete )
/// 사전 검색 및 플래시카드 내용 추가
///
class FlashCardScreen extends StatefulWidget {
  final String? noteId; // 특정 노트의 플래시카드만 표시할 때 사용
  final List<FlashCard>? initialFlashcards; // 초기 플래시카드 목록
  final bool isTtsEnabled; // TTS 활성화 여부 (외부에서 제어)

  const FlashCardScreen({
    super.key, 
    this.noteId,
    this.initialFlashcards,
    this.isTtsEnabled = true,
  });

  @override
  State<FlashCardScreen> createState() => _FlashCardScreenState();
}

class _FlashCardScreenState extends State<FlashCardScreen> {
  late FlashCardViewModel _viewModel;
  final CardSwiperController _cardController = CardSwiperController();
  final GlobalKey<FlipCardState> _flipCardKey = GlobalKey<FlipCardState>();
  @override
  void initState() {
    super.initState();
    // 뷰모델 초기화 (플래시카드 화면은 노트 생성 중이 아님)
    _viewModel = FlashCardViewModel(
      noteId: widget.noteId ?? '',
      initialFlashcards: widget.initialFlashcards,
      isNoteCreation: false, // 플래시카드 화면은 항상 기존 노트
    );
  }

  @override
  void dispose() {
    _cardController.dispose();
    super.dispose();
  }

  /// 카드 스와이프 처리
  bool _onSwipe(
      int? previousIndex, int? currentIndex, CardSwiperDirection direction) {
    if (_viewModel.flashCards.isEmpty) return false;

    debugPrint(
        '스와이프: 이전 인덱스=$previousIndex, 현재 인덱스=$currentIndex, 방향=$direction');

    // 플래시카드가 1개일 때 특별 처리
    if (_viewModel.flashCards.length == 1) {
      // 위로 스와이프: 카드 삭제
      if (direction == CardSwiperDirection.top) {
        _viewModel.deleteCurrentCard();
      }
      // 다른 방향으로 스와이프: 무시
      return false; // 스와이프 취소
    }

    // 🔧 수정: 플래시카드가 2개 이상일 때의 처리
    // 위로 스와이프: 카드 삭제
    if (direction == CardSwiperDirection.top) {
      _viewModel.deleteCurrentCard();
      return true;
    }
    
    // 좌우 스와이프: 카드 이동
    if (direction == CardSwiperDirection.left || direction == CardSwiperDirection.right) {
      // CardSwiper가 자동으로 인덱스를 업데이트하므로, 현재 인덱스를 사용
      if (currentIndex != null && currentIndex < _viewModel.flashCards.length) {
        _viewModel.setCurrentCardIndex(currentIndex);
        
        // 현재 카드의 복습 횟수 업데이트
        _viewModel.updateReviewCount(_viewModel.flashCards[currentIndex].id);
      }
      return true;
    }

    return false;
  }

  /// 단어를 사전에서 검색
  void _searchWordInDictionary(String word) {
    if (word.isEmpty) return;
    
    _viewModel.searchWordInDictionary(
      word,
      (isLoading) {
        setState(() {
          _viewModel.setLoading(isLoading);
        });
      },
      (message) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    );
  }

  /// 뒤로 가기 처리
  Future<bool> _handleBackButtonPressed() async {
    // 결과 반환: 플래시카드 개수와 함께 플래시카드 목록도 반환
    Navigator.of(context).pop({
      'count': _viewModel.flashCards.length,
      'flashcards': _viewModel.flashCards
    });
    
    return false; // 이미 명시적으로 pop을 호출했으므로 false 반환
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Consumer<FlashCardViewModel>(
        builder: (context, viewModel, child) {
          return PopScope(
            canPop: false,
            onPopInvoked: (didPop) {
              if (!didPop) {
                _handleBackButtonPressed();
              }
            },
            child: Scaffold(
              backgroundColor: Colors.white,
              appBar: PikaAppBar.flashcard(
                onBackPressed: _handleBackButtonPressed,
                currentCardIndex: viewModel.currentCardIndex,
                totalCards: viewModel.flashCards.length,
              ),
              body: Stack(
                children: [
                  // 로딩 중이면 로딩 인디케이터 표시
                  if (viewModel.isLoading)
                    const Center(
                      child: CircularProgressIndicator(),
                    )
                  // 오류가 있으면 오류 메시지 표시
                  else if (viewModel.error != null)
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline,
                              size: SpacingTokens.iconSizeXLarge, 
                              color: ColorTokens.error),
                          SizedBox(height: SpacingTokens.md),
                          Text(
                            viewModel.error!, 
                            textAlign: TextAlign.center,
                            style: TypographyTokens.body1.copyWith(
                              color: ColorTokens.textPrimary,
                            ),
                          ),
                          SizedBox(height: SpacingTokens.md),
                          ElevatedButton(
                            onPressed: () {
                              if (widget.noteId != null) {
                                viewModel.loadFlashCards();
                              } else {
                                viewModel.loadAllFlashCards();
                              }
                            },
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
                              '돌아가기',
                              style: TypographyTokens.button.copyWith(
                                color: ColorTokens.textLight,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  // 플래시카드가 없으면 빈 상태 표시
                  else if (viewModel.flashCards.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
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
                            const SizedBox(height: SpacingTokens.lg),
                            
                            // 제목 텍스트
                            Text(
                              '잘 안외워지는 단어는,\n플래시카드로 만들어봐요!',
                              textAlign: TextAlign.center,
                              style: TypographyTokens.subtitle1.copyWith(
                                color: ColorTokens.textPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: SpacingTokens.sm),
                            
                            // 설명 텍스트
                            Text(
                              '스마트 노트에서 단어를 선택해\n플래시카드로 추가하세요.',
                              textAlign: TextAlign.center,
                              style: TypographyTokens.body2.copyWith(
                                color: ColorTokens.textSecondary,
                              ),
                            ),
                            const SizedBox(height: SpacingTokens.xl),
                            
                            // 노트로 돌아가기 버튼
                            GestureDetector(
                              onTap: _handleBackButtonPressed,
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
                    )
                  // 플래시카드가 있으면 카드 스와이퍼 표시
                  else
                    Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(SpacingTokens.md),
                          child: CardSwiper(
                            controller: _cardController,
                            cardsCount: viewModel.flashCards.length,
                            onSwipe: _onSwipe,
                            allowedSwipeDirection: viewModel.flashCards.length == 1
                                ? const AllowedSwipeDirection.only(up: true)
                                : const AllowedSwipeDirection.symmetric(
                                    horizontal: true,
                                    vertical: true,
                                  ),
                            onSwipeDirectionChange: (_, __) {},
                            numberOfCardsDisplayed: viewModel.flashCards.length == 1 
                                ? 1 
                                : (viewModel.flashCards.length >= 3 ? 3 : viewModel.flashCards.length),
                            padding: const EdgeInsets.all(SpacingTokens.lg),
                            isLoop: viewModel.flashCards.length > 1,
                            threshold: 50,
                            maxAngle: 30,
                            duration: const Duration(milliseconds: 200),
                            initialIndex: viewModel.currentCardIndex,
                            cardBuilder: (context, index, horizontalThreshold,
                                verticalThreshold) {
                              final double scale;
                              final double yOffset;

                              if (viewModel.flashCards.length == 1) {
                                scale = 1.0;
                                yOffset = 0.0;
                              } else {
                                // 🔧 수정: 안전한 인덱스 계산으로 stack overflow 방지
                                final int cardCount = viewModel.flashCards.length;
                                final int currentIdx = viewModel.currentCardIndex.clamp(0, cardCount - 1);
                                
                                final bool isCurrentCard = index == currentIdx;
                                final bool isNextCard = cardCount > 1 && index == ((currentIdx + 1) % cardCount);
                                
                                if (isCurrentCard) {
                                  scale = 1.0;
                                  yOffset = 0.0;
                                } else if (isNextCard) {
                                  scale = 0.95;  // 두 번째 카드는 5% 작게
                                  yOffset = 20.0; // 아래로 20px 이동
                                } else {
                                  scale = 0.9;   // 나머지 카드들은 10% 작게
                                  yOffset = 40.0; // 아래로 40px 이동
                                }
                              }

                              return FlashCardUI.buildFlashCard(
                                card: viewModel.flashCards[index],
                                index: index,
                                currentIndex: viewModel.currentCardIndex,
                                flipCardKey: (index >= 0 && 
                                  index < viewModel.flashCards.length && 
                                  index == viewModel.currentCardIndex.clamp(0, viewModel.flashCards.length - 1))
                                    ? _flipCardKey
                                    : null,
                                isSpeaking: false, // UnifiedTtsButton이 자체 상태 관리
                                onFlip: () {
                                  viewModel.toggleCardFlip();
                                },
                                onSpeak: () {}, // 빈 함수 - UnifiedTtsButton이 자체 처리
                                onStopSpeaking: () {}, // 빈 함수 - UnifiedTtsButton이 자체 처리
                                getNextCardInfo: () => viewModel.getNextCardInfo(),
                                getPreviousCardInfo: () => viewModel.getPreviousCardInfo(),
                                onWordTap: _searchWordInDictionary,
                                onDelete: () => viewModel.deleteCurrentCard(),
                                scale: scale,
                                offset: Offset(0, yOffset),
                                isTtsEnabled: widget.isTtsEnabled,
                                ttsTooltip: !widget.isTtsEnabled ? '무료 사용량을 모두 사용했습니다.' : null,
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
                            color: ColorTokens.surface.withAlpha(0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // 삭제 버튼
                                Icon(
                                  Icons.delete_outline,
                                  color: ColorTokens.disabled,
                                  size: SpacingTokens.iconSizeMedium,
                                ),
                                const SizedBox(height: SpacingTokens.xsHalf),
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
                        if (viewModel.flashCards.length > 1)
                          Positioned(
                            bottom: SpacingTokens.xl,
                            left: 0,
                            right: 0,
                            child: Material(
                              color: ColorTokens.surface.withAlpha(0),
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
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
