import 'package:flutter/material.dart';
import '../features/note_detail/managers/content_manager.dart';
import '../core/models/dictionary.dart';
import '../core/theme/tokens/color_tokens.dart';
import '../core/theme/tokens/typography_tokens.dart';
import '../core/theme/tokens/spacing_tokens.dart';
import '../core/theme/tokens/ui_tokens.dart';
import '../widgets/common/pika_button.dart';
import '../widgets/common/tts_button.dart';

/// 사전 검색 결과를 표시하는 바텀 시트 위젯

class DictionaryResultWidget extends StatelessWidget {
  final DictionaryEntry entry;
  final Function(String, String, {String? pinyin}) onCreateFlashCard;
  final bool isExistingFlashcard;

  const DictionaryResultWidget({
    super.key,
    required this.entry,
    required this.onCreateFlashCard,
    this.isExistingFlashcard = false,
  });

  @override
  Widget build(BuildContext context) {
    final contentManager = ContentManager();

    return Container(
      padding: EdgeInsets.fromLTRB(
        SpacingTokens.lg, 
        SpacingTokens.lg, 
        SpacingTokens.lg, 
        SpacingTokens.lg + 10 // 패딩 바텀 +10 추가
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(SpacingTokens.md)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더 (제목 및 닫기 버튼)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '사전',
                style: TypographyTokens.button.copyWith(
                  color: ColorTokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(SpacingTokens.radiusXs),
                child: Padding(
                  padding: EdgeInsets.all(SpacingTokens.xs),
                  child: Icon(
                    Icons.close,
                    color: ColorTokens.textPrimary,
                    size: SpacingTokens.iconSizeMedium,
                  ),
                ),
              ),
            ],
          ),
          
          SizedBox(height: SpacingTokens.md),
          
          // 단어 내용
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 원문 및 발음 듣기 버튼
              Row(
                children: [
                  Text(
                    entry.word,
                    style: TypographyTokens.headline3.copyWith(
                      fontWeight: FontWeight.bold,
                      color: ColorTokens.textPrimary,
                    ),
                  ),
                  SizedBox(width: SpacingTokens.xs),
                  // 발음 듣기 버튼 - TtsButton 위젯으로 변경
                  FutureBuilder<bool>(
                    future: contentManager.ttsService.isTtsAvailable(),
                    builder: (context, snapshot) {
                      final bool isTtsEnabled = snapshot.data ?? true;
                      final String? ttsTooltip = !isTtsEnabled ? 
                          contentManager.ttsService.getTtsLimitMessage() : null;
                      
                      // 표준 TtsButton 위젯 사용
                      return TtsButton(
                        text: entry.word,
                        size: TtsButton.sizeMedium,
                        tooltip: ttsTooltip,
                      );
                    }
                  ),
                ],
              ),
              
              // 발음 (Pinyin) - 항상 표시
              Padding(
                padding: EdgeInsets.only(top: SpacingTokens.xs),
                child: Text(
                  entry.pinyin.isEmpty ? '발음 정보 없음' : entry.pinyin,
                  style: TypographyTokens.body2.copyWith(
                    color: ColorTokens.textSecondary,
                  ),
                ),
              ),
              
              // 의미
              Padding(
                padding: EdgeInsets.only(top: SpacingTokens.sm),
                child: Text(
                  entry.meaning,
                  style: TypographyTokens.body1.copyWith(
                    color: ColorTokens.secondary,
                  ),
                ),
              ),
            ],
          ),
          
          SizedBox(height: SpacingTokens.lg),
          
          // 플래시카드 추가 버튼
          PikaButton(
            text: isExistingFlashcard ? '플래시카드로 설정됨' : '플래시카드 추가',
            variant: isExistingFlashcard ? PikaButtonVariant.primary : PikaButtonVariant.primary,
            leadingIcon: !isExistingFlashcard 
              ? Image.asset(
                  'assets/images/icon_flashcard_dic.png',
                  width: 24,
                  height: 24,
                )
              : null,
            onPressed: isExistingFlashcard
                ? null
                : () {
                    onCreateFlashCard(
                      entry.word,
                      entry.meaning,
                      pinyin: entry.pinyin,
                    );
                    Navigator.pop(context);

                    // 추가 완료 메시지
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('플래시카드에 추가되었습니다'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
            isFullWidth: true,
          ),
        ],
      ),
    );
  }

  /// 사전 결과 바텀 시트 표시 헬퍼 메서드
  static void showDictionaryBottomSheet({
    required BuildContext context,
    required DictionaryEntry entry,
    required Function(String, String, {String? pinyin}) onCreateFlashCard,
    bool isExistingFlashcard = false,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DictionaryResultWidget(
          entry: entry,
          onCreateFlashCard: onCreateFlashCard,
          isExistingFlashcard: isExistingFlashcard,
        ),
      ),
    );
  }
}
