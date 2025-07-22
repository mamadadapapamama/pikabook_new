/// 🎛️ Feature Flag 관리
/// 
/// 개발 중이거나 비활성화된 기능들을 제어합니다.
/// 
class FeatureFlags {
  
  // ────────────────────────────────────────────────────────────────────────
  // 💳 구독 관련 Feature Flags
  // ────────────────────────────────────────────────────────────────────────
  
  /// 월간/연간 구독 기능 (현재 비활성화)
  static const bool ENABLE_SUBSCRIPTION_PLANS = false;
  
  /// 트라이얼 플랜 기능 (현재 비활성화)  
  static const bool ENABLE_TRIAL_PLAN = false;
  
  /// 자동 갱신 구독 기능 (현재 비활성화)
  static const bool ENABLE_AUTO_RENEWAL = false;
  
  // ────────────────────────────────────────────────────────────────────────
  // 🎯 현재 활성화된 플랜 시스템
  // ────────────────────────────────────────────────────────────────────────
  
  /// 현재 지원하는 플랜: 무료 / 프리미엄 (일회성 구매)
  static const bool ENABLE_ONE_TIME_PREMIUM = true;
  
  // ────────────────────────────────────────────────────────────────────────
  // 🚨 기존 시스템 호환성을 위한 Feature Flags (현재 비활성화)
  // ────────────────────────────────────────────────────────────────────────
  
  /// 인앱 구매 기능 활성화 여부 (현재 비활성화)
  static const bool IN_APP_PURCHASE_ENABLED = false;
  
  /// 구독 업그레이드 모달 표시 여부 (현재 비활성화)
  static const bool UPGRADE_MODAL_ENABLED = false;
  
  /// 홈 화면 구독 관련 배너 표시 여부 (현재 비활성화)
  static const bool SUBSCRIPTION_BANNERS_ENABLED = false;
  
  /// 환영 모달 (온보딩 후 구독 유도) 표시 여부 (현재 비활성화)
  static const bool WELCOME_MODAL_ENABLED = false;
  
  /// 사용량 한도 도달 시 수동 업그레이드 폼으로 연결 여부 (활성화)
  static const bool MANUAL_UPGRADE_REQUEST_ENABLED = true;
  
  /// Firestore 구독 데이터 실시간 동기화 활성화 여부 (현재 활성화)
  static const bool FIRESTORE_SUBSCRIPTION_SYNC_ENABLED = true;
  
  /// 자동 구독 상태 업데이트 활성화 여부 (현재 비활성화)
  static const bool AUTO_SUBSCRIPTION_UPDATE_ENABLED = false;
  
  /// 설정 화면 플랜 카드 표시 여부 (수동 업그레이드 시스템용) (활성화)
  static const bool PLAN_CARD_ENABLED = true;
  
  /// 구독 관련 디버그 로그 출력 여부 (현재 비활성화)
  static const bool SUBSCRIPTION_DEBUG_LOGS = false;
  
  /// 구독 상태 강제 설정 (개발용) - null이면 비활성화
  static const String? FORCE_SUBSCRIPTION_STATE = null; // 'free' 또는 'premium_manual'
  
  // ────────────────────────────────────────────────────────────────────────
  // 🔧 헬퍼 함수들
  // ────────────────────────────────────────────────────────────────────────
  
  /// 구독 관련 기능이 활성화되어 있는지 확인
  static bool get isSubscriptionEnabled => ENABLE_SUBSCRIPTION_PLANS;
  
  /// 트라이얼 기능이 활성화되어 있는지 확인
  static bool get isTrialEnabled => ENABLE_TRIAL_PLAN;
  
  /// 자동 갱신이 활성화되어 있는지 확인
  static bool get isAutoRenewalEnabled => ENABLE_AUTO_RENEWAL;
  
  /// 일회성 프리미엄 구매가 활성화되어 있는지 확인
  static bool get isOneTimePremiumEnabled => ENABLE_ONE_TIME_PREMIUM;
}

/// 🎯 수동 업그레이드 관련 상수
class ManualUpgradeConstants {
  /// 수동 업그레이드 요청 폼 URL
  static const String MANUAL_UPGRADE_FORM_URL = 'https://forms.gle/YaeznYjGLiMdHmBD9';
  
  /// 수동 업그레이드 안내 메시지
  static const String MANUAL_UPGRADE_MESSAGE = 
      '무료 사용량을 모두 사용하셨습니다.\n추가 사용을 원하시면 문의 폼을 통해 수동 업그레이드를 요청해주세요.';
  
  /// 수동 업그레이드 버튼 텍스트
  static const String MANUAL_UPGRADE_BUTTON_TEXT = '수동 업그레이드 요청';
} 