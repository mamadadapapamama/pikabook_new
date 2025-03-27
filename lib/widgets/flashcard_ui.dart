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

    return Column(
      children: [
        // 삭제 힌트와 버튼 (카드 위에 별도로 표시)
        if (isCurrentCard)
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 삭제 버튼
                Icon(
                  Icons.delete_outline,
                  color: const Color(0xFFD3E0DD),
                  size: 24,
                ),
                const SizedBox(height: 4),
                // 스와이프 안내 텍스트
                Text(
                  '위로 스와이프 해도 삭제 됩니다.',
                  style: TextStyle(
                    fontSize: 12.0,
                    color: const Color(0xFFD3E0DD),
                    fontWeight: FontWeight.w400,
                    fontFamily: 'Noto Sans KR',
                  ),
                ),
              ],
            ),
          ),
        
        // 플래시카드 본체
        Transform.scale(
          scale: scale,
          child: Transform.translate(
            offset: offset,
            child: SizedBox(
              width: 330, // 카드 너비를 피그마 디자인에 맞게 조정
              height: 400, // 카드 높이를 피그마 디자인에 맞게 조정
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
                  bgColor: const Color(0xFFFFF7D8), // Figma에서 가져온 색상
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
                  bgColor: Colors.white, // 뒷면은 흰색 배경
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
          ),
        ),
        
        // 하단 가이드 텍스트
        if (isCurrentCard)
          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: Text(
              '좌우로 스와이프 해서 다음 카드로 이동',
              style: TextStyle(
                fontSize: 12.0,
                color: const Color(0xFFD3E0DD),
                fontWeight: FontWeight.w400,
                fontFamily: 'Noto Sans KR',
              ),
            ),
          ),
      ],
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
            buildTtsButton(const Color(0xFF226357), isSpeaking, onSpeak, onStopSpeaking),

          // 카드 번호 표시 (좌하단)
          buildCardNumberBadge(cardIndex, const Color(0xFFFFD53C), Colors.white),
        ],
      ),
    );
  }

  /// 카드 장식 (배경, 테두리, 그림자) 생성
  static BoxDecoration buildCardDecoration(Color bgColor, bool isCurrentCard) {
    return BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(20), // 피그마에서 가져온 값으로 조정
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.15),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
      border: Border.all(
        color: const Color(0xFFFFD53C), // 피그마에서 가져온 테두리 색상
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 단어/의미 텍스트
            Text(
              text,
              style: TextStyle(
                fontSize: 36.0,
                fontWeight: FontWeight.w700,
                color: Colors.black,
                fontFamily: 'Noto Sans HK',
              ),
              textAlign: TextAlign.center,
            ),
            // 핀인 표시 (항상 표시)
            const SizedBox(height: 20),
            Text(
              pinyin.isEmpty ? 'xíng zǒu' : pinyin,
              style: TextStyle(
                fontSize: 14.0,
                color: const Color(0xFF969696),
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 번역 (의미)
            Text(
              translation,
              style: TextStyle(
                fontSize: 32.0,
                fontWeight: FontWeight.w700,
                color: Colors.black,
                fontFamily: 'Noto Sans KR',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            
            // 원문 (중국어)
            Text(
              original,
              style: TextStyle(
                fontSize: 22.0,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF969696),
                fontFamily: 'Noto Sans HK',
              ),
              textAlign: TextAlign.center,
            ),
            
            // 핀인 표시 (항상 표시)
            const SizedBox(height: 8),
            Text(
              pinyin.isEmpty ? 'xíng zǒu' : pinyin,
              style: TextStyle(
                fontSize: 14.0,
                color: const Color(0xFF969696),
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
      top: 20,
      right: 20,
      child: InkWell(
        onTap: isSpeaking ? onStopSpeaking : onSpeak,
        child: SizedBox(
          width: 24,
          height: 24,
          child: Icon(
            isSpeaking ? Icons.volume_up : Icons.volume_up_outlined,
            color: iconColor,
            size: 24,
          ),
        ),
      ),
    );
  }

  /// 카드 번호 배지 생성
  static Widget buildCardNumberBadge(int index, Color bgColor, Color textColor) {
    return Positioned(
      bottom: 20,
      left: 20,
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
