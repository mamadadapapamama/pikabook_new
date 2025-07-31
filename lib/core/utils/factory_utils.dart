/// 🏭 팩토리 메서드 유틸리티
/// 모델 생성 시 공통적으로 사용되는 팩토리 패턴들을 중앙 집중 관리합니다.

import '../constants/subscription_constants.dart';
import 'enum_utils.dart';

/// 🔧 공통 팩토리 유틸리티 클래스
class FactoryUtils {
  // ────────────────────────────────────────────────────────────────────────
  // 🎯 안전한 데이터 파싱 유틸리티
  // ────────────────────────────────────────────────────────────────────────
  
  /// 안전한 문자열 캐스팅
  static String? safeStringCast(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is int) return value.toString();
    if (value is double) return value.toString();
    if (value is bool) return value.toString();
    return value.toString();
  }
  
  /// 안전한 정수 파싱
  static int safeIntParse(dynamic value, {int defaultValue = 0}) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? defaultValue;
    if (value is double) return value.toInt();
    return defaultValue;
  }
  
  /// 안전한 불린 파싱
  static bool safeBoolParse(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is String) {
      return value.toLowerCase() == 'true' || value == '1';
    }
    if (value is int) return value != 0;
    return defaultValue;
  }
  
  /// 안전한 DateTime 파싱
  static DateTime? safeDateTimeParse(dynamic value) {
    if (value == null) return null;
    
    try {
      if (value is String) {
        if (value.isEmpty) return null;
        return DateTime.tryParse(value);
      }
      if (value is int) {
        // Unix timestamp (초 단위)로 간주
        return DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }
      if (value is double) {
        // Unix timestamp (초 단위)로 간주 (소수점 버림)
        return DateTime.fromMillisecondsSinceEpoch((value * 1000).toInt());
      }
    } catch (e) {
      // 파싱 실패 시 null 반환
      return null;
    }
    
    return null;
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 🏗️ 구독/플랜 관련 팩토리 유틸리티
  // ────────────────────────────────────────────────────────────────────────
  
  /// Entitlement 문자열 정규화 (대소문자 무관)
  static String normalizeEntitlement(String? entitlement) {
    if (entitlement == null || entitlement.isEmpty) return 'FREE';
    return entitlement.toUpperCase();
  }
  
  /// ProductId로부터 플랜 타입 결정
  static String getPlanTypeFromProductId(String? productId, String? entitlement) {
    final normalizedEntitlement = normalizeEntitlement(entitlement);
    
    if (normalizedEntitlement == 'PREMIUM' || normalizedEntitlement == 'TRIAL') {
      if (productId != null && productId.isNotEmpty) {
        // productId가 있으면 프리미엄으로 간주
        return SubscriptionConstants.PLAN_PREMIUM;
      }
    }
    
    return SubscriptionConstants.PLAN_FREE;
  }
  
  /// 구독 상태 코드 정규화 (int 또는 string 처리)
  static int normalizeSubscriptionStatus(dynamic subscriptionStatus) {
    if (subscriptionStatus is int) {
      return subscriptionStatus;
    }
    if (subscriptionStatus is String) {
      return int.tryParse(subscriptionStatus) ?? SubscriptionConstants.STATUS_UNKNOWN;
    }
    return SubscriptionConstants.STATUS_UNKNOWN;
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 🔄 Enum 변환 헬퍼
  // ────────────────────────────────────────────────────────────────────────
  
  /// 문자열을 Enum으로 안전하게 변환 (기본값 포함)
  static T? safeEnumFromString<T extends Enum>(
    List<T> enumValues,
    dynamic value, {
    T? defaultValue,
  }) {
    final stringValue = safeStringCast(value);
    return EnumUtils.stringToEnum<T>(
      enumValues,
      stringValue,
      defaultValue: defaultValue,
    );
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 📊 배너 생성 유틸리티
  // ────────────────────────────────────────────────────────────────────────
  
  /// 구독 상태에서 배너 목록 생성
  static List<String> generateBannersFromSubscriptionData({
    required String? entitlement,
    required dynamic subscriptionStatus,
    bool includeFallback = true,
  }) {
    final List<String> banners = [];
    
    final normalizedEntitlement = normalizeEntitlement(entitlement);
    final normalizedStatus = normalizeSubscriptionStatus(subscriptionStatus);
    
    // 중앙화된 상수 사용
    final bannerType = SubscriptionConstants.getBannerType(
      normalizedEntitlement,
      normalizedStatus,
    );
    
    if (bannerType != null) {
      banners.add(bannerType);
    }
    
    return banners;
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 🔍 데이터 검증 유틸리티
  // ────────────────────────────────────────────────────────────────────────
  
  /// Map에서 필수 필드 존재 여부 확인
  static bool hasRequiredFields(Map<String, dynamic> data, List<String> requiredFields) {
    for (final field in requiredFields) {
      if (!data.containsKey(field) || data[field] == null) {
        return false;
      }
    }
    return true;
  }
  
  /// 빈 Map 또는 null 체크
  static bool isEmptyOrInvalid(Map<String, dynamic>? data) {
    return data == null || data.isEmpty;
  }
  
  /// 중첩된 Map에서 안전하게 값 추출
  static T? safeGetNestedValue<T>(
    Map<String, dynamic> data,
    List<String> keyPath, {
    T? defaultValue,
  }) {
    dynamic current = data;
    
    for (final key in keyPath) {
      if (current is! Map<String, dynamic> || !current.containsKey(key)) {
        return defaultValue;
      }
      current = current[key];
    }
    
    return current is T ? current : defaultValue;
  }
  
  // ────────────────────────────────────────────────────────────────────────
  // 🎨 표시 이름 생성 유틸리티
  // ────────────────────────────────────────────────────────────────────────
  
  /// 플랜 ID에서 사용자 친화적 이름 생성
  static String generateDisplayName(String id, {String fallback = '알 수 없음'}) {
    return SubscriptionConstants.getPlanDisplayName(id);
  }
  
  /// 카멜케이스를 읽기 쉬운 텍스트로 변환
  static String camelCaseToDisplayText(String camelCase) {
    return camelCase
        .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(1)}')
        .trim()
        .split(' ')
        .map((word) => word.isNotEmpty 
            ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}'
            : '')
        .join(' ');
  }
}