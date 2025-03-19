import 'package:flutter/material.dart';
import 'dart:io';
import '../models/page.dart' as page_model;
import '../services/page_content_service.dart';
import '../services/text_reader_service.dart';
import '../utils/text_display_mode.dart';
import '../views/screens/full_image_screen.dart';
import 'page_indicator_widget.dart';
import 'text_display_toggle_widget.dart';

/// 노트 상세 화면 하단 내비게이션 바
/// 텍스트 표시 모드 토글, 이미지 썸네일, 전체 읽기 버튼 등 제공

class NoteDetailBottomBar extends StatelessWidget {
  final page_model.Page? currentPage;
  final File? imageFile;
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
    required this.imageFile,
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
    
    // 세그먼트 존재 여부 확인 (세그먼트 모드에서만 토글 버튼 표시)
    final bool hasSegments = processedText.segments != null && 
                             processedText.segments!.isNotEmpty; 
    
    // 디버그 정보 출력
    debugPrint('NoteDetailBottomBar - 현재 모드: $textDisplayMode, 병음 표시: ${processedText.showPinyin}');
    debugPrint('세그먼트 정보: ${processedText.segments?.length ?? 0}개, hasSegments: $hasSegments');
      
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 페이지 인디케이터 위젯
        if (totalPages > 1)
          PageIndicatorWidget(
            currentPageIndex: currentPageIndex,
            totalPages: totalPages,
            onPageChanged: onPageChanged,
          ),
            
        // 바텀 바 컨테이너  
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 4,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 텍스트 표시 모드 토글 위젯 (세그먼트 모드일 때만 표시)
              if (hasSegments)
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: KeyedSubtree(
                    key: ValueKey('toggle_${textDisplayMode.toString()}'),
                    child: TextDisplayToggleWidget(
                      currentMode: textDisplayMode,
                      onModeChanged: (newMode) {
                        debugPrint('토글 버튼 클릭: $textDisplayMode -> $newMode');
                        onTextDisplayModeChanged(newMode);
                      },
                      originalText: currentPage!.originalText,
                    ),
                  ),
                )
              else
                const SizedBox(width: 40), // 균형을 위한 공간
                
              // 우측 컨트롤 영역
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 이미지 썸네일
                  if (imageFile != null || currentPage!.imageUrl != null)
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => FullImageScreen(
                              imageFile: imageFile,
                              imageUrl: currentPage!.imageUrl,
                              title: '이미지',
                            ),
                          ),
                        );
                      },
                      child: Container(
                        width: 30,
                        height: 30,
                        margin: const EdgeInsets.symmetric(horizontal: 8.0),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0x45808080)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.image, color: Colors.grey, size: 18),
                      ),
                    ),
                    
                  // 전체 읽기/멈춤 아이콘 버튼
                  IconButton(
                    icon: Icon(
                      isPlaying ? Icons.stop : Icons.play_arrow,
                      color: Colors.blue,
                    ),
                    tooltip: isPlaying ? '읽기 중지' : '전체 읽기',
                    onPressed: onPlayPausePressed,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  // 최소한의 UI를 가진 바텀 바 (ProcessedText가 없는 경우)
  Widget _buildMinimalBottomBar(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 페이지 인디케이터 위젯
        if (totalPages > 1)
          PageIndicatorWidget(
            currentPageIndex: currentPageIndex,
            totalPages: totalPages,
            onPageChanged: onPageChanged,
          ),
            
        // 간소화된 바텀 바 컨테이너  
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 4,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 이미지 썸네일
              if (imageFile != null || currentPage!.imageUrl != null)
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FullImageScreen(
                          imageFile: imageFile,
                          imageUrl: currentPage!.imageUrl,
                          title: '이미지',
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: 30,
                    height: 30,
                    margin: const EdgeInsets.symmetric(horizontal: 8.0),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0x45808080)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.image, color: Colors.grey, size: 18),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
} 