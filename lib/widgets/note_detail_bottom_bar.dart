import 'package:flutter/material.dart';
import 'dart:io';
import '../models/page.dart' as page_model;
import '../services/page_content_service.dart';
import '../services/text_reader_service.dart';
import '../utils/text_display_mode.dart';
import '../theme/tokens/color_tokens.dart';
import 'package:google_fonts/google_fonts.dart';

/// 노트 상세 화면 하단 내비게이션 바
/// 텍스트 표시 모드 토글, 전체 읽기 버튼 등 제공

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
        
    if (processedText == null) {
      // ProcessedText가 없는 경우 최소한의 UI만 표시
      return _buildMinimalBottomBar(context);
    }
    
    // 세그먼트 존재 여부 확인
    final bool hasSegments = processedText.segments != null && 
                             processedText.segments!.isNotEmpty; 
    
    // 병음 표시 여부 확인
    final bool showPinyin = processedText.showPinyin;
    
    // 디버그 정보 출력
    debugPrint('NoteDetailBottomBar - 현재 모드: $textDisplayMode, 병음 표시: ${processedText.showPinyin}');
    debugPrint('세그먼트 정보: ${processedText.segments?.length ?? 0}개, hasSegments: $hasSegments');
      
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 24.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFFFF0E8), width: 4),
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
          // 병음 토글 버튼
          GestureDetector(
            onTap: () {
              // 토글: 현재 모드가 all이면 nopinyin으로, 아니면 all로 변경
              final newMode = showPinyin ? TextDisplayMode.nopinyin : TextDisplayMode.all;
              onTextDisplayModeChanged(newMode);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
          
          // 전체 읽기/멈춤 버튼
          IconButton(
            key: ValueKey('play_button_${isPlaying ? 'playing' : 'stopped'}'),
            icon: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: ColorTokens.secondary),
              ),
              child: Icon(
                isPlaying ? Icons.stop : Icons.volume_up,
                color: ColorTokens.secondary,
                size: 20,
              ),
            ),
            onPressed: onPlayPausePressed,
            tooltip: isPlaying ? '읽기 중지' : '전체 읽기',
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
  
  // 최소한의 UI를 가진 바텀 바 (ProcessedText가 없는 경우)
  Widget _buildMinimalBottomBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 24.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Color(0xFFFFF0E8), width: 4),
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
          // 병음 토글 버튼 (비활성화 상태)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
          
          // 전체 읽기 버튼 (비활성화 상태)
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Icon(
              Icons.volume_up,
              color: Colors.grey.shade400,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
} 