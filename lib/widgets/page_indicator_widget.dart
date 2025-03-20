import 'package:flutter/material.dart';
import '../theme/tokens/color_tokens.dart';
import 'package:google_fonts/google_fonts.dart';

class PageIndicatorWidget extends StatelessWidget {
  final int currentPageIndex;
  final int totalPages;
  final Function(int) onPageChanged;

  const PageIndicatorWidget({
    Key? key,
    required this.currentPageIndex,
    required this.totalPages,
    required this.onPageChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFFFFF0E8),
            width: 4,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 이전 페이지 버튼
          IconButton(
            icon: Icon(
              Icons.arrow_back_ios,
              size: 16,
              color: currentPageIndex > 0 ? const Color(0xFF969696) : Colors.grey.shade300,
            ),
            onPressed: currentPageIndex > 0
                ? () => onPageChanged(currentPageIndex - 1)
                : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 24,
              minHeight: 24,
            ),
          ),
          
          // 썸네일 이미지 (플레이스홀더)
          Container(
            width: 40,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          
          // 다음 페이지 버튼
          IconButton(
            icon: Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: currentPageIndex < totalPages - 1 ? ColorTokens.primary : Colors.grey.shade300,
            ),
            onPressed: currentPageIndex < totalPages - 1
                ? () => onPageChanged(currentPageIndex + 1)
                : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 24,
              minHeight: 24,
            ),
          ),
        ],
      ),
    );
  }
}
