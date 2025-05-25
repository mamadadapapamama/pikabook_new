import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/tokens/color_tokens.dart';
import 'debug_utils.dart';

// 툴팁 스타일 정의
enum HelpTextTooltipStyle {
  primary,
  secondary,
  info
}

// 커스텀 툴팁 위젯
class HelpTextTooltip extends StatelessWidget {
  final String text;
  final String description;
  final bool showTooltip;
  final VoidCallback onDismiss;
  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;
  final EdgeInsets tooltipPadding;
  final double tooltipWidth;
  final double spacing;
  final HelpTextTooltipStyle style;
  final Widget? image;
  final int currentStep;
  final int totalSteps;
  final VoidCallback onNextStep;
  final VoidCallback onPrevStep;

  const HelpTextTooltip({
    Key? key,
    required this.text,
    required this.description,
    required this.showTooltip,
    required this.onDismiss,
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
    required this.tooltipPadding,
    required this.tooltipWidth,
    required this.spacing,
    required this.style,
    this.image,
    required this.currentStep,
    required this.totalSteps,
    required this.onNextStep,
    required this.onPrevStep,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!showTooltip) return const SizedBox.shrink();

    return Container(
      width: tooltipWidth,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: tooltipPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onDismiss,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close,
                    size: 20,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: spacing),
          Text(
            description,
            style: TextStyle(
              fontSize: 14,
              color: textColor,
            ),
          ),
          if (image != null) ...[
            SizedBox(height: spacing),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: image,
            ),
          ],
          SizedBox(height: spacing),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 스텝 인디케이터
              Row(
                children: List.generate(
                  totalSteps,
                  (index) => Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: index == currentStep - 1
                          ? borderColor
                          : Colors.grey.withOpacity(0.3),
                    ),
                  ),
                ),
              ),
              
              // 이전/다음 버튼
              Row(
                children: [
                  if (currentStep > 1)
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios, size: 16),
                      onPressed: onPrevStep,
                      color: textColor,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  if (currentStep < totalSteps) ...[
                    const SizedBox(width: 16),
                    IconButton(
                      icon: const Icon(Icons.arrow_forward_ios, size: 16),
                      onPressed: onNextStep,
                      color: textColor,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
