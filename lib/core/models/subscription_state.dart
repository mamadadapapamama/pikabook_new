/// 구독 상태를 나타내는 통합 모델
class SubscriptionState {
  final bool isTrial;
  final bool isTrialExpiringSoon;
  final bool isPremium;
  final bool isExpired;
  final bool hasUsageLimitReached;
  final int daysRemaining;
  final List<BannerType> activeBanners;
  final String statusMessage;
  
  const SubscriptionState({
    required this.isTrial,
    required this.isTrialExpiringSoon,
    required this.isPremium,
    required this.isExpired,
    required this.hasUsageLimitReached,
    required this.daysRemaining,
    required this.activeBanners,
    required this.statusMessage,
  });

  /// 기본 상태 (로그아웃/샘플 모드)
  factory SubscriptionState.defaultState() {
    return const SubscriptionState(
      isTrial: false,
      isTrialExpiringSoon: false,
      isPremium: false,
      isExpired: false,
      hasUsageLimitReached: false,
      daysRemaining: 0,
      activeBanners: [],
      statusMessage: '샘플 모드',
    );
  }

  /// 프리미엄 기능 사용 가능 여부
  bool get canUsePremiumFeatures => isTrial || isPremium;

  /// 노트 생성 가능 여부 (사용량 한도 고려)
  bool get canCreateNote => canUsePremiumFeatures && !hasUsageLimitReached;

  @override
  String toString() {
    return 'SubscriptionState('
        'isTrial: $isTrial, '
        'isPremium: $isPremium, '
        'isExpired: $isExpired, '
        'hasUsageLimitReached: $hasUsageLimitReached, '
        'daysRemaining: $daysRemaining, '
        'activeBanners: ${activeBanners.map((e) => e.name).toList()}, '
        'statusMessage: $statusMessage'
        ')';
  }
}

/// 배너 타입 열거형
enum BannerType {
  premiumExpired,
  trialCompleted,
  usageLimit,
}

extension BannerTypeExtension on BannerType {
  String get name {
    switch (this) {
      case BannerType.premiumExpired:
        return 'premiumExpired';
      case BannerType.trialCompleted:
        return 'trialCompleted';
      case BannerType.usageLimit:
        return 'usageLimit';
    }
  }
} 