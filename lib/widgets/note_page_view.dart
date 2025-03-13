import 'package:flutter/material.dart';
import 'dart:io';
import '../models/page.dart' as page_model;
import '../models/text_processing_mode.dart';
import '../models/flash_card.dart';
import 'page_content_widget.dart';
import 'page_indicator_widget.dart';

class NotePageView extends StatelessWidget {
  final List<page_model.Page> pages;
  final List<File?> imageFiles;
  final int currentPageIndex;
  final Function(int) onPageChanged;
  final String noteId;
  final Function(String, String, {String? pinyin}) onCreateFlashCard;
  final TextProcessingMode textProcessingMode;
  final List<FlashCard>? flashCards;

  const NotePageView({
    Key? key,
    required this.pages,
    required this.imageFiles,
    required this.currentPageIndex,
    required this.onPageChanged,
    required this.noteId,
    required this.onCreateFlashCard,
    required this.textProcessingMode,
    this.flashCards,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.note_alt_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('페이지가 없습니다.', style: TextStyle(fontSize: 18)),
            SizedBox(height: 8),
            Text('이 노트에는 페이지가 없습니다.', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 페이지 인디케이터 (여러 페이지가 있는 경우)
        if (pages.length > 1)
          PageIndicatorWidget(
            currentPageIndex: currentPageIndex,
            totalPages: pages.length,
            onPageChanged: onPageChanged,
          ),

        // 현재 페이지 내용
        Expanded(
          child: GestureDetector(
            // 좌우 스와이프로 페이지 전환
            onHorizontalDragEnd: (details) {
              if (details.primaryVelocity == null) return;

              // 오른쪽에서 왼쪽으로 스와이프 (다음 페이지)
              if (details.primaryVelocity! < 0 &&
                  currentPageIndex < pages.length - 1) {
                onPageChanged(currentPageIndex + 1);
              }
              // 왼쪽에서 오른쪽으로 스와이프 (이전 페이지)
              else if (details.primaryVelocity! > 0 && currentPageIndex > 0) {
                onPageChanged(currentPageIndex - 1);
              }
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
              child: _buildCurrentPageContent(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentPageContent() {
    if (currentPageIndex >= pages.length) {
      return const Center(child: Text('페이지를 찾을 수 없습니다.'));
    }

    final currentPage = pages[currentPageIndex];
    final imageFile = imageFiles[currentPageIndex];
    final bool isLoadingImage =
        imageFile == null && currentPage.imageUrl != null;

    // 이미지가 로딩 중이면 로딩 인디케이터 표시
    if (isLoadingImage) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('페이지 로딩 중...', style: TextStyle(fontSize: 16)),
          ],
        ),
      );
    }

    return PageContentWidget(
      key: ValueKey('page_content_${currentPage.id}_$currentPageIndex'),
      page: currentPage,
      imageFile: imageFile,
      isLoadingImage: false,
      noteId: noteId,
      onCreateFlashCard: onCreateFlashCard,
      textProcessingMode: textProcessingMode,
      flashCards: flashCards,
    );
  }
}
