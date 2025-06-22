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
  
  /// 첫 번째 노트 생성 여부 저장 키
  static const String _firstNoteCreatedKey = 'first_note_created';
  
  /// 현재 튜토리얼 단계
  static int _currentStep = 0;
  
  /// 튜토리얼 단계 정의
  static final List<TutorialStep> _tutorialSteps = [
    const TutorialStep(
      title: '첫 노트가 만들어졌어요!\n🔍 모르는 단어, 바로 검색해보세요.',
      description: '궁금한 단어를 길게 눌러 선택해 보세요. 한국어와 영어 뜻, 병음까지 함께 보여드려요.',
      imagePath: 'assets/images/ill_note_help_1.png',
    ),
    const TutorialStep(
      title: '📝 외우기 어려운 단어는 플래시카드로 복습',
      description: '단어를 선택한 뒤 ‘플래시카드 만들기’ 를 눌러보세요. 받아쓰기와 단어 복습에 활용할 수 있어요.',
      imagePath: 'assets/images/ill_note_help_2.png',
    ),

    const TutorialStep(
      title: '🔊 원어민 발음을 느리게도 들어보세요.',
      description: '한 번 듣고, 또 천천히 들어보세요. 거북이 버튼을 누르면 느린 속도로 들을 수 있어요.',
      imagePath: 'assets/images/ill_note_help_3.png',
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
    
    // 첫 번째 노트가 생성되었는지 확인
    final firstNoteCreated = prefs.getBool(_firstNoteCreatedKey) ?? false;
    
    if (kDebugMode) {
      debugPrint('NoteTutorial: 첫 번째 노트 생성 여부 = $firstNoteCreated, 튜토리얼 표시 여부 = $firstNoteCreated');
    }
    
    // 첫 번째 노트가 생성되었고 이전에 튜토리얼을 보지 않은 경우에만 표시
    return firstNoteCreated && !hasSeenTutorial;
  }
  
  /// 튜토리얼 표시 완료 저장
  static Future<void> _markTutorialAsShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, true);
    
    if (kDebugMode) {
      debugPrint('NoteTutorial: 튜토리얼 표시 완료로 저장됨');
    }
  }
  
  /// 첫 번째 노트 생성 표시
  static Future<void> markFirstNoteCreated() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_firstNoteCreatedKey, true);
    
    if (kDebugMode) {
      debugPrint('NoteTutorial: 첫 번째 노트 생성 표시됨');
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
                    Expanded(
                      child: Text(
                        currentStep.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
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
                
                const SizedBox(height: 20),
                
                // 컨텐츠 영역 (텍스트와 이미지 side by side)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 설명 영역 (왼쪽)
                    Expanded(
                      child: Text(
                        currentStep.description,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    
                    // 텍스트와 이미지 사이 간격
                    if (currentStep.imagePath != null) const SizedBox(width: 16),
                    
                    // 이미지 영역 (오른쪽, 고정 너비 140)
                    if (currentStep.imagePath != null)
                      Container(
                        width: 140,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              spreadRadius: 1,
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            currentStep.imagePath!,
                            width: 140,
                            fit: BoxFit.contain,
                            // 해상도에 맞는 이미지 사용 (1x, 2x, 3x)
                            scale: MediaQuery.of(context).devicePixelRatio,
                            errorBuilder: (context, error, stackTrace) {
                              if (kDebugMode) {
                                debugPrint('튜토리얼 이미지 로드 실패: ${currentStep.imagePath}, 오류: $error');
                              }
                              // 이미지 로드 실패 시 대체 UI
                              return Container(
                                width: 140,
                                height: 120,
                                color: Colors.grey.shade200,
                                alignment: Alignment.center,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.image_not_supported,
                                      size: 32,
                                      color: Colors.grey.shade400,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '이미지 없음',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
                
                // 버튼 영역
                const SizedBox(height: 32),
                Row(
                  children: [
                    // 이전 버튼 (첫 번째 단계가 아닐 때만)
                    if (_currentStep > 0)
                      Expanded(
                        child: PikaButton(
                          text: '이전',
                          onPressed: () {
                            Navigator.pop(context);
                            _moveToPreviousStep(context);
                          },
                          variant: PikaButtonVariant.outline,
                          isFullWidth: true,
                        ),
                      ),
                    
                    // 버튼 사이 간격
                    if (_currentStep > 0) const SizedBox(width: 12),
                    
                    // 다음/완료 버튼
                    Expanded(
                      child: PikaButton(
                        text: _isLastStep() ? '완료' : '다음',
                        onPressed: () {
                          Navigator.pop(context);
                          _moveToNextStepWithBottomSheet(context);
                        },
                        variant: PikaButtonVariant.primary,
                        isFullWidth: true,
                      ),
                    ),
                  ],
                ),
                
                // 하단 여백
                const SizedBox(height: 8),
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
    await prefs.remove(_firstNoteCreatedKey);
    
    if (kDebugMode) {
      debugPrint('NoteTutorial: 튜토리얼 상태 리셋됨');
    }
  }
} 