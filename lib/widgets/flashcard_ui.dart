import 'package:flutter/material.dart';
import 'package:flip_card/flip_card.dart';
import '../models/flash_card.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';

/// 플래시카드 한 장 내의 UI와 기능
///
class FlashCardUI {
  /// 플래시카드 위젯 생성
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
  }) {
    final bool isCurrentCard = index == currentIndex;

    return Transform.scale(
      scale: scale,
      child: Transform.translate(
        offset: offset,
        child: Stack(
          children: [
            // 플래시카드
            FlipCard(
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
              ),
            ),
            
            // 삭제 힌트와 버튼 (카드 위에 표시)
            if (isCurrentCard)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: ColorTokens.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(SpacingTokens.radiusMedium),
                      topRight: Radius.circular(SpacingTokens.radiusMedium),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 삭제 버튼
                      GestureDetector(
                        onTap: onDelete,
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: ColorTokens.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                color: ColorTokens.error,
                                size: 14,
                              ),
                              SizedBox(width: 2),
                              Text(
                                '삭제',
                                style: TextStyle(
                                  fontSize: 12.0,
                                  color: ColorTokens.error,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                      
                      // 스와이프 안내
                      Icon(
                        Icons.arrow_upward,
                        color: ColorTokens.textSecondary,
                        size: 12,
                      ),
                      SizedBox(width: 4),
                      Text(
                        '위로 스와이프해도 삭제됩니다',
                        style: TextStyle(
                          fontSize: 12.0,
                          color: ColorTokens.textSecondary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
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
              )
            : buildBackCardContent(
                card.back,
                card.front,
                displayPinyin,
                textColor,
                onWordTap: onWordTap,
              ),

          // TTS 버튼 (항상 표시)
          if (isCurrentCard)
            buildTtsButton(ColorTokens.secondary, isSpeaking, onSpeak, onStopSpeaking),

          // 카드 번호 표시 (좌상단)
          buildCardNumberBadge(cardIndex, ColorTokens.tertiary, ColorTokens.secondary),
        ],
      ),
    );
  }

  /// 카드 장식 (배경, 테두리, 그림자) 생성
  static BoxDecoration buildCardDecoration(Color bgColor, bool isCurrentCard) {
    return BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
      boxShadow: [
        BoxShadow(
          color: ColorTokens.textPrimary.withOpacity(0.15),
          blurRadius: SpacingTokens.md - 6,
          offset: const Offset(0, SpacingTokens.xs),
        ),
      ],
      border: Border.all(
        color: ColorTokens.tertiary,
        width: 2.0,
      ),
    );
  }

  /// 카드 앞면 내용 (중국어, 핀인) 생성
  static Widget buildFrontCardContent(
    String text,
    String pinyin,
    Color textColor, {
    Function(String)? onWordTap,
  }) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 단어/의미 텍스트
            Text(
              text,
              style: TextStyle(
                fontSize: 36.0,
                fontWeight: FontWeight.w700,
                color: textColor,
                fontFamily: 'Noto Sans KR',
              ),
              textAlign: TextAlign.center,
            ),
            // 핀인 표시 (항상 표시)
            SizedBox(height: SpacingTokens.xs),
            Text(
              pinyin.isEmpty ? 'xíng zǒu' : pinyin,
              style: TextStyle(
                fontSize: 14.0,
                color: ColorTokens.textGrey,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w500,
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
  }) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 번역 (의미)
            Text(
              translation,
              style: TextStyle(
                fontSize: 32.0,
                fontWeight: FontWeight.w700,
                color: textColor,
                fontFamily: 'Noto Sans KR',
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: SpacingTokens.md),
            
            // 원문 (중국어)
            Text(
              original,
              style: TextStyle(
                fontSize: 24.0,
                fontWeight: FontWeight.w500,
                color: ColorTokens.secondary,
                fontFamily: 'Noto Sans KR',
              ),
              textAlign: TextAlign.center,
            ),
            
            // 핀인 표시 (항상 표시)
            SizedBox(height: SpacingTokens.xs),
            Text(
              pinyin.isEmpty ? 'xíng zǒu' : pinyin,
              style: TextStyle(
                fontSize: 14.0,
                color: ColorTokens.textGrey,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// TTS 버튼 생성
  static Widget buildTtsButton(
    Color iconColor,
    bool isSpeaking,
    Function() onSpeak,
    Function() onStopSpeaking,
  ) {
    return Positioned(
      top: SpacingTokens.md,
      right: SpacingTokens.md,
      child: Container(
        decoration: BoxDecoration(
          color: ColorTokens.secondary.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: Icon(
            isSpeaking ? Icons.volume_up : Icons.volume_up_outlined,
            color: iconColor,
            size: SpacingTokens.iconSizeMedium,
          ),
          onPressed: isSpeaking ? onStopSpeaking : onSpeak,
        ),
      ),
    );
  }

  /// 카드 번호 배지 생성
  static Widget buildCardNumberBadge(int index, Color bgColor, Color textColor) {
    return Positioned(
      bottom: SpacingTokens.md,
      left: SpacingTokens.md,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Center(
          child: Text(
            '${index + 1}',
            style: TextStyle(
              fontSize: 14.0,
              fontWeight: FontWeight.w500,
              color: textColor,
              fontFamily: 'Poppins',
            ),
          ),
        ),
      ),
    );
  }

  /// 하단 버튼 영역 위젯 생성
  static Widget buildBottomControls({
    required bool hasCards,
    Function()? onFlip,
    required Function() onDelete,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: SpacingTokens.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Flip 버튼 (선택적)
          if (onFlip != null) ...[
            IconButton(
              icon: const Icon(Icons.flip),
              onPressed: hasCards ? onFlip : null,
              iconSize: SpacingTokens.iconSizeLarge,
              color: hasCards ? ColorTokens.info : ColorTokens.disabled,
            ),
            SizedBox(width: SpacingTokens.md),
          ],
          // 삭제 버튼
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: hasCards ? onDelete : null,
            iconSize: SpacingTokens.iconSizeLarge,
            color: hasCards ? ColorTokens.error : ColorTokens.disabled,
          ),
        ],
      ),
    );
  }
}
