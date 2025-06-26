import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'usage_limit_service.dart';
import 'plan_service.dart';

/// 사용량 한도 도달 배너 상태 관리 서비스
class UsageLimitBannerService {
  static final UsageLimitBannerService _instance = UsageLimitBannerService._internal();
  factory UsageLimitBannerService() => _instance;
  UsageLimitBannerService._internal();

  final UsageLimitService _usageLimitService = UsageLimitService();
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
      final key = 'usage_limit_banner_dismissed_$userId';
      return prefs.getBool(key) ?? false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UsageLimitBanner] 배너 상태 확인 실패: $e');
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
      final key = 'usage_limit_banner_dismissed_$userId';
      await prefs.setBool(key, true);
      
      if (kDebugMode) {
        debugPrint('✅ [UsageLimitBanner] 배너 임시 해제: $userId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UsageLimitBanner] 배너 해제 실패: $e');
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

      // 2. 사용량 한도 도달 여부 확인
      final hasReachedLimit = await _usageLimitService.hasReachedAnyLimit();
      if (!hasReachedLimit) return false;

      // 3. 현재 플랜 확인 (모든 플랜에서 한도 도달 시 배너 표시)
      final subscriptionDetails = await _planService.getSubscriptionDetails();
      final currentPlan = subscriptionDetails['currentPlan'] as String?;

      if (kDebugMode) {
        debugPrint('🔍 [UsageLimitBanner] 배너 표시 여부 확인:');
        debugPrint('   사용자 ID: $userId');
        debugPrint('   배너 해제됨: $isDismissed');
        debugPrint('   사용량 한도 도달: $hasReachedLimit');
        debugPrint('   현재 플랜: $currentPlan');
        debugPrint('   배너 표시: $hasReachedLimit');
      }

      return hasReachedLimit;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UsageLimitBanner] 배너 표시 여부 확인 실패: $e');
      }
      return false;
    }
  }

  /// 배너 상태 초기화 (사용량이 리셋되었을 때 호출)
  Future<void> resetBannerState() async {
    final userId = _currentUserId;
    if (userId == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'usage_limit_banner_dismissed_$userId';
      await prefs.remove(key);
      
      if (kDebugMode) {
        debugPrint('🔄 [UsageLimitBanner] 배너 상태 초기화: $userId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UsageLimitBanner] 배너 상태 초기화 실패: $e');
      }
    }
  }
} 