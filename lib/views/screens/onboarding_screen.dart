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
        decoration: const BoxDecoration(
          color: Color(0xFFFFF9F1), // 배경색
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
                    child: Text(
                      "${_currentPage + 1} / 3",
                      style: _currentPage == 0 
                          ? TypographyTokens.body1En.copyWith(
                              fontWeight: FontWeight.w700, 
                              color: ColorTokens.primary
                            )
                          : TypographyTokens.body1En.copyWith(
                              fontWeight: FontWeight.w700
                            ),
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
                              foregroundColor: const Color(0xFFFE6A15),
                              side: const BorderSide(
                                color: Color(0xFFFE6A15),
                                width: 1,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: const Text('뒤로'),
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
                              : Text(_currentPage == 2 ? '시작해요!' : '다음으로'),
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
    );
  }

  // 첫 번째 페이지: 이름 입력
  Widget _buildNameInputPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text(
          "Pikabook은 원서 속 글자를 \n인식해 스마트한 학습 노트를 \n만들어 드리는 서비스입니다.\n\n먼저, 학습하실 분의 이름을 \n알려주세요.",
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 24,
            color: Color(0xFF143B34),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFFFFE1D0),
              width: 2,
            ),
          ),
          child: TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              hintText: '이름이나 별명을 알려주세요',
              hintStyle: TextStyle(
                fontFamily: 'Noto Sans KR',
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: Color(0xFF969696),
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            ),
            style: const TextStyle(
              fontFamily: 'Noto Sans KR',
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: Colors.black,
            ),
          ),
        ),
      ],
    );
  }

  // 두 번째 페이지: 사용 목적 선택
  Widget _buildPurposePage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text(
          "Pikabook을 어떤 목적으로 \n사용하실 예정이세요?",
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 24,
            color: Color(0xFF143B34),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        
        // 사용 목적 옵션들
        ..._purposeOptions.map((option) => _buildPurposeOption(option)),
        
        // 다른 목적 선택 시 직접 입력 필드 표시
        if (_selectedPurpose == _purposeOptions[2])
          Container(
            margin: const EdgeInsets.only(top: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFFFE1D0),
                width: 2,
              ),
            ),
            child: TextField(
              controller: _otherPurposeController,
              decoration: const InputDecoration(
                hintText: '사용 목적을 알려주세요',
                hintStyle: TextStyle(
                  fontFamily: 'Noto Sans KR',
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF969696),
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
              style: const TextStyle(
                fontFamily: 'Noto Sans KR',
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: Colors.black,
              ),
            ),
          ),
      ],
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
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFFE6A15) : const Color(0xFFFFE1D0),
            width: 2,
          ),
        ),
        child: Text(
          option,
          style: TextStyle(
            fontFamily: 'Noto Sans KR',
            fontSize: 16,
            fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  // 세 번째 페이지: 번역 모드 선택
  Widget _buildTranslationModePage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Text(
          "원서 번역을 어떻게 해드릴까요?",
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 24,
            color: Colors.black,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "나중에 변경할수 있어요.",
          style: TextStyle(
            fontFamily: 'Noto Sans KR',
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 24),
        
        // 문장별 번역 옵션
        _buildTranslationOption(
          title: "문장별 번역",
          description: "인식된 모든 문장을 한꺼번에 번역해 보여줍니다.\n모르는 단어는 사전 검색 합니다.",
          isSelected: _isSegmentMode,
          onTap: () {
            setState(() {
              _isSegmentMode = true;
            });
          },
        ),
        
        const SizedBox(height: 16),
        
        // 통으로 번역 옵션
        _buildTranslationOption(
          title: "통으로 번역",
          description: "인식된 모든 문장을 한꺼번에 번역해 보여줍니다.\n모르는 단어는 사전 검색 합니다.",
          isSelected: !_isSegmentMode,
          onTap: () {
            setState(() {
              _isSegmentMode = false;
            });
          },
        ),
      ],
    );
  }

  // 번역 모드 옵션 위젯
  Widget _buildTranslationOption({
    required String title,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFFE6A15) : const Color(0xFFFFE1D0),
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 옵션 제목
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Noto Sans KR',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 10),
            
            // 예시 이미지
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F8F8),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "学校开始了。我每天早上七点半上学。我们的学校有很多有趣的课外活动。",
                    style: TextStyle(
                      fontFamily: 'Noto Sans HK',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "학교가 시작했습니다. 나는 매일 아침 7시 30분에 학교에...",
                    style: TextStyle(
                      fontFamily: 'Noto Sans KR',
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF226357),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            
            // 설명 텍스트
            Text(
              description,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF969696),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
