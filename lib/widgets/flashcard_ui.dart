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
  }) {
    final bool isCurrentCard = index == currentIndex;
    
    // 앞 카드와 뒷 카드의 사이즈 조정
    final double cardScale = isCurrentCard ? 1.0 : 0.8;
    // 뒷 카드는 아래로 내려와 중첩이 보이도록 오프셋 조정
    final double cardOffset = isCurrentCard ? 0 : 40;

    return LayoutBuilder(
      builder: (context, constraints) {
        // 화면의 95% 크기로 카드 너비 계산 (기존 80%에서 95%로 변경)
        final double cardWidth = constraints.maxWidth * 0.95;
        // 카드 높이는 화면 높이의 80%로 설정하여 전체 화면 활용
        final double cardHeight = constraints.maxHeight * 0.8;
        
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 상단 삭제 힌트 (카드 위)
              if (isCurrentCard)
                Container(
                  width: cardWidth,
                  margin: const EdgeInsets.only(bottom: 8.0),
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
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                
              // 플래시카드 본체
              Transform.scale(
                scale: cardScale * scale,
                child: Transform.translate(
                  offset: Offset(0, cardOffset) + offset,
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
                Container(
                  width: cardWidth,
                  margin: const EdgeInsets.only(top: 12.0),
                  child: Text(
                    '좌우로 스와이프 해서 다음 카드로 이동',
                    style: TextStyle(
                      fontSize: 12.0,
                      color: const Color(0xFFD3E0DD),
                      fontWeight: FontWeight.w400,
                      fontFamily: 'Noto Sans KR',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
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
              ),

          // 카드 번호 표시 (좌상단)
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
    required bool isSpeaking,
    required Function() onSpeak,
    required Function() onStopSpeaking,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // TTS 버튼 (단어 위에 위치)
            buildTtsButtonInline(const Color(0xFF226357), isSpeaking, onSpeak, onStopSpeaking),
            const SizedBox(height: 8), // 단어와 TTS 버튼 사이 간격
            
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
    required bool isSpeaking,
    required Function() onSpeak,
    required Function() onStopSpeaking,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // TTS 버튼 (단어 위에 위치)
            buildTtsButtonInline(const Color(0xFF226357), isSpeaking, onSpeak, onStopSpeaking),
            const SizedBox(height: 8), // 단어와 TTS 버튼 사이 간격
            
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

  /// 인라인 TTS 버튼 생성 (카드 내용에 포함)
  static Widget buildTtsButtonInline(
    Color iconColor,
    bool isSpeaking,
    Function() onSpeak,
    Function() onStopSpeaking,
  ) {
    return InkWell(
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
    );
  }

  /// 카드 번호 배지 생성
  static Widget buildCardNumberBadge(int index, Color bgColor, Color textColor) {
    return Positioned(
      top: 20,
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

}
