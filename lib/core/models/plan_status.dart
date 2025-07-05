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
    // 🔍 서버에서 "trial"로 오는 경우 "trial_active"로 매핑
    if (value == 'trial') {
      return PlanStatus.trialActive;
    }
    
    return PlanStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => PlanStatus.free,
    );
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