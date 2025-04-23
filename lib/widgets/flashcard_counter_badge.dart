import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/tokens/color_tokens.dart';
import '../core/theme/tokens/typography_tokens.dart';
import '../core/theme/tokens/spacing_tokens.dart';
import '../core/theme/tokens/ui_tokens.dart';
import '../features/flashcard/flashcard_screen.dart';

/// 노트에 연결된 플래시카드 개수를 보여주는 배지 위젯
class FlashcardCounterBadge extends StatelessWidget {
  final int count;
  final String? noteId;
  
  const FlashcardCounterBadge({
    Key? key,
    required this.count,
    this.noteId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 플래시카드 개수에 따라 스타일 조정
    final bool hasFlashcards = count > 0;
    
    // 배지 배경색과 텍스트 색상 결정
    final Color bgColor = hasFlashcards 
        ? UITokens.flashcardBadgeBackground
        : UITokens.flashcardBadgeBackground.withOpacity(0.5);
    
    final Color textColor = hasFlashcards
        ? ColorTokens.secondary
        : ColorTokens.textGrey;
    
    Widget badge = Container(
      padding: EdgeInsets.symmetric(
        horizontal: SpacingTokens.sm + 2,
        vertical: SpacingTokens.xs,
      ),
      margin: EdgeInsets.only(right: SpacingTokens.xs),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 플래시카드 아이콘 (count가 0이면 흐리게 표시)
          Opacity(
            opacity: hasFlashcards ? 1.0 : 0.5,
            child: Image.asset(
              'assets/images/icon_flashcard_counter.png',
              width: 20,
              height: 20,
              errorBuilder: (context, error, stackTrace) {
                // 에러 시 대체 아이콘 표시 (기존 스택 방식)
                return SizedBox(
                  width: 20,
                  height: 20,
                  child: Center(
                    child: Stack(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(SpacingTokens.xs),
                            border: Border.all(
                              color: hasFlashcards ? UITokens.flashcardBadgeBorder : ColorTokens.textGrey,
                              width: 2,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 7,
                          left: 7,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(SpacingTokens.xs),
                              border: Border.all(
                                color: hasFlashcards ? UITokens.flashcardBadgeBorder : ColorTokens.textGrey,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(width: SpacingTokens.xs),
          Text(
            '$count',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ),
    );
    
    // noteId가 제공되고 플래시카드가 있으면 GestureDetector로 감싸서 탭 시 플래시카드 화면으로 이동
    if (noteId != null) {
      return GestureDetector(
        onTap: hasFlashcards ? () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => FlashCardScreen(noteId: noteId!),
            ),
          );
        } : null,
        child: badge,
      );
    }
    
    return badge;
  }
} 