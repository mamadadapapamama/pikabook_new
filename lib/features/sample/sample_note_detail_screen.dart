import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../core/models/note.dart';
import '../../core/models/page.dart' as pika_page;
import '../../core/models/processed_text.dart';
import '../../core/models/text_segment.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/widgets/pika_app_bar.dart';
import '../../core/widgets/dot_loading_indicator.dart';
import '../../features/note_detail/page_content_widget.dart';
import 'sample_notes_service.dart';

/// 샘플 노트 상세 화면 - 임시 처리를 위한 화면
class SampleNoteDetailScreen extends StatefulWidget {
  final Note note;
  final SampleNotesService sampleNotesService;

  const SampleNoteDetailScreen({
    Key? key,
    required this.note,
    required this.sampleNotesService,
  }) : super(key: key);

  @override
  State<SampleNoteDetailScreen> createState() => _SampleNoteDetailScreenState();
}

class _SampleNoteDetailScreenState extends State<SampleNoteDetailScreen> {
  late PageController _pageController;
  int _currentPageIndex = 0;
  bool _showFullText = false;
  bool _showPinyin = true;
  bool _showTranslation = true;
  ProcessedText? _processedText;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadProcessedText();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadProcessedText() async {
    setState(() {
      _isLoading = true;
    });

    if (widget.note.pages.isNotEmpty) {
      final pageId = widget.note.pages[0].id;
      if (pageId != null) {
        final processedText = widget.sampleNotesService.getProcessedTextForPage(pageId);
        
        setState(() {
          _processedText = processedText;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPage = widget.note.pages.isNotEmpty ? widget.note.pages[_currentPageIndex] : null;
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PikaAppBar.noteDetail(
        title: widget.note.originalText,
        currentPage: _currentPageIndex + 1,
        totalPages: widget.note.pages.length,
        flashcardCount: widget.note.flashcardCount,
        onMorePressed: () => _showMoreOptions(context),
        onFlashcardTap: () => _showLoginRequiredDialog(context),
        onBackPressed: () => Navigator.of(context).pop(),
        backgroundColor: Colors.white,
      ),
      body: _buildBody(context, currentPage),
      bottomNavigationBar: _buildBottomBar(context),
    );
  }

  Widget _buildBody(BuildContext context, pika_page.Page? currentPage) {
    if (_isLoading) {
      return const Center(child: DotLoadingIndicator(message: '페이지 로딩 중...'));
    }

    if (currentPage == null) {
      return Center(
        child: Text(
          '표시할 페이지가 없습니다.',
          style: TypographyTokens.body1,
        ),
      );
    }

    if (_processedText == null) {
      return Center(
        child: Text(
          '콘텐츠를 로드할 수 없습니다.',
          style: TypographyTokens.body1,
        ),
      );
    }

    // 실제로는 ProcessedText를 사용하지 않고 그냥 표시만 함
    // PageContentWidget은 자체적으로 처리할 것임
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 페이지 내용을 수동으로 표시
            Text(
              '샘플 노트 내용',
              style: TypographyTokens.headline3,
            ),
            const SizedBox(height: 16),
            
            // 원본 텍스트
            Text(
              '원문:',
              style: TypographyTokens.subtitle1.copyWith(
                color: ColorTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                currentPage.originalText,
                style: TypographyTokens.body1,
              ),
            ),
            
            const SizedBox(height: 24),
            
            // 번역 텍스트
            Text(
              '번역:',
              style: TypographyTokens.subtitle1.copyWith(
                color: ColorTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                currentPage.translatedText ?? '',
                style: TypographyTokens.body1,
              ),
            ),
            
            const SizedBox(height: 32),
            
            // 학습 팁
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: ColorTokens.primaryverylight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb, color: ColorTokens.primary),
                      const SizedBox(width: 8),
                      Text(
                        '학습 팁',
                        style: TypographyTokens.subtitle1.copyWith(
                          color: ColorTokens.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '로그인하시면 세그먼트 단위로 문장 학습, 발음 듣기, 단어장 추가 등 더 많은 기능을 이용하실 수 있습니다.',
                    style: TypographyTokens.body2,
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop(); // 노트 상세 화면 닫기
                        // 추가 로그인 처리는 App 위젯에서 수행
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ColorTokens.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('로그인하여 전체 기능 이용하기'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return BottomAppBar(
      color: Colors.white,
      elevation: 8,
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildBottomButton(
              icon: Icons.format_align_left,
              label: _showFullText ? '문장 모드' : '전체 텍스트',
              isActive: true,
              onPressed: () {
                setState(() {
                  _showFullText = !_showFullText;
                });
              },
            ),
            _buildBottomButton(
              icon: Icons.record_voice_over,
              label: '음성',
              isActive: true,
              onPressed: () => _showLoginRequiredDialog(context),
            ),
            _buildBottomButton(
              icon: Icons.g_translate,
              label: '번역',
              isActive: _showTranslation,
              onPressed: () {
                setState(() {
                  _showTranslation = !_showTranslation;
                });
              },
            ),
            if (widget.note.sourceLanguage == 'zh-CN')
              _buildBottomButton(
                icon: Icons.music_note,
                label: '병음',
                isActive: _showPinyin,
                onPressed: () {
                  setState(() {
                    _showPinyin = !_showPinyin;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? ColorTokens.primary : ColorTokens.textGrey,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TypographyTokens.caption.copyWith(
                color: isActive ? ColorTokens.primary : ColorTokens.textGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('공유하기'),
              onTap: () {
                Navigator.pop(context);
                _showLoginRequiredDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: const Text('즐겨찾기에 추가'),
              onTap: () {
                Navigator.pop(context);
                _showLoginRequiredDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('노트 편집하기'),
              onTap: () {
                Navigator.pop(context);
                _showLoginRequiredDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

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
                
                // 로그인 화면으로 이동 로직이 필요하다면 추가
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