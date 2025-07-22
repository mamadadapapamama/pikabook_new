/// 🎯 구독 관련 모든 상수 및 텍스트 중앙 관리
/// 
/// 이 파일에서 모든 구독 상태, 배너 텍스트, UI 표시 텍스트를 관리합니다.
/// 
class SubscriptionConstants {
  
  // ────────────────────────────────────────────────────────────────────────
  // 🔑 서버 상수 (서버와 정확히 일치해야 함)
  // ────────────────────────────────────────────────────────────────────────
  
  /// 서버 Entitlement 상수
  static const String ENTITLEMENT_FREE = 'FREE';
  static const String ENTITLEMENT_TRIAL = 'TRIAL';
  static const String ENTITLEMENT_PREMIUM = 'PREMIUM';
  
  /// 서버 SubscriptionStatus 상수 (숫자)
  static const int STATUS_ACTIVE = 1;        // 활성 (정상 구독, 유예 기간 포함)
  static const int STATUS_EXPIRED = 2;       // 만료됨
  static const int STATUS_REFUNDED = 3;      // 환불됨
  static const int STATUS_GRACE_PERIOD = 4;  // 유예 기간
  static const int STATUS_UNKNOWN = 5;       // 알 수 없음 (오류 등)
  static const int STATUS_INACTIVE = 6;      // 비활성 (구독 안 함)
  static const int STATUS_CANCELLED = 7;     // 취소됨 (만료 예정)
  static const int STATUS_TRIAL = 8;         // 무료 체험
  static const int STATUS_PROMOTION = 9;     // 프로모션
  static const int STATUS_FAMILY_SHARED = 10; // 가족 공유
  static const int STATUS_IN_UPGRADE = 11;   // 업그레이드/다운그레이드 진행 중
  static const int STATUS_ON_HOLD = 12;      // 계정 보류
  static const int STATUS_UNVERIFIED = 13;   // 구매 정보 미확인 (JWS 전송 필요)

  // ────────────────────────────────────────────────────────────────────────
  // 📱 플랜 표시 텍스트
  // ────────────────────────────────────────────────────────────────────────
  
  /// 플랜 이름 (UI 표시용)
  static const Map<String, String> PLAN_DISPLAY_NAMES = {
    'free': '무료',
    'premium_monthly': '프리미엄 (월간)',
    'premium_yearly': '프리미엄 (연간)',
  };
  
  /// 플랜 상태 표시 텍스트
  static const Map<String, String> PLAN_STATUS_DISPLAY = {
    'active': '활성',
    'cancelling': '취소 예정',
    'expired': '만료됨',
    'unverified': '확인 중',
    'unknown': '알 수 없음',
  };

  // ────────────────────────────────────────────────────────────────────────
  // 🎯 배너 텍스트 (BannerType별)
  // ────────────────────────────────────────────────────────────────────────
  
  static const Map<String, Map<String, String?>> BANNER_TEXTS = {
    'free': {
      'title': '🎯 무료 플랜 이용 중',
      'subtitle': '더 많은 기능을 사용해보세요!',
      'buttonText': '모든 플랜 보기',
    },
    'trialStarted': {
      'title': '🎉 7일 무료체험 시작!',
      'subtitle': '프리미엄 기능을 마음껏 사용해보세요',
      'buttonText': null, // 닫기만 가능
    },
    'premiumStarted': {
      'title': '🎉 프리미엄 구독 시작!',
      'subtitle': '모든 프리미엄 기능을 이용하실 수 있습니다',
      'buttonText': null, // 닫기만 가능
    },
    'trialCancelled': {
      'title': '📅 무료체험이 취소되었습니다',
      'subtitle': '언제든지 다시 시작하실 수 있어요',
      'buttonText': '모든 플랜 보기',
    },
    'premiumCancelled': {
      'title': '📅 프리미엄 구독이 취소되었습니다',
      'subtitle': '구독 기간이 끝날 때까지 계속 이용 가능합니다',
      'buttonText': '앱스토어에서 관리하기',
    },
    'switchToPremium': {
      'title': '💎 프리미엄 월 구독으로 전환되었습니다.',
      'subtitle': '7일 무료 체험이 끝났습니다. 프리미엄 기능을 마음껏 사용해보세요.',
      'buttonText': null,
    },
    'premiumGrace': {
      'title': '⚠️ 결제 문제가 발생했습니다',
      'subtitle': '앱스토어에서 결제 정보를 확인해주세요',
      'buttonText': '앱스토어에서 관리하기',
    },
    'usageLimitFree': {
      'title': '📊 무료 플랜 사용량 한도 도달',
      'subtitle': '프리미엄으로 업그레이드하여 무제한 이용하세요',
      'buttonText': '모든 플랜 보기',
    },
    'usageLimitPremium': {
      'title': '📊 프리미엄 사용량 한도 도달',
      'subtitle': '더 많은 사용량이 필요하시면 문의해주세요',
      'buttonText': '문의하기',
    },
  };

  // ────────────────────────────────────────────────────────────────────────
  // 💬 스낵바/알림 메시지
  // ────────────────────────────────────────────────────────────────────────
  
  static const Map<String, String> PURCHASE_SUCCESS_MESSAGES = {
    'premium_monthly': '🎉 프리미엄 월간 구독이 시작되었습니다!',
    'premium_yearly': '🎉 프리미엄 연간 구독이 시작되었습니다!',
  };
  
  static const Map<String, String> TRIAL_MESSAGES = {
    'started': '🎉 7일 무료체험이 시작되었습니다!',
    'ending_soon': '📅 무료체험이 내일 종료됩니다',
    'ended': '📅 무료체험이 종료되고 프리미엄 월 구독으로 전환되었습니다.',
  };

  // ────────────────────────────────────────────────────────────────────────
  // 🎯 CTA 버튼 텍스트 (상태별) - 수동 업그레이드 시스템용
  // ────────────────────────────────────────────────────────────────────────
  
  static const Map<String, String> CTA_TEXTS = {
    'free_active': '수동 업그레이드 요청',
    'premium_active': '현재 프리미엄 이용 중',
    'premium_cancelling': '현재 프리미엄 이용 중',
    'premium_expired': '수동 업그레이드 요청',
    'trial_active': '현재 프리미엄 이용 중',
    'trial_cancelling': '현재 프리미엄 이용 중',
    'trial_expired': '수동 업그레이드 요청',
  };

  // ────────────────────────────────────────────────────────────────────────
  // 🔧 헬퍼 함수들
  // ────────────────────────────────────────────────────────────────────────
  
  /// Entitlement + Status 조합으로 배너 타입 결정
  static String? getBannerType(String entitlement, int subscriptionStatus) {
    // 기본 entitlement 배너
    switch (entitlement.toUpperCase()) {
      case 'FREE':
        return 'free';
      case 'TRIAL':
        return 'trialStarted';
      case 'PREMIUM':
        return 'premiumStarted';
    }
    
    // 상태 기반 추가 배너
    if (subscriptionStatus == STATUS_CANCELLED) {
      if (entitlement.toUpperCase() == 'PREMIUM') {
        return 'premiumCancelled';
      } else if (entitlement.toUpperCase() == 'TRIAL') {
        return 'trialCancelled';
      }
    } else if (subscriptionStatus == STATUS_EXPIRED) {
      if (entitlement.toUpperCase() == 'PREMIUM' || entitlement.toUpperCase() == 'TRIAL') {
        return 'switchToPremium';
      }
    } else if (subscriptionStatus == STATUS_GRACE_PERIOD) {
      return 'premiumGrace';
    }
    
    return null;
  }
  
  /// 플랜 표시 이름 가져오기
  static String getPlanDisplayName(String planId) {
    return PLAN_DISPLAY_NAMES[planId] ?? '알 수 없는 플랜';
  }
  
  /// CTA 텍스트 가져오기
  static String getCTAText(String entitlement, String status) {
    final key = '${entitlement.toLowerCase()}_${status.toLowerCase()}';
    return CTA_TEXTS[key] ?? '모든 플랜 보기';
  }
  
  /// 구매 성공 메시지 가져오기
  static String getPurchaseSuccessMessage(String productId) {
    return PURCHASE_SUCCESS_MESSAGES[productId] ?? '구매가 완료되었습니다!';
  }
} 