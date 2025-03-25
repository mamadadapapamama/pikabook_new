import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/note.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import '../widgets/flashcard_counter_badge.dart';

class NoteDetailAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Note? note;
  final VoidCallback onShowMoreOptions;
  final Function() onFlashCardPressed;
  final int currentPageIndex;
  final int totalPages;

  const NoteDetailAppBar({
    Key? key,
    required this.note,
    required this.onShowMoreOptions,
    required this.onFlashCardPressed,
    this.currentPageIndex = 0,
    this.totalPages = 0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 상태 표시줄 색상을 검정으로 설정
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );
    
    final String pageNumberText = 'page ${currentPageIndex + 1} / $totalPages';
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // AppBar 내용
        SizedBox(
          height: 100, // 앱바 높이 조정 (홈 스크린 + 4px)
          child: Padding(
            padding: const EdgeInsets.only(top: 50.0, left: 16.0, right: 16.0, bottom:24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 왼쪽 부분: 뒤로가기 버튼 및 제목
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 뒤로가기 버튼
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back_ios_rounded,
                          color: Colors.black,
                          size: 20,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 4),
                      
                      // 제목 영역
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // 노트 제목
                            Flexible(
                              child: Text(
                                note?.originalText ?? 'Note',
                                style: TypographyTokens.subtitle2En.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: ColorTokens.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            
                            // 페이지 정보
                            if (totalPages > 0)
                              Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: Text(
                                  pageNumberText,
                                  style: TypographyTokens.caption.copyWith(
                                    color: ColorTokens.textGrey,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // 오른쪽 부분: 플래시카드 및 더보기 버튼
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 플래시카드 버튼 - note_list_item과 동일한 디자인
                    if (note != null)
                      GestureDetector(
                        onTap: onFlashCardPressed,
                        child: FlashcardCounterBadge(
                          count: note!.flashcardCount,
                        ),
                      ),
                      
                    const SizedBox(width: 8),
                    
                    // 더보기 버튼
                    IconButton(
                      icon: const Icon(
                        Icons.more_vert,
                        color: ColorTokens.textGrey,
                      ),
                      onPressed: onShowMoreOptions,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: '더 보기',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        
        // 프로그레스 바
        _buildProgressBar(context),
      ],
    );
  }

  Widget _buildProgressBar(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final progressWidth = totalPages > 0 
        ? (currentPageIndex + 1) / totalPages * screenWidth 
        : 0.0;
    
    return SizedBox(
      height: 4,
      width: double.infinity,
      child: Stack(
        children: [
          // 배경 바
          Container(
            width: double.infinity,
            color: ColorTokens.divider,
          ),
          // 진행 바
          Container(
            width: progressWidth,
            color: ColorTokens.primary,
          ),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(80);  //homescreen 과 통일
}