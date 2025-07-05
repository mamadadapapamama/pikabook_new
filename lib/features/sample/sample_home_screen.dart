import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../core/models/note.dart';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import '../../core/theme/tokens/spacing_tokens.dart';
import '../home/note_list_item.dart';
import 'sample_data_service.dart';
import '../note/view/note_detail_screen.dart';
import '../../core/widgets/pika_button.dart';
import '../../core/widgets/dot_loading_indicator.dart';

/// 샘플 모드 홈 화면
/// 홈 화면과 동일한 디자인이지만 샘플 데이터를 사용합니다.
class SampleHomeScreen extends StatefulWidget {
  final VoidCallback onRequestLogin;

  const SampleHomeScreen({
    Key? key,
    required this.onRequestLogin,
  }) : super(key: key);

  @override
  State<SampleHomeScreen> createState() => _SampleHomeScreenState();
}

class _SampleHomeScreenState extends State<SampleHomeScreen> {
  final SampleDataService _sampleDataService = SampleDataService();
  List<Note> _sampleNotes = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSampleData();
  }

  Future<void> _loadSampleData() async {
    try {
      if (kDebugMode) {
        debugPrint('🏠 [SampleHome] 샘플 데이터 로드 시작');
      }
      
      await _sampleDataService.loadSampleData();
      _sampleNotes = _sampleDataService.getSampleNotes();
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      
      if (kDebugMode) {
        debugPrint('🏠 [SampleHome] 샘플 노트 로드됨: ${_sampleNotes.length}개');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SampleHome] 샘플 데이터 로드 실패: $e');
      }
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9F1), // 홈 화면과 동일한 배경색
      appBar: _buildAppBar(),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFFFFF9F1),
      elevation: 0,
      automaticallyImplyLeading: false, // 백버튼 제거
      title: Row(
        children: [
          // Pikabook SVG 로고
          SvgPicture.asset(
            'assets/images/pikabook_textlogo_primary.svg',
            height: 24,
          ),
        ],
      ),
      actions: [
        // 로그인 버튼
        TextButton(
          onPressed: widget.onRequestLogin,
          child: Text(
            '나가기',
            style: TypographyTokens.body2.copyWith(
              color: ColorTokens.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(width: SpacingTokens.sm),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: DotLoadingIndicator(message: '샘플 데이터 로드 중...'),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: ColorTokens.error,
            ),
            SizedBox(height: SpacingTokens.lg),
            Text(
              '샘플 데이터를 불러올 수 없습니다',
              style: TypographyTokens.body1.copyWith(
                color: ColorTokens.textPrimary,
              ),
            ),
            SizedBox(height: SpacingTokens.sm),
            if (kDebugMode) ...[
              Padding(
                padding: EdgeInsets.symmetric(horizontal: SpacingTokens.lg),
                child: Text(
                  '에러: $_error',
                  style: TypographyTokens.caption.copyWith(
                    color: ColorTokens.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            SizedBox(height: SpacingTokens.md),
            ],
            PikaButton(
              text: '다시 시도',
              variant: PikaButtonVariant.text,
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
                _loadSampleData();
              },
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          // 헤드라인과 서브라인
          _buildHeader(),
          
          // 노트 목록
          Expanded(
            child: _buildNotesList(),
          ),
          
          // CTA 버튼
          _buildCTAButton(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(SpacingTokens.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤드라인
          Text(
            'Pikabook으로 만든 노트를\n미리 살펴보세요!',
            style: TypographyTokens.headline3.copyWith(
              color: ColorTokens.textPrimary,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),
          SizedBox(height: SpacingTokens.md),
          
          // 서브라인
          Text(
            '교재사진을 올리면, 아래와 같은 노트가 자동으로 만들어져요.',
            style: TypographyTokens.body1.copyWith(
              color: ColorTokens.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesList() {
    if (_sampleNotes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.note_alt_outlined,
              size: 64,
              color: ColorTokens.textGrey,
            ),
            SizedBox(height: SpacingTokens.lg),
            Text(
              '샘플 노트가 없습니다',
              style: TypographyTokens.body1.copyWith(
                color: ColorTokens.textGrey,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: SpacingTokens.lg),
      itemCount: _sampleNotes.length,
      itemBuilder: (context, index) {
        final note = _sampleNotes[index];
        return Padding(
          padding: EdgeInsets.only(
            bottom: index == _sampleNotes.length - 1 ? 8 : 12,
          ),
          child: NoteListItem(
            key: ValueKey('sample_note_${note.id}'),
            note: note,
            onDismissed: () {
              // 샘플 노트는 삭제 불가 - 스낵바로 안내
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('체험 모드에서는 노트를 삭제할 수 없습니다'),
                  backgroundColor: ColorTokens.secondary,
                ),
              );
            },
            onNoteTapped: (note) => _navigateToSampleNoteDetail(note),
          ),
        );
      },
    );
  }

  Widget _buildCTAButton() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(SpacingTokens.lg),
      child: PikaButton(
        text: '로그인하고 시작하기',
        variant: PikaButtonVariant.primary,
        isFullWidth: true,
        onPressed: widget.onRequestLogin,
      ),
    );
  }

  void _navigateToSampleNoteDetail(Note note) {
    if (kDebugMode) {
      debugPrint('🏠 [SampleHome] 샘플 노트 클릭: ${note.title}');
    }
    
    // 기존 NoteDetailScreenMVVM 사용
    Navigator.push(
      context,
      NoteDetailScreenMVVM.route(
        note: note,
        isProcessingBackground: false,
      ),
    );
  }
} 