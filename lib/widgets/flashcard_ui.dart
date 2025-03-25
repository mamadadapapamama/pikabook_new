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
    Function(String)? onWordTap,
    double scale = 1.0,
    Offset offset = Offset.zero,
  }) {
    final bool isCurrentCard = index == currentIndex;

    return Transform.scale(
      scale: scale,
      child: Transform.translate(
        offset: offset,
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
    // 핀인은 앞면에서만 표시
    final String? displayPinyin = isFront ? card.pinyin : null;

    // 스와이프 안내 텍스트 생성
    final String swipeGuideText = '좌우로 스와이프 해서 다음 카드로 이동';

    return Container(
      decoration: buildCardDecoration(bgColor, isCurrentCard),
      child: Stack(
        children: [
          // 카드 내용 (중앙)
          buildCardContent(
            displayText,
            displayPinyin,
            textColor,
            // 단어 탭 기능 비활성화
            onWordTap: null,
            isFront: isFront,
          ),

          // TTS 버튼 (앞면 & 현재 카드만)
          if (isFront && isCurrentCard)
            buildTtsButton(ColorTokens.secondary, isSpeaking, onSpeak, onStopSpeaking),

          // 스와이프 안내 텍스트 (하단)
          buildSwipeGuideText(swipeGuideText, ColorTokens.secondaryLight),

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

  /// 카드 내용 (텍스트, 핀인) 생성
  static Widget buildCardContent(
    String text,
    String? pinyin,
    Color textColor, {
    Function(String)? onWordTap,
    bool isFront = true,
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
                fontSize: isFront ? 36.0 : 32.0,
                fontWeight: FontWeight.w700,
                color: textColor,
                fontFamily: isFront ? 'Noto Sans KR' : 'Noto Sans KR',
              ),
              textAlign: TextAlign.center,
            ),
            // 핀인 표시 (있는 경우)
            if (pinyin != null && pinyin.isNotEmpty) ...[
              SizedBox(height: SpacingTokens.xs),
              Text(
                pinyin,
                style: TextStyle(
                  fontSize: 14.0,
                  color: ColorTokens.textGrey,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
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
      child: IconButton(
        icon: Icon(
          isSpeaking ? Icons.volume_up : Icons.volume_up_outlined,
          color: iconColor,
          size: SpacingTokens.iconSizeMedium,
        ),
        onPressed: isSpeaking ? onStopSpeaking : onSpeak,
      ),
    );
  }

  /// 스와이프 안내 텍스트 생성
  static Widget buildSwipeGuideText(String text, Color textColor) {
    return Positioned(
      bottom: SpacingTokens.md,
      left: 0,
      right: 0,
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12.0,
            color: textColor,
            fontFamily: 'Noto Sans KR',
            fontWeight: FontWeight.w400,
          ),
          textAlign: TextAlign.center,
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
