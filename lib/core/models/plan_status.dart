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
    print('🔍 [PlanStatus] fromServerResponse 호출됨');
    print('   planStatus: "$planStatus"');
    print('   testAccountType: "$testAccountType"');
    print('   autoRenewStatus: $autoRenewStatus');
    print('   hasEverUsedTrial: $hasEverUsedTrial');
    print('   isActive: $isActive');
    
    // 테스트 계정 타입 기반 보정
    if (testAccountType != null) {
      print('🔍 [PlanStatus] testAccountType 기반 처리 시작');
      switch (testAccountType) {
        case 'trial-expired':
          // 트라이얼 만료 → 취소되지 않았으면 프리미엄 활성, 취소되었으면 trial_completed
          final result = (autoRenewStatus == true) ? PlanStatus.premiumActive : PlanStatus.trialCompleted;
          print('🎯 [PlanStatus] trial-expired 처리: autoRenewStatus=$autoRenewStatus → $result');
          return result;
        case 'trial-cancelled':
          // 트라이얼 취소 → 만료 후 무료 플랜으로 전환
          print('🎯 [PlanStatus] trial-cancelled 처리 → PlanStatus.trialCancelled');
          return PlanStatus.trialCancelled;
        case 'premium-active':
          print('🎯 [PlanStatus] premium-active 처리 → PlanStatus.premiumActive');
          return PlanStatus.premiumActive;
        case 'premium-cancelled':
          print('🎯 [PlanStatus] premium-cancelled 처리 → PlanStatus.premiumCancelled');
          return PlanStatus.premiumCancelled;
        case 'premium-expired':
          print('🎯 [PlanStatus] premium-expired 처리 → PlanStatus.premiumExpired');
          return PlanStatus.premiumExpired;
        case 'premium-grace':
          print('🎯 [PlanStatus] premium-grace 처리 → PlanStatus.premiumGrace');
          return PlanStatus.premiumGrace;
        default:
          print('🎯 [PlanStatus] 알 수 없는 testAccountType: $testAccountType → 기본 파싱으로 이동');
          break;
      }
    } else {
      print('🔍 [PlanStatus] testAccountType이 null → 기본 파싱으로 이동');
    }

    // 기본 파싱 로직
    final result = fromString(planStatus);
    print('🎯 [PlanStatus] 기본 파싱 결과: "$planStatus" → $result');
    return result;
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