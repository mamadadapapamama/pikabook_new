import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'plan_service.dart';
import 'usage_limit_service.dart';
import '../authentication/deleted_user_service.dart';

/// 배너 타입 열거형
enum BannerType {
  premiumExpired,
  trialCompleted,
  usageLimit,
}

/// 통합 배너 관리 서비스
/// InitializationManager에서 결정된 상태를 단순히 표시/숨김 관리
class BannerManager {
  // 싱글톤 패턴
  static final BannerManager _instance = BannerManager._internal();
  factory BannerManager() => _instance;
  BannerManager._internal();

  // 배너별 상태 저장
  final Map<BannerType, bool> _bannerStates = {};
  
  // 플랜별 배너 ID 저장 (프리미엄 만료, 체험 완료용)
  final Map<BannerType, String?> _bannerPlanIds = {};

  // SharedPreferences 키 정의
  static const Map<BannerType, String> _bannerKeys = {
    BannerType.premiumExpired: 'premium_expired_banner_dismissed_',
    BannerType.trialCompleted: 'trial_completed_banner_dismissed_',
    BannerType.usageLimit: 'usage_limit_banner_shown',
  };

  /// InitializationManager에서 배너 상태 설정
  void setBannerState(BannerType type, bool shouldShow, {String? planId}) {
    _bannerStates[type] = shouldShow;
    
    // 플랜 ID가 필요한 배너들
    if (type == BannerType.premiumExpired || type == BannerType.trialCompleted) {
      _bannerPlanIds[type] = planId ?? '${type.name}_${DateTime.now().millisecondsSinceEpoch}';
    }
    
    if (kDebugMode) {
      debugPrint('🎯 [BannerManager] ${type.name} 상태 설정: $shouldShow${planId != null ? ' (플랜ID: $planId)' : ''}');
    }
  }

  /// 배너 표시 여부 확인
  Future<bool> shouldShowBanner(BannerType type) async {
    try {
      final shouldShow = _bannerStates[type] ?? false;
      if (!shouldShow) return false;

      final prefs = await SharedPreferences.getInstance();
      
      // 사용량 한도 배너는 단순 처리
      if (type == BannerType.usageLimit) {
        final hasUserDismissed = prefs.getBool(_bannerKeys[type]!) ?? false;
        final result = !hasUserDismissed;
        
        if (kDebugMode) {
          debugPrint('🎯 [BannerManager] ${type.name} 표시 여부: $result (설정=$shouldShow, 사용자닫음=$hasUserDismissed)');
        }
        
        return result;
      }
      
      // 프리미엄 만료, 체험 완료 배너는 플랜별 처리
      final planId = _bannerPlanIds[type];
      if (planId == null) return false;
      
      final dismissKey = '${_bannerKeys[type]!}$planId';
      final hasUserDismissed = prefs.getBool(dismissKey) ?? false;
      final result = !hasUserDismissed;
      
      if (kDebugMode) {
        debugPrint('🎯 [BannerManager] ${type.name} 표시 여부: $result');
        debugPrint('  - 설정 상태: $shouldShow');
        debugPrint('  - 플랜 ID: $planId');
        debugPrint('  - 사용자 닫음: $hasUserDismissed');
        debugPrint('  - 닫기 키: $dismissKey');
      }
      
      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [BannerManager] ${type.name} 상태 확인 실패: $e');
      }
      return false;
    }
  }

  /// 배너 닫기 (사용자가 X 버튼 클릭 시)
  Future<void> dismissBanner(BannerType type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 사용량 한도 배너는 단순 처리
      if (type == BannerType.usageLimit) {
        await prefs.setBool(_bannerKeys[type]!, true);
        
        if (kDebugMode) {
          debugPrint('🎯 [BannerManager] ${type.name} 사용자가 배너 닫음');
        }
        return;
      }
      
      // 프리미엄 만료, 체험 완료 배너는 플랜별 처리
      final planId = _bannerPlanIds[type];
      if (planId == null) {
        if (kDebugMode) {
          debugPrint('⚠️ [BannerManager] ${type.name} 플랜 ID가 없어서 닫기 처리 불가');
        }
        return;
      }
      
      final dismissKey = '${_bannerKeys[type]!}$planId';
      await prefs.setBool(dismissKey, true);
      
      if (kDebugMode) {
        debugPrint('🎯 [BannerManager] ${type.name} 사용자가 배너 닫음 (플랜: $planId)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [BannerManager] ${type.name} 배너 닫기 실패: $e');
      }
    }
  }

  /// 배너 상태 초기화 (테스트용)
  Future<void> resetBannerState(BannerType type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 사용량 한도 배너
      if (type == BannerType.usageLimit) {
        await prefs.remove(_bannerKeys[type]!);
      } else {
        // 프리미엄 만료, 체험 완료 배너 - 모든 플랜 ID 관련 키 제거
        final keyPrefix = _bannerKeys[type]!;
        final allKeys = prefs.getKeys();
        for (final key in allKeys) {
          if (key.startsWith(keyPrefix)) {
            await prefs.remove(key);
          }
        }
      }
      
      _bannerStates[type] = false;
      _bannerPlanIds[type] = null;
      
      if (kDebugMode) {
        debugPrint('🎯 [BannerManager] ${type.name} 상태 초기화');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [BannerManager] ${type.name} 상태 초기화 실패: $e');
      }
    }
  }

  /// 모든 배너 상태 초기화 (테스트용)
  Future<void> resetAllBannerStates() async {
    for (final type in BannerType.values) {
      await resetBannerState(type);
    }
    
    if (kDebugMode) {
      debugPrint('🎯 [BannerManager] 모든 배너 상태 초기화 완료');
    }
  }

  /// 🎯 핵심: 모든 배너 결정 로직 실행
  Future<List<BannerType>> getActiveBanners() async {
    try {
      if (kDebugMode) {
        debugPrint('🎯 [BannerManager] 배너 결정 시작');
      }

      // 1. PlanService에서 최신 플랜 데이터 조회
      final planService = PlanService();
      final subscriptionDetails = await planService.getSubscriptionDetails(forceRefresh: true);
      final currentPlan = subscriptionDetails['currentPlan'] as String;
      final isFreeTrial = subscriptionDetails['isFreeTrial'] as bool;
      
      if (kDebugMode) {
        debugPrint('🎯 [BannerManager] 현재 플랜: $currentPlan, 무료체험: $isFreeTrial');
      }

      // 2. UsageService에서 최신 사용량 데이터 조회
      final usageService = UsageLimitService();
      final usageLimitStatus = await usageService.checkInitialLimitStatus(forceRefresh: true);
      
      if (kDebugMode) {
        debugPrint('🎯 [BannerManager] 사용량 상태: $usageLimitStatus');
      }

      // 3. 배너 결정 로직 실행
      final activeBanners = <BannerType>[];
      
      // 3-1. 사용량 한도 배너 결정
      final ocrLimitReached = usageLimitStatus['ocrLimitReached'] ?? false;
      final ttsLimitReached = usageLimitStatus['ttsLimitReached'] ?? false;
      if (ocrLimitReached || ttsLimitReached) {
        activeBanners.add(BannerType.usageLimit);
        setBannerState(BannerType.usageLimit, true);
      } else {
        setBannerState(BannerType.usageLimit, false);
      }

      // 3-2. 플랜 관련 배너 결정
      if (currentPlan == PlanService.PLAN_FREE) {
        await _decidePlanRelatedBanners(activeBanners, subscriptionDetails);
      } else {
        // 프리미엄 사용자는 플랜 관련 배너 없음
        setBannerState(BannerType.premiumExpired, false);
        setBannerState(BannerType.trialCompleted, false);
      }

      if (kDebugMode) {
        debugPrint('🎯 [BannerManager] 활성 배너: ${activeBanners.map((e) => e.name).toList()}');
      }

      return activeBanners;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [BannerManager] 배너 결정 실패: $e');
      }
      return [];
    }
  }

  /// 플랜 관련 배너 결정 (무료 플랜 사용자)
  Future<void> _decidePlanRelatedBanners(List<BannerType> activeBanners, Map<String, dynamic> subscriptionDetails) async {
    try {
      final deletedUserService = DeletedUserService();
      
      // 이전 플랜 히스토리 확인
      Map<String, dynamic>? lastPlanInfo;
      try {
        lastPlanInfo = await deletedUserService.getLastPlanInfo(forceRefresh: true);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ [BannerManager] 이전 플랜 히스토리 확인 실패: $e');
        }
      }

      // 현재 구독 정보에서 이력 확인
      final hasEverUsedTrial = subscriptionDetails['hasEverUsedTrial'] as bool? ?? false;
      final hasEverUsedPremium = subscriptionDetails['hasEverUsedPremium'] as bool? ?? false;

      final planId = 'plan_${DateTime.now().millisecondsSinceEpoch}';

      if (lastPlanInfo != null) {
        // 탈퇴 후 재가입 사용자
        final previousPlanType = lastPlanInfo['planType'] as String?;
        final previousIsFreeTrial = lastPlanInfo['isFreeTrial'] as bool? ?? false;

        if (previousPlanType == PlanService.PLAN_PREMIUM) {
          if (previousIsFreeTrial) {
            // 이전에 무료 체험 → Trial Completed 배너
            activeBanners.add(BannerType.trialCompleted);
            setBannerState(BannerType.trialCompleted, true, planId: planId);
            setBannerState(BannerType.premiumExpired, false);
          } else {
            // 이전에 정식 프리미엄 → Premium Expired 배너
            activeBanners.add(BannerType.premiumExpired);
            setBannerState(BannerType.premiumExpired, true, planId: planId);
            setBannerState(BannerType.trialCompleted, false);
          }
        } else {
          // 이전에도 무료 플랜 → 배너 없음
          setBannerState(BannerType.premiumExpired, false);
          setBannerState(BannerType.trialCompleted, false);
        }
      } else {
        // 이전 플랜 히스토리 없음 → 현재 구독 정보 기반
        if (hasEverUsedPremium) {
          // 프리미엄 이력 있음 → Premium Expired 배너
          activeBanners.add(BannerType.premiumExpired);
          setBannerState(BannerType.premiumExpired, true, planId: planId);
          setBannerState(BannerType.trialCompleted, false);
        } else if (hasEverUsedTrial) {
          // 체험 이력만 있음 → Trial Completed 배너
          activeBanners.add(BannerType.trialCompleted);
          setBannerState(BannerType.trialCompleted, true, planId: planId);
          setBannerState(BannerType.premiumExpired, false);
        } else {
          // 아무 이력 없음 → 배너 없음
          setBannerState(BannerType.premiumExpired, false);
          setBannerState(BannerType.trialCompleted, false);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [BannerManager] 플랜 관련 배너 결정 실패: $e');
      }
      setBannerState(BannerType.premiumExpired, false);
      setBannerState(BannerType.trialCompleted, false);
    }
  }

  /// 현재 배너 상태 디버그 출력
  void debugPrintStates() {
    if (kDebugMode) {
      debugPrint('🎯 [BannerManager] 현재 배너 상태:');
      for (final type in BannerType.values) {
        final state = _bannerStates[type] ?? false;
        final planId = _bannerPlanIds[type];
        debugPrint('  - ${type.name}: $state${planId != null ? ' (플랜ID: $planId)' : ''}');
      }
    }
  }
} 