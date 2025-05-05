/**
 * 경고: 이 클래스는 현재 사용되지 않습니다.
 * 대신 lib/core/utils/note_tutorial.dart 파일의 NoteTutorial 클래스를 사용하세요.
 * 이 클래스는 향후 제거될 예정입니다.
 */

/*
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 튜토리얼 단계를 나타내는 모델 클래스
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

/// 노트 튜토리얼 관리 서비스
class NoteTutorialService {
  /// 튜토리얼 표시 여부 저장 키
  static const String _prefKey = 'has_seen_note_tutorial';
  
  /// 싱글톤 인스턴스
  static final NoteTutorialService _instance = NoteTutorialService._internal();
  
  /// 싱글톤 팩토리 생성자
  factory NoteTutorialService() => _instance;
  
  /// 내부 생성자
  NoteTutorialService._internal();
  
  /// 현재 표시 중인 단계
  int _currentStep = 0;
  
  /// 튜토리얼을 표시해야 하는지 확인
  Future<bool> shouldShowTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenTutorial = prefs.getBool(_prefKey) ?? false;
    
    if (hasSeenTutorial) return false;
    
    // 여기서 노트 개수가 1인지 확인
    // 실제 구현에서는 NotesRepository().getNoteCount() == 1 방식으로 확인
    // 예시 코드에서는 항상 true를 반환
    return true;
  }
  
  /// 튜토리얼 표시 완료 저장
  Future<void> markTutorialAsShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
  }
  
  /// 디버깅용: 튜토리얼 상태 리셋
  Future<void> resetTutorialState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
  }
  
  /// 튜토리얼 단계 표시
  void showTutorialBanner(
    BuildContext context, 
    List<TutorialStep> steps,
  ) {
    if (steps.isEmpty || _currentStep >= steps.length) return;
    
    final currentStep = steps[_currentStep];
    
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
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_currentStep + 1}/${steps.length}',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            if (currentStep.imagePath != null) ...[
              SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  currentStep.imagePath!,
                  height: 120,
                  fit: BoxFit.contain,
                ),
              ),
            ],
            SizedBox(height: 8),
            Text(currentStep.description),
          ],
        ),
        actions: [
          TextButton(
            child: Text(_isLastStep(steps) ? '완료' : '다음'),
            onPressed: () => _moveToNextStep(context, steps),
          ),
        ],
        backgroundColor: Colors.white,
        padding: EdgeInsets.all(12),
        leadingPadding: EdgeInsets.zero,
      ),
    );
  }
  
  /// 다음 단계로 이동
  void _moveToNextStep(BuildContext context, List<TutorialStep> steps) {
    // 현재 배너 닫기
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
    
    // 마지막 단계라면 완료 처리
    if (_isLastStep(steps)) {
      markTutorialAsShown();
      _currentStep = 0; // 초기화
      return;
    }
    
    // 다음 단계로 이동
    _currentStep++;
    
    // 다음 배너 표시
    showTutorialBanner(context, steps);
  }
  
  /// 마지막 단계인지 확인
  bool _isLastStep(List<TutorialStep> steps) => 
      _currentStep == steps.length - 1;
}
*/
