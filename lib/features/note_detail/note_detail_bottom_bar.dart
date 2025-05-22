import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../core/models/page.dart' as page_model;
import '../../core/models/processed_text.dart';
import '../../core/services/text_processing/text_reader_service.dart';
import '../../core/services/tts/tts_service.dart';
import '../../core/services/text_processing/llm_text_processing.dart';
import '../../core/utils/text_display_mode.dart';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import '../../core/theme/tokens/spacing_tokens.dart';
import '../../core/widgets/tts_button.dart';
import 'managers/page_content_manager.dart';
import 'dart:async';

/// 노트 상세 화면 하단 내비게이션 바
/// 페이지 탐색, 텍스트 표시 모드 토글, 모드 전환, 진행률 바 제공

class NoteDetailBottomBar extends StatefulWidget {
  final page_model.Page? currentPage;
  final int currentPageIndex;
  final int totalPages;
  final Function(int) onPageChanged;
  final SegmentManager contentManager;
  final TextReaderService textReaderService;
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
    required this.contentManager,
    required this.textReaderService,
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
  // 싱글톤 인스턴스 사용하도록 수정하고 지연 초기화 적용
  late final TtsService _ttsService = TtsService();
  // TextProcessingService는 실제 사용되는 곳이 없으므로 제거
  
  ProcessedText? processedText;
  bool _isLoadingText = false; // 로딩 상태 추적 변수 추가
  bool _isTtsPlaying = false; // TTS 재생 상태 추적 변수 추가
  Timer? _ttsStateCheckTimer; // TTS 상태 확인 타이머
  
  @override
  void initState() {
    super.initState();
    // 초기화 중에는 Future 시작만 하고 즉시 리턴 (non-blocking)
    _fetchProcessedTextSafely();
    
    // TTS 상태 변경 리스너 설정
    _setupTtsListener();
    
    // 현재 TTS 상태 확인
    _checkTtsState();
    
    // 주기적으로 TTS 상태 확인 (백업 메커니즘)
    _ttsStateCheckTimer = Timer.periodic(
      const Duration(milliseconds: 500), 
      (_) => _checkTtsState()
    );
  }
  
  @override
  void didUpdateWidget(NoteDetailBottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 페이지 ID가 변경된 경우에만 새로운 텍스트 가져오기
    if (oldWidget.currentPage?.id != widget.currentPage?.id) {
      _fetchProcessedTextSafely();
    }
  }
  
  // 안전하게 ProcessedText를 가져오는 메서드
  void _fetchProcessedTextSafely() {
    if (widget.currentPage?.id == null) {
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
    if (widget.currentPage?.id == null) {
      processedText = null;
      return;
    }
    
    try {
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
                             processedText!.segments != null && 
                             processedText!.segments!.isNotEmpty; 
    
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
              // 프로그레스 바 - 더 얇게 수정
              LinearProgressIndicator(
                value: progress,
                backgroundColor: ColorTokens.primarylight,
                valueColor: const AlwaysStoppedAnimation<Color>(ColorTokens.primary),
                minHeight: 2, // 3에서 2로 줄임
              ),
              
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
                      // 이전 페이지 버튼
                      SizedBox(
                        width: 32,
                        child: _buildNavigationButton(
                          icon: Icons.arrow_back_ios_rounded,
                          onTap: (widget.currentPageIndex > 0 && prevPageProcessed) 
                              ? () => widget.onPageChanged(widget.currentPageIndex - 1) 
                              : widget.currentPageIndex > 0 
                                  ? () => _showPageProcessingMessage(context, widget.currentPageIndex - 1)
                                  : null,
                          isDisabled: widget.currentPageIndex > 0 && !prevPageProcessed,
                        ),
                      ),
                      
                      // 중앙 -  TTS 버튼을 한 프레임에 넣기
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // TTS 버튼
                          if (widget.currentPage != null && !widget.isMinimalUI)
                          GestureDetector(
                              onTap: () {
                                // 현재 상태 토글 및 UI 즉시 업데이트
                                setState(() {
                                  _isTtsPlaying = !_isTtsPlaying;
                                });
                                
                                if (_isTtsPlaying) {
                                  // 재생 시작
                                  if (widget.onTtsPlay != null) {
                                    if (kDebugMode) {
                                      print("본문 전체 듣기 시작");
                                    }
                                    widget.onTtsPlay!();
                                  }
                                } else {
                                  // 재생 중지
                                  if (kDebugMode) {
                                    print("본문 전체 듣기 중지");
                                  }
                                  _ttsService.stop();
                                }
                              },
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // 상태에 따라 아이콘 직접 변경 (더 명확한 시각적 피드백)
                                  Container(
                                    width: 24,
                                    height: 24,
                              decoration: BoxDecoration(
                                      color: _isTtsPlaying 
                                          ? ColorTokens.secondaryLight 
                                          : Colors.transparent,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _isTtsPlaying ? Icons.stop : Icons.volume_up,
                                      color: ColorTokens.secondary,
                                      size: 14,
                                    ),
                              ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '본문 전체 듣기',
                                style: TypographyTokens.caption.copyWith(
                                  color: ColorTokens.secondary,
                                  fontSize: 12,
                                ),
                              ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      
                      // 오른쪽 영역 (페이지 번호 + 다음 페이지 버튼)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 페이지 번호 표시
                          Text(
                            '${widget.currentPageIndex + 1}/${widget.totalPages}',
                            style: TypographyTokens.caption.copyWith(
                              color: ColorTokens.textSecondary,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(width: 4),
                          
                          // 다음 페이지 버튼
                          _buildNavigationButton(
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
  Widget _buildNavigationButton({
    required IconData icon, 
    VoidCallback? onTap,
    bool isDisabled = false,
  }) {
    // 상태에 따른 색상 설정
    final Color bgColor = isDisabled 
      ? ColorTokens.greyLight  // 비활성화 상태 배경색
      : (onTap != null ? ColorTokens.surface : Colors.transparent);
      
    final Color iconColor = isDisabled 
      ? ColorTokens.greyMedium  // 비활성화 상태 아이콘 색상
      : (onTap != null ? ColorTokens.secondary : ColorTokens.greyMedium);
    
    return GestureDetector(
      onTap: isDisabled ? () {} : onTap,  // 비활성화 상태에서는 onTap을 실행하지 않음
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bgColor,
        ),
        child: Center(
          child: Icon(
            icon, 
            color: iconColor,
            size: SpacingTokens.iconSizeMedium,
          ),
        ),
      ),
    );
  }
  
  // TTS 상태 변경 리스너 설정
  void _setupTtsListener() {
    // 재생 상태 변경 리스너
    _ttsService.setOnPlayingStateChanged((segmentIndex) {
      if (mounted) {
        // 상태가 변경될 때마다 UI 업데이트 및 디버그 로그 출력
        if (kDebugMode) {
          print("TTS 상태 변경: currentSegmentIndex=$segmentIndex, state=${_ttsService.state}");
        }
        setState(() {
          _isTtsPlaying = _ttsService.state == TtsState.playing;
        });
      }
    });
    
    // 재생 완료 리스너
    _ttsService.setOnPlayingCompleted(() {
      if (mounted) {
        // 재생이 완료되면 UI 업데이트 및 디버그 로그 출력
        if (kDebugMode) {
          print("TTS 재생 완료 콜백: state=${_ttsService.state}");
        }
        setState(() {
          _isTtsPlaying = false;
        });
      }
    });
  }

  // TTS 상태 확인 및 UI 업데이트
  void _checkTtsState() {
    final isPlaying = _ttsService.state == TtsState.playing;
    if (_isTtsPlaying != isPlaying) {
      if (kDebugMode) {
        print("타이머에 의한 TTS 상태 업데이트: $_isTtsPlaying -> $isPlaying");
      }
      setState(() {
        _isTtsPlaying = isPlaying;
      });
      }
    }

  @override
  void dispose() {
    // 위젯이 제거될 때 리스너 정리
    _ttsService.setOnPlayingStateChanged((_) {});
    _ttsService.setOnPlayingCompleted(() {});
    
    // 타이머 취소
    _ttsStateCheckTimer?.cancel();
    
    super.dispose();
  }
} 