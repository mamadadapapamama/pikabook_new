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

  // 편의 메서드들
  bool get isPremium => [
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
    PlanStatus.premiumActive,
    PlanStatus.premiumGrace, // Grace Period도 활성으로 취급
  ].contains(this);

  bool get needsPayment => [
    PlanStatus.premiumExpired,
    PlanStatus.premiumGrace,
    PlanStatus.trialCompleted,
  ].contains(this);
}