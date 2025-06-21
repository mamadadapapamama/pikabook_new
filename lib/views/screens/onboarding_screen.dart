import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/services/authentication/user_preferences_service.dart';
import '../../core/services/common/plan_service.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../../core/widgets/pika_button.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../../../core/widgets/upgrade_modal.dart';
import 'package:flutter_svg/flutter_svg.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({Key? key, required this.onComplete}) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  final UserPreferencesService _userPreferences = UserPreferencesService();
  final PlanService _planService = PlanService();
  
  // 상태 변수
  int _currentPage = 0;
  bool _isProcessing = false;
  
  // 1단계: 사용자 이름
  final TextEditingController _nameController = TextEditingController();
  
  // 2단계: 사용 목적
  String? _selectedUsagePurpose;
  final TextEditingController _customPurposeController = TextEditingController();

  // 3단계: 중국어 학습 수준
  String? _selectedLevel;
  
  // 2단계 사용 목적 옵션
  final List<Map<String, String>> _usagePurposeOptions = [
    {'icon': '📚', 'text': '직접 원서를 공부하는데 사용'},
    {'icon': '🙂', 'text': '아이의 중국어 학습 보조'},
    {'icon': '🚀', 'text': '기타'},
  ];
  
  // 3단계 학습 수준 옵션
  final List<Map<String, String>> _levelOptions = [
    {
      'level': '초급',
      'title': '🌱 처음이에요',
      'description': '기본 단어, 간단한 문장을 공부할 예정이에요. 중국어 교과과정 유치원~ 초등 저학년 과정에 적합해요.',
    },
    {
      'level': '중급',
      'title': '🌿 중급이에요',
      'description': '책을 읽을 수 있지만 중간 중간 모르는 단어가 있어요. HSK나 워크북 같은 문제풀이에 좋아요.',
    },
    {
      'level': '고급',
      'title': '🌳 중국어에 익숙해요',
      'description': '신문 기사나 매거진, 두꺼운 책을 읽을 수 있어요',
    },
  ];

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_updateState);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.removeListener(_updateState);
    _nameController.dispose();
    _customPurposeController.dispose();
    super.dispose();
  }
  
  void _updateState() {
    setState(() {});
  }
  
  bool get _canProceed {
    switch (_currentPage) {
      case 0:
        return _nameController.text.isNotEmpty;
      case 1:
        // 기타 선택 시 커스텀 입력이 필요
        if (_selectedUsagePurpose == '기타') {
          return _customPurposeController.text.trim().isNotEmpty;
        }
        return _selectedUsagePurpose != null;
      case 2:
        return _selectedLevel != null;
      default:
        return false;
    }
  }

  void _nextPage() {
    if (_currentPage == 0 && _nameController.text.trim().isEmpty) {
      // 이름이 비어있으면 다음으로 넘어가지 않음
      return;
    }
    if (_currentPage == 1 && _selectedUsagePurpose == null) {
      // 사용 목적이 선택되지 않았으면 넘어가지 않음
      return;
    }
    
    // 마지막 페이지에서 '시작하기' 버튼을 누른 경우
    if (_currentPage == 2) {
      if (_selectedLevel != null) {
        _finishOnboarding();
      }
      return;
    }

    // 다음 페이지로 이동
    _pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
  
  // 이전 페이지로 이동
  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  // 온보딩 완료 처리
  void _finishOnboarding() {
    setState(() {
      _isProcessing = true;
    });

    _completeOnboarding();
  }

  // 온보딩 건너뛰기 처리
  void _skipOnboarding() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      // 기본값 설정
      final defaultName = "사용자";
      final defaultNoteSpace = "${defaultName}의 학습노트";
      
      // 기본 설정 저장
      await _userPreferences.setUseSegmentMode(true);
      await _userPreferences.setDefaultNoteSpace(defaultNoteSpace);
      await _userPreferences.addNoteSpace(defaultNoteSpace);
      await _userPreferences.setUserName(defaultName);

      // 툴팁 설정
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasShownTooltip', false);
      
      // Firestore에 기본 데이터 저장
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _userPreferences.setCurrentUserId(user.uid);
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'userName': defaultName,
          'chineseLevel': '초급', // 기본값
          'translationMode': 'segment',
          'hasOnboarded': true,
          'onboardingCompleted': true,
          'defaultNoteSpace': defaultNoteSpace,
          'noteSpaces': [defaultNoteSpace],
        }, SetOptions(merge: true));
      }
      
      // 온보딩 완료 표시
      await _userPreferences.setOnboardingCompleted(true);
      await _userPreferences.setHasOnboarded(true);
      
      // 건너뛰기를 해도 무료체험 유도 모달 표시
      if (mounted) {
        await UpgradePromptHelper.showWelcomeTrialPrompt(
          context,
          onComplete: widget.onComplete,
        );
      }
      
    } catch (e) {
      debugPrint('온보딩 건너뛰기 처리 중 오류 발생: $e');
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // 온보딩 데이터 저장 및 완료 처리
  Future<void> _completeOnboarding() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // 사용 목적 값 결정 (기타인 경우 커스텀 입력 값 사용)
      String finalUsagePurpose = _selectedUsagePurpose!;
      if (_selectedUsagePurpose == '기타' && _customPurposeController.text.trim().isNotEmpty) {
        finalUsagePurpose = _customPurposeController.text.trim();
      }

      // 번역 모드 자동 설정 (초급 -> 문장 모드, 중급/고급 -> 문단 모드)
      String translationMode = _selectedLevel == '처음이에요' ? 'sentence' : 'paragraph';

      // Firestore에 사용자 정보 저장
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': _nameController.text,
        'usagePurpose': finalUsagePurpose,
        'level': _selectedLevel,
        'translationMode': translationMode,
        'onboardingCompleted': true,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // SharedPreferences에도 저장
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('onboarding_completed', true);
      await prefs.setString('user_name', _nameController.text);
      await prefs.setString('usage_purpose', finalUsagePurpose);
      await prefs.setString('user_level', _selectedLevel!);
      await prefs.setString('translation_mode', translationMode);

      // 홈 화면으로 이동
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/main');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류가 발생했습니다: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: ColorTokens.background,
        elevation: 0,
        toolbarHeight: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: ColorTokens.background,
          statusBarIconBrightness: Brightness.dark, // 안드로이드용
          statusBarBrightness: Brightness.light, // iOS용
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          color: ColorTokens.background, // 디자인 토큰 사용
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                // 상단 stepper 영역
                Padding(
                  padding: EdgeInsets.only(top: SpacingTokens.lg, bottom: SpacingTokens.xl),
                  child: _buildStepper(),
                ),

                // 온보딩 페이지
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                      // 키보드 숨기기
                      FocusScope.of(context).unfocus();
                    },
                    children: [
                      _buildNameInputPage(),
                      _buildUsagePurposePage(),
                      _buildLevelPage(),
                    ],
                  ),
                ),

                // 하단 버튼 영역
                Padding(
                  padding: const EdgeInsets.only(bottom: 40.0),
                  child: Column(
                    children: [
                       Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 뒤로 버튼 (첫 페이지에서는 숨김)
                          if (_currentPage > 0)
                            Expanded(
                              child: PikaButton(
                                text: '뒤로',
                                variant: PikaButtonVariant.outline,
                                onPressed: _prevPage,
                                isFullWidth: true,
                              ),
                            ),
                                
                          // 뒤로 버튼과 다음 버튼 사이 간격
                          if (_currentPage > 0)
                            const SizedBox(width: 16),
                                
                          // 다음/시작 버튼
                          Expanded(
                            child: PikaButton(
                              text: _currentPage == 2 ? '시작하기' : '다음으로',
                              variant: PikaButtonVariant.primary,
                              size: PikaButtonSize.medium,
                              onPressed: _canProceed ? _nextPage : null,
                              isLoading: _isProcessing,
                              isFullWidth: true,
                            ),
                          ),
                        ],
                      ),
                      // Skip 버튼 (마지막 페이지에서는 숨김)
                      if (_currentPage < 2)
                        Padding(
                          padding: const EdgeInsets.only(top: 16.0),
                          child: TextButton(
                            onPressed: _isProcessing ? null : _skipOnboarding,
                            child: Text(
                              'skip',
                              style: TypographyTokens.button.copyWith(
                                color: ColorTokens.textGrey,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      // 키보드가 화면을 밀어올리지 않도록 설정
      resizeToAvoidBottomInset: false,
    );
  }

  // Stepper 위젯
  Widget _buildStepper() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 머리 아이콘
        SvgPicture.asset(
          'assets/images/icon_head.svg',
          width: 24,
          height: 24,
        ),
        const SizedBox(width: 12),
        
        // Step indicators
        Row(
          children: List.generate(3, (index) {
            final isActive = index == _currentPage;
            final isCompleted = index < _currentPage;
            
            return Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive || isCompleted 
                        ? ColorTokens.primary 
                        : ColorTokens.primarylight,
                    border: isActive 
                        ? Border.all(color: ColorTokens.primary, width: 2)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: TypographyTokens.body2.copyWith(
                        color: isActive || isCompleted 
                            ? Colors.white 
                            : ColorTokens.textSecondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                if (index < 2) // 마지막 step이 아닌 경우 연결선 추가
                  Container(
                    width: 40,
                    height: 2,
                    color: isCompleted 
                        ? ColorTokens.primary 
                        : ColorTokens.primarylight,
                  ),
              ],
            );
          }),
        ),
      ],
    );
  }

  // 1단계: 이름 입력
  Widget _buildNameInputPage() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 48),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              children: [
                TextSpan(
                  text: "책으로 하는 중국어 학습,\n",
                  style: TypographyTokens.headline3.copyWith(
                    fontWeight: FontWeight.w600,
                    color: ColorTokens.textPrimary,
                    height: 1.4,
                  ),
                ),
                TextSpan(
                  text: "Pikabook",
                  style: TypographyTokens.headline3.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ColorTokens.primary,
                    height: 1.4,
                  ),
                ),
                TextSpan(
                  text: "과 함께해요!",
                  style: TypographyTokens.headline3.copyWith(
                    fontWeight: FontWeight.w600,
                    color: ColorTokens.textPrimary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 60),
          Text(
            "먼저, 학습하실 분의\n이름을 알려주세요.",
            textAlign: TextAlign.center,
            style: TypographyTokens.subtitle1.copyWith(
              fontWeight: FontWeight.w500,
              color: ColorTokens.textPrimary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 40),
          Container(
            decoration: BoxDecoration(
              color: ColorTokens.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ColorTokens.primarylight),
            ),
            child: TextField(
              controller: _nameController,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '이름',
                hintStyle: TypographyTokens.body1.copyWith(
                  color: ColorTokens.textTertiary,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: SpacingTokens.lg,
                  vertical: SpacingTokens.lg,
                ),
              ),
              style: TypographyTokens.body1.copyWith(
                color: ColorTokens.textPrimary,
              ),
              onEditingComplete: () {
                FocusScope.of(context).unfocus();
                if (_nameController.text.trim().isNotEmpty) {
                  _nextPage();
                }
              },
              textInputAction: TextInputAction.done,
            ),
          ),
        ],
      ),
    );
  }

  // 2단계: 사용 목적 선택
  Widget _buildUsagePurposePage() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 48),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              children: [
                TextSpan(
                  text: "Pikabook",
                  style: TypographyTokens.headline3En.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ColorTokens.primary,
                    height: 1.4,
                  ),
                ),
                TextSpan(
                  text: "을\n어떻게 사용하실 예정이세요?",
                  style: TypographyTokens.headline3.copyWith(
                    fontWeight: FontWeight.w600,
                    color: ColorTokens.textPrimary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),
          ..._usagePurposeOptions
              .asMap()
              .entries
              .map((entry) {
                final index = entry.key;
                final option = entry.value;
                return Column(
                  children: [
                    _buildOption(
                      icon: option['icon']!,
                      text: option['text']!,
                      isSelected: _selectedUsagePurpose == option['text'],
                      onTap: () {
                        setState(() {
                          _selectedUsagePurpose = option['text'];
                          // 기타가 아닌 다른 옵션 선택 시 커스텀 입력 초기화
                          if (option['text'] != '기타') {
                            _customPurposeController.clear();
                          }
                        });
                      },
                    ),
                    // 기타 선택 시 입력 필드 표시
                    if (_selectedUsagePurpose == '기타' && option['text'] == '기타')
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: ColorTokens.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: ColorTokens.primarylight),
                          ),
                          child: TextField(
                            controller: _customPurposeController,
                            decoration: InputDecoration(
                              hintText: '구체적인 사용 목적을 입력해주세요',
                              hintStyle: TypographyTokens.body1.copyWith(
                                color: ColorTokens.textTertiary,
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: SpacingTokens.lg,
                                vertical: SpacingTokens.md,
                              ),
                            ),
                            style: TypographyTokens.body1.copyWith(
                              color: ColorTokens.textPrimary,
                            ),
                            textInputAction: TextInputAction.done,
                          ),
                        ),
                      ),
                    // 옵션 간 spacing (마지막 항목이 아닌 경우)
                    if (index < _usagePurposeOptions.length - 1)
                      const SizedBox(height: 12),
                  ],
                );
              })
              .toList(),
        ],
      ),
    );
  }

  // 공용 옵션 선택 위젯
  Widget _buildOption({
    required String icon,
    required String text,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: SpacingTokens.lg,
          vertical: SpacingTokens.lg,
        ),
        decoration: BoxDecoration(
          color: isSelected ? ColorTokens.primaryverylight : ColorTokens.surface,
          borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
          border: Border.all(
            color: isSelected ? ColorTokens.primary : ColorTokens.primarylight,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Text(
              icon, 
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                text,
                style: TypographyTokens.body1Bold.copyWith(
                  color: ColorTokens.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 3단계: 학습 수준 선택
  Widget _buildLevelPage() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_currentPage == 2) {
        FocusScope.of(context).unfocus();
      }
    });

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: _nameController.text.trim(),
                  style: TypographyTokens.headline3.copyWith(
                    fontWeight: FontWeight.w700,
                    color: ColorTokens.primary,
                  ),
                ),
                TextSpan(
                  text: "님의\n중국어 학습 수준을 알려주세요.",
                  style: TypographyTokens.headline3.copyWith(
                    fontWeight: FontWeight.w600,
                    color: ColorTokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 48),
          ..._levelOptions
              .asMap()
              .entries
              .map((entry) {
                final index = entry.key;
                final option = entry.value;
                return Column(
                  children: [
                    _buildLevelOption(option),
                    // 옵션 간 spacing (마지막 항목이 아닌 경우)
                    if (index < _levelOptions.length - 1)
                      const SizedBox(height: 12),
                  ],
                );
              })
              .toList(),
        ],
      ),
    );
  }

  // 레벨 선택 옵션 위젯
  Widget _buildLevelOption(Map<String, String> option) {
    final isSelected = _selectedLevel == option['text'];
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedLevel = option['text'];
        });
      },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: SpacingTokens.lg,
          vertical: SpacingTokens.lg,
        ),
        decoration: BoxDecoration(
          color: isSelected ? ColorTokens.primaryverylight : ColorTokens.surface,
          borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
          border: Border.all(
            color: isSelected ? ColorTokens.primary : ColorTokens.primarylight,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Text(
              option['icon']!, 
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                option['text']!,
                style: TypographyTokens.body1Bold.copyWith(
                  color: ColorTokens.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

