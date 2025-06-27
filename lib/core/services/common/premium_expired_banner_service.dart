import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 프리미엄 만료 배너 서비스
/// InitializationManager에서 결정된 상태를 단순히 표시/숨김 관리
/// 플랜별 닫기 상태 추적으로 플랜 변경 시 배너 재표시
class PremiumExpiredBannerService {
  static const String _bannerStateKey = 'premium_expired_banner_shown';
  static const String _bannerStateKeyPrefix = 'premium_expired_banner_dismissed_';
  
  // 싱글톤 패턴
  static final PremiumExpiredBannerService _instance = PremiumExpiredBannerService._internal();
  factory PremiumExpiredBannerService() => _instance;
  PremiumExpiredBannerService._internal();
  
  // 현재 배너 표시 상태 (InitializationManager에서 설정)
  bool _shouldShow = false;
  
  // 현재 플랜 정보 (닫기 상태 추적용)
  String? _currentPlanId;
  
  /// InitializationManager에서 배너 상태 설정 (플랜 정보 포함)
  void setBannerState(bool shouldShow, {String? planId}) {
    _shouldShow = shouldShow;
    _currentPlanId = planId ?? 'premium_expired_${DateTime.now().millisecondsSinceEpoch}';
    
    if (kDebugMode) {
      debugPrint('🎯 [PremiumExpiredBanner] 상태 설정: $shouldShow (플랜ID: $_currentPlanId)');
    }
  }
  
  /// 배너 표시 여부 확인 (플랜별 닫기 상태 확인)
  Future<bool> shouldShowBanner() async {
    try {
      if (!_shouldShow || _currentPlanId == null) {
        return false;
      }
      
      // 현재 플랜에 대해 사용자가 배너를 닫았는지 확인
      final prefs = await SharedPreferences.getInstance();
      final dismissKey = '$_bannerStateKeyPrefix$_currentPlanId';
      final hasUserDismissed = prefs.getBool(dismissKey) ?? false;
      
      // 사용자가 현재 플랜에 대해 닫지 않았고, InitializationManager에서 true로 설정된 경우만 표시
      final result = !hasUserDismissed;
      
      if (kDebugMode) {
        debugPrint('🎯 [PremiumExpiredBanner] 표시 여부: $result');
        debugPrint('  - 설정 상태: $_shouldShow');
        debugPrint('  - 플랜 ID: $_currentPlanId');
        debugPrint('  - 사용자 닫음: $hasUserDismissed');
        debugPrint('  - 닫기 키: $dismissKey');
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
      if (_currentPlanId == null) {
        if (kDebugMode) {
          debugPrint('⚠️ [PremiumExpiredBanner] 플랜 ID가 없어서 닫기 처리 불가');
        }
        return;
      }
      
      final prefs = await SharedPreferences.getInstance();
      final dismissKey = '$_bannerStateKeyPrefix$_currentPlanId';
      await prefs.setBool(dismissKey, true);
      
      if (kDebugMode) {
        debugPrint('🎯 [PremiumExpiredBanner] 사용자가 배너 닫음 (플랜: $_currentPlanId)');
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