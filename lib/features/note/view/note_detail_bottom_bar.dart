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
    
    // 이전/다음 페이지 처리 상태
    final bool prevPageProcessed = _isPrevPageProcessed();
    final bool nextPageProcessed = _isNextPageProcessed();
    final bool prevPageProcessing = _isPrevPageProcessing();
    final bool nextPageProcessing = _isNextPageProcessing();
    
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
                      // 이전 페이지 버튼 - 분리된 위젯 사용
                      SizedBox(
                        width: 32,
                        child: PageNavigationButton(
                          icon: Icons.arrow_back_ios_rounded,
                          onTap: (widget.currentPageIndex > 0 && prevPageProcessed && !prevPageProcessing) 
                              ? () => widget.onPageChanged(widget.currentPageIndex - 1) 
                              : widget.currentPageIndex > 0 
                                  ? () => _showPageProcessingMessage(context, widget.currentPageIndex - 1)
                                  : null,
                          isDisabled: widget.currentPageIndex > 0 && !prevPageProcessed && !prevPageProcessing,
                          isProcessing: prevPageProcessing,
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
                          
                          // 다음 페이지 버튼 - 분리된 위젯 사용
                          PageNavigationButton(
                            icon: Icons.arrow_forward_ios_rounded,
                            onTap: (widget.currentPageIndex < widget.totalPages - 1 && nextPageProcessed && !nextPageProcessing)
                                ? () => widget.onPageChanged(widget.currentPageIndex + 1) 
                                : widget.currentPageIndex < widget.totalPages - 1
                                    ? () => _showPageProcessingMessage(context, widget.currentPageIndex + 1)
                                    : null,
                            isDisabled: widget.currentPageIndex < widget.totalPages - 1 && !nextPageProcessed && !nextPageProcessing,
                            isProcessing: nextPageProcessing,
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

  // 이전 페이지가 처리되었는지 확인
  bool _isPrevPageProcessed() {
    final prevPageIndex = widget.currentPageIndex - 1;
    if (prevPageIndex < 0) return true; // 첫 페이지면 항상 true
    
    // processedPages 배열이 있고, 해당 인덱스가 유효하면 해당 값 반환
    if (widget.processedPages.isNotEmpty && prevPageIndex < widget.processedPages.length) {
      return widget.processedPages[prevPageIndex];
    }
    
    // 페이지 처리 상태 정보가 없으면 처리된 것으로 간주
    return true;
  }
  
  // 다음 페이지가 처리되었는지 확인
  bool _isNextPageProcessed() {
    final nextPageIndex = widget.currentPageIndex + 1;
    if (nextPageIndex >= widget.totalPages) return true; // 마지막 페이지면 항상 true
    
    // processedPages 배열이 있고, 해당 인덱스가 유효하면 해당 값 반환
    if (widget.processedPages.isNotEmpty && nextPageIndex < widget.processedPages.length) {
      return widget.processedPages[nextPageIndex];
    }
    
    // 페이지 처리 상태 정보가 없으면 기본적으로 처리된 것으로 간주
    return true;
  }
  
  // 처리되지 않은 페이지로 이동하려 할 때 메시지 표시
  void _showPageProcessingMessage(BuildContext context, int pageIndex) {
    final pageNum = pageIndex + 1;
    final int progress = (pageIndex + 1);
    final int total = widget.totalPages;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            // 로딩 인디케이터
            Container(
              width: 16,
              height: 16,
              margin: const EdgeInsets.only(right: 12),
              child: const CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            // 텍스트 메시지
            Expanded(
              child: Text(
                '$pageNum번째 페이지($progress/$total)가 아직 처리 중입니다.\n잠시 후 이동할 수 있습니다.',
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: '닫기',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  // 이전 페이지가 처리 중인지 확인
  bool _isPrevPageProcessing() {
    final prevPageIndex = widget.currentPageIndex - 1;
    if (prevPageIndex < 0) return false; // 첫 페이지면 항상 false
    
    // processingPages 배열이 있고, 해당 인덱스가 유효하면 해당 값 반환
    if (widget.processingPages.isNotEmpty && prevPageIndex < widget.processingPages.length) {
      return widget.processingPages[prevPageIndex];
    }
    
    // 페이지 처리 상태 정보가 없으면 처리된 것으로 간주
    return false;
  }
  
  // 다음 페이지가 처리 중인지 확인
  bool _isNextPageProcessing() {
    final nextPageIndex = widget.currentPageIndex + 1;
    if (nextPageIndex >= widget.totalPages) return false; // 마지막 페이지면 항상 false
    
    // processingPages 배열이 있고, 해당 인덱스가 유효하면 해당 값 반환
    if (widget.processingPages.isNotEmpty && nextPageIndex < widget.processingPages.length) {
      return widget.processingPages[nextPageIndex];
    }
    
    // 페이지 처리 상태 정보가 없으면 기본적으로 처리된 것으로 간주
    return false;
  }
} 