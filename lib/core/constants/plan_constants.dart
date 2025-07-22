/// 플랜 관련 상수 정의
class PlanConstants {
  // 플랜 유형
  static const String PLAN_FREE = '무료';
  static const String PLAN_PREMIUM = '프리미엄';
  
  // 플랜별 제한값
  static const Map<String, Map<String, int>> PLAN_LIMITS = {
    PLAN_FREE: {
      'ocrPages': 30,          // 월 30장 (업로드 이미지 수)
      'ttsRequests': 50,       // 월 50회 (듣기 기능)
    },
    PLAN_PREMIUM: {
      'ocrPages': 300,         // 월 300장 (업로드 이미지 수)
      'ttsRequests': 1000,     // 월 1,000회 (듣기 기능)
    },
  };
  
  /// 플랜 이름 가져오기 (표시용)
  static String getPlanName(String planType, {bool showBadge = false}) {
    switch (planType) {
      case PLAN_PREMIUM:
        return '프리미엄';
      case PLAN_FREE:
      default:
        return showBadge ? '무료 플랜' : '무료';
    }
  }
  
  /// 플랜별 기능 제한 정보 가져오기
  static Map<String, int> getPlanLimits(String planType) {
    return Map<String, int>.from(PLAN_LIMITS[planType] ?? PLAN_LIMITS[PLAN_FREE]!);
  }
  
  /// 사용자의 구독 업그레이드 여부 확인
  static bool canUpgradePlan(String currentPlan) {
    return currentPlan != PLAN_PREMIUM;
  }
} 