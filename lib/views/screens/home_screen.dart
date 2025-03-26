import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:flutter_svg/flutter_svg.dart';
import '../../viewmodels/home_viewmodel.dart';
import '../../widgets/note_list_item.dart';
import '../../widgets/loading_dialog.dart';
import '../../widgets/home_screen_app_bar.dart';
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

/// 노트 카드 리스트를 보여주는 홈 화면
/// profile setting, note detail, flashcard 화면으로 이동 가능

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final UserPreferencesService _userPreferences = UserPreferencesService();
  String _noteSpaceName = '';
  bool _showTooltip = false;
  late AnimationController _animationController;
  late Animation<double> _animation;
  
  @override
  void initState() {
    super.initState();
    _loadNoteSpaceName();
    _checkOnboardingStatus();
    
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

  Future<void> _checkOnboardingStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final hasShownTooltip = prefs.getBool('hasShownTooltip') ?? false;
    final hasCompletedOnboarding = prefs.getBool('onboarding_completed') ?? false;
    
    if (hasCompletedOnboarding && !hasShownTooltip) {
      if (mounted) {
        setState(() {
          _showTooltip = true;
        });
      }
      
      // 툴팁을 표시했다고 표시
      await prefs.setBool('hasShownTooltip', true);
      
      // 10초 후에 툴팁 숨기기
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted) {
          setState(() {
            _showTooltip = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 상태 표시줄 색상을 검정으로 설정
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );
    
    return ChangeNotifierProvider(
      create: (_) => HomeViewModel(),
      child: Scaffold(
        backgroundColor: UITokens.homeBackground,
        appBar: HomeScreenAppBar(
          noteSpaceName: _noteSpaceName,
          onSettingsPressed: () {
            Navigator.pushNamed(context, '/settings').then((_) {
              // 설정 화면에서 돌아올 때 노트 스페이스 이름 다시 로드
              _loadNoteSpaceName();
            });
          },
        ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (_showTooltip)
                Transform.translate(
                  offset: Offset(0, _animation.value),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: ColorTokens.primarylight.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: ColorTokens.primary.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "노트 저장 공간이 성공적으로 만들어졌어요!",
                          style: TypographyTokens.body2.copyWith(
                            color: ColorTokens.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "이제 이미지를 올려, 스마트 노트를 만들어보세요.",
                          style: TypographyTokens.body2.copyWith(
                            color: ColorTokens.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
                padding: const EdgeInsets.all(16),
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
            ],
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
}
