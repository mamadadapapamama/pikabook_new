import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/subscription_state.dart';
import '../common/plan_service.dart';
import '../common/usage_limit_service.dart';
import '../authentication/deleted_user_service.dart';

/// 구독 상태를 통합 관리하는 서비스
/// 모든 상태 로직을 한 곳에서 처리하여 일관성 보장
class SubscriptionStatusService {
  // 싱글톤 패턴
  static final SubscriptionStatusService _instance = SubscriptionStatusService._internal();
  factory SubscriptionStatusService() => _instance;
  SubscriptionStatusService._internal();

  final PlanService _planService = PlanService();
  final UsageLimitService _usageLimitService = UsageLimitService();
  final DeletedUserService _deletedUserService = DeletedUserService();

  /// 🎯 핵심: 모든 구독 상태를 한 번에 조회
  static Future<SubscriptionState> fetchStatus({bool forceRefresh = false}) async {
    final instance = SubscriptionStatusService();
    return instance._fetchStatus(forceRefresh: forceRefresh);
  }

  /// 내부 구현: 상태 조회 로직
  Future<SubscriptionState> _fetchStatus({bool forceRefresh = false}) async {
    try {
      if (kDebugMode) {
        debugPrint('🎯 [SubscriptionStatusService] 상태 조회 시작 (forceRefresh: $forceRefresh)');
      }

      // 1. 로그인 상태 확인
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        if (kDebugMode) {
          debugPrint('🎯 [SubscriptionStatusService] 로그아웃 상태 - 기본 상태 반환');
        }
        return SubscriptionState.defaultState();
      }

      // 2. 플랜 정보 조회
      final subscriptionDetails = await _planService.getSubscriptionDetails(forceRefresh: forceRefresh);
      final currentPlan = subscriptionDetails['currentPlan'] as String;
      final isFreeTrial = subscriptionDetails['isFreeTrial'] as bool? ?? false;
      final daysRemaining = subscriptionDetails['daysRemaining'] as int? ?? 0;
      final hasEverUsedTrial = subscriptionDetails['hasEverUsedTrial'] as bool? ?? false;
      final hasEverUsedPremium = subscriptionDetails['hasEverUsedPremium'] as bool? ?? false;

      // 3. 사용량 정보 조회
      final usageLimitStatus = await _usageLimitService.checkInitialLimitStatus(forceRefresh: forceRefresh);
      final ocrLimitReached = usageLimitStatus['ocrLimitReached'] ?? false;
      final ttsLimitReached = usageLimitStatus['ttsLimitReached'] ?? false;
      final hasUsageLimitReached = ocrLimitReached || ttsLimitReached;

      // 4. 상태 계산
      final isTrial = currentPlan == PlanService.PLAN_PREMIUM && isFreeTrial;
      final isPremium = currentPlan == PlanService.PLAN_PREMIUM && !isFreeTrial;
      final isExpired = currentPlan == PlanService.PLAN_FREE;
      final isTrialExpiringSoon = isTrial && daysRemaining <= 1;

      // 5. 활성 배너 결정
      final activeBanners = await _determineActiveBanners(
        currentPlan: currentPlan,
        isFreeTrial: isFreeTrial,
        hasEverUsedTrial: hasEverUsedTrial,
        hasEverUsedPremium: hasEverUsedPremium,
        hasUsageLimitReached: hasUsageLimitReached,
        subscriptionDetails: subscriptionDetails,
      );

      // 6. 상태 메시지 생성
      final statusMessage = _generateStatusMessage(
        isTrial: isTrial,
        isPremium: isPremium,
        isExpired: isExpired,
        daysRemaining: daysRemaining,
      );

      final result = SubscriptionState(
        isTrial: isTrial,
        isTrialExpiringSoon: isTrialExpiringSoon,
        isPremium: isPremium,
        isExpired: isExpired,
        hasUsageLimitReached: hasUsageLimitReached,
        daysRemaining: daysRemaining,
        activeBanners: activeBanners,
        statusMessage: statusMessage,
      );

      if (kDebugMode) {
        debugPrint('🎯 [SubscriptionStatusService] 상태 조회 완료: $result');
      }

      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SubscriptionStatusService] 상태 조회 실패: $e');
      }
      return SubscriptionState.defaultState();
    }
  }

  /// 활성 배너 결정 로직
  Future<List<BannerType>> _determineActiveBanners({
    required String currentPlan,
    required bool isFreeTrial,
    required bool hasEverUsedTrial,
    required bool hasEverUsedPremium,
    required bool hasUsageLimitReached,
    required Map<String, dynamic> subscriptionDetails,
  }) async {
    final activeBanners = <BannerType>[];

    try {
      // 1. 사용량 한도 배너
      if (hasUsageLimitReached) {
        activeBanners.add(BannerType.usageLimit);
      }

      // 2. 플랜 관련 배너 (무료 플랜 사용자만)
      if (currentPlan == PlanService.PLAN_FREE) {
        final planBanner = await _determinePlanBanner(
          hasEverUsedTrial: hasEverUsedTrial,
          hasEverUsedPremium: hasEverUsedPremium,
          subscriptionDetails: subscriptionDetails,
        );
        
        if (planBanner != null) {
          activeBanners.add(planBanner);
        }
      }

      if (kDebugMode) {
        debugPrint('🎯 [SubscriptionStatusService] 활성 배너: ${activeBanners.map((e) => e.name).toList()}');
      }

      return activeBanners;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SubscriptionStatusService] 배너 결정 실패: $e');
      }
      return [];
    }
  }

  /// 플랜 관련 배너 결정
  Future<BannerType?> _determinePlanBanner({
    required bool hasEverUsedTrial,
    required bool hasEverUsedPremium,
    required Map<String, dynamic> subscriptionDetails,
  }) async {
    try {
      // 이전 플랜 히스토리 확인
      Map<String, dynamic>? lastPlanInfo;
      try {
        lastPlanInfo = await _deletedUserService.getLastPlanInfo(forceRefresh: true);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ [SubscriptionStatusService] 이전 플랜 히스토리 확인 실패: $e');
        }
      }

      if (lastPlanInfo != null) {
        // 탈퇴 후 재가입 사용자
        final previousPlanType = lastPlanInfo['planType'] as String?;
        final previousIsFreeTrial = lastPlanInfo['isFreeTrial'] as bool? ?? false;

        if (previousPlanType == PlanService.PLAN_PREMIUM) {
          if (previousIsFreeTrial) {
            return BannerType.trialCompleted;
          } else {
            return BannerType.premiumExpired;
          }
        }
      } else {
        // 이전 플랜 히스토리 없음 → 현재 구독 정보 기반
        if (hasEverUsedPremium) {
          return BannerType.premiumExpired;
        } else if (hasEverUsedTrial) {
          return BannerType.trialCompleted;
        }
      }

      return null; // 배너 없음
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SubscriptionStatusService] 플랜 배너 결정 실패: $e');
      }
      return null;
    }
  }

  /// 상태 메시지 생성
  String _generateStatusMessage({
    required bool isTrial,
    required bool isPremium,
    required bool isExpired,
    required int daysRemaining,
  }) {
    if (isPremium) {
      return '프리미엄 사용자';
    } else if (isTrial) {
      if (daysRemaining > 0) {
        return '무료체험 ${daysRemaining}일 남음';
      } else {
        return '무료체험 곧 종료';
      }
    } else if (isExpired) {
      return '무료 플랜';
    } else {
      return '상태 확인 중';
    }
  }

  /// 디버그 정보 출력
  static Future<void> printDebugInfo() async {
    if (!kDebugMode) return;

    try {
      final status = await fetchStatus(forceRefresh: true);
      debugPrint('=== SubscriptionStatusService Debug Info ===');
      debugPrint(status.toString());
      debugPrint('===========================================');
    } catch (e) {
      debugPrint('❌ [SubscriptionStatusService] 디버그 정보 출력 실패: $e');
    }
  }
} 