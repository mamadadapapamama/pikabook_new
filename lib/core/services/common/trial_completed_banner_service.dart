import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'plan_service.dart';
import 'premium_expired_banner_service.dart';

/// 체험 완료 배너 표시 관리 서비스
class TrialCompletedBannerService {
  static const String _kTrialCompletedBannerDismissedKey = 'trial_completed_banner_dismissed';
  final PlanService _planService = PlanService();
  final PremiumExpiredBannerService _premiumExpiredBannerService = PremiumExpiredBannerService();
  
  /// 배너를 표시해야 하는지 확인
  Future<bool> shouldShowBanner() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isDismissed = prefs.getBool(_kTrialCompletedBannerDismissedKey) ?? false;
      
      // 이미 해제된 경우
      if (isDismissed) return false;
      
      // 🎯 프리미엄 만료 배너가 표시되어야 하는 경우 체험 완료 배너는 숨김
      final shouldShowPremiumExpiredBanner = await _premiumExpiredBannerService.shouldShowBanner();
      if (shouldShowPremiumExpiredBanner) {
        if (kDebugMode) {
          debugPrint('🎉 [TrialCompletedBannerService] 프리미엄 만료 배너 우선 - 체험 완료 배너 숨김');
        }
        return false;
      }
      
      if (kDebugMode) {
        debugPrint('🎉 [TrialCompletedBannerService] 배너 표시 여부: true');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [TrialCompletedBannerService] 배너 표시 여부 확인 실패: $e');
      }
      return false;
    }
  }
  
  /// 배너 해제 (사용자가 닫기 버튼 클릭)
  Future<void> dismissBanner() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kTrialCompletedBannerDismissedKey, true);
      
      if (kDebugMode) {
        debugPrint('🎉 [TrialCompletedBannerService] 배너 해제됨');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [TrialCompletedBannerService] 배너 해제 실패: $e');
      }
    }
  }
  
  /// 배너 표시 트리거 (체험 완료 시 호출)
  Future<void> triggerBanner() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kTrialCompletedBannerDismissedKey, false);
      
      if (kDebugMode) {
        debugPrint('🎉 [TrialCompletedBannerService] 배너 트리거됨');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [TrialCompletedBannerService] 배너 트리거 실패: $e');
      }
    }
  }
  
  /// 배너 상태 초기화 (테스트용)
  Future<void> resetBannerState() async {
    if (!kDebugMode) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kTrialCompletedBannerDismissedKey);
      
      if (kDebugMode) {
        debugPrint('🎉 [TrialCompletedBannerService] 배너 상태 초기화됨');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [TrialCompletedBannerService] 배너 상태 초기화 실패: $e');
      }
    }
  }
} 