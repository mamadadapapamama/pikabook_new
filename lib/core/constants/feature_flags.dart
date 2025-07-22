/// 🎯 앱 기능 활성화/비활성화를 위한 Feature Flag
/// 
/// 심사 제출 시 구독 기능을 임시 비활성화하기 위해 사용됩니다.
/// 심사 통과 후 다시 활성화할 수 있습니다.
class FeatureFlags {
  // ────────────────────────────────────────────────────────────────────────
  // 🚨 구독 관련 기능 플래그 (심사용 임시 비활성화)
  // ────────────────────────────────────────────────────────────────────────
  
  /// 인앱 구매 기능 활성화 여부
  static const bool IN_APP_PURCHASE_ENABLED = false;
  
  /// 구독 업그레이드 모달 표시 여부
  static const bool UPGRADE_MODAL_ENABLED = false;
  
  /// 홈 화면 구독 관련 배너 표시 여부
  static const bool SUBSCRIPTION_BANNERS_ENABLED = false;
  
  /// 환영 모달 (온보딩 후 구독 유도) 표시 여부
  static const bool WELCOME_MODAL_ENABLED = false;
  
  // ────────────────────────────────────────────────────────────────────────
  // ✅ 사용량 제한 관련 플래그 (유지됨)
  // ────────────────────────────────────────────────────────────────────────
  
  /// 사용량 제한 체크 활성화 여부 (유지)
  static const bool USAGE_LIMITS_ENABLED = true;
  
  /// 사용량 한도 도달 시 수동 업그레이드 폼으로 연결 여부 (유지)
  static const bool MANUAL_UPGRADE_REQUEST_ENABLED = true;
  
  // ────────────────────────────────────────────────────────────────────────
  // 🎯 구독 상태 관리 플래그
  // ────────────────────────────────────────────────────────────────────────
  
  /// Firestore 구독 데이터 실시간 동기화 활성화 여부
  static const bool FIRESTORE_SUBSCRIPTION_SYNC_ENABLED = false;
  
  /// 자동 구독 상태 업데이트 활성화 여부
  static const bool AUTO_SUBSCRIPTION_UPDATE_ENABLED = false;
  
  // ────────────────────────────────────────────────────────────────────────
  // 📱 UI 관련 플래그
  // ────────────────────────────────────────────────────────────────────────
  
  /// 설정 화면 플랜 카드 표시 여부
  static const bool PLAN_CARD_ENABLED = false;
  
  /// 설정 화면 구독 관련 CTA 버튼 표시 여부
  static const bool SUBSCRIPTION_CTA_ENABLED = false;
  
  // ────────────────────────────────────────────────────────────────────────
  // 🔧 개발/디버그 플래그
  // ────────────────────────────────────────────────────────────────────────
  
  /// 구독 관련 디버그 로그 출력 여부
  static const bool SUBSCRIPTION_DEBUG_LOGS = false;
  
  /// 구독 상태 강제 설정 (개발용)
  static const String? FORCE_SUBSCRIPTION_STATE = null; // 'free' 또는 'premium_manual'
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