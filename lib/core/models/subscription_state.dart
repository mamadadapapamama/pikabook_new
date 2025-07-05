// lib/models/subscription_info.dart
import '../services/common/banner_manager.dart';
import 'plan_status.dart'; // 새로 추가

class SubscriptionInfo {
  final PlanStatus planStatus;
  final String? expirationDate;
  final bool autoRenewStatus;
  final bool hasEverUsedTrial;
  final bool hasEverUsedPremium;
  final String dataSource;
  final String? gracePeriodEnd;

  SubscriptionInfo({
    required this.planStatus,
    this.expirationDate,
    required this.autoRenewStatus,
    required this.hasEverUsedTrial,
    required this.hasEverUsedPremium,
    required this.dataSource,
    this.gracePeriodEnd,
  });

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) {
    return SubscriptionInfo(
      planStatus: PlanStatus.fromString(json['planStatus'] ?? 'free'),
      expirationDate: json['expirationDate'],
      autoRenewStatus: json['autoRenewStatus'] ?? false,
      hasEverUsedTrial: json['hasEverUsedTrial'] ?? false,
      hasEverUsedPremium: json['hasEverUsedPremium'] ?? false,
      dataSource: json['dataSource'] ?? 'unknown',
      gracePeriodEnd: json['gracePeriodEnd'],
    );
  }

  // 편의 메서드들
  bool get canUsePremiumFeatures => planStatus.isActive;
  
  bool get shouldShowTrialOffer => 
      planStatus == PlanStatus.free && !hasEverUsedTrial;
      
  String get displayName {
    switch (planStatus) {
      case PlanStatus.free:
        return '무료 플랜';
      case PlanStatus.trialActive:
        return '7일 무료체험 중';
      case PlanStatus.trialCancelled:
        return '무료체험 (취소됨)';
      case PlanStatus.trialCompleted:
        return '무료체험 완료';
      case PlanStatus.premiumActive:
        return '프리미엄';
      case PlanStatus.premiumCancelled:
        return '프리미엄 (취소 예정)';
      case PlanStatus.premiumExpired:
        return '프리미엄 만료';
      case PlanStatus.premiumGrace:
        return '결제 문제 발생';
      case PlanStatus.refunded:
        return '환불됨';
    }
  }
}

/// 구독 상태를 나타내는 통합 모델
class SubscriptionState {
  final PlanStatus planStatus; // 새로 추가
  final bool isTrial;
  final bool isTrialExpiringSoon;
  final bool isPremium;
  final bool isExpired;
  final bool hasUsageLimitReached;
  final int daysRemaining;
  final List<BannerType> activeBanners;
  final String statusMessage;
  
  const SubscriptionState({
    required this.planStatus, // 새로 추가
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
      planStatus: PlanStatus.free, // 새로 추가
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

  /// PlanStatus 기반으로 상태 생성
  factory SubscriptionState.fromPlanStatus(PlanStatus planStatus, {
    bool hasUsageLimitReached = false,
    int daysRemaining = 0,
    List<BannerType> activeBanners = const [],
  }) {
    return SubscriptionState(
      planStatus: planStatus,
      isTrial: planStatus.isTrial,
      isTrialExpiringSoon: planStatus == PlanStatus.trialActive && daysRemaining <= 3,
      isPremium: planStatus.isPremium,
      isExpired: !planStatus.isActive,
      hasUsageLimitReached: hasUsageLimitReached,
      daysRemaining: daysRemaining,
      activeBanners: activeBanners,
      statusMessage: _getStatusMessage(planStatus),
    );
  }

  static String _getStatusMessage(PlanStatus planStatus) {
    switch (planStatus) {
      case PlanStatus.free:
        return '무료';
      case PlanStatus.trialActive:
        return '무료 체험';
      case PlanStatus.trialCancelled:
        return '체험 취소됨';
      case PlanStatus.trialCompleted:
        return '체험 완료';
      case PlanStatus.premiumActive:
        return '프리미엄';
      case PlanStatus.premiumCancelled:
        return '프리미엄 취소됨';
      case PlanStatus.premiumExpired:
        return '프리미엄 만료';
      case PlanStatus.premiumGrace:
        return '프리미엄 유예 기간';
      case PlanStatus.refunded:
        return '환불됨';
    }
  }

  /// 프리미엄 기능 사용 가능 여부
  bool get canUsePremiumFeatures => planStatus.isActive;

  /// 노트 생성 가능 여부 (사용량 한도 고려)
  bool get canCreateNote => canUsePremiumFeatures && !hasUsageLimitReached;

  @override
  String toString() {
    return 'SubscriptionState('
        'planStatus: ${planStatus.value}, '
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