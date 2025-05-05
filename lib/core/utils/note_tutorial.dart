import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 튜토리얼의 각 단계를 나타내는 모델 클래스 (로컬 정의)
class TutorialStep {
  /// 제목
  final String title;
  
  /// 설명
  final String description;
  
  /// 이미지 경로 (없을 수 있음)
  final String? imagePath;
  
  const TutorialStep({
    required this.title,
    required this.description,
    this.imagePath,
  });
}

/// 노트 튜토리얼 관리 유틸리티 클래스
class NoteTutorial {
  /// 튜토리얼 표시 여부 저장 키
  static const String _prefKey = 'has_seen_note_tutorial';
  
  /// 노트 개수 저장 키
  static const String _noteCountKey = 'note_count';
  
  /// 현재 튜토리얼 단계
  static int _currentStep = 0;
  
  /// 튜토리얼 단계 정의
  static final List<TutorialStep> _tutorialSteps = [
    const TutorialStep(
      title: '첫 노트가 만들어졌어요!',
      description: '스마트 노트가 만들어졌습니다. 모르는 단어가 있으면 선택해 사전 검색이나 플래시카드로 만들어 보세요.',
      imagePath: 'assets/images/tutorial/note_help_1.png',
    ),
    const TutorialStep(
      title: '불필요한 문장은 지워요',
      description: '잘못 인식된 문장은 왼쪽으로 스와이프 하면 지울수 있어요.',
      imagePath: 'assets/images/tutorial/note_help_3.png',
    ),
  ];
  
  /// 튜토리얼 표시 여부 확인
  static Future<bool> _shouldShowTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenTutorial = prefs.getBool(_prefKey) ?? false;
    
    // 이미 튜토리얼을 봤으면 표시하지 않음
    if (hasSeenTutorial) return false;
    
    // 노트 개수가 1개인 경우에만 표시
    final noteCount = prefs.getInt(_noteCountKey) ?? 0;
    
    // 노트가 처음 생성된 경우 (0에서 1로 변경)
    if (noteCount == 1) {
      return true;
    }
    
    return false;
  }
  
  /// 노트 개수 업데이트
  static Future<void> updateNoteCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_noteCountKey, count);
  }
  
  /// 튜토리얼 표시 완료 저장
  static Future<void> _markTutorialAsShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
  }
  
  /// 튜토리얼을 표시하고 확인하는 메서드
  static Future<void> checkAndShowTutorial(BuildContext context) async {
    // 튜토리얼을 표시해야 하는지 확인
    final shouldShow = await _shouldShowTutorial();
    if (!shouldShow) return;
    
    // 현재 단계 초기화
    _currentStep = 0;
    
    // 첫 번째 튜토리얼 배너 표시
    if (context.mounted) {
      _showTutorialBanner(context);
    }
  }
  
  /// 튜토리얼 배너 표시
  static void _showTutorialBanner(BuildContext context) {
    if (_currentStep >= _tutorialSteps.length) return;
    
    final currentStep = _tutorialSteps[_currentStep];
    
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  currentStep.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_currentStep + 1}/${_tutorialSteps.length}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            if (currentStep.imagePath != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  currentStep.imagePath!,
                  height: 120,
                  fit: BoxFit.contain,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(currentStep.description),
          ],
        ),
        actions: [
          TextButton(
            child: Text(_isLastStep() ? '완료' : '다음'),
            onPressed: () => _moveToNextStep(context),
          ),
        ],
        backgroundColor: Colors.white,
        padding: const EdgeInsets.all(12),
        leadingPadding: EdgeInsets.zero,
      ),
    );
  }
  
  /// 다음 단계로 이동
  static void _moveToNextStep(BuildContext context) {
    // 현재 배너 닫기
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
    
    // 마지막 단계라면 완료 처리
    if (_isLastStep()) {
      _markTutorialAsShown();
      _currentStep = 0; // 초기화
      return;
    }
    
    // 다음 단계로 이동
    _currentStep++;
    
    // 다음 배너 표시
    _showTutorialBanner(context);
  }
  
  /// 마지막 단계인지 확인
  static bool _isLastStep() => _currentStep == _tutorialSteps.length - 1;
  
  /// 디버깅용: 튜토리얼 상태 리셋
  static Future<void> resetTutorialState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    await prefs.remove(_noteCountKey);
  }
} 