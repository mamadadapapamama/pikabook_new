import 'banner_manager.dart';

/// 🎯 배너 관리 설정 상수들
/// 
/// BannerManager에서 사용하는 모든 설정 상수들을 중앙화하여 관리
class BannerConfig {
  // ────────────────────────────────────────────────────────────────────────
  // 🔑 SharedPreferences 키 설정
  // ────────────────────────────────────────────────────────────────────────
  
  /// 배너 타입별 SharedPreferences 키 접두사
  static const Map<BannerType, String> bannerKeyPrefixes = {
    BannerType.free: 'free_banner_dismissed_',
    BannerType.trialStarted: 'trial_started_banner_dismissed_',
    BannerType.trialCancelled: 'trial_cancelled_banner_dismissed_',
    BannerType.switchToPremium: 'switch_to_premium_banner_dismissed_',
    BannerType.premiumStarted: 'premium_started_banner_dismissed_',
    BannerType.premiumGrace: 'premium_grace_banner_dismissed_',
    BannerType.premiumCancelled: 'premium_cancelled_banner_dismissed_',
    BannerType.usageLimitFree: 'usage_limit_free_banner_shown_',
    BannerType.usageLimitPremium: 'usage_limit_premium_banner_shown_',
  };

  // ────────────────────────────────────────────────────────────────────────
  // ⏰ 시간 관련 설정
  // ────────────────────────────────────────────────────────────────────────
  
  /// Grace Period 감지 임계값 (일)
  static const int gracePeriodThresholdDays = 7;
  
  /// 캐시 유효 시간 (분)
  static const int cacheValidityMinutes = 5;

  // ────────────────────────────────────────────────────────────────────────
  // 🗑️ 제거: 플랜 ID 관련 설정 (더 이상 필요 없음)
  // ────────────────────────────────────────────────────────────────────────
  
  /*
  /// 플랜 ID가 필요한 배너 타입들
  static const Set<BannerType> planIdRequiredBanners = {
    BannerType.free,
    BannerType.trialStarted,
    BannerType.trialCancelled,
    BannerType.switchToPremium,
    BannerType.premiumStarted,
    BannerType.switchToFree,
    BannerType.premiumCancelled,
    BannerType.premiumGrace,
  };
  */

  // ────────────────────────────────────────────────────────────────────────
  // 🔧 기본값 설정
  // ────────────────────────────────────────────────────────────────────────
  
  /// 기본 entitlement
  static const String defaultEntitlement = 'free';
  
  /// 기본 subscriptionStatus
  static const String defaultSubscriptionStatus = 'cancelled';
  
  /// 기본 hasUsedTrial
  static const bool defaultHasUsedTrial = false;
  
  /// 익명 사용자 ID
  static const String anonymousUserId = 'anonymous';

  // ────────────────────────────────────────────────────────────────────────
  // 🎨 디버그 메시지 설정
  // ────────────────────────────────────────────────────────────────────────
  
  /// 디버그 메시지 활성화 여부
  static const bool enableDebugMessages = true;
  
  /// 성능 측정 활성화 여부
  static const bool enablePerformanceTracking = true;
} 