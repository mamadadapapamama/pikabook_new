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
  
  // 사용자 이름
  final TextEditingController _nameController = TextEditingController();
  
  // 중국어 학습 수준
  String? _selectedLevel;
  
  // 번역 모드 (학습 수준에 따라 자동 설정)
  bool _isSegmentMode = true; // true: 문장별 번역, false: 문단별 번역
  
  // 학습 수준 옵션
  final List<Map<String, String>> _levelOptions = [
    {
      'level': '초급',
      'title': '처음이에요',
      'description': '기본 단어, 간단한 문장을 공부할 예정이에요',
    },
    {
      'level': '중급',
      'title': '중급이에요',
      'description': '책을 읽을 수 있지만 중간 중간 모르는 단어가 있어요.\n페이지당 20문장 이상의 교재를 공부할 예정이에요.',
    },
    {
      'level': '고급',
      'title': '중국어에 익숙해요',
      'description': '신문 기사나 매거진, 두꺼운 책을 읽을 수 있어요',
    },
  ];

  @override
  void initState() {
    super.initState();
    // 입력 변경 리스너 추가
    _nameController.addListener(_updateState);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.removeListener(_updateState);
    _nameController.dispose();
    super.dispose();
  }
  
  // 상태 업데이트 (UI 리프레시용)
  void _updateState() {
    setState(() {});
  }
  
  // 현재 페이지의 버튼이 활성화되어야 하는지 확인
  bool _isNextButtonEnabled() {
    if (_isProcessing) return false;
    
    if (_currentPage == 0) {
      return true; // 첫 번째 페이지는 항상 활성화
    } else if (_currentPage == 1) {
      return _nameController.text.trim().isNotEmpty;
    } else if (_currentPage == 2) {
      return _selectedLevel != null;
    }
    
    return true;
  }

  // 다음 페이지로 이동
  void _nextPage() {
    // 두 번째 페이지에서 세 번째 페이지로 갈 때는 이름이 입력되었는지 확인
    if (_currentPage == 1) {
      final name = _nameController.text.trim();
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이름을 입력해주세요')),
        );
        return;
      }
    }
    
    // 세 번째 페이지에서 완료할 때는 학습 수준이 선택되었는지 확인
    if (_currentPage == 2) {
      if (_selectedLevel == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('학습 수준을 선택해주세요')),
        );
        return;
      }
      _finishOnboarding();
      return;
    }

    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
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
      
      // 온보딩 완료 콜백 호출
      widget.onComplete();
      
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
      // 사용자 이름 저장
      final userName = _nameController.text.trim();
      
      // 학습 수준에 따라 번역 모드 설정
      if (_selectedLevel == '초급') {
        _isSegmentMode = true; // 문장별 번역
      } else {
        _isSegmentMode = false; // 문단별 번역 (중급, 고급)
      }
          
      // 번역 모드 저장
      await _userPreferences.setUseSegmentMode(_isSegmentMode);
      
      // 이름을 기반으로 노트 스페이스 이름 설정
      final noteSpaceName = "${userName}의 학습노트";
      
      // 노트 스페이스 이름을 설정
      await _userPreferences.setDefaultNoteSpace(noteSpaceName);
      
      // 노트 스페이스 목록에 추가
      await _userPreferences.addNoteSpace(noteSpaceName);
      
      // 사용자 이름 저장
      await _userPreferences.setUserName(userName);

      // 툴팁을 아직 보지 않았다고 설정
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasShownTooltip', false);
      
      // Firestore에 사용자 데이터 저장
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // 현재 사용자 ID 설정 (데이터가 올바른 사용자에게 저장되도록)
        await _userPreferences.setCurrentUserId(user.uid);
        
        // Firestore에 사용자 데이터 저장
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'userName': userName,
          'chineseLevel': _selectedLevel, // 중국어 학습 수준 저장
          'translationMode': _isSegmentMode ? 'segment' : 'paragraph',
          'hasOnboarded': true,
          'onboardingCompleted': true,
          'defaultNoteSpace': noteSpaceName,
          'noteSpaces': [noteSpaceName], // 노트 스페이스 목록도 저장
        }, SetOptions(merge: true));
      }
      
      // 온보딩 완료 표시
      await _userPreferences.setOnboardingCompleted(true);
      await _userPreferences.setHasOnboarded(true);
      
      // 온보딩 완료 콜백 호출
      widget.onComplete();
      
    } catch (e) {
      debugPrint('온보딩 완료 처리 중 오류 발생: $e');
      // 오류 처리
      setState(() {
        _isProcessing = false;
      });
      return;
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
                // 상단 로고 영역과 페이지 인디케이터를 같은 줄에 배치
                Padding(
                  padding: EdgeInsets.only(top: SpacingTokens.lg, bottom: SpacingTokens.md),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 왼쪽: 페이지 인디케이터
                      Row(
                        children: [
                          Text(
                            "${_currentPage + 1}",
                            style: TypographyTokens.body1En.copyWith(
                              fontWeight: FontWeight.w700,
                              color: ColorTokens.primary,
                            ),
                          ),
                          Text(
                            " / 3",
                            style: TypographyTokens.body1En.copyWith(
                              fontWeight: FontWeight.w600,
                              color: ColorTokens.secondary
                            ),
                          ),
                        ],
                      ),
                      
                      // 오른쪽: 건너뛰기 버튼
                      TextButton(
                        onPressed: _isProcessing ? null : _skipOnboarding,
                        style: TextButton.styleFrom(
                          foregroundColor: ColorTokens.textSecondary,
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 16,
                          ),
                        ),
                        child: Text(
                          'Skip',
                          style: TypographyTokens.button.copyWith(
                            color: ColorTokens.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
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
                      _buildIntroPage(),
                      _buildNameInputPage(),
                      _buildLevelPage(),
                    ],
                  ),
                ),

                // 하단 버튼 영역 (3번째 페이지에서는 다른 버튼)
                Padding(
                  padding: const EdgeInsets.only(bottom: 40.0),
                  child: Row(
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
                          onPressed: _isNextButtonEnabled() ? _nextPage : null,
                          isLoading: _isProcessing,
                          isFullWidth: true,
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

  // 첫 번째 페이지: 앱 소개
  Widget _buildIntroPage() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            "Pikabook은 책으로 하는 중국어 학습을\n도와주는 앱입니다.",
            style: TypographyTokens.subtitle2En.copyWith(
              fontWeight: FontWeight.w600,
              color: ColorTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          
          // 향후 이미지 제공 예정 영역
          Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              color: ColorTokens.primaryverylight,
              borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
              border: Border.all(
                color: ColorTokens.primarylight,
                width: 1,
              ),
            ),
            child: Center(
              child: Text(
                "앱 소개 이미지\n(향후 제공 예정)",
                textAlign: TextAlign.center,
                style: TypographyTokens.body2.copyWith(
                  color: ColorTokens.textSecondary,
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          Text(
            "원서 속 글자를 인식해 스마트한 학습 노트를 만들어 드리는 서비스입니다.",
            style: TypographyTokens.body1.copyWith(
              color: ColorTokens.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // 두 번째 페이지: 이름 입력
  Widget _buildNameInputPage() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            "먼저, 학습하실 분의 이름을 알려주세요.",
            style: TypographyTokens.subtitle2En.copyWith(
              fontWeight: FontWeight.w600,
              color: ColorTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: ColorTokens.surface,
              borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
              border: Border.all(
                color: ColorTokens.primarylight,
                width: 2,
              ),
            ),
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: '이름이나 별명을 알려주세요',
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
              onEditingComplete: () {
                // 입력 완료시 키보드 숨기기
                FocusScope.of(context).unfocus();
                _nextPage();
              },
              textInputAction: TextInputAction.done,
            ),
          ),
        ],
      ),
    );
  }

  // 세 번째 페이지: 학습 수준 선택
  Widget _buildLevelPage() {
    // 세 번째 페이지에서는 키보드 자동으로 숨기기
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
                  text: "중국어 학습 수준",
                  style: TypographyTokens.subtitle2En.copyWith(
                    fontWeight: FontWeight.w800,
                    color: ColorTokens.primary,
                  ),
                ),
                TextSpan(
                  text: "을 알려주세요.",
                  style: TypographyTokens.subtitle2En.copyWith(
                  fontWeight: FontWeight.w600,
                 color: ColorTokens.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // 학습 수준 옵션들
          ..._levelOptions.map((option) => _buildLevelOption(option)),
        ],
      ),
    );
  }

  // 학습 수준 옵션 위젯
  Widget _buildLevelOption(Map<String, String> option) {
    final bool isSelected = _selectedLevel == option['level'];
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedLevel = option['level'];
        });
        
        // 다른 옵션 선택 시 키보드 숨기기
        FocusScope.of(context).unfocus();
      },
      child: Container(
        width: double.infinity, // 전체 너비 사용
        margin: EdgeInsets.only(bottom: SpacingTokens.md),
        padding: EdgeInsets.symmetric(
          horizontal: SpacingTokens.lg,
          vertical: SpacingTokens.md,
        ),
        decoration: BoxDecoration(
          color: ColorTokens.surface,
          borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
          border: Border.all(
            color: isSelected ? ColorTokens.primary : ColorTokens.primarylight,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              option['title']!,
              style: TypographyTokens.body1.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: ColorTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              option['description']!,
              style: TypographyTokens.caption.copyWith(
                color: ColorTokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
