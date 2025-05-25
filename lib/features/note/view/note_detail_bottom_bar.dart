import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../core/models/page.dart' as page_model;
import '../../core/models/processed_text.dart';
import '../../../core/services/tts/tts_service.dart';
import '../../../core/services/tts/tts_playback_service.dart';
import '../../../core/services/text_processing/llm_text_processing.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../../core/widgets/tts_button.dart';
import 'dart:async';
import '../view/note_progress_bar.dart';
import '../view/page_indicator.dart';
import '../view/page_navigation_button.dart';
import '../tts/tts_play_all_button.dart';

/// 노트 상세 화면 하단 내비게이션 바
/// 페이지 탐색, 본문 전체 듣기, 진행률 바 제공

class NoteDetailBottomBar extends StatefulWidget {
  final page_model.Page? currentPage;
  final int currentPageIndex;
  final int totalPages;
  final Function(int) onPageChanged;
  final dynamic contentManager;
  final TtsPlaybackService ttsPlaybackService;
  final bool isProcessing; // 현재 페이지가 처리 중인지 여부
  final double progressValue;
  final VoidCallback? onTtsPlay;
  final bool isMinimalUI;
  final List<bool> processedPages; // 각 페이지의 처리 상태 추적 배열 추가

  const NoteDetailBottomBar({
    super.key,
    required this.currentPage,
    required this.currentPageIndex,
    required this.totalPages,
    required this.onPageChanged,
    this.contentManager,
    required this.ttsPlaybackService,
    this.isProcessing = false, // 기본값은 false (처리 중이 아님)
    this.progressValue = 0.0,
    this.onTtsPlay,
    this.isMinimalUI = false,
    this.processedPages = const [], // 기본값은 빈 배열
  });

  @override
  State<NoteDetailBottomBar> createState() => _NoteDetailBottomBarState();
}

class _NoteDetailBottomBarState extends State<NoteDetailBottomBar> {
  ProcessedText? processedText;
  bool _isLoadingText = false; // 로딩 상태 추적 변수 추가
  
  @override
  void initState() {
    super.initState();
    // contentManager가 제공된 경우에만 텍스트 가져오기 시도
    if (widget.contentManager != null) {
      _fetchProcessedTextSafely();
    }
  }
  
  @override
  void didUpdateWidget(NoteDetailBottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 페이지 ID가 변경된 경우에만 새로운 텍스트 가져오기
    if (oldWidget.currentPage?.id != widget.currentPage?.id && widget.contentManager != null) {
      _fetchProcessedTextSafely();
    }
  }
  
  // 안전하게 ProcessedText를 가져오는 메서드
  void _fetchProcessedTextSafely() {
    if (widget.currentPage?.id == null || widget.contentManager == null) {
      setState(() {
        processedText = null;
        _isLoadingText = false;
      });
      return;
    }
    
    // 이미 로딩 중이면 중복 요청 방지
    if (_isLoadingText) return;
    
    setState(() {
      _isLoadingText = true;
    });
    
    // 비동기 작업을 Future로 실행하고 완료되면 상태 업데이트
    _updateProcessedText().then((_) {
      if (mounted) {
        setState(() {
          _isLoadingText = false;
        });
      }
    }).catchError((e) {
      if (kDebugMode) {
        debugPrint("❌ ProcessedText 업데이트 오류: $e");
      }
      if (mounted) {
        setState(() {
          _isLoadingText = false;
        });
      }
    });
  }
  
  Future<void> _updateProcessedText() async {
    if (widget.currentPage?.id == null || widget.contentManager == null) {
      processedText = null;
      return;
    }
    
    try {
      // contentManager가 getProcessedText 메서드를 가지고 있는지 확인
      if (widget.contentManager != null && 
          widget.contentManager is Function ||
          widget.contentManager.getProcessedText is Function) {
        // 타임아웃 설정으로 무한 대기 방지
        processedText = await widget.contentManager.getProcessedText(widget.currentPage!.id!)
            .timeout(
              const Duration(seconds: 3),
              onTimeout: () {
                if (kDebugMode) {
                  debugPrint("⚠️ ProcessedText 로드 타임아웃");
                }
                return null;
              }
            );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("❌ ProcessedText 업데이트 오류: $e");
      }
      processedText = null;
    }
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

  @override
  Widget build(BuildContext context) {
    if (widget.currentPage == null) return const SizedBox.shrink();
    
    // 세그먼트 존재 여부 확인 - 지역 변수로 결과 캐싱
    final bool hasSegments = processedText != null && 
                             processedText!.units.isNotEmpty; 
    
    // 디버그 정보 출력을 kDebugMode 상태에서만 실행
    if (kDebugMode) {
      debugPrint('NoteDetailBottomBar - 세그먼트: ${hasSegments ? "있음" : "없음"}');
    }
    
    // 현재 페이지 진행률 계산 (0.0 ~ 1.0 사이 값)
    final double progress = widget.progressValue > 0 
        ? widget.progressValue 
        : (widget.totalPages > 0 ? (widget.currentPageIndex + 1) / widget.totalPages : 0.0);
    
    // 하단 safe area 영역 고려
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    
    // 이전/다음 페이지 처리 상태
    final bool prevPageProcessed = _isPrevPageProcessed();
    final bool nextPageProcessed = _isNextPageProcessed();
    
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
                          onTap: (widget.currentPageIndex > 0 && prevPageProcessed) 
                              ? () => widget.onPageChanged(widget.currentPageIndex - 1) 
                              : widget.currentPageIndex > 0 
                                  ? () => _showPageProcessingMessage(context, widget.currentPageIndex - 1)
                                  : null,
                          isDisabled: widget.currentPageIndex > 0 && !prevPageProcessed,
                        ),
                      ),
                      
                      // 중앙 - TTS 버튼
                      if (widget.currentPage != null && !widget.isMinimalUI && hasSegments)
                      TtsPlayAllButton(
                        text: processedText?.fullOriginalText ?? '',
                        onPlayStart: widget.onTtsPlay,
                      ),
                      
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
                            onTap: (widget.currentPageIndex < widget.totalPages - 1 && nextPageProcessed)
                                ? () => widget.onPageChanged(widget.currentPageIndex + 1) 
                                : widget.currentPageIndex < widget.totalPages - 1
                                    ? () => _showPageProcessingMessage(context, widget.currentPageIndex + 1)
                                    : null,
                            isDisabled: widget.currentPageIndex < widget.totalPages - 1 && !nextPageProcessed,
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