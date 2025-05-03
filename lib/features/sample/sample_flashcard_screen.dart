import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flip_card/flip_card.dart';
import 'package:flutter/foundation.dart';
import '../../core/models/flash_card.dart';
import '../../core/widgets/tts_button.dart';
import '../../core/services/media/tts_service.dart';
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
  final TtsService _ttsService = TtsService();

  int _currentIndex = 0;
  bool _isFlipped = false;
  bool _isSpeaking = false;
  bool _ttsEnabled = true;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  // TTS 초기화
  Future<void> _initTts() async {
    try {
      await _ttsService.init();
      
      // TTS 완료 리스너 설정
      _ttsService.setOnPlayingCompleted(() {
        if (mounted && _isSpeaking) {
          setState(() {
            _isSpeaking = false;
          });
        }
      });
      
      // 사용 가능 여부 확인
      final isAvailable = await _ttsService.isTtsAvailable();
      if (mounted) {
        setState(() {
          _ttsEnabled = isAvailable;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('TTS 초기화 오류: $e');
      }
    }
  }

  @override
  void dispose() {
    _ttsService.dispose();
    _cardController.dispose();
    super.dispose();
  }

  // 카드 뒤집기
  void _flipCard() {
    _flipCardKey.currentState?.toggleCard();
    setState(() => _isFlipped = !_isFlipped);
  }

  // TTS 재생
  Future<void> _speakText(String text) async {
    if (_isSpeaking) {
      await _stopSpeaking();
      return;
    }

    if (!_ttsEnabled) return;

    setState(() {
      _isSpeaking = true;
    });

    try {
      // 중국어로 설정
      await _ttsService.setLanguage('zh-CN');
      await _ttsService.speak(text);
    } catch (e) {
      if (kDebugMode) {
        print('TTS 실행 오류: $e');
      }
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

  // TTS 중지
  Future<void> _stopSpeaking() async {
    if (!_isSpeaking) return;

    try {
      await _ttsService.stop();
    } catch (e) {
      if (kDebugMode) {
        print('TTS 중지 오류: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    }
  }

  // 다음 카드 정보 가져오기
  String? _getNextCardInfo() {
    if (_currentIndex < widget.flashcards.length - 1) {
      return widget.flashcards[_currentIndex + 1].front;
    }
    return null;
  }

  // 이전 카드 정보 가져오기
  String? _getPreviousCardInfo() {
    if (_currentIndex > 0) {
      return widget.flashcards[_currentIndex - 1].front;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PikaAppBar.flashcard(
        onBackPressed: () => Navigator.of(context).pop(),
        currentCardIndex: _currentIndex,
        totalCards: widget.flashcards.length,
      ),
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(SpacingTokens.md),
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
              numberOfCardsDisplayed: widget.flashcards.length == 1 ? 1 : 2,
              allowedSwipeDirection: AllowedSwipeDirection.symmetric(
                horizontal: true,
              ),
              padding: EdgeInsets.all(SpacingTokens.lg),
              isLoop: widget.flashcards.length > 1,
              cardBuilder: (context, index, horizontalThreshold, verticalThreshold) {
                final bool isCurrentCard = index == _currentIndex;
                final double cardScale = isCurrentCard ? 1.0 : 0.9;
                final double cardOffset = isCurrentCard ? 0 : 40;
                
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final double cardWidth = constraints.maxWidth * 0.95;
                    final double cardHeight = constraints.maxHeight * 0.9;
                    
                    return Stack(
                      children: [
                        Center(
                          child: Transform.scale(
                            scale: cardScale,
                            child: Transform.translate(
                              offset: Offset(0, cardOffset - 20),
                              child: SizedBox(
                                width: cardWidth,
                                height: cardHeight,
                                child: GestureDetector(
                                  onTap: _flipCard,
                                  child: FlipCard(
                                    key: isCurrentCard ? _flipCardKey : null,
                                    direction: FlipDirection.HORIZONTAL,
                                    speed: 300,
                                    onFlipDone: (isFront) {
                                      if (isCurrentCard) {
                                        setState(() => _isFlipped = !isFront);
                                      }
                                    },
                                    front: _buildCardSide(
                                      card: widget.flashcards[index],
                                      bgColor: ColorTokens.flashcardBackground,
                                      textColor: ColorTokens.textPrimary,
                                      isFront: true,
                                      isCurrentCard: isCurrentCard,
                                      cardIndex: index,
                                    ),
                                    back: _buildCardSide(
                                      card: widget.flashcards[index],
                                      bgColor: ColorTokens.surface,
                                      textColor: ColorTokens.textPrimary,
                                      isFront: false,
                                      isCurrentCard: isCurrentCard,
                                      cardIndex: index,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                );
              },
            ),
          ),
          
          // 이동 안내 텍스트 (하단)
          if (widget.flashcards.length > 1)
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
            
          // 삭제 안내 텍스트 (상단)
          Positioned(
            top: SpacingTokens.md,
            left: 0,
            right: 0,
            child: Material(
              color: ColorTokens.surface.withOpacity(0),
              child: Text(
                '실제 플래시카드는 위로 스와이프해서 삭제 가능합니다',
                style: TypographyTokens.caption.copyWith(
                  color: ColorTokens.disabled,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  /// 카드 앞/뒷면 위젯 생성
  Widget _buildCardSide({
    required FlashCard card,
    required Color bgColor,
    required Color textColor,
    required bool isFront,
    required bool isCurrentCard,
    required int cardIndex,
  }) {
    // 표시할 텍스트와 핀인 결정
    final String displayText = isFront ? card.front : card.back;
    // 핀인은 항상 표시
    final String displayPinyin = card.pinyin;

    return Container(
      decoration: _buildCardDecoration(bgColor, isCurrentCard),
      child: Stack(
        children: [
          // 카드 내용 (중앙)
          isFront 
            ? _buildFrontCardContent(
                card.front,
                displayPinyin,
                textColor,
              )
            : _buildBackCardContent(
                card.back,
                card.front,
                displayPinyin,
                textColor,
              ),

          // 카드 번호 배지 (좌상단)
          _buildCardNumberBadge(cardIndex, ColorTokens.tertiary, ColorTokens.surface),
        ],
      ),
    );
  }

  /// 카드 장식 (배경, 테두리, 그림자) 생성
  BoxDecoration _buildCardDecoration(Color bgColor, bool isCurrentCard) {
    return BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(SpacingTokens.radiusLarge),
      boxShadow: [
        BoxShadow(
          color: ColorTokens.black.withOpacity(0.15),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
      border: Border.all(
        color: ColorTokens.tertiary,
        width: 2.0,
      ),
    );
  }

  /// 카드 앞면 내용 (단어, 핀인) 생성
  Widget _buildFrontCardContent(
    String text,
    String pinyin,
    Color textColor,
  ) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // TTS 버튼 (단어 위에 위치)
            TtsButton(
              text: text, // 실제 텍스트 전달
              size: TtsButton.sizeMedium,
              tooltip: !_ttsEnabled ? '샘플 모드에서는 TTS 사용이 제한될 수 있습니다.' : null,
              iconColor: ColorTokens.secondary,
              activeBackgroundColor: ColorTokens.primary.withOpacity(0.2),
              onPlayStart: () => _speakText(text),
              onPlayEnd: _stopSpeaking,
            ),
            SizedBox(height: SpacingTokens.sm),
            
            // 단어/의미 텍스트
            Text(
              text,
              style: TypographyTokens.headline2Cn.copyWith(
                color: ColorTokens.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            // 핀인 표시 (항상 표시)
            SizedBox(height: SpacingTokens.lg),
            Text(
              pinyin.isEmpty ? 'xíng zǒu' : pinyin,
              style: TypographyTokens.caption.copyWith(
                color: ColorTokens.textGrey,
                fontFamily: TypographyTokens.poppins,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 카드 뒷면 내용 (번역, 원문, 핀인) 생성
  Widget _buildBackCardContent(
    String translation,
    String original,
    String pinyin,
    Color textColor,
  ) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // TTS 버튼 (단어 위에 위치)
            TtsButton(
              text: original, // 원문 텍스트 전달
              size: TtsButton.sizeMedium,
              tooltip: !_ttsEnabled ? '샘플 모드에서는 TTS 사용이 제한될 수 있습니다.' : null,
              iconColor: ColorTokens.secondary,
              activeBackgroundColor: ColorTokens.primary.withOpacity(0.2),
              onPlayStart: () => _speakText(original),
              onPlayEnd: _stopSpeaking,
            ),
            SizedBox(height: SpacingTokens.sm),
            
            // 번역 (의미)
            Text(
              translation,
              style: TypographyTokens.headline2.copyWith(
                color: ColorTokens.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: SpacingTokens.lg),
            
            // 원문 (중국어)
            Text(
              original,
              style: TypographyTokens.headline3Cn.copyWith(
                color: ColorTokens.textGrey,
              ),
              textAlign: TextAlign.center,
            ),
            
            // 핀인 표시 (항상 표시)
            SizedBox(height: SpacingTokens.sm),
            Text(
              pinyin.isEmpty ? 'xíng zǒu' : pinyin,
              style: TypographyTokens.body2.copyWith(
                color: ColorTokens.textGrey,
                fontFamily: TypographyTokens.poppins,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// 카드 번호 배지 생성
  Widget _buildCardNumberBadge(int index, Color bgColor, Color textColor) {
    return Positioned(
      top: SpacingTokens.lg,
      left: SpacingTokens.lg,
      child: Container(
        width: SpacingTokens.iconSizeMedium,
        height: SpacingTokens.iconSizeMedium,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Center(
          child: Text(
            '${index + 1}',
            style: TypographyTokens.captionEn.copyWith(
              fontWeight: FontWeight.w500,
              color: ColorTokens.black,
            ),
          ),
        ),
      ),
    );
  }
} 