import 'package:flutter/material.dart';
import 'package:pikabook_new/core/theme/tokens/color_tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:pikabook_new/core/theme/tokens/color_tokens.dart';
import 'package:pikabook_new/core/widgets/pika_button.dart';

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
      imagePath: 'assets/images/note_help_1.png',
    ),
    const TutorialStep(
      title: '불필요한 문장은 지워요',
      description: '잘못 인식된 문장은 왼쪽으로 스와이프 하면 지울수 있어요.',
      imagePath: 'assets/images/note_help_3.png',
    ),
  ];
  
  /// 튜토리얼 표시 여부 확인
  static Future<bool> _shouldShowTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 이미 튜토리얼을 봤는지 확인
    final hasSeenTutorial = prefs.getBool(_prefKey) ?? false;
    
    // 이미 봤으면 다시 표시하지 않음
    if (hasSeenTutorial) {
      if (kDebugMode) {
        debugPrint('NoteTutorial: 이미 튜토리얼을 본 상태, 다시 표시하지 않음');
      }
      return false;
    }
    
    // 노트 개수가 1개인 경우에만 표시
    final noteCount = prefs.getInt(_noteCountKey) ?? 0;
    
    if (kDebugMode) {
      debugPrint('NoteTutorial: 현재 노트 개수 = $noteCount, 튜토리얼 표시 여부 = ${noteCount == 1}, 이전에 봤는지 여부 = $hasSeenTutorial');
    }
    
    // 노트가 1개이고 이전에 튜토리얼을 보지 않은 경우에만 표시
    return noteCount == 1 && !hasSeenTutorial;
  }
  
  /// 노트 개수 업데이트
  static Future<void> updateNoteCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    
    // 저장 전 현재 값 확인
    final currentCount = prefs.getInt(_noteCountKey) ?? 0;
    
    if (kDebugMode) {
      debugPrint('NoteTutorial: 노트 개수 업데이트 시작 - 현재=$currentCount, 새 값=$count');
    }
    
    // 노트 개수 저장
    await prefs.setInt(_noteCountKey, count);
    
    // 저장 후 확인
    final savedCount = prefs.getInt(_noteCountKey) ?? 0;
    
    if (kDebugMode) {
      debugPrint('NoteTutorial: 노트 개수 업데이트 완료 - 저장된 값=$savedCount');
    }
  }
  
  /// 튜토리얼 표시 완료 저장
  static Future<void> _markTutorialAsShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
    
    if (kDebugMode) {
      debugPrint('NoteTutorial: 튜토리얼 표시 완료로 저장됨');
    }
  }
  
  /// 튜토리얼을 표시하고 확인하는 메서드
  static Future<void> checkAndShowTutorial(BuildContext context) async {
    // 튜토리얼을 표시해야 하는지 확인
    final shouldShow = await _shouldShowTutorial();
    
    if (kDebugMode) {
      debugPrint('NoteTutorial: 튜토리얼 표시 여부 검사 결과 = $shouldShow');
    }
    
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
    
    // 기존 배너가 있으면 제거
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
    
    // 화면 크기 가져오기
    final screenWidth = MediaQuery.of(context).size.width;
    
    // 스낵바 스타일의 바텀 시트로 표시
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: ColorTokens.surface,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                spreadRadius: 1,
                blurRadius: 10,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더 영역
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 제목 영역
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: ColorTokens.primaryverylight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.lightbulb,
                            color: ColorTokens.primary,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          currentStep.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                    
                    // 현재 단계 표시
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_currentStep + 1}/${_tutorialSteps.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
                
                // 이미지 영역 (이미지가 있는 경우)
                if (currentStep.imagePath != null) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: Container(
                      width: screenWidth * 0.9,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            spreadRadius: 1,
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          currentStep.imagePath!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            if (kDebugMode) {
                              debugPrint('튜토리얼 이미지 로드 실패: ${currentStep.imagePath}, 오류: $error');
                            }
                            // 이미지 로드 실패 시 대체 UI
                            return Container(
                              height: 150,
                              color: Colors.grey.shade200,
                              alignment: Alignment.center,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.image_not_supported,
                                    size: 48,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '이미지를 표시할 수 없습니다',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
                
                // 설명 영역
                const SizedBox(height: 16),
                Text(
                  currentStep.description,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Colors.black,
                  ),
                ),
                
                // 버튼 영역
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 첫 번째 단계가 아닐 때만 이전 버튼 표시
                    if (_currentStep > 0)
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context); // 바텀 시트 닫기
                          _moveToPreviousStep(context);
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: ColorTokens.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          minimumSize: const Size(80, 40),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.arrow_back_ios, size: 12, color: ColorTokens.primary),
                            const SizedBox(width: 4),
                            const Text(
                              '이전',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      // 이전 버튼이 없을 때 균형을 맞추기 위한 빈 공간
                      const SizedBox(width: 40),
                    
                    // 이전 버튼과 다음 버튼 사이 간격
                    const SizedBox(width: 60),
                    
                    // 다음/완료 버튼 (outline 스타일)
                    OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context); // 바텀 시트 닫기
                        _moveToNextStepWithBottomSheet(context);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ColorTokens.primary,
                        side: BorderSide(color: ColorTokens.primary),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        minimumSize: const Size(80, 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isLastStep() ? '완료' : '다음',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (!_isLastStep()) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.arrow_forward_ios, size: 12, color: ColorTokens.primary),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                // 하단 여백 추가
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
  
  /// 다음 단계로 이동 (바텀 시트 버전)
  static void _moveToNextStepWithBottomSheet(BuildContext context) {
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
  
  /// 다음 단계로 이동 (기존 메서드는 보존)
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
  
  /// 이전 단계로 이동
  static void _moveToPreviousStep(BuildContext context) {
    // 이미 첫 번째 단계면 아무것도 하지 않음
    if (_currentStep <= 0) {
      return;
    }
    
    // 이전 단계로 이동
    _currentStep--;
    
    // 튜토리얼 배너 표시
    _showTutorialBanner(context);
  }
  
  /// 디버깅용: 튜토리얼 상태 리셋
  static Future<void> resetTutorialState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    await prefs.remove(_noteCountKey);
    
    if (kDebugMode) {
      debugPrint('NoteTutorial: 튜토리얼 상태 리셋됨');
    }
  }
} 