// lib/models/subscription_info.dart
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'plan.dart';
import 'plan_status.dart';
import '../constants/subscription_constants.dart';

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
        return '무료';
      case Entitlement.premium:
        // subscriptionType이 있으면 월간/연간 구분
        if (subscriptionType == SubscriptionType.monthly) {
          return '프리미엄 (월간)';
        } else if (subscriptionType == SubscriptionType.yearly) {
          return '프리미엄 (연간)';
        } else {
          return '프리미엄';
        }
      case Entitlement.trial:
        return '트라이얼';
    }
  }

  String? get dateInfoText {
    if (expirationDate == null) return null;
    final expiry = DateTime.tryParse(expirationDate!);
    if (expiry == null) return null;

    final now = DateTime.now();
    final diff = expiry.difference(now);

    if (diff.inDays < 0) {
      return '만료됨';
    } else if (diff.inDays < 1) {
      final hours = diff.inHours;
      return '${hours}시간 후 만료';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}일 후 만료';
    } else {
      // 🎯 구독 갱신일 형식: 2025.01.01
      final year = expiry.year;
      final month = expiry.month.toString().padLeft(2, '0');
      final day = expiry.day.toString().padLeft(2, '0');
      return '구독 갱신일: $year.$month.$day';
    }
  }

  String get ctaText {
    // 🎯 중앙화된 상수 사용
    final entitlementStr = entitlement.name;
    final status = subscriptionStatus.name;
    return SubscriptionConstants.getCTAText(entitlementStr, status);
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
class SubscriptionState extends Equatable {
  final Plan plan;
  final PlanStatus status;
  final DateTime? expiresDate;
  final bool hasUsedTrial;
  final DateTime? timestamp;
  final List<String> activeBanners;

  const SubscriptionState({
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
      // 🎯 서버 필드명에 맞게 수정
      final productId = data['productId'] as String?;
      final entitlement = data['entitlement'] as String?;
      final subscriptionStatus = data['subscriptionStatus']; // int 또는 string 가능
      
      if (kDebugMode) {
        debugPrint('🔍 [SubscriptionState] Firestore 데이터 파싱:');
        debugPrint('   - productId: $productId');
        debugPrint('   - entitlement: $entitlement');
        debugPrint('   - subscriptionStatus: $subscriptionStatus');
      }

      // entitlement 기반으로 Plan 결정
      Plan plan;
      if (entitlement == 'premium' && productId != null) {
        plan = Plan.fromId(productId);
      } else {
        plan = Plan.free();
      }

      // subscriptionStatus 파싱 (int 또는 string)
      PlanStatus status;
      
      // 🎯 무료 플랜일 때는 항상 active 상태
      if (entitlement == 'FREE' || entitlement == 'free') {
        status = PlanStatus.active;
        if (kDebugMode) {
          debugPrint('   - 무료 플랜이므로 강제로 active 상태 설정');
        }
      } else if (subscriptionStatus is int) {
        switch (subscriptionStatus) {
          case 1:
            status = PlanStatus.active;      // ACTIVE
            break;
          case 2:
            status = PlanStatus.expired;     // 🎯 수정: EXPIRED (만료됨)
            break;
          case 3:
            status = PlanStatus.expired;     // REFUNDED (환불됨 -> 만료 처리)
            break;
          case 7:
            status = PlanStatus.cancelling;  // 🎯 수정: CANCELLED (취소됨)
            break;
          default:
            status = PlanStatus.unknown;
        }
      } else {
        status = PlanStatus.fromString(subscriptionStatus?.toString() ?? 'active');
      }

      if (kDebugMode) {
        debugPrint('   - 최종 Plan: ${plan.name}');
        debugPrint('   - 최종 Status: ${status.name}');
      }

      return SubscriptionState(
        plan: plan,
        status: status,
        expiresDate: _parseExpirationDate(data),
        hasUsedTrial: data['hasUsedTrial'] as bool? ?? false,
        timestamp: _parseDateTime(data['lastUpdatedAt']) ?? DateTime.now(),
        // 🎯 Firestore 데이터에서도 배너 동적 생성
        activeBanners: _generateBannersFromFirestoreData(data, plan, status),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SubscriptionState.fromFirestore 파싱 오류: $e');
        debugPrint('데이터: $data');
      }
      return SubscriptionState.defaultState();
    }
  }

  /// 🎯 서버 응답으로부터 상태 객체 생성
  factory SubscriptionState.fromServerResponse(Map<String, dynamic> data) {
    try {
      // 🔧 안전한 타입 캐스팅
      final planId = _safeStringCast(data['subscriptionType']) ?? _safeStringCast(data['productId']);
      final rawStatus = _safeStringCast(data['subscriptionStatus']);
      final entitlement = _safeStringCast(data['entitlement']);

      if (kDebugMode) {
        debugPrint('🔍 [SubscriptionState] 서버 응답 파싱:');
        debugPrint('   - planId: $planId');
        debugPrint('   - rawStatus: $rawStatus');
        debugPrint('   - entitlement: $entitlement');
      }

      // entitlement가 'PREMIUM' 또는 'TRIAL'이면 planId를 기반으로 Plan 생성, 아니면 free Plan
      final plan = (entitlement == 'PREMIUM' || entitlement == 'TRIAL') && planId != null
          ? Plan.fromId(planId)
          : Plan.free();

      if (kDebugMode) {
        debugPrint('   - 최종 Plan: ${plan.name}');
      }

      return SubscriptionState(
        plan: plan,
        status: PlanStatus.fromString(rawStatus ?? 'unknown'),
        expiresDate: _parseDateTime(data['expiresDate']),
        hasUsedTrial: data['hasUsedTrial'] as bool? ?? false,
        timestamp: _parseDateTime(data['timestamp']) ?? DateTime.now(),
        // 🎯 서버 응답 기반으로 배너 생성
        activeBanners: _generateBannersFromServerResponse(data, plan),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SubscriptionState.fromServerResponse 파싱 오류: $e');
        debugPrint('서버 응답 데이터: $data');
      }
      return SubscriptionState.defaultState();
    }
  }

  /// 🔧 만료일 파싱 헬퍼 (서버 필드명 고려)
  static DateTime? _parseExpirationDate(Map<String, dynamic> data) {
    // 서버에서는 expirationDate (밀리초) 사용
    final expirationDate = data['expirationDate'];
    if (expirationDate != null) {
      if (expirationDate is int) {
        return DateTime.fromMillisecondsSinceEpoch(expirationDate);
      } else if (expirationDate is String) {
        final timestamp = int.tryParse(expirationDate);
        if (timestamp != null) {
          return DateTime.fromMillisecondsSinceEpoch(timestamp);
        }
        return DateTime.tryParse(expirationDate);
      }
    }
    
    // Fallback: expiresDate 필드도 확인
    final expiresDate = data['expiresDate'];
    if (expiresDate is String) {
      return DateTime.tryParse(expiresDate);
    }
    
    return null;
  }

  /// 🔧 안전한 String 캐스팅 헬퍼 메서드
  static String? _safeStringCast(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is int) return value.toString();
    if (value is double) return value.toString();
    if (value is bool) return value.toString();
    return value.toString(); // 다른 타입도 문자열로 변환 시도
  }

  /// 🔧 안전한 DateTime 파싱 헬퍼 메서드
  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    
    try {
      // String인 경우 ISO 8601 형식으로 파싱
      if (value is String) {
        if (value.isEmpty) return null;
        return DateTime.tryParse(value);
      }
      // int인 경우 Unix timestamp (초 단위)로 간주
      else if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }
      // double인 경우도 Unix timestamp로 간주 (소수점 버림)
      else if (value is double) {
        return DateTime.fromMillisecondsSinceEpoch((value * 1000).toInt());
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ DateTime 파싱 실패: $value (타입: ${value.runtimeType}), 오류: $e');
      }
    }
    
    return null;
  }

  /// 🎯 서버 응답 기반으로 배너 생성 (중앙화된 상수 사용)
  static List<String> _generateBannersFromServerResponse(Map<String, dynamic> data, Plan plan) {
    final List<String> banners = [];
    final entitlement = _safeStringCast(data['entitlement']) ?? '';
    final subscriptionStatusRaw = data['subscriptionStatus'];
    
    // subscriptionStatus를 int로 변환
    int subscriptionStatus;
    if (subscriptionStatusRaw is int) {
      subscriptionStatus = subscriptionStatusRaw;
    } else if (subscriptionStatusRaw is String) {
      subscriptionStatus = int.tryParse(subscriptionStatusRaw) ?? SubscriptionConstants.STATUS_UNKNOWN;
    } else {
      subscriptionStatus = SubscriptionConstants.STATUS_UNKNOWN;
    }

    if (kDebugMode) {
      debugPrint('🎯 [SubscriptionState] 서버 응답 배너 생성:');
      debugPrint('   - entitlement: $entitlement');
      debugPrint('   - subscriptionStatus: $subscriptionStatus');
      debugPrint('   - plan.isPremium: ${plan.isPremium}');
    }

    // 🎯 중앙화된 상수 사용
    final bannerType = SubscriptionConstants.getBannerType(entitlement, subscriptionStatus);
    if (bannerType != null) {
      banners.add(bannerType);
      if (kDebugMode) {
        debugPrint('   - 추가된 배너: $bannerType');
      }
    }

    if (kDebugMode) {
      debugPrint('   - 최종 배너 목록: $banners');
    }

    return banners;
  }

  /// 🎯 Firestore 데이터에서도 배너 동적 생성 (중앙화된 상수 사용)
  static List<String> _generateBannersFromFirestoreData(Map<String, dynamic> data, Plan plan, PlanStatus status) {
    final List<String> banners = [];
    final entitlement = _safeStringCast(data['entitlement']) ?? '';
    final subscriptionStatusRaw = data['subscriptionStatus'];
    
    // subscriptionStatus를 int로 변환
    int subscriptionStatus;
    if (subscriptionStatusRaw is int) {
      subscriptionStatus = subscriptionStatusRaw;
    } else if (subscriptionStatusRaw is String) {
      subscriptionStatus = int.tryParse(subscriptionStatusRaw) ?? SubscriptionConstants.STATUS_UNKNOWN;
    } else {
      subscriptionStatus = SubscriptionConstants.STATUS_UNKNOWN;
    }

    if (kDebugMode) {
      debugPrint('🎯 [SubscriptionState] Firestore 배너 생성:');
      debugPrint('   - entitlement: $entitlement');
      debugPrint('   - subscriptionStatus: $subscriptionStatus');
      debugPrint('   - plan.isPremium: ${plan.isPremium}');
    }

    // 🎯 중앙화된 상수 사용
    final bannerType = SubscriptionConstants.getBannerType(entitlement, subscriptionStatus);
    if (bannerType != null) {
      banners.add(bannerType);
      if (kDebugMode) {
        debugPrint('   - 추가된 배너: $bannerType');
      }
    }

    if (kDebugMode) {
      debugPrint('   - 최종 배너 목록: $banners');
    }

    return banners;
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

  @override
  List<Object?> get props => [
        plan,
        status,
        expiresDate,
        hasUsedTrial,
        // timestamp는 상태 비교에서 제외 (항상 바뀌므로)
        activeBanners,
      ];
}