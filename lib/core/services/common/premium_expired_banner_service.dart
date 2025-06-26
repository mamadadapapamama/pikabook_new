import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'plan_service.dart';

/// 프리미엄 만료 배너 상태 관리 서비스
class PremiumExpiredBannerService {
  static final PremiumExpiredBannerService _instance = PremiumExpiredBannerService._internal();
  factory PremiumExpiredBannerService() => _instance;
  PremiumExpiredBannerService._internal();

  final PlanService _planService = PlanService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// 현재 사용자 ID
  String? get _currentUserId => _auth.currentUser?.uid;

  /// 배너 해제 상태 확인
  Future<bool> isBannerDismissed() async {
    final userId = _currentUserId;
    if (userId == null) return true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'premium_expired_banner_dismissed_$userId';
      return prefs.getBool(key) ?? false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [PremiumExpiredBanner] 배너 상태 확인 실패: $e');
      }
      return true; // 오류 시 배너 숨김
    }
  }

  /// 배너 해제 상태 설정
  Future<void> dismissBanner() async {
    final userId = _currentUserId;
    if (userId == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'premium_expired_banner_dismissed_$userId';
      await prefs.setBool(key, true);
      
      if (kDebugMode) {
        debugPrint('✅ [PremiumExpiredBanner] 배너 영구 해제: $userId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [PremiumExpiredBanner] 배너 해제 실패: $e');
      }
    }
  }

  /// 배너 표시 여부 확인
  Future<bool> shouldShowBanner() async {
    final userId = _currentUserId;
    if (userId == null) return false;

    try {
      // 1. 이미 해제된 배너인지 확인
      final isDismissed = await isBannerDismissed();
      if (isDismissed) return false;

      // 2. 플랜 변경 감지 (프리미엄 → 무료)
      final hasPlanChangedToFree = await _planService.hasPlanChangedToFree();
      if (!hasPlanChangedToFree) return false;

      // 3. 현재 구독 상태 확인 (만료 상태인지)
      final subscriptionDetails = await _planService.getSubscriptionDetails();
      final currentPlan = subscriptionDetails['currentPlan'] as String?;
      final status = subscriptionDetails['status'] as String?;

      // 현재 무료이고, 이전 구독이 만료 상태인 경우
      final shouldShow = currentPlan == PlanService.PLAN_FREE && 
                        status == 'expired';

      if (kDebugMode) {
        debugPrint('🔍 [PremiumExpiredBanner] 배너 표시 여부 확인:');
        debugPrint('   사용자 ID: $userId');
        debugPrint('   배너 해제됨: $isDismissed');
        debugPrint('   플랜 변경 (프리미엄→무료): $hasPlanChangedToFree');
        debugPrint('   현재 플랜: $currentPlan');
        debugPrint('   구독 상태: $status');
        debugPrint('   배너 표시: $shouldShow');
      }

      return shouldShow;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [PremiumExpiredBanner] 배너 표시 여부 확인 실패: $e');
      }
      return false;
    }
  }

  /// 배너 상태 초기화 (테스트용)
  Future<void> resetBannerState() async {
    if (!kDebugMode) return;

    final userId = _currentUserId;
    if (userId == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'premium_expired_banner_dismissed_$userId';
      await prefs.remove(key);
      
      if (kDebugMode) {
        debugPrint('🔄 [PremiumExpiredBanner] 배너 상태 초기화: $userId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [PremiumExpiredBanner] 배너 상태 초기화 실패: $e');
      }
    }
  }
} 