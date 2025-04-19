import 'package:flutter/material.dart';
import 'dart:io';

import '../../../../models/note.dart';
import '../../../../widgets/page_content_widget.dart';
import '../../../../widgets/dot_loading_indicator.dart';
import '../../../../theme/tokens/color_tokens.dart';
import '../managers/note_page_manager_wrapper.dart';
import '../managers/image_loading_manager.dart';

/// 노트 상세 화면의 본문 위젯
/// 
/// 페이지 이미지와 텍스트 콘텐츠를 표시합니다.

class NoteDetailBody extends StatelessWidget {
  final Note? note;
  final NotePageManagerWrapper pageManagerWrapper;
  final bool useSegmentMode;
  final ImageLoadingManager imageLoadingManager;
  
  const NoteDetailBody({
    super.key,
    required this.note,
    required this.pageManagerWrapper,
    required this.useSegmentMode,
    required this.imageLoadingManager,
  });
  
  @override
  Widget build(BuildContext context) {
    final currentPage = pageManagerWrapper.getCurrentPage();
    
    if (currentPage == null) {
      return _buildEmptyState();
    }
    
    return PageView.builder(
      controller: pageManagerWrapper.getPageController(),
      itemCount: pageManagerWrapper.getTotalPageCount(),
      onPageChanged: (index) {
        pageManagerWrapper.changePage(index);
      },
      itemBuilder: (context, index) {
        if (index >= pageManagerWrapper.getPages().length) {
          return _buildLoadingPage();
        }
        
        final page = pageManagerWrapper.getPages()[index];
        return _buildPageContent(context, page);
      },
    );
  }
  
  // 페이지 콘텐츠 빌드
  Widget _buildPageContent(BuildContext context, dynamic page) {
    final imageFile = imageLoadingManager.currentImageFile;
    final isLoading = imageLoadingManager.isLoading;
    
    if (isLoading) {
      return _buildLoadingPage();
    }
    
    return Column(
      children: [
        Expanded(
          child: _buildPageImage(imageFile),
        ),
        Container(
          decoration: BoxDecoration(
            color: ColorTokens.surface,
            boxShadow: [
              BoxShadow(
                color: ColorTokens.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: PageContentWidget(
            page: page,
            showFullText: !useSegmentMode,
            onTextTapped: (text, translation) {
              // 텍스트 탭 이벤트 처리
            },
          ),
        ),
      ],
    );
  }
  
  // 페이지 이미지 빌드
  Widget _buildPageImage(File? imageFile) {
    if (imageFile == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_not_supported,
              size: 48,
              color: ColorTokens.black.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '이미지를 불러올 수 없습니다',
              style: TextStyle(
                color: ColorTokens.black.withOpacity(0.5),
              ),
            ),
          ],
        ),
      );
    }
    
    return GestureDetector(
      onTap: () {
        // 이미지 전체화면 보기
      },
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 3.0,
        child: Image.file(
          imageFile,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
  
  // 로딩 페이지 빌드
  Widget _buildLoadingPage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const DotLoadingIndicator(),
          const SizedBox(height: 16),
          Text(
            '페이지를 로드하고 있습니다...',
            style: TextStyle(
              color: ColorTokens.black.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
  
  // 빈 상태 빌드
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.text_snippet_outlined,
            size: 48,
            color: ColorTokens.black.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            '페이지가 없습니다',
            style: TextStyle(
              color: ColorTokens.black.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
} 