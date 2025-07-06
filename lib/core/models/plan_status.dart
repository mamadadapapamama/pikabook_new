enum PlanStatus {
  free('free'),
  trialActive('trial_active'),
  trialCancelled('trial_cancelled'), 
  trialCompleted('trial_completed'),
  premiumActive('premium_active'),
  premiumCancelled('premium_cancelled'),
  premiumExpired('premium_expired'),
  premiumGrace('premium_grace'),
  refunded('refunded');

  const PlanStatus(this.value);
  final String value;

  static PlanStatus fromString(String value) {
    // 🔍 서버에서 오는 다양한 형식을 표준 enum으로 매핑
    switch (value) {
      case 'trial':
      case 'trial_active':
        return PlanStatus.trialActive;
      case 'trial_cancelled':
      case 'trialCancelled':
        return PlanStatus.trialCancelled;
      case 'trial_completed':
      case 'trialCompleted':
        return PlanStatus.trialCompleted;
      case 'premium':
      case 'premium_active':
      case 'premiumActive':
        return PlanStatus.premiumActive;
      case 'premium_cancelled':
      case 'premiumCancelled':
        return PlanStatus.premiumCancelled;
      case 'premium_expired':
      case 'premiumExpired':
        return PlanStatus.premiumExpired;
      case 'premium_grace':
      case 'premiumGrace':
        return PlanStatus.premiumGrace;
      case 'refunded':
        return PlanStatus.refunded;
      case 'free':
      default:
        return PlanStatus.free;
    }
  }

  // 🔍 서버 응답과 추가 컨텍스트를 고려한 스마트 파싱
  static PlanStatus fromServerResponse(String planStatus, {
    String? testAccountType,
    bool? hasEverUsedTrial,
    bool? autoRenewStatus,
    bool? isActive,
  }) {
    // 테스트 계정 타입 기반 보정
    if (testAccountType != null) {
      switch (testAccountType) {
        case 'trial-expired':
          // 트라이얼 만료 → 취소되지 않았으면 프리미엄 활성, 취소되었으면 trial_completed
          return (autoRenewStatus == true) ? PlanStatus.premiumActive : PlanStatus.trialCompleted;
        case 'trial-cancelled':
          // 트라이얼 취소 → 만료 후 무료 플랜으로 전환
          return PlanStatus.trialCancelled;
        case 'premium-active':
          return PlanStatus.premiumActive;
        case 'premium-cancelled':
          return PlanStatus.premiumCancelled;
        case 'premium-expired':
          return PlanStatus.premiumExpired;
        case 'premium-grace':
          return PlanStatus.premiumGrace;
      }
    }

    // 기본 파싱 로직
    return fromString(planStatus);
  }

  // 편의 메서드들
  bool get isPremium => [
    PlanStatus.trialCompleted, // 트라이얼 완료 후 프리미엄 전환
    PlanStatus.premiumActive,
    PlanStatus.premiumCancelled,
    PlanStatus.premiumGrace,
  ].contains(this);

  bool get isTrial => [
    PlanStatus.trialActive,
    PlanStatus.trialCancelled,
  ].contains(this);

  bool get isActive => [
    PlanStatus.trialActive,
    PlanStatus.trialCompleted, // 트라이얼 완료 후 프리미엄 활성
    PlanStatus.premiumActive,
    PlanStatus.premiumGrace, // Grace Period도 활성으로 취급
  ].contains(this);

  bool get needsPayment => [
    PlanStatus.premiumExpired,
    PlanStatus.premiumGrace,
    PlanStatus.trialCompleted,
  ].contains(this);
}