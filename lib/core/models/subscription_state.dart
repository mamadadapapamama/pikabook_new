// lib/models/subscription_info.dart
import '../services/common/banner_manager.dart';

/// 권한 타입 (기능 접근 제어)
enum Entitlement {
  free('free'),
  trial('trial'),
  premium('premium');

  const Entitlement(this.value);
  final String value;

  static Entitlement fromString(String value) {
    switch (value) {
      case 'trial':
        return Entitlement.trial;
      case 'premium':
        return Entitlement.premium;
      case 'free':
      default:
        return Entitlement.free;
    }
  }

  // 편의 메서드들
  bool get isPremiumOrTrial => this != Entitlement.free;
  bool get isPremium => this == Entitlement.premium;
  bool get isTrial => this == Entitlement.trial;
  bool get isFree => this == Entitlement.free;
}

/// 구독 상태 (실제 구독 상태)
enum SubscriptionStatus {
  active('active'),
  cancelling('cancelling'),
  cancelled('cancelled'),
  expired('expired'),
  refunded('refunded');

  const SubscriptionStatus(this.value);
  final String value;

  static SubscriptionStatus fromString(String value) {
    switch (value) {
      case 'active':
        return SubscriptionStatus.active;
      case 'cancelling':
        return SubscriptionStatus.cancelling;
      case 'cancelled':
        return SubscriptionStatus.cancelled;
      case 'expired':
        return SubscriptionStatus.expired;
      case 'refunded':
        return SubscriptionStatus.refunded;
      default:
        return SubscriptionStatus.cancelled;
    }
  }

  // 편의 메서드들
  bool get isActive => this == SubscriptionStatus.active;
  bool get isCancelling => this == SubscriptionStatus.cancelling;
  bool get isCancelled => this == SubscriptionStatus.cancelled;
  bool get isExpired => this == SubscriptionStatus.expired;
  bool get isRefunded => this == SubscriptionStatus.refunded;
}

/// 구독 타입
enum SubscriptionType {
  monthly('monthly'),
  yearly('yearly');

  const SubscriptionType(this.value);
  final String value;

  static SubscriptionType? fromString(String? value) {
    if (value == null) return null;
    switch (value) {
      case 'monthly':
        return SubscriptionType.monthly;
      case 'yearly':
        return SubscriptionType.yearly;
      default:
        return null;
    }
  }
}

/// 배너 메타데이터 (테스트 계정용)
class BannerMetadata {
  final String bannerType;
  final DateTime? bannerDismissedAt;

  const BannerMetadata({
    required this.bannerType,
    this.bannerDismissedAt,
  });

  factory BannerMetadata.fromJson(Map<String, dynamic> json) {
    return BannerMetadata(
      bannerType: json['bannerType'] as String,
      bannerDismissedAt: json['bannerDismissedAt'] != null
          ? DateTime.parse(json['bannerDismissedAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bannerType': bannerType,
      'bannerDismissedAt': bannerDismissedAt?.toIso8601String(),
    };
  }
}

/// 새로운 구독 정보 모델 (v4-simplified)
class SubscriptionInfo {
  // 핵심 3개 필드
  final Entitlement entitlement;           // 기능 접근
  final SubscriptionStatus subscriptionStatus;
  final bool hasUsedTrial;                 // 체험 경험

  // 메타데이터
  final bool autoRenewEnabled;
  final String? expirationDate;
  final SubscriptionType? subscriptionType;
  final String? originalTransactionId;

  // 배너용 (테스트 계정만)
  final BannerMetadata? bannerMetadata;

  // 응답 메타데이터
  final String dataSource;
  final String version;

  SubscriptionInfo({
    required this.entitlement,
    required this.subscriptionStatus,
    required this.hasUsedTrial,
    required this.autoRenewEnabled,
    this.expirationDate,
    this.subscriptionType,
    this.originalTransactionId,
    this.bannerMetadata,
    required this.dataSource,
    required this.version,
  });

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) {
    // subscription 필드에서 실제 구독 정보 추출
    final subscription = json['subscription'] as Map<String, dynamic>? ?? json;
    
    return SubscriptionInfo(
      entitlement: Entitlement.fromString(subscription['entitlement'] as String? ?? 'free'),
      subscriptionStatus: SubscriptionStatus.fromString(subscription['subscriptionStatus'] as String? ?? 'cancelled'),
      hasUsedTrial: subscription['hasUsedTrial'] as bool? ?? false,
      autoRenewEnabled: subscription['autoRenewEnabled'] as bool? ?? false,
      expirationDate: subscription['expirationDate'] as String?,
      subscriptionType: SubscriptionType.fromString(subscription['subscriptionType'] as String?),
      originalTransactionId: subscription['originalTransactionId'] as String?,
      bannerMetadata: subscription['bannerMetadata'] != null
          ? BannerMetadata.fromJson(Map<String, dynamic>.from(subscription['bannerMetadata']))
          : null,
      dataSource: json['dataSource'] as String? ?? 'unknown',
      version: json['version'] as String? ?? 'unknown',
    );
  }

  // 편의 메서드들
  bool get canUsePremiumFeatures => entitlement.isPremiumOrTrial;
  
  bool get shouldShowTrialOffer => 
      entitlement.isFree && !hasUsedTrial;

  String get displayStatus {
    if (entitlement.isTrial) {
      return subscriptionStatus.isCancelling 
          ? '무료체험 (취소 예정)' 
          : '무료체험 중';
    } else if (entitlement.isPremium) {
      return subscriptionStatus.isCancelling 
          ? '프리미엄 (취소 예정)' 
          : '프리미엄';
    } else {
      return '무료 플랜';
    }
  }

  /// 기존 코드 호환성을 위한 변환 메서드들
  bool get isPremium => entitlement.isPremium;
  bool get isTrial => entitlement.isTrial;
  bool get isExpired => subscriptionStatus.isExpired;
  bool get isActive => subscriptionStatus.isActive;

  @override
  String toString() {
    return 'SubscriptionInfo('
        'entitlement: ${entitlement.value}, '
        'subscriptionStatus: ${subscriptionStatus.value}, '
        'hasUsedTrial: $hasUsedTrial, '
        'dataSource: $dataSource'
        ')';
  }
}

/// 구독 상태를 나타내는 통합 모델
class SubscriptionState {
  final Entitlement entitlement;
  final SubscriptionStatus subscriptionStatus;
  final bool hasUsedTrial;
  final bool hasUsageLimitReached;
  final List<BannerType> activeBanners;
  final String statusMessage;
  
  const SubscriptionState({
    required this.entitlement,
    required this.subscriptionStatus,
    required this.hasUsedTrial,
    required this.hasUsageLimitReached,
    required this.activeBanners,
    required this.statusMessage,
  });

  /// 기본 상태 (로그아웃/샘플 모드)
  factory SubscriptionState.defaultState() {
    return const SubscriptionState(
      entitlement: Entitlement.free,
      subscriptionStatus: SubscriptionStatus.cancelled,
      hasUsedTrial: false,
      hasUsageLimitReached: false,
      activeBanners: [],
      statusMessage: '샘플 모드',
    );
  }

  /// SubscriptionInfo 기반으로 상태 생성
  factory SubscriptionState.fromSubscriptionInfo(
    SubscriptionInfo info, {
    bool hasUsageLimitReached = false,
    List<BannerType> activeBanners = const [],
  }) {
    return SubscriptionState(
      entitlement: info.entitlement,
      subscriptionStatus: info.subscriptionStatus,
      hasUsedTrial: info.hasUsedTrial,
      hasUsageLimitReached: hasUsageLimitReached,
      activeBanners: activeBanners,
      statusMessage: info.displayStatus,
    );
  }

  /// 프리미엄 기능 사용 가능 여부
  bool get canUsePremiumFeatures => entitlement.isPremiumOrTrial;

  /// 노트 생성 가능 여부 (사용량 한도 고려)
  bool get canCreateNote => canUsePremiumFeatures && !hasUsageLimitReached;

  // 기존 코드 호환성을 위한 편의 메서드들
  bool get isPremium => entitlement.isPremium;
  bool get isTrial => entitlement.isTrial;
  bool get isTrialExpiringSoon => false; // 새 구조에서는 서버에서 관리
  bool get isExpired => subscriptionStatus.isExpired;
  int get daysRemaining => 0; // 새 구조에서는 서버에서 관리

  @override
  String toString() {
    return 'SubscriptionState('
        'entitlement: ${entitlement.value}, '
        'subscriptionStatus: ${subscriptionStatus.value}, '
        'hasUsedTrial: $hasUsedTrial, '
        'hasUsageLimitReached: $hasUsageLimitReached, '
        'activeBanners: ${activeBanners.map((e) => e.name).toList()}, '
        'statusMessage: $statusMessage'
        ')';
  }
}