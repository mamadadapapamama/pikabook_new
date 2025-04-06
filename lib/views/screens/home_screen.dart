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
import '../../services/usage_limit_service.dart';
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
import '../../widgets/common/usage_dialog.dart';
import 'flashcard_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'settings_screen.dart';
import '../../app.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/debug_utils.dart';

/// 노트 카드 리스트를 보여주는 홈 화면
/// profile setting, note detail, flashcard 화면으로 이동 가능

class HomeScreen extends StatefulWidget {
  final VoidCallback? onSettingsPressed;
  
  const HomeScreen({
    Key? key,
    this.onSettingsPressed,
  }) : super(key: key);
  
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final UserPreferencesService _userPreferences = UserPreferencesService();
  final UsageLimitService _usageLimitService = UsageLimitService();
  String _noteSpaceName = '';
  late AnimationController _animationController;
  late Animation<double> _animation;
  
  // 사용량 관련 상태 변수
  bool _hasCheckedUsage = false;
  Map<String, dynamic> _limitStatus = {};
  Map<String, double> _usagePercentages = {};
  
  HomeViewModel? _viewModel;

  @override
  void initState() {
    super.initState();
    
    // 첫 로드
    _loadNoteSpaceName();
    
    // 화면 구성 완료 후 데이터 확인 및 새로고침
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 노트 스페이스 이름 다시 로드
      _loadNoteSpaceName();
      
      // 사용량 확인
      _checkUsageLimits();
    });
    
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
    // 리스너 제거
    _viewModel?.removeListener(_onViewModelChanged);
    _animationController.dispose();
    super.dispose();
  }
  
  Future<void> _loadNoteSpaceName() async {
    try {
      final noteSpaceName = await _userPreferences.getDefaultNoteSpace();
      
      // 디버깅을 위해 현재 사용자 ID 로깅
      final currentUserId = await _userPreferences.getCurrentUserId();
      debugPrint('노트 스페이스 이름 로드: "$noteSpaceName" (사용자 ID: $currentUserId)');
      
      if (mounted) {
        setState(() {
          _noteSpaceName = noteSpaceName;
        });
      }
    } catch (e) {
      debugPrint('노트 스페이스 이름 로드 오류: $e');
      // 오류 발생 시 기본값 사용
      if (mounted) {
        setState(() {
          _noteSpaceName = '학습 노트';
        });
      }
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
            // 디버그 로그 추가
            debugPrint('홈 화면에서 설정 버튼 클릭됨 - 네비게이션 시작');
            
            // widget.onSettingsPressed가 있으면 사용, 없으면 기본 설정 화면으로 이동
            if (widget.onSettingsPressed != null) {
              debugPrint('외부 제공된 onSettingsPressed 콜백 사용');
              widget.onSettingsPressed!();
            } else {
              debugPrint('기본 설정 화면으로 이동');
              // 설정 화면으로 이동 (라우팅 사용)
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(
                    onLogout: () async {
                      // 로그아웃 처리
                      await FirebaseAuth.instance.signOut();
                      // 페이드 애니메이션을 사용한 로그인 화면 전환
                      if (context.mounted) {
                        Navigator.of(context).pushAndRemoveUntil(
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => const App(),
                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                              const begin = 0.0;
                              const end = 1.0;
                              const curve = Curves.easeInOut;
                              
                              var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                              var fadeAnimation = animation.drive(tween);
                              
                              return FadeTransition(
                                opacity: fadeAnimation,
                                child: child,
                              );
                            },
                            transitionDuration: const Duration(milliseconds: 500),
                          ),
                          (route) => false,
                        );
                      }
                    },
                  ),
                ),
              ).then((_) {
                // 설정 화면에서 돌아올 때 노트 스페이스 이름 다시 로드
                debugPrint('설정 화면에서 돌아옴 - 노트 스페이스 이름 다시 로드');
                _loadNoteSpaceName();
              });
            }
          },
        ),
        body: SafeArea(
          bottom: false,
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 스마트 노트 만들기 버튼 - 노트가 있을 때만 표시
                    Consumer<HomeViewModel>(
                      builder: (context, viewModel, _) {
                        // 노트가 있을 때만 버튼 표시
                        if (viewModel.hasNotes) {
                          return Column(
                            children: [
                              _isButtonDisabled()
                                ? Tooltip(
                                    message: '사용량 한도 초과로 비활성화되었습니다',
                                    child: PikaButton(
                                      text: '스마트 노트 만들기',
                                      variant: PikaButtonVariant.primary,
                                      onPressed: null, // 비활성화
                                    ),
                                  )
                                : PikaButton(
                                    text: '스마트 노트 만들기',
                                    variant: PikaButtonVariant.primary,
                                    onPressed: () => _showImagePickerBottomSheet(context),
                                  ),
                              const SizedBox(height: 16),
                            ],
                          );
                        }
                        return const SizedBox.shrink(); // 노트가 없으면 버튼 숨김
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 사용량 제한 확인 및 다이얼로그 표시
  Future<void> _checkUsageLimits() async {
    try {
      // 사용량 제한 상태 확인
      final limitStatus = await _usageLimitService.checkFreeLimits();
      final usagePercentages = await _usageLimitService.getUsagePercentages();
      
      setState(() {
        _limitStatus = limitStatus;
        _usagePercentages = usagePercentages;
        _hasCheckedUsage = true;
      });
      
      // 한도 초과 시 다이얼로그 표시
      if (limitStatus['anyLimitReached'] == true && mounted) {
        // 약간의 지연 후 다이얼로그 표시 (화면 전환 애니메이션 완료 후)
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            UsageDialog.show(
              context,
              limitStatus: limitStatus,
              usagePercentages: usagePercentages,
              onContactSupport: _handleContactSupport,
            );
          }
        });
      }
    } catch (e) {
      debugPrint('사용량 확인 중 오류 발생: $e');
    }
  }
  
  // 지원팀 문의하기 처리
  void _handleContactSupport() async {
    // 프리미엄 문의 구글 폼 URL
    const String formUrl = 'https://forms.gle/9EBEV1vaLpNbkhxD9';
    final Uri url = Uri.parse(formUrl);
    
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        // URL을 열 수 없는 경우 스낵바로 알림
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('문의 폼을 열 수 없습니다. 직접 브라우저에서 다음 주소를 입력해 주세요: $formUrl'),
              duration: const Duration(seconds: 10),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('URL 열기 오류: $e');
      // 오류 발생 시 스낵바로 알림
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('문의 폼을 여는 중 오류가 발생했습니다. 이메일로 문의해 주세요: hello.pikabook@gmail.com'),
            duration: const Duration(seconds: 10),
          ),
        );
      }
    }
  }

  void _showImagePickerBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return ImagePickerBottomSheet();
      },
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
            Image.asset(
              'assets/images/zeronote.png',
              width: 214,
              height: 160,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 30),
            
            Text(
              '먼저, 번역이 필요한\n이미지를 올려주세요.',
              textAlign: TextAlign.center,
              style: TypographyTokens.subtitle1.copyWith(
                color: ColorTokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            
            Text(
              '이미지를 기반으로 학습 노트를 만들어드립니다. \n카메라 촬영도 가능합니다.',
              textAlign: TextAlign.center,
              style: TypographyTokens.body2.copyWith(
                color: ColorTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            // CTA 버튼 - 이미지 업로드하기 (사용량 초과시 비활성화)
            _isButtonDisabled()
              ? Tooltip(
                  message: '사용량 한도 초과로 비활성화되었습니다',
                  child: PikaButton(
                    text: '이미지 올리기',
                    variant: PikaButtonVariant.primary,
                    onPressed: null, // 비활성화
                  ),
                )
              : PikaButton(
                  text: '이미지 올리기',
                  variant: PikaButtonVariant.primary,
                  onPressed: () => _showImagePickerBottomSheet(context),
                ),
          ],
        ),
      ),
    );
  }

  // Zero state에서 '새 노트 만들기' 버튼 클릭 핸들러
  void _handleAddImage(BuildContext context) async {
    // 바로 이미지 피커 바텀 시트 표시
    if (!mounted) return;
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

  // 버튼 비활성화 여부 확인
  bool _isButtonDisabled() {
    // _limitStatus가 비어있거나 null이면 false 반환 (버튼 활성화)
    if (_limitStatus.isEmpty) {
      return false;
    }
    
    // OCR, 번역, 저장 공간 중 하나라도 한도 도달 시 버튼 비활성화
    return _limitStatus['ocrLimitReached'] == true || 
           _limitStatus['translationLimitReached'] == true || 
           _limitStatus['storageLimitReached'] == true;
  }

  // HomeViewModel 변경 시 호출될 메서드
  void _onViewModelChanged() {
    // 필요시 상태 업데이트
    if (!mounted || _viewModel == null) return;
  }
} 