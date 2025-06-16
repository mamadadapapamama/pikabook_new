import 'package:flutter/material.dart';
import 'package:flip_card/flip_card.dart';
import '../../core/models/flash_card.dart';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import '../../core/theme/tokens/spacing_tokens.dart';
import '../../core/services/tts/tts_service.dart';
import '../tts/tts_button.dart';

/// 플래시카드 한 장 내의 UI와 기능
///
class FlashCardUI {
  /// 플래시카드 위젯 생성
  /// 
  /// [중요]: 카드 삭제 시 FlashcardCounter를 업데이트하여 
  /// note_detail_screen 및 home_screen에 반영되어야 함
  static Widget buildFlashCard({
    required FlashCard card,
    required int index,
    required int currentIndex,
    required GlobalKey<FlipCardState>? flipCardKey,
    required bool isSpeaking,
    required Function() onFlip,
    required Function() onSpeak,
    required Function() onStopSpeaking,
    required String? Function() getNextCardInfo,
    required String? Function() getPreviousCardInfo,
    required Function() onDelete,
    Function(String)? onWordTap,
    double scale = 1.0,
    Offset offset = Offset.zero,
    bool isTtsEnabled = true,
    String? ttsTooltip,
  }) {
    final bool isCurrentCard = index == currentIndex;
    
    // 앞 카드와 뒷 카드의 사이즈 조정
    final double cardScale = isCurrentCard ? 1.0 : 0.9;
    // 뒷 카드는 아래로 내려와 중첩이 보이도록 오프셋 조정
    final double cardOffset = isCurrentCard ? 0 : 40;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 화면의 95% 크기로 카드 너비 계산 (기존 80%에서 95%로 변경)
        final double cardWidth = constraints.maxWidth * 0.95;
        // 카드 높이는 화면 높이의 90%로 설정하여 전체 화면 활용
        final double cardHeight = constraints.maxHeight * 0.9;
        
        return Stack(
          children: [
            // 플래시카드 본체 (중앙)
            Center(
              child: Transform.scale(
                scale: cardScale * scale,
                child: Transform.translate(
                  offset: Offset(0, cardOffset - 20) + offset, // 카드 위치를 20 픽셀 위로 올림
                  child: SizedBox(
                    width: cardWidth,
                    height: cardHeight,
                    child: FlipCard(
                      key: isCurrentCard ? flipCardKey : null,
                      direction: FlipDirection.HORIZONTAL,
                      speed: 300,
                      onFlipDone: (isFront) {
                        if (isCurrentCard) {
                          onFlip();
                        }
                      },
                      front: buildCardSide(
                        card: card,
                        bgColor: ColorTokens.flashcardBackground,
                        textColor: ColorTokens.textPrimary,
                        isFront: true,
                        isCurrentCard: isCurrentCard,
                        cardIndex: index,
                        isSpeaking: isSpeaking,
                        onSpeak: onSpeak,
                        onStopSpeaking: onStopSpeaking,
                        getNextCardInfo: getNextCardInfo,
                        getPreviousCardInfo: getPreviousCardInfo,
                        onWordTap: onWordTap,
                        isEnabled: isTtsEnabled,
                        tooltip: ttsTooltip,
                      ),
                      back: buildCardSide(
                        card: card,
                        bgColor: ColorTokens.surface,
                        textColor: ColorTokens.textPrimary,
                        isFront: false,
                        isCurrentCard: isCurrentCard,
                        cardIndex: index,
                        isSpeaking: isSpeaking,
                        onSpeak: onSpeak,
                        onStopSpeaking: onStopSpeaking,
                        getNextCardInfo: getNextCardInfo,
                        getPreviousCardInfo: getPreviousCardInfo,
                        onWordTap: onWordTap,
                        isEnabled: isTtsEnabled,
                        tooltip: ttsTooltip,
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
  }

  /// 카드 앞/뒷면 위젯 생성
  static Widget buildCardSide({
    required FlashCard card,
    required Color bgColor,
    required Color textColor,
    required bool isFront,
    required bool isCurrentCard,
    required int cardIndex,
    required bool isSpeaking,
    required Function() onSpeak,
    required Function() onStopSpeaking,
    required String? Function() getNextCardInfo,
    required String? Function() getPreviousCardInfo,
    Function(String)? onWordTap,
    bool isEnabled = true,
    String? tooltip,
  }) {
    // 표시할 텍스트와 핀인 결정
    final String displayText = isFront ? card.front : card.back;
    // 핀인은 항상 표시
    final String displayPinyin = card.pinyin;

    return Container(
      decoration: buildCardDecoration(bgColor, isCurrentCard),
      child: Stack(
        children: [
          // 카드 내용 (중앙)
          isFront 
            ? buildFrontCardContent(
                card.front,
                displayPinyin,
                textColor,
                onWordTap: onWordTap,
                isSpeaking: isSpeaking,
                onSpeak: onSpeak,
                onStopSpeaking: onStopSpeaking,
                isEnabled: isEnabled,
                tooltip: tooltip,
              )
            : buildBackCardContent(
                card.back,
                card.front,
                displayPinyin,
                textColor,
                onWordTap: onWordTap,
                isSpeaking: isSpeaking,
                onSpeak: onSpeak,
                onStopSpeaking: onStopSpeaking,
                isEnabled: isEnabled,
                tooltip: tooltip,
              ),

          // 카드 번호 표시 (좌상단)
          buildCardNumberBadge(cardIndex, ColorTokens.tertiary, ColorTokens.surface),
        ],
      ),
    );
  }

  /// 카드 장식 (배경, 테두리, 그림자) 생성
  static BoxDecoration buildCardDecoration(Color bgColor, bool isCurrentCard) {
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
  static Widget buildFrontCardContent(
    String text,
    String pinyin,
    Color textColor, {
    Function(String)? onWordTap,
    required bool isSpeaking,
    required Function() onSpeak,
    required Function() onStopSpeaking,
    bool isEnabled = true,
    String? tooltip,
  }) {
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
              tooltip: isEnabled ? null : tooltip ?? '무료 TTS 사용량을 모두 사용했습니다.',
              iconColor: ColorTokens.secondary,
              activeBackgroundColor: ColorTokens.primary.withOpacity(0.2),
              onPlayStart: () => onSpeak(),
              onPlayEnd: onStopSpeaking,
            ),
            SizedBox(height: SpacingTokens.sm),
            
            // 단어/의미 텍스트
            Text(
              text,
              style: TypographyTokens.headline1Cn.copyWith(
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
  static Widget buildBackCardContent(
    String translation,
    String original,
    String pinyin,
    Color textColor, {
    Function(String)? onWordTap,
    required bool isSpeaking,
    required Function() onSpeak,
    required Function() onStopSpeaking,
    bool isEnabled = true,
    String? tooltip,
  }) {
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
              tooltip: isEnabled ? null : tooltip ?? '무료 TTS 사용량을 모두 사용했습니다.',
              iconColor: ColorTokens.secondary,
              activeBackgroundColor: ColorTokens.primary.withOpacity(0.2),
              onPlayStart: () => onSpeak(),
              onPlayEnd: onStopSpeaking,
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

  /// 인라인 TTS 버튼 생성 (카드 내용에 포함)
  static Widget buildTtsButtonInline(
    Color iconColor,
    bool isSpeaking,
    Function() onSpeak,
    Function() onStopSpeaking, {
    bool isEnabled = true,
    String? tooltip,
    String text = '',
  }) {
    // 표준 TtsButton 위젯으로 대체
    return TtsButton(
      text: text,
      size: TtsButton.sizeMedium,
      tooltip: isEnabled ? null : tooltip ?? '무료 TTS 사용량을 모두 사용했습니다.',
      iconColor: iconColor,
      activeBackgroundColor: ColorTokens.primary.withOpacity(0.2),
    );
  }

  /// 카드 번호 배지 생성
  static Widget buildCardNumberBadge(int index, Color bgColor, Color textColor) {
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
