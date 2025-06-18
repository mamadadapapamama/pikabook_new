import 'package:flutter/material.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../core/theme/tokens/spacing_tokens.dart';
import 'note_progress_bar.dart';
import 'page_indicator.dart';
import 'page_navigation_button.dart';
import '../../tts/tts_play_all_button.dart';

/// 노트 상세 화면 하단 내비게이션 바
/// 페이지 탐색, 진행률 바 제공 (세그먼트 모드에서는 전체 텍스트 재생 포함)

class NoteDetailBottomBar extends StatefulWidget {
  final page_model.Page? currentPage;
  final int currentPageIndex;
  final int totalPages;
  final Function(int) onPageChanged;
  final String ttsText; // TTS 재생할 텍스트 (세그먼트 모드에서만 사용)
  final bool isProcessing; // 현재 페이지가 처리 중인지 여부
  final double progressValue;
  final VoidCallback? onTtsPlay; // TTS 재생 콜백 (세그먼트 모드에서만 사용)
  final bool isMinimalUI;
  final bool useSegmentMode; // 세그먼트 모드 여부
  final List<bool> processedPages; // 각 페이지의 처리 상태 추적 배열 추가
  final List<bool> processingPages; // 각 페이지의 처리 중 상태 추적 배열 추가

  const NoteDetailBottomBar({
    super.key,
    required this.currentPage,
    required this.currentPageIndex,
    required this.totalPages,
    required this.onPageChanged,
    this.ttsText = '', // TTS 재생할 텍스트
    this.isProcessing = false, // 기본값은 false (처리 중이 아님)
    this.progressValue = 0.0,
    this.onTtsPlay,
    this.isMinimalUI = false,
    this.useSegmentMode = false, // 기본값은 문단 모드
    this.processedPages = const [], // 기본값은 빈 배열
    this.processingPages = const [], // 기본값은 빈 배열
  });

  @override
  State<NoteDetailBottomBar> createState() => _NoteDetailBottomBarState();
}

class _NoteDetailBottomBarState extends State<NoteDetailBottomBar> {
  @override
  Widget build(BuildContext context) {
    if (widget.currentPage == null) return const SizedBox.shrink();
    
    // 현재 페이지 진행률 계산 (0.0 ~ 1.0 사이 값)
    final double progress = widget.progressValue > 0 
        ? widget.progressValue 
        : (widget.totalPages > 0 ? (widget.currentPageIndex + 1) / widget.totalPages : 0.0);
    
    // 하단 safe area 영역 고려
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    

    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, -2),
            blurRadius: 8,
            color: Colors.black.withOpacity(0.15),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          // 바텀 패딩을 고려하여 높이 조정 - 전체 높이를 더 줄임
          height: 48 + (bottomPadding > 0 ? 4 : 0), // notch 기기에서만 약간의 추가 높이
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 프로그레스 바 - 분리된 위젯 사용
              NoteProgressBar(progress: progress),
              
              // 컨트롤 영역
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: SpacingTokens.xs,
                    right: SpacingTokens.xs,
                    top: 2, // 패딩 줄임
                    bottom: 2, // 패딩 줄임
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 이전 페이지 버튼 - 항상 활성화
                      SizedBox(
                        width: 32,
                        child: PageNavigationButton(
                          icon: Icons.arrow_back_ios_rounded,
                          onTap: widget.currentPageIndex > 0 
                              ? () => widget.onPageChanged(widget.currentPageIndex - 1) 
                              : null,
                          isDisabled: false,
                          isProcessing: false,
                        ),
                      ),
                      
                      // 중앙 - TTS 버튼 (세그먼트 모드에서만 표시)
                      if (widget.useSegmentMode && 
                          widget.currentPage != null && 
                          !widget.isMinimalUI && 
                          widget.ttsText.isNotEmpty)
                        TtsPlayAllButton(
                          text: widget.ttsText,
                          onPlayStart: widget.onTtsPlay,
                        )
                      else
                        const SizedBox.shrink(),
                      
                      // 오른쪽 영역 (페이지 번호 + 다음 페이지 버튼)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 페이지 번호 표시
                          PageIndicator(currentIndex: widget.currentPageIndex, totalPages: widget.totalPages),
                          const SizedBox(width: 4),
                          
                          // 다음 페이지 버튼 - 항상 활성화
                          PageNavigationButton(
                            icon: Icons.arrow_forward_ios_rounded,
                            onTap: widget.currentPageIndex < widget.totalPages - 1
                                ? () => widget.onPageChanged(widget.currentPageIndex + 1) 
                                : null,
                            isDisabled: false,
                            isProcessing: false,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


} 