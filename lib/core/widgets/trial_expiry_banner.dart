import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../services/trial/trial_manager.dart';

class TrialExpiryBanner extends StatelessWidget {
  final VoidCallback? onUpgradePressed;
  final VoidCallback? onDismiss;

  const TrialExpiryBanner({
    super.key,
    this.onUpgradePressed,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            ColorTokens.primary.withOpacity(0.1),
            ColorTokens.secondary.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ColorTokens.primary.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // 아이콘
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ColorTokens.primary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.access_time_rounded,
              color: ColorTokens.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          
          // 텍스트 내용
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '무료체험 내일 종료',
                  style: TypographyTokens.body1Bold.copyWith(
                    color: ColorTokens.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '프리미엄 구독하고 계속 학습하세요!',
                  style: TypographyTokens.body2.copyWith(
                    color: ColorTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          
          // 버튼들
          Column(
            children: [
              // 업그레이드 버튼
              ElevatedButton(
                onPressed: onUpgradePressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: ColorTokens.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  minimumSize: const Size(0, 32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  '구독하기',
                  style: TypographyTokens.body2.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              
              // 닫기 버튼
              TextButton(
                onPressed: onDismiss,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(0, 24),
                ),
                child: Text(
                  '닫기',
                  style: TypographyTokens.body2.copyWith(
                    color: ColorTokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 무료체험 만료 상태를 관리하는 클래스
class TrialExpiryManager {
  static const String _dismissedKey = 'trial_expiry_banner_dismissed';
  
  /// 무료체험 만료 1일 전인지 확인
  static bool shouldShowExpiryBanner() {
    final trialManager = TrialManager();
    
    // 무료체험 중이 아니면 배너 표시 안함
    if (!trialManager.isTrialActive) {
      return false;
    }
    
    final trialEndDate = trialManager.trialEndDate;
    if (trialEndDate == null) {
      return false;
    }
    
    final now = DateTime.now();
    
    // 무료체험이 내일 또는 오늘 종료되는 경우
    final daysDifference = trialEndDate.difference(now).inDays;
    
    return daysDifference <= 1 && daysDifference >= 0;
  }
  
  /// 배너가 오늘 이미 닫혔는지 확인
  static Future<bool> isBannerDismissedToday() async {
    // SharedPreferences를 사용하여 오늘 날짜로 닫기 상태 확인
    // 간단하게 구현하기 위해 여기서는 false 반환
    // 실제로는 SharedPreferences에서 날짜별로 관리해야 함
    return false;
  }
  
  /// 배너 닫기 상태 저장
  static Future<void> dismissBannerForToday() async {
    // SharedPreferences에 오늘 날짜로 닫기 상태 저장
    // 실제 구현 시 날짜별 관리 필요
  }
} 