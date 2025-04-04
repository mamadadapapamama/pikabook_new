import 'package:flutter/material.dart';
import 'dart:io';
import '../models/page.dart' as page_model;
import '../models/processed_text.dart';
import '../services/page_content_service.dart';
import '../services/text_reader_service.dart';
import '../services/tts_service.dart';
import '../utils/text_display_mode.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import 'common/tts_button.dart';

/// 노트 상세 화면 하단 내비게이션 바
/// 페이지 탐색, 텍스트 표시 모드 토글, 모드 전환, 진행률 바 제공

class NoteDetailBottomBar extends StatefulWidget {
  final page_model.Page? currentPage;
  final int currentPageIndex;
  final int totalPages;
  final Function(int) onPageChanged;
  final TextDisplayMode textDisplayMode;
  final Function(TextDisplayMode) onTextDisplayModeChanged;
  final bool isFullTextMode;
  final VoidCallback onToggleFullTextMode;
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
    required this.isFullTextMode,
    required this.onToggleFullTextMode,
    required this.pageContentService,
    required this.textReaderService,
  });

  @override
  State<NoteDetailBottomBar> createState() => _NoteDetailBottomBarState();
}

class _NoteDetailBottomBarState extends State<NoteDetailBottomBar> {
  final TtsService _ttsService = TtsService();
  ProcessedText? processedText;
  
  @override
  void initState() {
    super.initState();
    _updateProcessedText();
  }
  
  @override
  void didUpdateWidget(NoteDetailBottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentPage?.id != widget.currentPage?.id) {
      _updateProcessedText();
    }
  }
  
  void _updateProcessedText() {
    if (widget.currentPage?.id != null) {
      processedText = widget.pageContentService.getProcessedText(widget.currentPage!.id!);
    } else {
      processedText = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentPage == null) return const SizedBox.shrink();
    
    // 세그먼트 존재 여부 확인
    final bool hasSegments = processedText != null && 
                             processedText!.segments != null && 
                             processedText!.segments!.isNotEmpty; 
    
    // 병음 표시 여부 확인
    final bool showPinyin = processedText?.showPinyin ?? false;
    
    // 디버그 정보 출력
    debugPrint('NoteDetailBottomBar - 현재 모드: ${widget.textDisplayMode}, 페이지: ${widget.currentPageIndex + 1}/${widget.totalPages}, 전체보기: ${widget.isFullTextMode}');
    
    // 현재 페이지 진행률 계산 (0.0 ~ 1.0 사이 값)
    final double progress = widget.totalPages > 0 ? (widget.currentPageIndex + 1) / widget.totalPages : 0.0;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 프로그레스 바
        _buildProgressBar(context, progress),
        
        // 컨트롤 부분
        Container(
          padding: EdgeInsets.symmetric(vertical: SpacingTokens.sm + SpacingTokens.xs, horizontal: SpacingTokens.md),
          decoration: BoxDecoration(
            color: ColorTokens.surface,
            border: const Border(
              top: BorderSide(color: ColorTokens.primaryverylight, width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: ColorTokens.black.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, -2),
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
                onTap: widget.currentPageIndex > 0 
                    ? () => widget.onPageChanged(widget.currentPageIndex - 1) 
                    : null,
              ),
              
              // 중앙 컨트롤 영역 (병음 토글 + 모드 전환 버튼)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 병음 토글 버튼
                  GestureDetector(
                    onTap: () {
                      // 토글: 현재 모드가 all이면 nopinyin으로, 아니면 all로 변경
                      final newMode = showPinyin ? TextDisplayMode.nopinyin : TextDisplayMode.all;
                      widget.onTextDisplayModeChanged(newMode);
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: SpacingTokens.sm + SpacingTokens.xs/2, 
                        vertical: SpacingTokens.xs + SpacingTokens.xs/2
                      ),
                      decoration: BoxDecoration(
                        color: showPinyin ? ColorTokens.secondary : ColorTokens.surface,
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: ColorTokens.secondary),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '한어병음',
                            style: TypographyTokens.caption.copyWith(
                              color: showPinyin ? ColorTokens.textLight : ColorTokens.secondary,
                            ),
                          ),
                          if (showPinyin)
                            Container(
                              width: SpacingTokens.xs * 2,
                              height: SpacingTokens.xs * 2,
                              margin: EdgeInsets.only(left: SpacingTokens.xs),
                              decoration: const BoxDecoration(
                                color: ColorTokens.textLight,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  
                  SizedBox(width: SpacingTokens.md),
                  
                  // 모드 전환 버튼 (문장별 구분/원문 전체)
                  GestureDetector(
                    onTap: widget.onToggleFullTextMode,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: SpacingTokens.sm + SpacingTokens.xs/2, 
                        vertical: SpacingTokens.xs + SpacingTokens.xs/2
                      ),
                      decoration: BoxDecoration(
                        color: ColorTokens.surface,
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: ColorTokens.secondary),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.isFullTextMode ? '문장별 구분' : '원문 전체',
                            style: TypographyTokens.caption.copyWith(
                              color: ColorTokens.secondary,
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
                onTap: widget.currentPageIndex < widget.totalPages - 1 
                    ? () => widget.onPageChanged(widget.currentPageIndex + 1) 
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  /// 프로그레스 바 위젯 빌드
  Widget _buildProgressBar(BuildContext context, double progress) {
    // progress는 0.0 ~ 1.0 사이 값
    final double clampedProgress = progress.clamp(0.0, 1.0);
    
    return Stack(
      children: [
        // 배경 (회색 배경)
        Container(
          width: double.infinity,
          height: 2,
          color: ColorTokens.divider,
        ),
        // 진행 상태 (오렌지색)
        Container(
          width: MediaQuery.of(context).size.width * clampedProgress,
          height: 2,
          color: ColorTokens.primary,
        ),
      ],
    );
  }
  
  // 네비게이션 버튼 위젯
  Widget _buildNavigationButton({required IconData icon, VoidCallback? onTap}) {
    return IconButton(
      onPressed: onTap != null ? () {
        // 탭이 가능한 상태일 때만 실행
        debugPrint('네비게이션 버튼 클릭: ${icon == Icons.arrow_back_ios_rounded ? "이전" : "다음"}');
        
        // 페이지 전환 직후 텍스트 렌더링 지연 방지를 위한 short delay
        // 페이지 변경 콜백 호출
        onTap();
      } : null,
      icon: Icon(
        icon, 
        color: onTap != null ? ColorTokens.secondary : ColorTokens.greyMedium,
        size: SpacingTokens.iconSizeMedium,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      visualDensity: VisualDensity.compact,
      splashRadius: SpacingTokens.iconSizeMedium,
    );
  }
  
  /*
  // 현재 사용되지 않는 코드입니다 - 향후 참조를 위해 보존
  // minimal UI 버전의 하단바가 필요할 때 활용할 수 있습니다
  
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
                width: widget.totalPages > 0 
                    ? (widget.currentPageIndex + 1) / widget.totalPages * MediaQuery.of(context).size.width 
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
  */
} 