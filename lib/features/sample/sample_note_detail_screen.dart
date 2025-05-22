import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../core/models/note.dart';
import '../../core/models/flash_card.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/widgets/pika_app_bar.dart';
import 'sample_notes_service.dart';
import 'sample_flashcard_screen.dart';

/// 샘플 노트 상세 화면 - 간소화된 버전
class SampleNoteDetailScreen extends StatelessWidget {
  final Note note;
  final SampleNotesService sampleNotesService;

  const SampleNoteDetailScreen({
    Key? key,
    required this.note,
    required this.sampleNotesService,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(context),
      body: _buildBody(context),
    );
  }
  
  // 앱바 구성
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final bool isAnimalNote = note.id == 'sample-animal-book';
    final List<FlashCard> flashcards = sampleNotesService.getFlashcardsForNote(note.id ?? '');
    
    return PikaAppBar(
      title: note.title,
      backgroundColor: Colors.white,
      actions: [
        // 플래시카드 버튼
        if (!isAnimalNote && flashcards.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.style_outlined),
            tooltip: '플래시카드 보기',
            onPressed: () => _navigateToFlashcards(context, flashcards),
          ),
      ],
      onBackPressed: () => Navigator.of(context).pop(),
    );
  }
  
  // 플래시카드 화면으로 이동
  void _navigateToFlashcards(BuildContext context, List<FlashCard> flashcards) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SampleFlashCardScreen(
          flashcards: flashcards,
          noteTitle: note.title,
        ),
      ),
    );
  }
  
  // 바디 구성
  Widget _buildBody(BuildContext context) {
    final String? imagePath = sampleNotesService.getImagePathForNote(note.id ?? '');
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 이미지 표시
          if (imagePath != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 24.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  imagePath,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            
          // 노트 제목
          Text(
            note.title,
            style: TypographyTokens.headline1.copyWith(
              color: ColorTokens.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          // 노트 설명
          Text(
            note.description ?? '',
            style: TypographyTokens.body1.copyWith(
              color: ColorTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          
          // 플래시카드 정보
          if (note.flashcardCount > 0)
            _buildFlashcardInfo(context),
            
          // 샘플 모드 안내
          const SizedBox(height: 36),
          _buildSampleModeInfo(context),
        ],
      ),
    );
  }
  
  // 플래시카드 정보 표시
  Widget _buildFlashcardInfo(BuildContext context) {
    final List<FlashCard> flashcards = sampleNotesService.getFlashcardsForNote(note.id ?? '');
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '플래시카드',
          style: TypographyTokens.subtitle1.copyWith(
            fontWeight: FontWeight.bold,
            color: ColorTokens.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              Text(
                '${flashcards.length}개의 플래시카드',
                style: TypographyTokens.body2.copyWith(
                  color: ColorTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _navigateToFlashcards(context, flashcards),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ColorTokens.primary,
                  side: BorderSide(color: ColorTokens.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('플래시카드 보기'),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  // 샘플 모드 안내 정보
  Widget _buildSampleModeInfo(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              Text(
                '샘플 모드 안내',
                style: TypographyTokens.subtitle2.copyWith(
                  color: Colors.blue.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '실제 앱에서는 교재 사진을 찍거나 업로드하면 자동으로 텍스트를 인식하고 번역하여 노트와 플래시카드를 생성합니다. 로그인하시면 더 많은 기능을 이용하실 수 있습니다.',
            style: TypographyTokens.body2.copyWith(
              color: ColorTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
  
  // 로그인 필요 다이얼로그 표시
  void _showLoginRequiredDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            '로그인이 필요한 서비스입니다',
            style: TypographyTokens.subtitle2,
          ),
          content: Text(
            '노트 저장과 맞춤 학습을 위해 로그인이 필요합니다.',
            style: TypographyTokens.body2,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // 다이얼로그 닫기
              },
              child: Text(
                '취소',
                style: TypographyTokens.button.copyWith(
                  color: ColorTokens.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // 다이얼로그 닫기
                Navigator.of(context).pop(); // 노트 상세 화면 닫기
              },
              child: Text(
                '로그인',
                style: TypographyTokens.button.copyWith(
                  color: ColorTokens.primary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
} 