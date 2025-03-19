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
    
    final processedText = pageContentService.getProcessedText(currentPage!.id ?? '');
    final bool hasSegments = processedText != null && 
                              processedText.segments != null && 
                              processedText.segments!.isNotEmpty;
    
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
          height: 50, // 명시적인 높이 설정
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 6.0),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(26), // 0.1 transparency
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 텍스트 표시 모드 토글 위젯 (좌측)
              if (hasSegments)
                Expanded(
                  child: TextDisplayToggleWidget(
                    currentMode: textDisplayMode,
                    onModeChanged: (mode) {
                      // 모드 변경 처리
                      onTextDisplayModeChanged(mode);
                      
                      // ProcessedText 업데이트 로직은 콜백에서 처리
                    },
                    originalText: currentPage!.originalText,
                  ),
                )
              else
                const Spacer(),
              
              // 우측 컨트롤 영역
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 이미지 썸네일
                  if (imageFile != null || currentPage!.imageUrl != null)
                    GestureDetector(
                      onTap: () {
                        // FullImageScreen으로 이동
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => FullImageScreen(
                              imageFile: imageFile,
                              imageUrl: currentPage!.imageUrl,
                              title: '페이지 이미지',
                            ),
                          ),
                        );
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        margin: const EdgeInsets.symmetric(horizontal: 6.0),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.withAlpha(77)), // 0.3 transparency
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: imageFile != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.file(
                                imageFile!,
                                fit: BoxFit.cover,
                              ),
                            )
                          : const Icon(Icons.image, color: Colors.grey, size: 18),
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
                      minWidth: 40,
                      minHeight: 40,
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
} 