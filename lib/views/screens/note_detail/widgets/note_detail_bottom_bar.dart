import 'package:flutter/material.dart';

import '../../../../theme/tokens/color_tokens.dart';
import '../../../../theme/tokens/spacing_tokens.dart';
import '../managers/note_page_manager_wrapper.dart';

/// 노트 상세 화면의 하단 바 위젯
/// 
/// 페이지 내비게이션, 텍스트 모드 전환 등의 기능을 제공합니다.

class NoteDetailBottomBar extends StatelessWidget {
  final NotePageManagerWrapper pageManagerWrapper;
  final bool useSegmentMode;
  final VoidCallback onToggleTextMode;
  
  const NoteDetailBottomBar({
    super.key,
    required this.pageManagerWrapper,
    required this.useSegmentMode,
    required this.onToggleTextMode,
  });
  
  @override
  Widget build(BuildContext context) {
    final currentPageIndex = pageManagerWrapper.getCurrentPageIndex();
    final totalPages = pageManagerWrapper.getTotalPageCount();
    
    return Container(
      decoration: BoxDecoration(
        color: ColorTokens.surface,
        boxShadow: [
          BoxShadow(
            color: ColorTokens.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        horizontal: SpacingTokens.lg,
        vertical: SpacingTokens.md,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 페이지 내비게이션 버튼
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 20),
                onPressed: currentPageIndex > 0
                    ? () => pageManagerWrapper.previousPage()
                    : null,
                color: currentPageIndex > 0
                    ? ColorTokens.textPrimary
                    : ColorTokens.textPrimary.withOpacity(0.3),
              ),
              const SizedBox(width: 8),
              Text(
                '${currentPageIndex + 1} / $totalPages',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios, size: 20),
                onPressed: currentPageIndex < totalPages - 1
                    ? () => pageManagerWrapper.nextPage()
                    : null,
                color: currentPageIndex < totalPages - 1
                    ? ColorTokens.textPrimary
                    : ColorTokens.textPrimary.withOpacity(0.3),
              ),
            ],
          ),
          
          // 기능 버튼들
          Row(
            children: [
              // 텍스트 모드 토글 버튼
              IconButton(
                icon: Icon(useSegmentMode
                    ? Icons.segment
                    : Icons.article_outlined),
                onPressed: onToggleTextMode,
                tooltip: useSegmentMode
                    ? '전체 텍스트 모드로 전환'
                    : '세그먼트 모드로 전환',
                color: ColorTokens.textPrimary,
              ),
              
              // TTS 버튼
              IconButton(
                icon: const Icon(Icons.volume_up),
                onPressed: () {
                  // TTS 재생 로직
                },
                color: ColorTokens.textPrimary,
              ),
              
              // 플래시카드 생성 버튼
              IconButton(
                icon: const Icon(Icons.flash_on),
                onPressed: () {
                  // 플래시카드 생성 로직
                },
                color: ColorTokens.textPrimary,
              ),
            ],
          ),
        ],
      ),
    );
  }
} 