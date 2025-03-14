import 'package:flutter/material.dart';
import '../../models/text_processing_mode.dart';
import '../../services/user_preferences_service.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback? onComplete;

  const OnboardingScreen({Key? key, this.onComplete}) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  final UserPreferencesService _preferencesService = UserPreferencesService();
  int _currentPage = 0;
  TextProcessingMode _selectedMode = TextProcessingMode.languageLearning;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 건너뛰기 버튼
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _finishOnboarding,
                child: const Text('건너뛰기'),
              ),
            ),

            // 페이지 인디케이터
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3, // 온보딩 페이지 수
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentPage == index
                        ? Theme.of(context).primaryColor
                        : Colors.grey.shade300,
                  ),
                ),
              ),
            ),

            // 온보딩 페이지
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                children: [
                  _buildWelcomePage(),
                  _buildPurposePage(),
                  _buildCompletePage(),
                ],
              ),
            ),

            // 다음/시작하기 버튼
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                onPressed: () {
                  if (_currentPage < 2) {
                    _pageController.nextPage(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  } else {
                    _finishOnboarding();
                  }
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: Text(_currentPage < 2 ? '다음' : '시작하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 환영 페이지
  Widget _buildWelcomePage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.book, size: 80, color: Colors.blue),
          const SizedBox(height: 24),
          const Text(
            'Pikabook에 오신 것을 환영합니다!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            '중국어 학습을 위한 최고의 도구, Pikabook과 함께 효과적으로 중국어를 배워보세요.',
            style: TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // 사용 목적 선택 페이지
  Widget _buildPurposePage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '어떤 목적으로 앱을 사용하실 건가요?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // 언어 학습 모드 선택
          _buildModeCard(
            icon: Icons.school,
            title: '언어 학습',
            description: '문장별 번역과 핀인을 제공하여 중국어 학습에 집중합니다.',
            isSelected: _selectedMode == TextProcessingMode.languageLearning,
            onTap: () {
              setState(() {
                _selectedMode = TextProcessingMode.languageLearning;
              });
            },
          ),

          const SizedBox(height: 16),

          // 전문 서적 모드 선택
          _buildModeCard(
            icon: Icons.menu_book,
            title: '전문 서적 읽기',
            description: '전체 텍스트 번역을 제공하여 내용 이해에 집중합니다.',
            isSelected: _selectedMode == TextProcessingMode.professionalReading,
            onTap: () {
              setState(() {
                _selectedMode = TextProcessingMode.professionalReading;
              });
            },
          ),

          const SizedBox(height: 16),
          const Text(
            '걱정 마세요! 나중에 설정에서 언제든지 변경할 수 있습니다.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // 모드 선택 카드
  Widget _buildModeCard({
    required IconData icon,
    required String title,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected
                ? Theme.of(context).primaryColor
                : Colors.grey.shade300,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected ? Colors.blue.shade50 : Colors.white,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 40,
              color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? Theme.of(context).primaryColor
                          : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      color: isSelected
                          ? Colors.blue.shade800
                          : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: Theme.of(context).primaryColor,
              ),
          ],
        ),
      ),
    );
  }

  // 완료 페이지
  Widget _buildCompletePage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, size: 80, color: Colors.green),
          const SizedBox(height: 24),
          const Text(
            '모든 준비가 완료되었습니다!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            _selectedMode == TextProcessingMode.languageLearning
                ? '언어 학습 모드로 중국어 학습을 시작해보세요.'
                : '전문 서적 모드로 중국어 텍스트를 읽어보세요.',
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // 온보딩 완료 및 홈 화면으로 이동
  Future<void> _finishOnboarding() async {
    // 선택한 모드 저장
    await _preferencesService.setDefaultTextProcessingMode(_selectedMode);

    // 온보딩 완료 상태 저장
    await _preferencesService.setOnboardingCompleted(true);

    if (mounted) {
      // 홈 화면으로 이동
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    }

    if (widget.onComplete != null) {
      widget.onComplete!();
    }
  }
}
