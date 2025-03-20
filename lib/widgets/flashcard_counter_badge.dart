import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import '../theme/tokens/ui_tokens.dart';
import '../views/screens/flashcard_screen.dart';

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
    if (count <= 0) return const SizedBox.shrink();
    
    Widget badge = Container(
      padding: EdgeInsets.symmetric(
        horizontal: SpacingTokens.sm,
        vertical: SpacingTokens.xs / 2,
      ),
      decoration: BoxDecoration(
        color: UITokens.flashcardBadgeBackground,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Center(
              child: Stack(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: UITokens.flashcardBadgeBackground,
                      borderRadius: BorderRadius.circular(SpacingTokens.xs),
                      border: Border.all(
                        color: UITokens.flashcardBadgeBorder,
                        width: 2,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(SpacingTokens.xs),
                        border: Border.all(
                          color: UITokens.flashcardBadgeBorder,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: SpacingTokens.xs),
          Text(
            '$count',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: ColorTokens.secondary,
            ),
          ),
        ],
      ),
    );
    
    // noteId가 제공되면 GestureDetector로 감싸서 탭 시 플래시카드 화면으로 이동
    if (noteId != null) {
      return GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => FlashCardScreen(noteId: noteId!),
            ),
          );
        },
        child: badge,
      );
    }
    
    return badge;
  }
} 