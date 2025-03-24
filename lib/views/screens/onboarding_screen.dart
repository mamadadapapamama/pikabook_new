import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/user_preferences_service.dart';
import '../../theme/tokens/color_tokens.dart';
import '../../theme/tokens/typography_tokens.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({Key? key, required this.onComplete}) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  final UserPreferencesService _userPreferences = UserPreferencesService();
  
  // 상태 변수
  int _currentPage = 0;
  bool _isProcessing = false;
  
  // 사용자 이름
  final TextEditingController _nameController = TextEditingController();
  
  // 앱 사용 목적
  String? _selectedPurpose;
  final TextEditingController _otherPurposeController = TextEditingController();
  
  // 번역 모드
  bool _isSegmentMode = true; // true: 문장별 번역, false: 통으로 번역
  
  // 사용 목적 옵션
  final List<String> _purposeOptions = [
    '제가 직접 원서를 공부할 예정이에요',
    '아이의 원서 학습을 돕고 싶어요',
    '다른 목적으로 활용할 예정이에요'
  ];

  @override
  void initState() {
    super.initState();
    // 입력 변경 리스너 추가
    _nameController.addListener(_updateState);
    _otherPurposeController.addListener(_updateState);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.removeListener(_updateState);
    _otherPurposeController.removeListener(_updateState);
    _nameController.dispose();
    _otherPurposeController.dispose();
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
      return _nameController.text.trim().isNotEmpty;
    } else if (_currentPage == 1) {
      if (_selectedPurpose == null) return false;
      if (_selectedPurpose == _purposeOptions[2] && 
          _otherPurposeController.text.trim().isEmpty) {
        return false;
      }
      return true;
    }
    
    return true;
  }

  // 다음 페이지로 이동
  void _nextPage() {
    // 첫 번째 페이지에서 두 번째 페이지로 갈 때는 이름이 입력되었는지 확인
    if (_currentPage == 0) {
      final name = _nameController.text.trim();
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이름을 입력해주세요')),
        );
        return;
      }
    }
    
    // 두 번째 페이지에서 세 번째 페이지로 갈 때는 목적이 선택되었는지 확인
    if (_currentPage == 1) {
      if (_selectedPurpose == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사용 목적을 선택해주세요')),
        );
        return;
      }
      
      // 세 번째 옵션 선택 시 직접 입력 확인
      if (_selectedPurpose == _purposeOptions[2] && _otherPurposeController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사용 목적을 입력해주세요')),
        );
        return;
      }
    }

    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finishOnboarding();
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

  // 온보딩 데이터 저장 및 완료 처리
  Future<void> _completeOnboarding() async {
    try {
      // 사용자 이름 저장
      final userName = _nameController.text.trim();
      
      // 목적 저장
      final purpose = _selectedPurpose == _purposeOptions[2]
          ? _otherPurposeController.text.trim()
          : _selectedPurpose;
          
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
      
      // 사용 목적 저장
      await _userPreferences.setLearningPurpose(purpose ?? '');
      
      // Firestore에 사용자 데이터 저장
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'userName': userName,
          'learningPurpose': purpose,
          'translationMode': _isSegmentMode ? 'segment' : 'full',
          'hasOnboarded': true,
          'onboardingCompleted': true,
          'defaultNoteSpace': noteSpaceName,
        });
      }
      
      // 온보딩 완료 표시
      await _userPreferences.setOnboardingCompleted(true);
      await _userPreferences.setHasOnboarded(true);
      
      if (mounted) {
        widget.onComplete();
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('설정 저장 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          color: ColorTokens.background, // 디자인 토큰 사용
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                // 상단 로고 영역
                const SizedBox(height: 44),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: Image.asset('assets/images/pikabird_80x80.png'),
                    ),
                  ],
                ),
                
                // 페이지 인디케이터 (현재 페이지/전체 페이지)
                Padding(
                  padding: const EdgeInsets.only(top: 24.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
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
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
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
                      _buildNameInputPage(),
                      _buildPurposePage(),
                      _buildTranslationModePage(),
                    ],
                  ),
                ),

                // 하단 버튼 영역
                Padding(
                  padding: const EdgeInsets.only(bottom: 40.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 뒤로 버튼 (첫 페이지에서는 숨김)
                      if (_currentPage > 0)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _prevPage,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: ColorTokens.primary,
                              side: BorderSide(
                                color: ColorTokens.primary,
                                width: 1,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Text('뒤로', style: TypographyTokens.button),
                          ),
                        ),
                        
                      // 뒤로 버튼과 다음 버튼 사이 간격
                      if (_currentPage > 0)
                        const SizedBox(width: 16),
                        
                      // 다음 버튼
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isNextButtonEnabled() ? _nextPage : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ColorTokens.primary,
                            disabledBackgroundColor: ColorTokens.disabled,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _isProcessing
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : Text(
                                  _currentPage == 2 ? '시작해요!' : '다음으로',
                                  style: TypographyTokens.button,
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

  // 첫 번째 페이지: 이름 입력
  Widget _buildNameInputPage() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            "Pikabook",
            style: TypographyTokens.subtitle1En.copyWith(
              fontWeight: FontWeight.w900,
              color: ColorTokens.primary,
            ),
          ),
          Text(
            "은 원서 속 글자를 인식해\n 스마트한 학습 노트를 만들어 드리는 서비스입니다.\n\n먼저, 학습하실 분의 이름을 알려주세요.",
            style: TypographyTokens.subtitle1.copyWith(
              fontWeight: FontWeight.w700,
              color: ColorTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: ColorTokens.primarylight,
                width: 2,
              ),
            ),
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: '이름이나 별명을 알려주세요',
                hintStyle: TypographyTokens.body2.copyWith(
                  color: ColorTokens.textTertiary,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
              style: TypographyTokens.body2.copyWith(
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

  // 두 번째 페이지: 사용 목적 선택
  Widget _buildPurposePage() {
    // 두 번째 페이지에서는 키보드 자동으로 숨기기
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_currentPage == 1 && _selectedPurpose != _purposeOptions[2]) {
        FocusScope.of(context).unfocus();
      }
    });

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            "Pikabook",
            style: TypographyTokens.subtitle1En.copyWith(
              fontWeight: FontWeight.w900,
              color: ColorTokens.primary,
            ),
          ),
          Text(
            "을 어떤 목적으로 \n사용하실 예정이세요?",
            style: TypographyTokens.subtitle1.copyWith(
              fontWeight: FontWeight.w700,
              color: ColorTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 24),
          // 사용 목적 옵션들
          ..._purposeOptions.map((option) => _buildPurposeOption(option)),
          // 다른 목적 선택 시 직접 입력 필드 표시
          if (_selectedPurpose == _purposeOptions[2])
            Container(
              width: double.infinity, // 전체 너비 사용
              margin: const EdgeInsets.only(top: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: ColorTokens.primarylight,
                  width: 2,
                ),
              ),
              child: TextField(
                controller: _otherPurposeController,
                autofocus: _selectedPurpose == _purposeOptions[2],
                decoration: InputDecoration(
                  hintText: '사용 목적을 알려주세요',
                  hintStyle: TypographyTokens.body2.copyWith(
                    color: ColorTokens.textTertiary,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
                style: TypographyTokens.body2.copyWith(
                  color: ColorTokens.textPrimary,
                ),
                onEditingComplete: () {
                  FocusScope.of(context).unfocus();
                  _nextPage();
                },
                textInputAction: TextInputAction.done,
              ),
            ),
          // 키보드가 표시될 때 추가 여백
          SizedBox(height: _selectedPurpose == _purposeOptions[2] ? 200 : 0),
        ],
      ),
    );
  }

  // 사용 목적 옵션 위젯
  Widget _buildPurposeOption(String option) {
    final bool isSelected = _selectedPurpose == option;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPurpose = option;
        });
        
        // 세 번째 옵션 선택 시 키보드 표시
        if (option == _purposeOptions[2]) {
          // 약간 딜레이를 주고 포커스 설정
          Future.delayed(const Duration(milliseconds: 100), () {
            // 입력 필드에 초점 맞추고 키보드 표시
            FocusScope.of(context).requestFocus(FocusNode());
            _otherPurposeController.clear();
            
            // 스크롤 조정
            final ScrollController scrollController = ScrollController();
            if (scrollController.hasClients) {
              scrollController.animateTo(
                200,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            }
          });
        } else {
          // 다른 옵션 선택 시 키보드 숨기기
          FocusScope.of(context).unfocus();
        }
      },
      child: Container(
        width: double.infinity, // 전체 너비 사용
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? ColorTokens.primary : ColorTokens.primarylight,
            width: 2,
          ),
        ),
        child: Text(
          option,
          style: TypographyTokens.body2.copyWith(
            fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
            color: ColorTokens.textPrimary,
          ),
        ),
      ),
    );
  }

  // 세 번째 페이지: 번역 모드 선택
  Widget _buildTranslationModePage() {
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
          Text(
            "원서 번역을 어떻게 해드릴까요?",
            style: TypographyTokens.subtitle1.copyWith(
              fontWeight: FontWeight.w700,
              color: ColorTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "나중에 변경할수 있어요.",
            style: TypographyTokens.body2.copyWith(
              color: ColorTokens.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          
          // Figma 디자인에 맞게 번역 모드 옵션 업데이트
          _buildUpdatedTranslationOption(
            title: "문장별 번역",
            description: "각 문장별로 번역해 보여줍니다.\n모르는 단어는 탭해서 사전 검색할 수 있어요.",
            isSelected: _isSegmentMode,
            onTap: () {
              setState(() {
                _isSegmentMode = true;
              });
            },
          ),
          
          const SizedBox(height: 16),
          
          _buildUpdatedTranslationOption(
            title: "통으로 번역",
            description: "인식된 모든 문장을 통으로 번역해 보여줍니다.\n모르는 단어는 탭해서 사전 검색할 수 있어요.",
            isSelected: !_isSegmentMode,
            onTap: () {
              setState(() {
                _isSegmentMode = false;
              });
            },
          ),
        ],
      ),
    );
  }

  // 업데이트된 번역 모드 옵션 위젯 (Figma 디자인에 맞게)
  Widget _buildUpdatedTranslationOption({
    required String title,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? ColorTokens.primary : ColorTokens.primarylight,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 옵션 제목
            Text(
              title,
              style: TypographyTokens.body2.copyWith(
                fontWeight: FontWeight.w500,
                color: ColorTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            
            // 예시 컨테이너
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8F8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 원문 텍스트
                  Text(
                    title == "문장별 번역" 
                      ? "学校开始了。" 
                      : "学校开始了。我每天早上七点半上学。我们的学校有很多有趣的课外活动。",
                    style: TypographyTokens.body2.copyWith(
                      fontFamily: 'Noto Sans HK',
                      fontWeight: FontWeight.w500,
                      color: ColorTokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // 번역 텍스트
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFFEEEEEE),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      title == "문장별 번역" 
                        ? "학교가 시작했습니다." 
                        : "학교가 시작했습니다. 나는 매일 아침 7시 30분에 등교합니다. 우리 학교에는 흥미로운 특별활동이 많이 있습니다.",
                      style: TypographyTokens.body2.copyWith(
                        color: ColorTokens.textSecondary,
                      ),
                    ),
                  ),
                  
                  // 문장별 번역일 경우 다음 문장 표시
                  if (title == "문장별 번역") ...[
                    const SizedBox(height: 12),
                    Text(
                      "我每天早上七点半上学。",
                      style: TypographyTokens.body2.copyWith(
                        fontFamily: 'Noto Sans HK',
                        fontWeight: FontWeight.w500,
                        color: ColorTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFFEEEEEE),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        "나는 매일 아침 7시 30분에 등교합니다.",
                        style: TypographyTokens.body2.copyWith(
                          color: ColorTokens.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            
            // 설명 텍스트
            Text(
              description,
              style: TypographyTokens.caption.copyWith(
                color: ColorTokens.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
