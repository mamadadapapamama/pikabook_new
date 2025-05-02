import 'package:flutter/material.dart';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import '../../core/theme/tokens/spacing_tokens.dart';
import '../../core/widgets/pika_app_bar.dart';
import '../../core/widgets/pika_button.dart';
import '../../core/models/note.dart';
import '../../widgets/note_list_item.dart';
import '../../views/screens/login_screen.dart';
import 'sample_notes_service.dart';

class SampleHomeScreen extends StatelessWidget {
  SampleHomeScreen({Key? key}) : super(key: key);

  // 샘플 노트 서비스
  final SampleNotesService _sampleNotesService = SampleNotesService();

  // 로그인 필요 알림 다이얼로그 표시
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
                _navigateToLogin(context);
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

  // 로그인 화면으로 이동
  void _navigateToLogin(BuildContext context) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => LoginScreen(
          onLoginSuccess: (user) {
            // 로그인 성공 후 처리할 로직
          },
          isInitializing: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sampleNotes = _sampleNotesService.getSampleNotes();

    return Scaffold(
      backgroundColor: const Color(0xFFFFF9F1), // Figma 디자인의 #FFF9F1 배경색
      appBar: PikaAppBar.home(
        noteSpaceName: '샘플 모드',
        onSettingsPressed: () => _showLoginRequiredDialog(context),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // 노트 목록
            ListView.builder(
              padding: const EdgeInsets.only(top: 4, bottom: 80), // 하단 FAB 공간 확보
              itemCount: sampleNotes.length,
              itemBuilder: (context, index) {
                final note = sampleNotes[index];
                return Padding(
                  padding: const EdgeInsets.only(
                    left: 16, 
                    right: 16, 
                    bottom: 8
                  ),
                  child: NoteListItem(
                    note: note,
                    onDismissed: () {},
                    onNoteTapped: (_) => _showLoginRequiredDialog(context),
                    onFavoriteToggled: (_, __) {},
                    isFilteredList: false,
                  ),
                );
              },
            ),
            
            // 하단 스마트 노트 만들기 버튼
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: PikaButton(
                  text: '스마트 노트 만들기',
                  onPressed: () => _showLoginRequiredDialog(context),
                  width: 220,
                  variant: PikaButtonVariant.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 