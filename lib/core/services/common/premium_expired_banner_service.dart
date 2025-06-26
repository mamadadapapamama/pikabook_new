import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 프리미엄 만료 배너 서비스
/// InitializationManager에서 결정된 상태를 단순히 표시/숨김 관리
class PremiumExpiredBannerService {
  static const String _bannerStateKey = 'premium_expired_banner_shown';
  static const String _bannerStateKeyPrefix = 'premium_expired_banner_state_';
  
  // 싱글톤 패턴
  static final PremiumExpiredBannerService _instance = PremiumExpiredBannerService._internal();
  factory PremiumExpiredBannerService() => _instance;
  PremiumExpiredBannerService._internal();
  
  // 현재 배너 표시 상태 (InitializationManager에서 설정)
  bool _shouldShow = false;
  
  /// InitializationManager에서 배너 상태 설정
  void setBannerState(bool shouldShow) {
    _shouldShow = shouldShow;
    if (kDebugMode) {
      debugPrint('🎯 [PremiumExpiredBanner] 상태 설정: $shouldShow');
    }
  }
  
  /// 배너 표시 여부 확인 (단순히 설정된 상태 반환)
  Future<bool> shouldShowBanner() async {
    try {
      // 사용자가 배너를 닫았는지 확인
      final prefs = await SharedPreferences.getInstance();
      final hasUserDismissed = prefs.getBool(_bannerStateKey) ?? false;
      
      // 사용자가 닫지 않았고, InitializationManager에서 true로 설정된 경우만 표시
      final result = _shouldShow && !hasUserDismissed;
      
      if (kDebugMode) {
        debugPrint('🎯 [PremiumExpiredBanner] 표시 여부: $result (설정=$_shouldShow, 사용자닫음=$hasUserDismissed)');
      }
      
      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [PremiumExpiredBanner] 상태 확인 실패: $e');
      }
      return false;
    }
  }
  
  /// 배너 닫기 (사용자가 X 버튼 클릭 시)
  Future<void> dismissBanner() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_bannerStateKey, true);
      
      if (kDebugMode) {
        debugPrint('🎯 [PremiumExpiredBanner] 사용자가 배너 닫음');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [PremiumExpiredBanner] 배너 닫기 실패: $e');
      }
    }
  }
  
  /// 배너 상태 초기화 (테스트용)
  Future<void> resetBannerState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_bannerStateKey);
      _shouldShow = false;
      
      if (kDebugMode) {
        debugPrint('🎯 [PremiumExpiredBanner] 상태 초기화');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [PremiumExpiredBanner] 상태 초기화 실패: $e');
      }
    }
  }
} 