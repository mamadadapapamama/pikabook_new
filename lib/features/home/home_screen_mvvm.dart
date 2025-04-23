import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../../viewmodels/home_viewmodel.dart';
import '../../widgets/note_list_item.dart';
import '../../services/content/note_service.dart';
import '../../services/authentication/user_preferences_service.dart';
import '../../services/common/usage_limit_service.dart';
import '../../theme/tokens/color_tokens.dart';
import '../../theme/tokens/typography_tokens.dart';
import '../../theme/tokens/spacing_tokens.dart';
import '../../theme/tokens/ui_tokens.dart';
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
import '../../models/note.dart';
import 'note_detail_screen_mvvm.dart';

/// 오버스크롤 색상을 주황색으로 변경하는 커스텀 스크롤 비헤이비어
class OrangeOverscrollBehavior extends ScrollBehavior {
  const OrangeOverscrollBehavior();
  
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return GlowingOverscrollIndicator(
      axisDirection: details.direction,
      color: ColorTokens.primarylight, // 오버스크롤 색상을 주황색으로 변경
      child: child,
    );
  }
}

/// 노트 카드 리스트를 보여주는 홈 화면
/// profile setting, note detail, flashcard 화면으로 이동 가능

class HomeScreen extends StatefulWidget {
  final Function(BuildContext)? onSettingsPressed;
  
  const HomeScreen({
    Key? key,
    this.onSettingsPressed,
  }) : super(key: key);
  
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final UserPreferencesService _userPreferences = UserPreferencesService();
  final UsageLimitService _usageLimitService = UsageLimitService();
  String _noteSpaceName = '';
  late AnimationController _animationController;
  late Animation<double> _animation;
  
  // 사용량 관련 상태 변수
  bool _hasCheckedUsage = false;
  Map<String, dynamic> _limitStatus = {};
  Map<String, double> _usagePercentages = {};
  
  // 홈 화면 도움말 표시 관련 변수
  bool _showHomeHelp = false;
  
  HomeViewModel? _viewModel;

  @override
  void initState() {
    super.initState();
    
    // WidgetsBinding 옵저버 등록
    WidgetsBinding.instance.addObserver(this);
    
    // 화면 구성하는 동안 필요한 데이터 즉시 로드
    _loadNoteSpaceName();
    _checkUsageLimits();
    _checkShowHomeHelp();
    
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
    
    // Route 변경 감지를 위한 리스너 추가
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 현재 라우트 감지를 위한 observer 등록
      final navigator = Navigator.of(context);
      // 페이지 리로드를 위한 포커스 리스너 추가
      if (ModalRoute.of(context) != null) {
        ModalRoute.of(context)!.addScopedWillPopCallback(() async {
          // 화면으로 돌아올 때마다 노트스페이스 이름을 다시 로드
          await _loadNoteSpaceName();
          return false; // false를 반환하여 pop을 방해하지 않음
        });
      }
    });
  }
  
  @override
  void dispose() {
    // 리스너 제거
    _viewModel?.removeListener(_onViewModelChanged);
    _animationController.dispose();
    
    // WidgetsBinding 옵저버 제거
    WidgetsBinding.instance.removeObserver(this);
    
    super.dispose();
  }
  
  // 앱 라이프사이클 변경 감지
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    // 앱이 다시 포그라운드로 돌아왔을 때
    if (state == AppLifecycleState.resumed) {
      // 노트스페이스 이름을 다시 로드
      _loadNoteSpaceName();
    }
  }
  
  // 홈 화면 도움말 표시 여부 확인
  Future<void> _checkShowHomeHelp() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool homeHelpShown = prefs.getBool('home_help_shown') ?? false;
    
    if (!homeHelpShown && mounted) {
      // 딜레이 없이 바로 도움말 표시
      setState(() {
        _showHomeHelp = true;
      });
    }
  }
  
  // 도움말 닫기 처리
  void _handleHelpDismiss() async {
    setState(() {
      _showHomeHelp = false;
    });
    
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('home_help_shown', true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // 화면이 활성화될 때마다 노트스페이스 이름 다시 로드
    _loadNoteSpaceName();
  }

  @override
  Widget build(BuildContext context) {
    // ChangeNotifierProvider로 HomeViewModel 제공
    return ChangeNotifierProvider(
      create: (_) => HomeViewModel(),
      child: Builder(
        builder: (context) {
          // 각 Consumer에서 viewModel 참조를 설정하므로 여기서는 필요 없음

          return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0.5,
              title: GestureDetector(
                onTap: _showNoteSpaceOptions,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _noteSpaceName.isNotEmpty ? _noteSpaceName : '로딩 중...',
                      style: const TextStyle(
                        color: ColorTokens.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Icon(
                      Icons.keyboard_arrow_down,
                      color: ColorTokens.textPrimary,
                      size: 20,
                    ),
                  ],
                ),
              ),
              centerTitle: false,
              actions: [
                // 페이지 로드 테스트 버튼 추가
                IconButton(
                  icon: const Icon(Icons.bug_report, color: ColorTokens.primary),
                  onPressed: () => Navigator.of(context).pushNamed('/page-test'),
                  tooltip: '페이지 로드 테스트',
                ),
                IconButton(
                  icon: const Icon(Icons.settings, color: ColorTokens.textSecondary),
                  onPressed: () {
                    Navigator.of(context).pushNamed('/settings');
                  },
                ),
              ],
            ),
            body: SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: Consumer<HomeViewModel>(
                          builder: (context, viewModel, child) {
                            // ViewModel 참조 보관
                            _viewModel = viewModel;
                            
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
                            return ScrollConfiguration(
                              behavior: OrangeOverscrollBehavior(),
                              child: RefreshIndicator(
                                onRefresh: () => viewModel.refreshNotes(),
                                color: ColorTokens.primary,
                                backgroundColor: Colors.white, // 배경색을 흰색으로 설정
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
                                        onNoteTapped: (note) => _navigateToNoteDetail(context, note),
                                        onFavoriteToggled: (noteId, isFavorite) {
                                          viewModel.toggleFavorite(noteId, isFavorite);
                                        },
                                        onDismissed: () {
                                          if (note.id != null) {
                                            viewModel.deleteNote(note.id!);
                                          }
                                        },
                                      );
                                    },
                                  ),
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
                  // 홈 화면 도움말 툴팁 (첫 방문 시에만 표시)
                  if (_showHomeHelp)
                    Positioned(
                      bottom: 150,
                      left: 16,
                      right: 16,
                      child: HelpTextTooltip(
                        text: '피카북에 오신 걸 환영해요! 🎉',
                        description: '4월 30일까지, 교재 이미지 100장까지 무료로 스마트 학습 노트를 만들어보실 수 있어요.\n사용량은 [설정]에서 언제든 확인하실 수 있어요!',
                        image: Image.asset(
                          'assets/images/home_help.png',
                          fit: BoxFit.contain,
                          width: MediaQuery.of(context).size.width - 64, // 화면 너비에 맞게 조정 (패딩 고려)
                        ),
                        showTooltip: true,
                        onDismiss: _handleHelpDismiss,
                        tooltipWidth: MediaQuery.of(context).size.width - 32,
                        spacing: 8.0,
                        style: HelpTextTooltipStyle.primary,
                        titleStyle: TypographyTokens.subtitle1.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: ColorTokens.primary,
                        ),
                        descriptionStyle: const TextStyle(
                          fontSize: 14,
                          color: ColorTokens.textPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }
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
      DebugUtils.error('사용량 확인 중 오류 발생: $e');
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

  void _navigateToNoteDetail(BuildContext context, Note note) async {
    try {
      if (note.id == null || note.id!.isEmpty) {
        print("[HOME] 노트 ID가 유효하지 않습니다: ${note.id}");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('노트 정보가 유효하지 않습니다.')),
        );
        return;
      }

      print("[HOME] 노트 상세화면으로 이동합니다. ID: ${note.id!}");
      print("[HOME] 노트 이미지 URL: ${note.imageUrl}");
      print("[HOME] 노트 페이지 수: ${note.pages?.length ?? 0}, 플래시카드 수: ${note.flashcardCount ?? 0}");
      
      // 페이지 로드 문제 해결을 위해 pages 필드를 null로 설정하여
      // 상세 화면에서 직접 Firestore에서 페이지를 로드하도록 함
      final cleanNote = note.copyWith(pages: null);
      print("[HOME] 페이지 필드를 null로 설정하여 노트 전달");

      // 네비게이션 직전 로그 추가
      print("🚀 [HOME] Navigator.push 호출 직전. Note ID: ${cleanNote.id}");

      Navigator.of(context).push(
        NoteDetailScreenMVVM.route(note: cleanNote), // MVVM 패턴 적용한 화면으로 변경
      ).then((_) {
        print("[HOME] 노트 상세화면에서 돌아왔습니다.");
        Provider.of<HomeViewModel>(context, listen: false).refreshNotes();
      });
    } catch (e, stackTrace) {
      print("[HOME] 노트 상세화면 이동 중 오류 발생: $e");
      print("[HOME] 스택 트레이스: $stackTrace");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('노트 상세화면으로 이동할 수 없습니다: $e')),
      );
    }
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

  // 노트스페이스 옵션 표시
  void _showNoteSpaceOptions() {
    // 현재는 기능 구현 없이 로그만 출력
    print('노트스페이스 옵션 메뉴 표시 예정');
    // TODO: 노트스페이스 선택 또는 관리 메뉴 표시 구현
  }

  Future<void> _loadNoteSpaceName() async {
    try {
      // 노트스페이스 이름 변경 이벤트를 확인
      SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? lastChangedName = prefs.getString('last_changed_notespace_name');
      
      // 일반적인 방법으로 노트스페이스 이름 로드
      final noteSpaceName = await _userPreferences.getDefaultNoteSpace();
      
      // 디버깅을 위해 현재 사용자 ID 로깅
      final currentUserId = await _userPreferences.getCurrentUserId();
      
      if (mounted) {
        setState(() {
          // 마지막으로 변경된 이름이 있으면 해당 이름 사용, 없으면 일반 로드 값 사용
          _noteSpaceName = lastChangedName ?? noteSpaceName;
          
          // 디버그 정보 출력
          DebugUtils.log('노트스페이스 이름 로드: $_noteSpaceName (변경된 이름: $lastChangedName)');
        });
      }
    } catch (e) {
      // 오류 발생 시 기본값 사용
      if (mounted) {
        setState(() {
          _noteSpaceName = '학습 노트';
        });
      }
    }
  }
} 