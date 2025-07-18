/// 배너 타입 열거형
enum BannerType {
  free,               // 무료 플랜
  trialStarted,       // 🆕 트라이얼 시작
  trialCancelled,     // 프리미엄 체험 취소
  switchToPremium,     // 트라이얼 완료후 월구독 시작
  premiumStarted,     // 🆕 연구독 프리미엄 시작 (무료체험 없이 바로 구매)
  premiumGrace,       // 🆕 Grace Period
  premiumCancelled,   // 🆕 프리미엄 구독 취소
  usageLimitFree,     // 무료 플랜 사용량 한도 → 업그레이드 모달
  usageLimitPremium,  // 프리미엄 플랜 사용량 한도 → 문의 폼
}

extension BannerTypeExtension on BannerType {
  String get name {
    switch (this) {
      case BannerType.free:
        return 'free';
      case BannerType.trialStarted:
        return 'trialStarted';
      case BannerType.trialCancelled:
        return 'trialCancelled';
      case BannerType.switchToPremium:
        return 'switchToPremium';
      case BannerType.premiumStarted:
        return 'premiumStarted';
      case BannerType.premiumGrace:
        return 'premiumGrace';
      case BannerType.premiumCancelled:
        return 'premiumCancelled';
      case BannerType.usageLimitFree:
        return 'usageLimitFree';
      case BannerType.usageLimitPremium:
        return 'usageLimitPremium';
    }
  }

  String get title {
    switch (this) {
      case BannerType.free:
        return '무료 플랜 시작';
      case BannerType.trialStarted:
        return '🎉 프리미엄 무료 체험 시작!';
      case BannerType.trialCancelled:
        return '⏰ 프리미엄 구독 전환 취소됨';
      case BannerType.switchToPremium:
        return '💎 프리미엄 월 구독 시작!';
      case BannerType.premiumStarted:
        return '🎉 프리미엄 연 구독 시작!';
      case BannerType.premiumGrace:
        return '⚠️ 결제 확인 필요';
      case BannerType.premiumCancelled:
        return '⏰ 프리미엄 구독 취소됨';
      case BannerType.usageLimitFree:
        return '⚠️ 사용량 한도 도달';
      case BannerType.usageLimitPremium:
        return '⚠️ 프리미엄 사용량 한도 도달';
    }
  }

  String get subtitle {
    switch (this) {
      case BannerType.free:
        return '무료 플랜이 시작되었습니다. 여유있게 사용하시려면 프리미엄을 구독해 보세요.';
      case BannerType.trialStarted:
        return '7일간 프리미엄 기능을 무료로 사용해보세요.';
      case BannerType.trialCancelled:
        return '체험 기간 종료 시 무료 플랜으로 전환됩니다.';
      case BannerType.switchToPremium:
        return '프리미엄 월 구독으로 전환되었습니다! 피카북을 여유있게 사용해보세요.';
      case BannerType.premiumStarted:
        return '프리미엄 연 구독이 시작되었습니다! 피카북을 여유있게 사용해보세요.';
      case BannerType.premiumGrace:
        return 'App Store에서 결제 정보를 확인해주세요. 확인되지 않으면 구독이 취소될 수 있습니다';
      case BannerType.premiumCancelled:
        return '잔여 기간동안 프리미엄 혜택을 사용하시고 이후 무료로 전환됩니다.';
      case BannerType.usageLimitFree:
        return '프리미엄으로 업그레이드하여 넉넉하게 사용하세요.';
      case BannerType.usageLimitPremium:
        return '추가 사용량이 필요하시면 문의해 주세요';
    }
  }
} 