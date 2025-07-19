// lib/models/subscription_info.dart
import 'package:flutter/foundation.dart';
import 'plan.dart';
import 'plan_status.dart';

// 레거시 enum들은 SubscriptionInfo와의 호환성을 위해 당분간 유지합니다.
enum Entitlement {
  free,
  premium,
  trial,
}

enum SubscriptionStatus {
  active,
  cancelling,
  expired,
  unknown,
}

enum SubscriptionType {
  monthly,
  yearly,
}

/// 새로운 구독 정보 모델 (v4-simplified)
/// 🚨 레거시: SettingsViewModel과의 호환성을 위해 임시로 유지됩니다.
/// TODO: SettingsViewModel을 리팩토링하여 SubscriptionState를 직접 사용하고 이 클래스를 제거해야 합니다.
class SubscriptionInfo {
  final Entitlement entitlement;
  final SubscriptionStatus subscriptionStatus;
  final bool hasUsedTrial;
  final String? expirationDate;
  final SubscriptionType? subscriptionType;

  SubscriptionInfo({
    required this.entitlement,
    required this.subscriptionStatus,
    required this.hasUsedTrial,
    this.expirationDate,
    this.subscriptionType,
  });

  /// 🎯 SubscriptionState로부터 SubscriptionInfo를 생성하는 팩토리 생성자
  factory SubscriptionInfo.fromSubscriptionState(SubscriptionState state) {
    Entitlement entitlement;
    if (state.plan.isPremium) {
      // 'trial' 상태를 구분할 방법이 현재 Plan 모델에 없으므로,
      // 프리미엄이면 'premium'으로 간주합니다.
      entitlement = Entitlement.premium;
    } else {
      entitlement = Entitlement.free;
    }

    // PlanStatus를 레거시 SubscriptionStatus로 매핑
    SubscriptionStatus status;
    switch (state.status) {
      case PlanStatus.active:
        status = SubscriptionStatus.active;
        break;
      case PlanStatus.cancelling:
        status = SubscriptionStatus.cancelling;
        break;
      case PlanStatus.expired:
        status = SubscriptionStatus.expired;
        break;
      case PlanStatus.unknown:
      default:
        status = SubscriptionStatus.unknown;
        break;
    }

    SubscriptionType? type;
    if (state.plan.id.contains('monthly')) {
      type = SubscriptionType.monthly;
    } else if (state.plan.id.contains('yearly')) {
      type = SubscriptionType.yearly;
    }

    return SubscriptionInfo(
      entitlement: entitlement,
      subscriptionStatus: status,
      hasUsedTrial: state.hasUsedTrial,
      expirationDate: state.expiresDate?.toIso8601String(),
      subscriptionType: type,
    );
  }

  /// 객체를 JSON 맵으로 변환
  Map<String, dynamic> toJson() {
    return {
      'entitlement': entitlement.name,
      'subscriptionStatus': subscriptionStatus.name,
      'hasUsedTrial': hasUsedTrial,
      'expirationDate': expirationDate,
      'subscriptionType': subscriptionType?.name,
    };
  }

  String get planTitle {
    switch (entitlement) {
      case Entitlement.free:
        return 'Free';
      case Entitlement.premium:
        return 'Premium';
      case Entitlement.trial:
        return 'Trial';
    }
  }

  String? get dateInfoText {
    if (expirationDate == null) return null;
    final expiry = DateTime.tryParse(expirationDate!);
    if (expiry == null) return null;

    final now = DateTime.now();
    final diff = expiry.difference(now);

    if (diff.inDays < 0) {
      return 'Expired';
    } else if (diff.inDays < 7) {
      return 'Expires in ${diff.inDays} days';
    } else {
      return 'Expires in ${diff.inDays ~/ 7} weeks';
    }
  }

  String get ctaText {
    switch (subscriptionStatus) {
      case SubscriptionStatus.active:
        return '프리미엄 구독하기';
      case SubscriptionStatus.cancelling:
        return '앱스토어에서 확인하기';
      case SubscriptionStatus.expired:
        return '프리미엄 구독하기';
      case SubscriptionStatus.unknown:
      default:
        return '플랜 관리';
    }
  }

  String? get ctaSubtext {
    if (subscriptionStatus == SubscriptionStatus.active) {
      return null;
    } else if (subscriptionStatus == SubscriptionStatus.cancelling) {
      return null;
    } else if (subscriptionStatus == SubscriptionStatus.expired) {
      return null;
    }
    return null;
  }

  String get displayStatus {
    switch (subscriptionStatus) {
      case SubscriptionStatus.active:
        return 'Active';
      case SubscriptionStatus.cancelling:
        return 'Cancelling';
      case SubscriptionStatus.expired:
        return 'Expired';
      case SubscriptionStatus.unknown:
      default:
        return 'Unknown';
    }
  }

  bool get isPremiumOrTrial => entitlement == Entitlement.premium || entitlement == Entitlement.trial;
  
  bool get canUsePremiumFeatures => isPremiumOrTrial;
}

/// 앱의 전체 구독 상태를 나타내는 클래스
/// Firestore, 서버 응답 등 모든 소스의 데이터를 통합하여 관리합니다.
class SubscriptionState {
  final Plan plan;
  final PlanStatus status;
  final DateTime? expiresDate;
  final bool hasUsedTrial;
  final DateTime? timestamp;
  final List<String> activeBanners;

  SubscriptionState({
    required this.plan,
    required this.status,
    this.expiresDate,
    this.hasUsedTrial = false,
    this.timestamp,
    this.activeBanners = const [],
  });

  /// 기본 상태 (로그아웃 또는 초기 상태)
  factory SubscriptionState.defaultState() {
    return SubscriptionState(
      plan: Plan.free(),
      status: PlanStatus.active,
      timestamp: DateTime.now(),
    );
  }

  /// Firestore 문서로부터 상태 객체 생성
  factory SubscriptionState.fromFirestore(Map<String, dynamic> data) {
    try {
      final planId = data['planId'] as String? ?? 'free_monthly';
      final rawStatus = data['status'] as String? ?? 'active';

      return SubscriptionState(
        plan: Plan.fromId(planId),
        status: PlanStatus.fromString(rawStatus),
        expiresDate: (data['expiresDate'] as String?) != null
            ? DateTime.tryParse(data['expiresDate'] ?? '')
            : null,
        hasUsedTrial: data['hasUsedTrial'] as bool? ?? false,
        timestamp: (data['timestamp'] as String?) != null
            ? DateTime.tryParse(data['timestamp'] ?? '')
            : DateTime.now(),
        activeBanners: List<String>.from(data['activeBanners'] ?? []),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SubscriptionState.fromFirestore 파싱 오류: $e');
      }
      return SubscriptionState.defaultState();
    }
  }

  /// 🎯 서버 응답으로부터 상태 객체 생성
  factory SubscriptionState.fromServerResponse(Map<String, dynamic> data) {
    try {
      final planId = data['subscriptionType'] as String?;
      final rawStatus = data['subscriptionStatus'] as String?;
      final entitlement = data['entitlement'] as String?;

      // entitlement가 'PREMIUM' 또는 'TRIAL'이면 planId를 기반으로 Plan 생성, 아니면 free Plan
      final plan = (entitlement == 'PREMIUM' || entitlement == 'TRIAL') && planId != null
          ? Plan.fromId(planId)
          : Plan.free();

      return SubscriptionState(
        plan: plan,
        status: PlanStatus.fromString(rawStatus ?? 'unknown'),
        expiresDate: (data['expiresDate'] as String?) != null
            ? DateTime.tryParse(data['expiresDate'] ?? '')
            : null,
        hasUsedTrial: data['hasUsedTrial'] as bool? ?? false,
        timestamp: (data['timestamp'] as String?) != null
            ? DateTime.tryParse(data['timestamp'] ?? '')
            : DateTime.now(),
        // 서버 응답에는 배너 정보가 없으므로 기본값 사용
        activeBanners: [],
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SubscriptionState.fromServerResponse 파싱 오류: $e');
      }
      return SubscriptionState.defaultState();
    }
  }

  /// 객체를 JSON 맵으로 변환
  Map<String, dynamic> toJson() {
    return {
      'planId': plan.id,
      'status': status.name,
      'expiresDate': expiresDate?.toIso8601String(),
      'hasUsedTrial': hasUsedTrial,
      'timestamp': timestamp?.toIso8601String(),
      'activeBanners': activeBanners,
    };
  }
  
  // 편의 getter
  bool get isPremiumOrTrial => plan.isPremium;

  /// 상태 복사 및 일부 값 변경
  SubscriptionState copyWith({
    Plan? plan,
    PlanStatus? status,
    DateTime? expiresDate,
    bool? hasUsedTrial,
    DateTime? timestamp,
    List<String>? activeBanners,
  }) {
    return SubscriptionState(
      plan: plan ?? this.plan,
      status: status ?? this.status,
      expiresDate: expiresDate ?? this.expiresDate,
      hasUsedTrial: hasUsedTrial ?? this.hasUsedTrial,
      timestamp: timestamp ?? this.timestamp,
      activeBanners: activeBanners ?? this.activeBanners,
    );
  }

  @override
  String toString() {
    return 'SubscriptionState(plan: ${plan.name}, status: ${status.name}, expires: $expiresDate)';
  }
}