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
  expired('expired'),
  refunded('refunded'),
  gracePeriod('grace'),
  unknown('unknown'),
  cancelled('cancelled');

  const SubscriptionStatus(this.value);
  final String value;

  factory SubscriptionStatus.fromString(String? value) {
    switch (value) {
      case 'active': return SubscriptionStatus.active;
      case 'cancelling': return SubscriptionStatus.cancelling;
      case 'grace': return SubscriptionStatus.gracePeriod;
      case 'expired': return SubscriptionStatus.expired;
      case 'refunded': return SubscriptionStatus.refunded;
      case 'cancelled': return SubscriptionStatus.cancelled;
      default: return SubscriptionStatus.unknown;
    }
  }

  bool get isActive => this == SubscriptionStatus.active;
  bool get isCancelling => this == SubscriptionStatus.cancelling;
  bool get isGracePeriod => this == SubscriptionStatus.gracePeriod;
  bool get isExpired => this == SubscriptionStatus.expired;
  bool get isRefunded => this == SubscriptionStatus.refunded;
  bool get isCancelled => this == SubscriptionStatus.cancelled;
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
    // subscription 필드에서 실제 구독 정보 추출 (안전한 타입 변환)
    final subscription = json['subscription'] != null
        ? Map<String, dynamic>.from(json['subscription'] as Map)
        : json;
    
    // expirationDate를 안전하게 파싱
    String? parsedExpirationDate;
    final dynamic rawExpirationDate = subscription['expirationDate'];
    if (rawExpirationDate is String) {
      parsedExpirationDate = rawExpirationDate;
    } else if (rawExpirationDate is int) {
      // Unix timestamp (milliseconds)로 가정
      parsedExpirationDate = DateTime.fromMillisecondsSinceEpoch(rawExpirationDate).toIso8601String();
    }
    
    return SubscriptionInfo(
      entitlement: Entitlement.fromString(subscription['entitlement'] as String? ?? 'free'),
      subscriptionStatus: SubscriptionStatus.fromString(subscription['subscriptionStatus'] as String?),
      hasUsedTrial: subscription['hasUsedTrial'] as bool? ?? false,
      autoRenewEnabled: subscription['autoRenewEnabled'] as bool? ?? false,
      expirationDate: parsedExpirationDate,
      subscriptionType: SubscriptionType.fromString(subscription['subscriptionType'] as String?),
      originalTransactionId: subscription['originalTransactionId'] as String?,
      bannerMetadata: subscription['bannerMetadata'] != null
          ? BannerMetadata.fromJson(Map<String, dynamic>.from(subscription['bannerMetadata'] as Map))
          : null,
      dataSource: json['dataSource'] as String? ?? 'unknown',
      version: json['version'] as String? ?? 'unknown',
    );
  }

  // 편의 메서드들
  bool get canUsePremiumFeatures => entitlement.isPremiumOrTrial;
  
  bool get shouldShowTrialOffer => 
      entitlement.isFree && !hasUsedTrial;

  // 🎯 UI 표시용 텍스트 getter들
  
  /// 플랜 제목 (남은 기간 포함)
  String get planTitle {
    final typeDisplay = subscriptionType?.value == 'yearly' ? '연간' : '월간';
    String title;

    if (entitlement.isTrial) {
      title = '프리미엄 체험';
    } else if (entitlement.isPremium) {
      title = '프리미엄 ($typeDisplay)';
    } else {
      title = '무료';
    }
    
    if (subscriptionStatus.isCancelling) {
      title += ' (취소됨)';
    } else if (subscriptionStatus.isGracePeriod) {
      title += ' (결제 확인 요망)';
    }
    
    return title;
  }

  /// 날짜 정보 텍스트 (다음 결제일 / 체험 종료일)
  String? get dateInfoText {
    if (entitlement.isFree) {
      return '현재 무료 플랜을 사용하고 있습니다.';
    }

    if (expirationDate == null) return null;
    final expiry = DateTime.tryParse(expirationDate!);
    if (expiry == null) return null;

    final nextDay = expiry.add(const Duration(days: 1));
    final formattedNextDay = '${nextDay.year}년 ${nextDay.month}월 ${nextDay.day}일';
    final formattedExpiry = '${expiry.year}년 ${expiry.month}월 ${expiry.day}일';

    if (entitlement.isTrial) {
      if (subscriptionStatus.isCancelling) {
        return '$formattedNextDay에 무료 플랜으로 전환됩니다.';
      }
      return '$formattedNextDay에 월 구독으로 전환됩니다.';
    }

    if (entitlement.isPremium) {
      if (subscriptionStatus.isCancelling || subscriptionStatus.isGracePeriod) {
        return '$formattedNextDay에 무료 플랜으로 전환됩니다.';
      }
      return '다음 구독 결제일: $formattedExpiry';
    }
    
    return null;
  }

  /// CTA 버튼 텍스트
  String get ctaText {
    if (entitlement.isFree) return '프리미엄으로 업그레이드';
    if (subscriptionStatus.isCancelling) return '구독 갱신하기';
    return 'App Store에서 관리';
  }

  /// CTA 버튼 보조 텍스트
  String? get ctaSubtext {
    if (entitlement.isTrial && !subscriptionStatus.isCancelling) {
      return '체험 기간 종료 시 자동으로 결제됩니다.';
    }
    if (entitlement.isPremium && !subscriptionStatus.isCancelling) {
      return null;
    }
    return null;
  }

  int _getRemainingDays() {
    if (expirationDate == null) return 0;
    final expiry = DateTime.tryParse(expirationDate!);
    if (expiry == null) return 0;
    final remaining = expiry.difference(DateTime.now()).inDays;
    return remaining > 0 ? remaining : 0;
  }


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

  // 기본 생성자
  const SubscriptionState({
    required this.entitlement,
    required this.subscriptionStatus,
    required this.hasUsedTrial,
    required this.hasUsageLimitReached,
    required this.activeBanners,
    required this.statusMessage,
  });

  factory SubscriptionState.fromServerResponse(Map<String, dynamic> serverResponse) {
    final subscriptionRaw = serverResponse['subscription'];
    final subscription = (subscriptionRaw is Map) ? Map<String, dynamic>.from(subscriptionRaw) : <String, dynamic>{};
    final entitlementString = subscription['entitlement'] as String? ?? 'free';
    final subscriptionStatusString = subscription['subscriptionStatus'] as String? ?? 'cancelled';
    final hasUsedTrial = subscription['hasUsedTrial'] as bool? ?? false;
    
    return SubscriptionState(
      entitlement: Entitlement.fromString(entitlementString),
      subscriptionStatus: SubscriptionStatus.fromString(subscriptionStatusString),
      hasUsedTrial: hasUsedTrial,
      hasUsageLimitReached: false, // 이 값은 BannerManager에서 UsageLimitService를 통해 별도로 계산되어야 함
      activeBanners: [], // 이 값은 BannerManager에서 최종적으로 계산함
      statusMessage: "Status message based on entitlement and status", // 필요 시 구현
    );
  }

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
  bool get isPremiumOrTrial => entitlement.isPremiumOrTrial; // 🎯 추가
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