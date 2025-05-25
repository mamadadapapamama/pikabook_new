import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import '../../core/theme/tokens/spacing_tokens.dart';
import '../../core/widgets/pika_app_bar.dart';
import '../../core/widgets/pika_button.dart';
import '../../core/models/note.dart';
import '../home/note_list_item.dart';
import 'sample_notes_service.dart';
import 'sample_mode_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'sample_note_detail_screen.dart';
import 'sample_flashcard_screen.dart';

class SampleHomeScreen extends StatelessWidget {
  // 콜백 함수 타입 정의 및 이름 변경 (onLogin -> onRequestLogin)
  final VoidCallback? onRequestLogin;
  
  // 생성자 수정
  SampleHomeScreen({Key? key, this.onRequestLogin}) : super(key: key);

  // 샘플 노트 서비스
  final SampleNotesService _sampleNotesService = SampleNotesService();
  final SampleModeService _sampleModeService = SampleModeService();

  // 로그인 필요 알림 다이얼로그 표시
  void _showLoginRequiredDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          backgroundColor: Colors.white,
          title: Text(
            '로그인이 필요한 서비스입니다',
            style: TypographyTokens.subtitle2.copyWith(
              fontWeight: FontWeight.bold,
              color: ColorTokens.textPrimary,
            ),
          ),
          content: Text(
            '노트 저장과 맞춤 학습을 위해 로그인이 필요합니다.',
            style: TypographyTokens.body2.copyWith(
              color: ColorTokens.textSecondary,
            ),
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
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // 다이얼로그 닫기
                _navigateToLogin(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: ColorTokens.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: Text(
                '로그인',
                style: TypographyTokens.button.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
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
          debugPrint('[SampleHomeScreen] 기존 로그인 사용자 감지, 로그아웃 수행');
        }
        await FirebaseAuth.instance.signOut();
      }
      
      // 샘플 모드 비활성화 (서비스 호출은 유지)
      if (kDebugMode) {
        debugPrint('[SampleHomeScreen] 샘플 모드 비활성화 시도 (Service)');
      }
      await _sampleModeService.disableSampleMode();
      if (kDebugMode) {
        debugPrint('[SampleHomeScreen] 샘플 모드 비활성화 완료 (Service)');
      }
      
      // App 위젯에 상태 변경 요청 (pop 대신 콜백 호출)
      if (onRequestLogin != null) {
        if (kDebugMode) {
          debugPrint('[SampleHomeScreen] App 위젯에 로그인 화면 전환 요청');
        }
        onRequestLogin!(); // App 위젯의 setState 호출
      } else {
        // 콜백이 없는 경우 (예상치 못한 상황)
        if (kDebugMode) {
          debugPrint('[SampleHomeScreen] 경고: onRequestLogin 콜백이 null입니다.');
        }
        // 안전하게 pop 시도 (만약 가능하다면)
        if (context.mounted && Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
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
            backgroundColor: ColorTokens.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            margin: EdgeInsets.all(12),
          ),
        );
      }
      
      // 오류 복구 시도: 강제로 샘플 모드 비활성화 후 콜백 호출 시도
      try {
        await _sampleModeService.disableSampleMode();
        if (onRequestLogin != null) {
          onRequestLogin!();
        } else if (context.mounted && Navigator.canPop(context)) {
           Navigator.of(context).pop();
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[SampleHomeScreen] 복구 시도 중에도 오류 발생: $e');
        }
      }
    }
  }

  // 앱바에 나가기 버튼 추가
  Widget _buildExitButton(BuildContext context) {
    return TextButton(
      onPressed: () => _navigateToLogin(context),
      style: TextButton.styleFrom(
        foregroundColor: ColorTokens.textPrimary,
        padding: EdgeInsets.symmetric(horizontal: SpacingTokens.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('나가기', style: TypographyTokens.button.copyWith(color: ColorTokens.primary)),
        ],
      ),
    );
  }
  
  // 노트 상세 화면으로 이동
  void _navigateToNoteDetail(BuildContext context, Note note) {
    if (kDebugMode) {
      debugPrint('[SampleHomeScreen] 샘플 노트 상세 화면으로 이동: ${note.id}');
    }
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SampleNoteDetailScreen(
          note: note,
          sampleNotesService: _sampleNotesService,
        ),
      ),
    );
  }

  // 플래시카드 화면으로 이동
  void _navigateToFlashcards(BuildContext context, Note note) {
    if (kDebugMode) {
      debugPrint('[SampleHomeScreen] 샘플 플래시카드 화면으로 이동: ${note.id}');
    }
    
    if (note.flashcardCount > 0) {
      // 새로운 API 사용하여 플래시카드 가져오기
      final flashcards = _sampleNotesService.getFlashcardsForNote(note.id ?? '');
      
      if (flashcards.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => SampleFlashCardScreen(
              flashcards: flashcards,
              noteTitle: note.title,
            ),
          ),
        );
        return;
      }
    }
    
    // 플래시카드가 없는 경우
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('이 노트에는 플래시카드가 없습니다.')),
    );
  }

  // 헤더 위젯 구현
  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pikabook으로 만든 노트를\n미리 살펴보세요! ',
            style: TypographyTokens.headline2En.copyWith(
              color: ColorTokens.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            '교재 사진을 올리면,\n아래와 같은 노트가 자동으로 만들어져요. ',
            style: TypographyTokens.body1.copyWith(
              color: ColorTokens.textPrimary,
            ),
          ),
          SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sampleNotes = _sampleNotesService.getSampleNotes();
    // 화면 하단 패딩 계산 (안전 영역 포함)
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFFEFAF1),
      appBar: PikaAppBar(
        showLogo: true,
        backgroundColor: const Color(0xFFFEFAF1),
        height: 96,
        actions: [
          _buildExitButton(context),
          SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // 메인 콘텐츠 영역 (확장 가능한 영역)
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _buildHeader(),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final note = sampleNotes[index];
                      return Padding(
                        padding: const EdgeInsets.only(
                          left: 16, 
                          right: 16, 
                          bottom: 12
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: NoteListItem(
                            note: note,
                            onDismissed: () {},
                            onNoteTapped: (_) => _navigateToNoteDetail(context, note),
                            isFilteredList: false,
                          ),
                        ),
                      );
                    },
                    childCount: sampleNotes.length,
                  ),
                ),
                // 하단 여백 추가 (하단 버튼 영역을 위한 공간)
                SliverToBoxAdapter(
                  child: SizedBox(height: 24),
                ),
              ],
            ),
          ),
          
          // 하단 로그인 버튼 (고정 높이)
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFFFEFAF1).withOpacity(0.8),
                  const Color(0xFFFEFAF1),
                ],
                stops: [0.0, 0.5],
              ),
            ),
            padding: EdgeInsets.only(
              left: 16, 
              right: 16, 
              top: 16, 
              bottom: 16 + bottomPadding // 안전 영역 고려
            ),
            child: PikaButton(
              variant: PikaButtonVariant.primary,
              onPressed: () => _navigateToLogin(context),
              text: '로그인하고 시작하기',
              width: 240,
            ),
          ),
        ],
      ),
    );
  }
} 