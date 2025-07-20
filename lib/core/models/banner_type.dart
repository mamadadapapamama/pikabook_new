import '../constants/subscription_constants.dart';

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

  /// 🎯 중앙화된 상수에서 배너 텍스트 가져오기
  String get title {
    final bannerTexts = SubscriptionConstants.BANNER_TEXTS[name];
    return bannerTexts?['title'] ?? '알림';
  }

  String get subtitle {
    final bannerTexts = SubscriptionConstants.BANNER_TEXTS[name];
    return bannerTexts?['subtitle'] ?? '';
  }

  String? get buttonText {
    final bannerTexts = SubscriptionConstants.BANNER_TEXTS[name];
    return bannerTexts?['buttonText'];
  }
} 