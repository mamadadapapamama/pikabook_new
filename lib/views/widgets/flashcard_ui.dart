import 'package:flutter/material.dart';
import 'package:flip_card/flip_card.dart';
import '../../models/flash_card.dart';

/// 플래시카드 UI 관련 위젯과 메서드를 제공하는 클래스
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
  }) {
    final bool isCurrentCard = index == currentIndex;

    // 카드 스케일 계산 (현재 카드는 100%, 뒤 카드는 점점 작아짐)
    final double scale =
        isCurrentCard ? 1.0 : 1.0 - (0.05 * (index - currentIndex));

    // 카드 오프셋 계산 (뒤 카드는 아래로 내려감)
    final double yOffset = isCurrentCard ? 0 : 10.0 * (index - currentIndex);

    return Transform.scale(
      scale: scale,
      child: Transform.translate(
        offset: Offset(0, yOffset),
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
            bgColor: Colors.white,
            textColor: Colors.blue.shade800,
            isFront: true,
            isCurrentCard: isCurrentCard,
            cardIndex: index,
            isSpeaking: isSpeaking,
            onSpeak: onSpeak,
            onStopSpeaking: onStopSpeaking,
            getNextCardInfo: getNextCardInfo,
            getPreviousCardInfo: getPreviousCardInfo,
          ),
          back: buildCardSide(
            card: card,
            bgColor: Colors.blue.shade50,
            textColor: Colors.blue.shade800,
            isFront: false,
            isCurrentCard: isCurrentCard,
            cardIndex: index,
            isSpeaking: isSpeaking,
            onSpeak: onSpeak,
            onStopSpeaking: onStopSpeaking,
            getNextCardInfo: getNextCardInfo,
            getPreviousCardInfo: getPreviousCardInfo,
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
  }) {
    // 표시할 텍스트와 핀인 결정
    final String displayText = isFront ? card.front : card.back;
    final String? displayPinyin = card.pinyin;

    // 스와이프 안내 텍스트 생성
    final String swipeGuideText = isFront
        ? '왼쪽으로 스와이프: 다음 카드 (${getNextCardInfo() ?? "없음"})\n'
            '오른쪽으로 스와이프: 이전 카드 (${getPreviousCardInfo() ?? "없음"})'
        : '탭하여 단어 보기';

    return Container(
      decoration: buildCardDecoration(bgColor, isCurrentCard),
      child: Stack(
        children: [
          // 카드 내용 (중앙)
          buildCardContent(displayText, displayPinyin, textColor),

          // TTS 버튼 (앞면 & 현재 카드만)
          if (isFront && isCurrentCard)
            buildTtsButton(textColor, isSpeaking, onSpeak, onStopSpeaking),

          // 스와이프 안내 텍스트 (하단)
          buildSwipeGuideText(swipeGuideText, textColor),

          // 카드 번호 표시 (좌상단)
          buildCardNumberBadge(cardIndex, textColor),
        ],
      ),
    );
  }

  /// 카드 장식 (배경, 테두리, 그림자) 생성
  static BoxDecoration buildCardDecoration(Color bgColor, bool isCurrentCard) {
    return BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(16.0),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.2),
          blurRadius: 8.0,
          offset: const Offset(0, 4),
        ),
      ],
      border: Border.all(
        color:
            isCurrentCard ? Colors.blue.withOpacity(0.3) : Colors.transparent,
        width: 2.0,
      ),
    );
  }

  /// 카드 내용 (텍스트, 핀인) 생성
  static Widget buildCardContent(String text, String? pinyin, Color textColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 단어/의미 텍스트
            Text(
              text,
              style: TextStyle(
                fontSize: 32.0,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
              textAlign: TextAlign.center,
            ),
            // 핀인 표시 (있는 경우)
            if (pinyin != null && pinyin.isNotEmpty) ...[
              const SizedBox(height: 16.0),
              Text(
                pinyin,
                style: TextStyle(
                  fontSize: 20.0,
                  color: textColor.withOpacity(0.7),
                  fontStyle: FontStyle.italic,
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
    Color textColor,
    bool isSpeaking,
    Function() onSpeak,
    Function() onStopSpeaking,
  ) {
    return Positioned(
      top: 16.0,
      right: 16.0,
      child: IconButton(
        icon: Icon(
          isSpeaking ? Icons.volume_up : Icons.volume_up_outlined,
          color: textColor,
        ),
        onPressed: isSpeaking ? onStopSpeaking : onSpeak,
      ),
    );
  }

  /// 스와이프 안내 텍스트 생성
  static Widget buildSwipeGuideText(String text, Color textColor) {
    return Positioned(
      bottom: 16.0,
      left: 0,
      right: 0,
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12.0,
            color: textColor.withOpacity(0.5),
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  /// 카드 번호 배지 생성
  static Widget buildCardNumberBadge(int index, Color textColor) {
    return Positioned(
      top: 16.0,
      left: 16.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: textColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12.0),
        ),
        child: Text(
          '${index + 1}',
          style: TextStyle(
            fontSize: 14.0,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
      ),
    );
  }

  /// 하단 버튼 영역 위젯 생성
  static Widget buildBottomControls({
    required bool hasCards,
    required Function() onFlip,
    required Function() onDelete,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.flip),
            onPressed: hasCards ? onFlip : null,
            iconSize: 32.0,
            color: hasCards ? Colors.blue : Colors.grey,
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: hasCards ? onDelete : null,
            iconSize: 32.0,
            color: hasCards ? Colors.red : Colors.grey,
          ),
        ],
      ),
    );
  }
}
