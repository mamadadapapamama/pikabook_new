import 'package:flutter/material.dart';
import 'dart:io';
import '../../models/page.dart' as page_model;
import '../../models/flash_card.dart';
import '../../widgets/page_content_widget.dart';
import '../../theme/tokens/spacing_tokens.dart';
import '../../widgets/dot_loading_indicator.dart';
import '../../models/processed_text.dart';
import '../../widgets/processed_text_widget.dart';
import '../../theme/tokens/color_tokens.dart';

class CurrentPageContent extends StatelessWidget {
  final page_model.Page? currentPage;
  final File? currentImageFile;
  final List<FlashCard>? flashCards;
  final bool useSegmentMode;
  final String noteId;
  final Function(String, String, {String? pinyin}) onCreateFlashCard;
  final Function(int) onDeleteSegment;
  final bool isProcessingText;
  final bool wasVisitedBefore;
  final ProcessedText? processedText;
  final bool isLoading;
  final bool isProcessing;
  final int currentIndex;
  final VoidCallback onToggleDisplayMode;
  final VoidCallback onTogglePinyin;
  final VoidCallback onToggleTranslation;
  final VoidCallback onAddFlashcard;
  final VoidCallback onDelete;
  final VoidCallback onReadText;
  
  const CurrentPageContent({
    Key? key,
    required this.currentPage,
    required this.currentImageFile,
    required this.flashCards,
    required this.useSegmentMode,
    required this.noteId,
    required this.onCreateFlashCard,
    required this.onDeleteSegment,
    required this.isProcessingText,
    this.wasVisitedBefore = false,
    required this.processedText,
    required this.isLoading,
    required this.isProcessing,
    required this.currentIndex,
    required this.onToggleDisplayMode,
    required this.onTogglePinyin,
    required this.onToggleTranslation,
    required this.onAddFlashcard,
    required this.onDelete,
    required this.onReadText,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return _buildLoadingState();
    }

    if (currentPage == null) {
      return _buildEmptyContent('페이지를 찾을 수 없습니다');
    }

    // 아직 처리되지 않은 경우 (백그라운드 처리 중인 경우)
    if (currentPage!.originalText == '___PROCESSING___' || isProcessing) {
      return _buildLoadingState();
    }

    // 방문하지 않은 페이지인 경우
    if (!wasVisitedBefore) {
      return _buildLoadingState();
    }

    // 텍스트가 비어있는 경우
    if ((currentPage!.originalText.isEmpty || currentPage!.originalText == '') 
        && processedText == null) {
      return _buildEmptyContent('페이지에 텍스트가 없습니다');
    }

    // 텍스트가 처리된 경우 해당 내용 표시
    if (processedText != null) {
      return _buildProcessedTextContent();
    }

    // 기본적으로 원본 텍스트 표시
    return _buildOriginalTextContent();
  }

  // 통합된 로딩 상태 표시
  Widget _buildLoadingState() {
    return Center(
      child: DotLoadingIndicator(
        message: '페이지를 준비하고 있어요...',
        dotColor: ColorTokens.primary,
      ),
    );
  }

  Widget _buildEmptyContent(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.text_snippet_outlined,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessedTextContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 텍스트 제어 버튼
          _buildTextControls(),
          
          // 처리된 텍스트 표시
          const SizedBox(height: 16),
          ProcessedTextWidget(
            processedText: processedText!,
          ),
        ],
      ),
    );
  }

  Widget _buildOriginalTextContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Text(
        currentPage!.originalText,
        style: const TextStyle(
          fontSize: 16,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildTextControls() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            // 표시 모드 전환 버튼
            _buildControlButton(
              icon: processedText?.showFullText ?? false 
                ? Icons.segment : Icons.text_fields,
              label: processedText?.showFullText ?? false 
                ? '문장별' : '전체글',
              onTap: onToggleDisplayMode,
            ),
            
            // 병음 표시 전환 버튼
            _buildControlButton(
              icon: Icons.language,
              label: '병음',
              active: processedText?.showPinyin ?? false,
              onTap: onTogglePinyin,
            ),
            
            // 번역 표시 전환 버튼
            _buildControlButton(
              icon: Icons.translate,
              label: '번역',
              active: processedText?.showTranslation ?? false,
              onTap: onToggleTranslation,
            ),
            
            // 플래시 카드 추가 버튼
            _buildControlButton(
              icon: Icons.flash_on,
              label: '단어장',
              onTap: onAddFlashcard,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    bool active = true,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: active ? ColorTokens.primary : Colors.grey,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: active ? ColorTokens.primary : Colors.grey,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
