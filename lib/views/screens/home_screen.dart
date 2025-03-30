import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:flutter_svg/flutter_svg.dart';
import '../../viewmodels/home_viewmodel.dart';
import '../../widgets/note_list_item.dart';
import '../../widgets/loading_dialog.dart';
import '../../services/note_service.dart';
import '../../services/image_service.dart';
import '../../services/user_preferences_service.dart';
import '../../theme/tokens/color_tokens.dart';
import '../../theme/tokens/typography_tokens.dart';
import '../../theme/tokens/spacing_tokens.dart';
import '../../theme/tokens/ui_tokens.dart';
import '../../models/note.dart';
import 'note_detail_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/image_picker_bottom_sheet.dart';
import '../../widgets/dot_loading_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/common/pika_button.dart';
import '../../widgets/common/help_text_tooltip.dart';
import '../../widgets/common/pika_app_bar.dart';
import 'flashcard_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/initialization_service.dart';
import 'settings_screen.dart';

/// 노트 카드 리스트를 보여주는 홈 화면
/// profile setting, note detail, flashcard 화면으로 이동 가능

class HomeScreen extends StatefulWidget {
  final bool showTooltip;
  final VoidCallback? onCloseTooltip;
  final InitializationService? initializationService;

  const HomeScreen({
    Key? key, 
    this.showTooltip = false,
    this.onCloseTooltip,
    this.initializationService,
  }) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final UserPreferencesService _userPreferences = UserPreferencesService();
  String _noteSpaceName = '';
  bool _showTooltip = false;
  late AnimationController _animationController;
  late Animation<double> _animation;
  
  // 디버그 탭 카운터 (숨겨진 디버그 메뉴용)
  int _debugTapCount = 0;
  
  @override
  void initState() {
    super.initState();
    _loadNoteSpaceName();
    
    // 외부에서 전달받은 툴팁 표시 여부 적용
    _showTooltip = widget.showTooltip;
    
    // 기존 온보딩 상태 확인은 제거하고, 외부에서 제어하도록 수정
    if (_showTooltip) {
      // 10초 후에 툴팁 자동으로 숨기기
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted) {
          setState(() {
            _showTooltip = false;
          });
          
          // 툴팁 닫기 콜백 호출
          if (widget.onCloseTooltip != null) {
            widget.onCloseTooltip!();
          }
        }
      });
    }
    
    // 애니메이션 컨트롤러 초기화
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    
    // 위아래로 움직이는 애니메이션 설정
    _animation = Tween<double>(
      begin: -4.0,
      end: 4.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ))..addListener(() {
      setState(() {});
    });
    
    // 애니메이션 반복 설정
    _animationController.repeat(reverse: true);
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  Future<void> _loadNoteSpaceName() async {
    final noteSpaceName = await _userPreferences.getDefaultNoteSpace();
    if (mounted) {
      setState(() {
        _noteSpaceName = noteSpaceName;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HomeViewModel(),
      child: Scaffold(
        backgroundColor: UITokens.homeBackground,
        appBar: PikaAppBar.home(
          noteSpaceName: _noteSpaceName,
          onSettingsPressed: () {
            // initializationService가 null인지 확인
            if (widget.initializationService == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('설정을 로드할 수 없습니다. 앱을 다시 시작해주세요.'))
              );
              return;
            }
            
            // 설정 화면으로 이동 (라우팅 사용)
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => SettingsScreen(
                  initializationService: widget.initializationService!, // null이 아님을 보장했으므로 ! 사용
                  onLogout: () async {
                    // 로그아웃 처리
                    await FirebaseAuth.instance.signOut();
                    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                  },
                ),
              ),
            ).then((_) {
              // 설정 화면에서 돌아올 때 노트 스페이스 이름 다시 로드
              _loadNoteSpaceName();
            });
          },
        ),
        body: SafeArea(
          bottom: false,
          // 앱 로고 부분에 탭 제스처 추가
          child: GestureDetector(
            onDoubleTap: () {
              setState(() {
                _debugTapCount++;
              });
              
              // 5번 더블 탭하면 디버그 메뉴 표시
              if (_debugTapCount >= 5) {
                _showDebugMenu();
                setState(() {
                  _debugTapCount = 0; // 카운터 리셋
                });
              }
            },
            child: Column(
              children: [
                Expanded(
                  child: Consumer<HomeViewModel>(
                    builder: (context, viewModel, child) {
                      if (viewModel.isLoading) {
                        return const DotLoadingIndicator(message: '노트 불러오는 중...');
                      }

                      if (viewModel.error != null) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: SpacingTokens.iconSizeXLarge,
                                color: ColorTokens.error,
                              ),
                              SizedBox(height: SpacingTokens.md),
                              Text(
                                viewModel.error!,
                                textAlign: TextAlign.center,
                                style: TypographyTokens.body1,
                              ),
                              SizedBox(height: SpacingTokens.md),
                              ElevatedButton(
                                onPressed: () => viewModel.refreshNotes(),
                                child: const Text('다시 시도'),
                                style: UITokens.primaryButtonStyle,
                              ),
                            ],
                          ),
                        );
                      }

                      if (!viewModel.hasNotes) {
                        // Zero State 디자인
                        return _buildZeroState(context);
                      }

                      // RefreshIndicator로 감싸서 pull to refresh 기능 추가
                      return RefreshIndicator(
                        onRefresh: () => viewModel.refreshNotes(),
                        color: ColorTokens.primary,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: SpacingTokens.md,
                            vertical: SpacingTokens.sm,
                          ),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: viewModel.notes.length,
                            itemBuilder: (context, index) {
                              // 일반 노트 아이템
                              final note = viewModel.notes[index];
                              return NoteListItem(
                                note: note,
                                onTap: () => _navigateToNoteDetail(context, note.id!),
                                onFavoriteToggle: (isFavorite) {
                                  if (note.id != null) {
                                    viewModel.toggleFavorite(note.id!, isFavorite);
                                  }
                                },
                                onDelete: () {
                                  if (note.id != null) {
                                    viewModel.deleteNote(note.id!);
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                  child: HelpTextTooltip(
                    text: "노트 저장 공간이 성공적으로 만들어졌어요!",
                    description: "이제 이미지를 올려, 스마트 노트를 만들어보세요.",
                    showTooltip: _showTooltip,
                    onDismiss: _handleCloseTooltip,
                    backgroundColor: ColorTokens.primarylight,
                    borderColor: ColorTokens.primaryMedium,
                    textColor: ColorTokens.textPrimary,
                    tooltipPadding: const EdgeInsets.all(12),
                    spacing: 4.0,
                    child: SizedBox(
                      width: double.infinity,
                      child: Consumer<HomeViewModel>(
                        builder: (context, viewModel, _) {
                          if (viewModel.hasNotes) {
                            return PikaButton(
                              text: '스마트 노트 만들기',
                              variant: PikaButtonVariant.floating,
                              leadingIcon: const Icon(Icons.add),
                              onPressed: () => _showImagePickerBottomSheet(context),
                            );
                          }
                          return const SizedBox.shrink(); // 노트가 없을 때는 FAB 숨김
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showImagePickerBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ImagePickerBottomSheet(),
    );
  }

  void _navigateToNoteDetail(BuildContext context, String noteId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NoteDetailScreen(noteId: noteId),
      ),
    );
  }

  Widget _buildZeroState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              'assets/images/icon_addnote.svg',
              width: 48,
              height: 48,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 48),
            
            Text(
              '번역이 필요한\n이미지를 올려주세요.',
              textAlign: TextAlign.center,
              style: TypographyTokens.subtitle1.copyWith(
                color: ColorTokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            
            Text(
              '이미지를 기반으로 학습 노트를 만들어드립니다. \n카메라 촬영도 가능합니다.',
              textAlign: TextAlign.center,
              style: TypographyTokens.body2.copyWith(
                color: ColorTokens.textSecondary,
              ),
            ),
            
            const SizedBox(height: 32),
            
            SizedBox(
              width: double.infinity,
              child: PikaButton(
                text: '스마트 노트 만들기',
                variant: PikaButtonVariant.primary,
                size: PikaButtonSize.large,
                leadingIcon: const Icon(Icons.add),
                onPressed: () => _handleAddNote(context),
                isFullWidth: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Zero state에서 '새 노트 만들기' 버튼 클릭 핸들러
  void _handleAddNote(BuildContext context) {
    _showImagePickerBottomSheet(context);
  }

  /// 모든 플래시카드 보기 화면으로 이동
  Future<void> _navigateToAllFlashcards() async {
    try {
      // 플래시카드 화면으로 이동
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const FlashCardScreen(),
        ),
      );

      // 플래시카드 카운터 업데이트가 필요한 경우
      if (result != null && result is Map && result.containsKey('flashcardCount')) {
        final HomeViewModel viewModel = Provider.of<HomeViewModel>(context, listen: false);
        
        // 특정 노트의 플래시카드 카운터만 업데이트
        if (result.containsKey('noteId') && result['noteId'] != null) {
          String noteId = result['noteId'] as String;
          
          // 해당 노트 찾아서 카운터 업데이트
          final int index = viewModel.notes.indexWhere((note) => note.id == noteId);
          if (index >= 0) {
            final int flashcardCount = result['flashcardCount'] as int;
            final note = viewModel.notes[index].copyWith(flashcardCount: flashcardCount);
            
            // 노트 서비스를 통해 캐시 업데이트
            NoteService().cacheNotes([note]);
          }
        }
        
        // 최신 데이터로 새로고침
        viewModel.refreshNotes();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('플래시카드 화면 이동 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  // 툴팁 닫기 처리 메서드
  void _handleCloseTooltip() {
    setState(() {
      _showTooltip = false;
    });
    
    // 툴팁 닫기 콜백 호출
    if (widget.onCloseTooltip != null) {
      widget.onCloseTooltip!();
    }
  }

  // 디버그 메뉴 표시
  void _showDebugMenu() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🐞 디버그 메뉴'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('개발 테스트용 메뉴입니다.'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                try {
                  // 강제 로그아웃 실행
                  await FirebaseAuth.instance.signOut();
                  
                  // 앱 다시 시작 (Navigator.pushNamedAndRemoveUntil)
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('로그아웃 완료. 앱을 다시 시작합니다.')),
                    );
                    
                    // 모든 화면 제거하고 로그인 화면으로 이동
                    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('로그아웃 오류: $e')),
                    );
                  }
                }
                Navigator.pop(context); // 다이얼로그 닫기
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('강제 로그아웃'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }
}
