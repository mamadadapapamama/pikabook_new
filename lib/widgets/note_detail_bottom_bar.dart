import 'package:flutter/material.dart';
import 'dart:io';
import '../models/page.dart' as page_model;
import '../services/page_content_service.dart';
import '../services/text_reader_service.dart';
import '../utils/text_display_mode.dart';
import '../theme/tokens/color_tokens.dart';
import 'package:google_fonts/google_fonts.dart';

/// 노트 상세 화면 하단 내비게이션 바
/// 페이지 탐색, 텍스트 표시 모드 토글, 전체 읽기 버튼, 진행률 바 제공

class NoteDetailBottomBar extends StatelessWidget {
  final page_model.Page? currentPage;
  final int currentPageIndex;
  final int totalPages;
  final Function(int) onPageChanged;
  final TextDisplayMode textDisplayMode;
  final Function(TextDisplayMode) onTextDisplayModeChanged;
  final bool isPlaying;
  final VoidCallback onPlayPausePressed;
  final PageContentService pageContentService;
  final TextReaderService textReaderService;

  const NoteDetailBottomBar({
    super.key,
    required this.currentPage,
    required this.currentPageIndex,
    required this.totalPages,
    required this.onPageChanged,
    required this.textDisplayMode,
    required this.onTextDisplayModeChanged,
    required this.isPlaying,
    required this.onPlayPausePressed,
    required this.pageContentService,
    required this.textReaderService,
  });

  @override
  Widget build(BuildContext context) {
    if (currentPage == null) return const SizedBox.shrink();
    
    final processedText = currentPage!.id != null 
        ? pageContentService.getProcessedText(currentPage!.id!) 
        : null;
        
    // 세그먼트 존재 여부 확인
    final bool hasSegments = processedText != null && 
                             processedText.segments != null && 
                             processedText.segments!.isNotEmpty; 
    
    // 병음 표시 여부 확인
    final bool showPinyin = processedText?.showPinyin ?? false;
    
    // 디버그 정보 출력
    debugPrint('NoteDetailBottomBar - 현재 모드: $textDisplayMode, 페이지: ${currentPageIndex + 1}/$totalPages');
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 페이지 진행률 바
        _buildProgressBar(context),
        
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Color(0xFFFFF0E8), width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 8,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 이전 페이지 버튼
              _buildNavigationButton(
                icon: Icons.arrow_back_ios_rounded,
                onTap: currentPageIndex > 0 
                    ? () => onPageChanged(currentPageIndex - 1) 
                    : null,
              ),
              
              // 중앙 컨트롤 영역 (병음 토글 + 재생 버튼)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 병음 토글 버튼
                  GestureDetector(
                    onTap: () {
                      // 토글: 현재 모드가 all이면 nopinyin으로, 아니면 all로 변경
                      final newMode = showPinyin ? TextDisplayMode.nopinyin : TextDisplayMode.all;
                      onTextDisplayModeChanged(newMode);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: showPinyin ? ColorTokens.secondary : Colors.white,
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: ColorTokens.secondary),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '한어병음',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: showPinyin ? Colors.white : ColorTokens.secondary,
                            ),
                          ),
                          if (showPinyin)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(left: 4),
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // 전체 읽기/멈춤 버튼 (page_content_widget과 동일한 디자인)
                  InkWell(
                    onTap: onPlayPausePressed,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isPlaying ? ColorTokens.secondary : Colors.white,
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: ColorTokens.secondary),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPlaying ? Icons.stop : Icons.volume_up,
                            color: isPlaying ? Colors.white : ColorTokens.secondary,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isPlaying ? '정지' : '전체 재생',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: isPlaying ? Colors.white : ColorTokens.secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              
              // 다음 페이지 버튼
              _buildNavigationButton(
                icon: Icons.arrow_forward_ios_rounded,
                onTap: currentPageIndex < totalPages - 1 
                    ? () => onPageChanged(currentPageIndex + 1) 
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  // 페이지 진행률 바 위젯
  Widget _buildProgressBar(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final progressWidth = totalPages > 0 
        ? (currentPageIndex + 1) / totalPages * screenWidth 
        : 0.0;
    
    return Container(
      height: 4,
      width: double.infinity,
      color: const Color(0xFFFFF0E8),
      child: Row(
        children: [
          // 진행된 부분 (현재 페이지까지)
          Container(
            width: progressWidth,
            color: ColorTokens.primary,
          ),
        ],
      ),
    );
  }
  
  // 네비게이션 버튼 위젯
  Widget _buildNavigationButton({required IconData icon, VoidCallback? onTap}) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(
        icon, 
        color: onTap != null ? ColorTokens.secondary : Colors.grey.shade300,
        size: 24,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
      splashRadius: 24,
    );
  }
  
  // 최소한의 UI를 가진 바텀 바 (ProcessedText가 없는 경우)
  Widget _buildMinimalBottomBar(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 페이지 진행률 바 (비활성화 상태)
        Container(
          height: 4,
          width: double.infinity,
          color: const Color(0xFFFFF0E8),
          child: Row(
            children: [
              // 진행된 부분 (현재 페이지까지)
              Container(
                width: totalPages > 0 
                    ? (currentPageIndex + 1) / totalPages * MediaQuery.of(context).size.width 
                    : 0,
                color: ColorTokens.primary,
              ),
            ],
          ),
        ),
        
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Color(0xFFFFF0E8), width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 8,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 이전 페이지 버튼 (비활성화)
              Icon(
                Icons.arrow_back_ios_rounded, 
                color: Colors.grey.shade300,
                size: 24,
              ),
              
              // 중앙 컨트롤 영역 (비활성화 상태)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 병음 토글 버튼 (비활성화)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      '한어병음',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // 재생 버튼 (비활성화)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.volume_up,
                          color: Colors.grey.shade400,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '전체 재생',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              // 다음 페이지 버튼 (비활성화)
              Icon(
                Icons.arrow_forward_ios_rounded, 
                color: Colors.grey.shade300,
                size: 24,
              ),
            ],
          ),
        ),
      ],
    );
  }
} 