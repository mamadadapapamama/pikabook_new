import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flip_card/flip_card.dart';
import 'package:flutter/foundation.dart';
import '../../core/models/flash_card.dart';
import '../../core/widgets/loading_experience.dart';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import '../../core/theme/tokens/spacing_tokens.dart';
import '../../core/widgets/pika_app_bar.dart';

/// 샘플 모드의 플래시카드 화면 (플래시카드 UI 로드, app bar, bottom controls)
class SampleFlashCardScreen extends StatefulWidget {
  final List<FlashCard> flashcards;
  final String noteTitle;

  const SampleFlashCardScreen({
    super.key, 
    required this.flashcards,
    required this.noteTitle,
  });

  @override
  State<SampleFlashCardScreen> createState() => _SampleFlashCardScreenState();
}

class _SampleFlashCardScreenState extends State<SampleFlashCardScreen> {
  final CardSwiperController _cardController = CardSwiperController();
  final GlobalKey<FlipCardState> _flipCardKey = GlobalKey<FlipCardState>();

  int _currentIndex = 0;
  bool _isFlipped = false;

  @override
  void dispose() {
    _cardController.dispose();
    super.dispose();
  }

  // 카드 뒤집기
  void _flipCard() {
    _flipCardKey.currentState?.toggleCard();
    setState(() => _isFlipped = !_isFlipped);
  }

  // 다음 카드로 이동
  void _goToNextCard() {
    if (_currentIndex < widget.flashcards.length - 1) {
      _cardController.swipe(CardSwiperDirection.right);
    }
  }

  // 이전 카드로 이동
  void _goToPrevCard() {
    if (_currentIndex > 0) {
      // 이전 카드로 이동하는 기능은 CardSwiper에서 직접 지원하지 않으므로
      // 여기서는 단순히 메시지만 출력합니다.
      if (kDebugMode) {
        print('이전 카드로 이동 - 이 기능은 실제로 작동하지 않습니다.');
      }
    }
  }

  // 현재 진행 상태 표시
  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${_currentIndex + 1}/${widget.flashcards.length}',
            style: TypographyTokens.caption.copyWith(
              color: ColorTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // 하단 컨트롤 버튼 영역
  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 이전 카드 버튼
          IconButton(
            onPressed: _goToPrevCard,
            icon: const Icon(Icons.arrow_back),
            color: ColorTokens.primary,
            tooltip: '이전 카드',
          ),
          
          // 카드 뒤집기 버튼
          IconButton(
            onPressed: _flipCard,
            icon: const Icon(Icons.flip),
            color: ColorTokens.primary,
            tooltip: '카드 뒤집기',
          ),
          
          // 다음 카드 버튼
          IconButton(
            onPressed: _goToNextCard,
            icon: const Icon(Icons.arrow_forward),
            color: ColorTokens.primary,
            tooltip: '다음 카드',
          ),
        ],
      ),
    );
  }

  // 플래시카드 위젯 빌드
  Widget _buildFlashCard(FlashCard card) {
    return FlipCard(
      key: _flipCardKey,
      direction: FlipDirection.HORIZONTAL,
      flipOnTouch: false,
      speed: 400,
      onFlip: () {
        setState(() => _isFlipped = !_isFlipped);
      },
      front: _buildCardSide(card.front, card.pinyin, true),
      back: _buildCardSide(card.back, null, false),
    );
  }

  // 카드 앞/뒷면 빌드
  Widget _buildCardSide(String mainText, String? subText, bool isFront) {
    return Container(
      margin: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                mainText,
                style: isFront
                    ? TypographyTokens.headline1.copyWith(color: ColorTokens.textPrimary)
                    : TypographyTokens.headline2.copyWith(color: ColorTokens.textPrimary),
                textAlign: TextAlign.center,
              ),
              if (subText != null) ...[
                const SizedBox(height: 8),
                Text(
                  subText,
                  style: TypographyTokens.subtitle1.copyWith(
                    color: ColorTokens.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              Text(
                isFront ? '클릭하여 한국어 뜻 보기' : '클릭하여 중국어로 돌아가기',
                style: TypographyTokens.caption.copyWith(
                  color: ColorTokens.textTertiary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFEFAF1),
      appBar: PikaAppBar(
        title: '플래시카드 - ${widget.noteTitle}',
        backgroundColor: const Color(0xFFFEFAF1),
      ),
      body: Column(
        children: [
          _buildProgressIndicator(),
          const SizedBox(height: 8),
          
          // 메인 카드 영역
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: CardSwiper(
                controller: _cardController,
                cardsCount: widget.flashcards.length,
                onSwipe: (previousIndex, currentIndex, direction) {
                  // 카드가 스와이프되면 상태 업데이트
                  if (currentIndex != null) {
                    setState(() {
                      _currentIndex = currentIndex;
                      _isFlipped = false; // 새 카드는 항상 앞면부터
                    });
                  }
                  return true;
                },
                onEnd: () {
                  if (kDebugMode) {
                    print('카드 끝에 도달했습니다.');
                  }
                },
                numberOfCardsDisplayed: 1,
                allowedSwipeDirection: AllowedSwipeDirection.symmetric(
                  horizontal: true,
                ),
                padding: const EdgeInsets.symmetric(vertical: 8),
                cardBuilder: (context, index, _, __) {
                  return GestureDetector(
                    onTap: _flipCard,
                    child: _buildFlashCard(widget.flashcards[index]),
                  );
                },
              ),
            ),
          ),
          
          // 하단 컨트롤 영역
          _buildBottomControls(),
          
          // 안전 영역 확보
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
} 