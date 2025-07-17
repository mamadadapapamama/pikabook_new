import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'usage_limit_service.dart';
import '../../models/subscription_state.dart';
import 'banner_config.dart';

// ============================================================================
// 🎯 1. 배너 타입 정의 섹션
// ============================================================================

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
        return '무료 플랜 시작!';
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
        return '무료 플랜으로 시작합니다. 여유있게 사용하시려면 프리미엄을 구독해 보세요.';
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

// ============================================================================
// 🎯 2. 핵심 상태 관리 섹션
// ============================================================================

/// 통합 배너 관리 서비스 (서버 응답 기반)
/// 구독 상태에 따른 배너 표시/숨김 관리 (사용자별 분리)
class BannerManager {
  // ────────────────────────────────────────────────────────────────────────
  // 📦 상태 변수 및 초기화
  // ────────────────────────────────────────────────────────────────────────
  
  // 싱글톤 패턴
  static final BannerManager _instance = BannerManager._internal();
  factory BannerManager() => _instance;
  BannerManager._internal();

  // 🆔 현재 사용자 ID 가져오기
  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  // ────────────────────────────────────────────────────────────────────────
  // 🔗 Public 인터페이스 메서드들
  // ────────────────────────────────────────────────────────────────────────
  
  /// 배너 닫기 (사용자가 X 버튼 클릭 시)
  Future<void> dismissBanner(BannerType type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 사용량 배너
      if (type == BannerType.usageLimitFree || type == BannerType.usageLimitPremium) {
        final key = _getSimpleUsageBannerKey(type);
        await prefs.setBool(key, true);
        if (kDebugMode) {
          debugPrint('✅ [BannerManager] 사용량 배너 닫기: $key');
        }
        return;
      }
      
      // 상태 배너는 현재 구독 상태를 알아야 정확한 키를 생성할 수 있으므로,
      // 여기서는 일반적인 키로 닫기를 시도합니다.
      // 가장 정확한 방법은 dismiss 시점에 구독 상태를 다시 조회하는 것이지만,
      // 현재 구조에서는 단순화를 위해 타입 기반 키로 처리합니다.
      final key = _getSimpleStateBannerKey(type);
      await prefs.setBool(key, true);
      
      if (kDebugMode) {
        debugPrint('✅ [BannerManager] 상태 배너 닫기: $key');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [BannerManager] 배너 닫기 실패: $e');
      }
    }
  }

  /// 🆕 로그아웃 시 배너 상태 초기화 (메모리만)
  void clearUserBannerStates() {
    // SharedPreferences는 사용자별로 키가 분리되므로 메모리 상태만 초기화하면 됨.
    // 현재 메모리 상태를 사용하지 않으므로 비워둡니다.
    if (kDebugMode) {
      debugPrint('🔄 [BannerManager] 로그아웃. SharedPreferences는 사용자별로 관리됩니다.');
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // 🎯 3. 배너 결정 로직 섹션
  // ────────────────────────────────────────────────────────────────────────

  /// 🆕 서버 응답으로부터 직접 배너 결정 (단순화된 최종 버전)
  Future<List<BannerType>> getActiveBannersFromServerResponse(
    Map<String, dynamic> serverResponse,
  ) async {
    try {
      if (kDebugMode) {
        debugPrint('🎯 [BannerManager] ===== 단순화된 배너 결정 시작 =====');
      }
      
      final activeBanners = <BannerType>[];
      final prefs = await SharedPreferences.getInstance();
      
      // 1. 서버 응답 파싱
      final subscriptionData = _parseServerResponse(serverResponse);
      if (subscriptionData == null) {
        return activeBanners;
      }
      
      // 2. 테스트 계정 처리
      final testBanners = await _handleTestAccountBanners(subscriptionData, prefs);
      if (testBanners != null) {
        return testBanners;
      }
      
      final entitlement = subscriptionData['entitlement'] as String;
      final subscriptionStatus = subscriptionData['subscriptionStatus'] as String;
      final hasUsedTrial = subscriptionData['hasUsedTrial'] as bool;
      final expirationDate = subscriptionData['expirationDate'] as String?;
      
      // 3. 사용량 배너 결정
      final usageLimitStatus = await UsageLimitService().checkInitialLimitStatus();
      _addUsageBanners(activeBanners, entitlement, usageLimitStatus, prefs);
      
      // 4. 상태 배너 결정
      _addStateBanner(activeBanners, entitlement, subscriptionStatus, hasUsedTrial, expirationDate, prefs);
      
      if (kDebugMode) {
        debugPrint('✅ [BannerManager] 단순화된 배너 결정 완료');
        debugPrint('   활성 배너: ${activeBanners.map((e) => e.name).toList()}');
      }
      
      return activeBanners;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [BannerManager] 단순화된 배너 결정 실패: $e');
      }
      return [];
    }
  }

  // ┌─────────────────────────────────────────────────────────────────────┐
  // │ 🔧 배너 결정 세부 로직들 (Private)                                     │
  // └─────────────────────────────────────────────────────────────────────┘

  /// 1. 서버 응답 파싱
  Map<String, dynamic>? _parseServerResponse(Map<String, dynamic> serverResponse) {
    final subscription = _safeMapConversion(serverResponse['subscription']);
    if (subscription == null) {
      if (kDebugMode) debugPrint('⚠️ [BannerManager] subscription 필드 없음');
      return null;
    }
    
    return {
      'entitlement': _safeStringConversion(subscription['entitlement']) ?? BannerConfig.defaultEntitlement,
      'subscriptionStatus': _safeStringConversion(subscription['subscriptionStatus']) ?? BannerConfig.defaultSubscriptionStatus,
      'hasUsedTrial': _safeBoolConversion(subscription['hasUsedTrial']) ?? BannerConfig.defaultHasUsedTrial,
      'expirationDate': _safeStringConversion(subscription['expirationDate']),
      'bannerMetadata': _safeMapConversion(subscription['bannerMetadata']),
    };
  }
  
  /// 2. 테스트 계정 처리
  Future<List<BannerType>?> _handleTestAccountBanners(Map<String, dynamic> subscriptionData, SharedPreferences prefs) async {
    final bannerMetadata = subscriptionData['bannerMetadata'] as Map<String, dynamic>?;
    if (bannerMetadata == null) return null;

    final bannerTypeName = _safeStringConversion(bannerMetadata['bannerType']);
    if (bannerTypeName == null) return [];

    if (kDebugMode) debugPrint('🧪 [BannerManager] 테스트 배너 처리: $bannerTypeName');

    final bannerType = BannerType.values.firstWhere((e) => e.name == bannerTypeName, orElse: () => BannerType.free);
    final key = _getSimpleStateBannerKey(bannerType);
    final hasUserDismissed = prefs.getBool(key) ?? false;
    
    return !hasUserDismissed ? [bannerType] : [];
  }

  /// 3. 사용량 배너 추가
  void _addUsageBanners(
    List<BannerType> activeBanners,
    String entitlement,
    Map<String, bool> usageLimitStatus,
    SharedPreferences prefs,
  ) {
    final ocrLimitReached = usageLimitStatus['ocrLimitReached'] ?? false;
    final ttsLimitReached = usageLimitStatus['ttsLimitReached'] ?? false;
    
    if (ocrLimitReached || ttsLimitReached) {
      final bannerType = entitlement == 'premium' 
        ? BannerType.usageLimitPremium 
        : BannerType.usageLimitFree;
      
      final key = _getSimpleUsageBannerKey(bannerType);
      final hasUserDismissed = prefs.getBool(key) ?? false;
      
      if (!hasUserDismissed) {
        activeBanners.add(bannerType);
        if (kDebugMode) debugPrint('✅ [BannerManager] 사용량 배너 추가: ${bannerType.name}');
      }
    }
  }
  
  /// 4. 상태 배너 추가
  void _addStateBanner(
    List<BannerType> activeBanners,
    String entitlement,
    String subscriptionStatus,
    bool hasUsedTrial,
    String? expirationDate,
    SharedPreferences prefs,
  ) {
    final isGracePeriod = _isGracePeriod(entitlement, subscriptionStatus, expirationDate);
    
    BannerType? bannerType;
    
    if (isGracePeriod) {
      bannerType = BannerType.premiumGrace;
    } else if (subscriptionStatus == 'active') {
      if (entitlement == 'trial') {
        bannerType = BannerType.trialStarted;
      } else if (entitlement == 'premium') {
        bannerType = hasUsedTrial ? BannerType.switchToPremium : BannerType.premiumStarted;
      }
    } else if (subscriptionStatus == 'cancelling') {
      bannerType = entitlement == 'trial' ? BannerType.trialCancelled : BannerType.premiumCancelled;
    } else if (subscriptionStatus == 'expired') {
      bannerType = (entitlement == 'trial' || hasUsedTrial) ? BannerType.switchToPremium : BannerType.free;
    } else if (subscriptionStatus == 'refunded') {
      bannerType = BannerType.premiumCancelled;
    } else if (subscriptionStatus == 'cancelled' && entitlement == 'free') {
      bannerType = BannerType.free;
    }
    
    if (bannerType != null) {
      final key = _getSimpleStateBannerKey(bannerType);
      final hasUserDismissed = prefs.getBool(key) ?? false;
      
      if (!hasUserDismissed) {
        activeBanners.add(bannerType);
        if (kDebugMode) debugPrint('✅ [BannerManager] 상태 배너 추가: ${bannerType.name}');
      }
    }
  }

  // ────────────────────────────────────────────────────────────────────────
  // 🔧 4. 헬퍼 메서드 섹션
  // ────────────────────────────────────────────────────────────────────────

  /// Grace Period 감지
  bool _isGracePeriod(String entitlement, String subscriptionStatus, String? expirationDate) {
    if (entitlement == 'premium' && subscriptionStatus == 'active' && expirationDate != null) {
      try {
        final expiration = DateTime.parse(expirationDate);
        final now = DateTime.now();
        final daysUntilExpiration = expiration.difference(now).inDays;
        return daysUntilExpiration <= BannerConfig.gracePeriodThresholdDays && daysUntilExpiration >= 0;
      } catch (e) {
        return false;
      }
    }
    return false;
  }
  
  /// 단순한 사용량 배너 키 생성
  String _getSimpleUsageBannerKey(BannerType type) {
    final userId = _currentUserId ?? BannerConfig.anonymousUserId;
    return '${type.name}_dismissed_$userId';
  }
  
  /// 단순한 상태 배너 키 생성
  String _getSimpleStateBannerKey(BannerType type) {
    final userId = _currentUserId ?? BannerConfig.anonymousUserId;
    // 상태가 바뀌면 새로운 배너가 표시되도록 상태 자체는 키에 포함시키지 않음.
    // 사용자가 한 종류의 상태 배너(예: trialStarted)를 닫으면,
    // 다음에 같은 상태가 되어도 다시 보이지 않음.
    return '${type.name}_dismissed_$userId';
  }

  /// 안전한 Map 변환 헬퍼
  Map<String, dynamic>? _safeMapConversion(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  /// 안전한 String 변환 헬퍼
  String? _safeStringConversion(dynamic data) {
    if (data == null) return null;
    return data.toString();
  }

  /// 안전한 Bool 변환 헬퍼
  bool? _safeBoolConversion(dynamic data) {
    if (data is bool) return data;
    if (data is String) {
      if (data.toLowerCase() == 'true') return true;
      if (data.toLowerCase() == 'false') return false;
    }
    return null;
  }
} 