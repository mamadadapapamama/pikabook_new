import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/tokens/color_tokens.dart';
import 'debug_utils.dart';

class TooltipManager {
  bool showTooltip = false;
  int tooltipStep = 1;
  final int totalTooltipSteps = 3;
  
  // 툴팁 UI 구성
  Widget buildTooltip(BuildContext context, {
    required Function onDismiss,
    required Function onNextStep,
    required Function onPrevStep
  }) {
    return Positioned(
      bottom: 80,
      left: 16,
      right: 16,
      child: Material(
        elevation: 0,
        color: Colors.transparent,
        child: HelpTextTooltip(
          key: const Key('note_detail_tooltip'),
          text: tooltipStep == 1 
            ? "첫 노트가 만들어졌어요!" 
            : tooltipStep == 2
              ? "다음 페이지로 이동은 스와이프나 화살표로!"
              : "불필요한 텍스트는 지워요.",
          description: tooltipStep == 1
            ? "모르는 단어는 선택하여 사전 검색 하거나, 플래시카드를 만들어 복습해 볼수 있어요."
            : tooltipStep == 2
              ? "노트의 빈 공간을 왼쪽으로 슬라이드하거나, 바텀 바의 화살표를 눌러 다음 장으로 넘어갈 수 있어요."
              : "잘못 인식된 문장은 왼쪽으로 슬라이드해 삭제할수 있어요.",
          showTooltip: showTooltip,
          onDismiss: () => onDismiss(),
          backgroundColor: ColorTokens.primaryverylight,
          borderColor: ColorTokens.primary,
          textColor: ColorTokens.textPrimary,
          tooltipPadding: const EdgeInsets.all(16),
          tooltipWidth: MediaQuery.of(context).size.width - 32,
          spacing: 8.0,
          style: HelpTextTooltipStyle.primary,
          image: Image.asset(
            tooltipStep == 1 
              ? 'assets/images/note_help_1.png'
              : tooltipStep == 2
                ? 'assets/images/note_help_2.png'
                : 'assets/images/note_help_3.png',
            width: double.infinity,
            fit: BoxFit.contain,
          ),
          currentStep: tooltipStep,
          totalSteps: totalTooltipSteps,
          onNextStep: () => onNextStep(),
          onPrevStep: () => onPrevStep(),
        ),
      ),
    );
  }
  
  void handleTooltipDismiss() {
    DebugUtils.log('📝 노트 상세 화면에서 툴팁 닫기 버튼 클릭됨!!');
    
    showTooltip = false;
    tooltipStep = 1; // 툴팁 단계 초기화
    
    // 툴팁 표시 완료 상태 저장
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('note_detail_tooltip_shown', true);
      DebugUtils.log('📝 툴팁 표시 완료 상태 저장 성공');
    });
  }
  
  // 툴팁 표시 여부 확인
  Future<void> checkAndShowInitialTooltip() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bool tooltipShown = prefs.getBool('note_detail_tooltip_shown') ?? false;
      
      if (!tooltipShown) {
        showTooltip = true;
        tooltipStep = 1;
        DebugUtils.log('📝 첫 방문으로 툴팁 표시 활성화');
      }
    } catch (e) {
      DebugUtils.log('📝 툴팁 상태 확인 중 오류: $e');
    }
  }
  
  void setTooltipStep(int step) {
    if (step >= 1 && step <= totalTooltipSteps) {
      tooltipStep = step;
    }
  }
}
