import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import '../../core/theme/tokens/spacing_tokens.dart';
import '../../core/widgets/pika_app_bar.dart';
import '../../core/widgets/pika_button.dart';
import '../../core/models/note.dart';
import '../../widgets/note_list_item.dart';
import '../../views/screens/login_screen.dart';
import 'sample_notes_service.dart';
import '../../features/auth/sample_mode_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SampleHomeScreen extends StatelessWidget {
  // 콜백 함수 추가
  final VoidCallback? onLogin;
  
  // 생성자 수정
  SampleHomeScreen({Key? key, this.onLogin}) : super(key: key);

  // 샘플 노트 서비스
  final SampleNotesService _sampleNotesService = SampleNotesService();
  final SampleModeService _sampleModeService = SampleModeService();

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
  void _navigateToLogin(BuildContext context) async {
    try {
      if (kDebugMode) {
        debugPrint('[SampleHomeScreen] 샘플 화면에서 로그인 화면으로 이동 시도');
      }
      
      // 현재 사용자가 있다면 로그아웃 (안전 장치)
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        if (kDebugMode) {
          debugPrint('[SampleHomeScreen] 기존 사용자 감지, 로그아웃 수행');
        }
        await FirebaseAuth.instance.signOut();
      }
      
      // 샘플 모드 비활성화
      if (kDebugMode) {
        debugPrint('[SampleHomeScreen] 샘플 모드 비활성화 시도');
      }
      await _sampleModeService.disableSampleMode();
      if (kDebugMode) {
        debugPrint('[SampleHomeScreen] 샘플 모드 비활성화 완료');
      }
      
      // SampleHomeScreen을 pop하여 App 위젯이 LoginScreen을 그리도록 함
      if (context.mounted) {
        if (kDebugMode) {
          debugPrint('[SampleHomeScreen] SampleHomeScreen pop');
        }
        Navigator.of(context).pop(); 
      }
      
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[SampleHomeScreen] 로그인 화면으로 이동 중 오류: $e');
        debugPrint('[SampleHomeScreen] 스택 트레이스: $stackTrace');
      }
      
      // 오류 발생 시 사용자에게 알림
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('로그인 화면으로 이동 중 문제가 발생했습니다. 다시 시도해주세요.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      
      // 오류 복구 시도: 강제로 샘플 모드 비활성화 후 pop
      try {
        await _sampleModeService.disableSampleMode();
        if (context.mounted) {
           Navigator.of(context).pop();
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[SampleHomeScreen] 복구 시도 중에도 오류 발생: $e');
        }
      }
    }
  }

  // 앱바에 로그인 버튼 추가
  Widget _buildLoginButton(BuildContext context) {
    return TextButton(
      onPressed: () => _navigateToLogin(context),
      style: TextButton.styleFrom(
        foregroundColor: ColorTokens.textLight,
        padding: EdgeInsets.symmetric(horizontal: SpacingTokens.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.login, size: 18),
          SizedBox(width: 4),
          Text('로그인', style: TypographyTokens.button),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sampleNotes = _sampleNotesService.getSampleNotes();

    return Scaffold(
      backgroundColor: const Color(0xFFFFF9F1), // Figma 디자인의 #FFF9F1 배경색
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          '샘플 모드',
          style: TypographyTokens.headline3.copyWith(
            color: ColorTokens.textPrimary,
          ),
        ),
        actions: [
          _buildLoginButton(context),
        ],
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PikaButton(
                      text: '스마트 노트 만들기',
                      onPressed: () => _showLoginRequiredDialog(context),
                      width: 220,
                      variant: PikaButtonVariant.primary,
                    ),
                    SizedBox(height: 12),
                    TextButton(
                      onPressed: () => _navigateToLogin(context),
                      child: Text(
                        '로그인하여 시작하기',
                        style: TypographyTokens.button.copyWith(
                          color: ColorTokens.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 