import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'usage_limit_service.dart';
import '../authentication/deleted_user_service.dart';
import '../subscription/subscription_entitlement_engine.dart';
import '../../models/plan_status.dart';

/// 배너 타입 열거형
enum BannerType {
  premiumExpired,
  trialCompleted,
  trialCancelled,     // 🆕 프리미엄 체험 취소
  usageLimitFree,     // 무료 플랜 사용량 한도 → 업그레이드 모달
  usageLimitPremium,  // 프리미엄 플랜 사용량 한도 → 문의 폼
}

extension BannerTypeExtension on BannerType {
  String get name {
    switch (this) {
      case BannerType.premiumExpired:
        return 'premiumExpired';
      case BannerType.trialCompleted:
        return 'trialCompleted';
      case BannerType.trialCancelled:
        return 'trialCancelled';
      case BannerType.usageLimitFree:
        return 'usageLimitFree';
      case BannerType.usageLimitPremium:
        return 'usageLimitPremium';
    }
  }

  String get title {
    switch (this) {
      case BannerType.premiumExpired:
        return '💎 프리미엄 만료';
      case BannerType.trialCompleted:
        return '⏰ 프리미엄 체험 종료';
      case BannerType.trialCancelled:
        return '⏰ 체험 자동 갱신 취소됨';
      case BannerType.usageLimitFree:
        return '⚠️ 사용량 한도 도달';
      case BannerType.usageLimitPremium:
        return '⚠️ 사용량 한도 도달';
    }
  }

  String get subtitle {
    switch (this) {
      case BannerType.premiumExpired:
        return '프리미엄 혜택이 만료되었습니다. 계속 사용하려면 다시 구독하세요';
      case BannerType.trialCompleted:
        return '프리미엄 체험이 종료되어 무료 플랜으로 전환되었습니다. 프리미엄을 계속 사용하려면 업그레이드하세요';
      case BannerType.trialCancelled:
        return '체험 기간 종료 시 무료 플랜으로 전환됩니다. 계속 사용하려면 구독하세요';
      case BannerType.usageLimitFree:
        return '프리미엄으로 업그레이드하여 무제한으로 사용하세요';
      case BannerType.usageLimitPremium:
        return '추가 사용량이 필요하시면 문의해 주세요';
    }
  }
}

/// 통합 배너 관리 서비스
/// 구독 상태에 따른 배너 표시/숨김 관리
class BannerManager {
  // 싱글톤 패턴
  static final BannerManager _instance = BannerManager._internal();
  factory BannerManager() => _instance;
  BannerManager._internal();

  // 배너별 상태 저장
  final Map<BannerType, bool> _bannerStates = {};
  
  // 플랜별 배너 ID 저장 (프리미엄 만료, 체험 완료용)
  final Map<BannerType, String?> _bannerPlanIds = {};
  
  // 🎯 새로운 Source of Truth 사용
  final SubscriptionEntitlementEngine _entitlementEngine = SubscriptionEntitlementEngine();
  
  // 플랜 상수 (PlanService 대신)
  static const String PLAN_FREE = 'free';
  static const String PLAN_PREMIUM = 'premium';

  // SharedPreferences 키 정의
  static const Map<BannerType, String> _bannerKeys = {
    BannerType.premiumExpired: 'premium_expired_banner_dismissed_',
    BannerType.trialCompleted: 'trial_completed_banner_dismissed_',
    BannerType.trialCancelled: 'trial_cancelled_banner_dismissed_',
    BannerType.usageLimitFree: 'usage_limit_free_banner_shown',
    BannerType.usageLimitPremium: 'usage_limit_premium_banner_shown',
  };

  /// 구독 상태에 따른 배너 상태 설정
  void setBannerState(BannerType type, bool shouldShow, {String? planId}) {
    _bannerStates[type] = shouldShow;
    
    // 플랜 ID가 필요한 배너들
    if (type == BannerType.premiumExpired || type == BannerType.trialCompleted || type == BannerType.trialCancelled) {
      _bannerPlanIds[type] = planId ?? '${type.name}_${DateTime.now().millisecondsSinceEpoch}';
    }
    
    if (kDebugMode) {
      debugPrint('🎯 [BannerManager] ${type.name} 상태 설정: $shouldShow${planId != null ? ' (플랜ID: $planId)' : ''}');
    }
  }

  /// 배너 표시 여부 확인
  Future<bool> shouldShowBanner(BannerType type) async {
    try {
      if (kDebugMode) {
        debugPrint('🔍 [BannerManager] shouldShowBanner 확인: ${type.name}');
      }
      
      final shouldShow = _bannerStates[type] ?? false;
      if (!shouldShow) {
        if (kDebugMode) {
          debugPrint('🔍 [BannerManager] ${type.name} 배너 상태가 false → 표시 안함');
        }
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      
      // 사용량 한도 배너는 단순 처리
      if (type == BannerType.usageLimitFree || type == BannerType.usageLimitPremium) {
        final key = _bannerKeys[type]!;
        final hasUserDismissed = prefs.getBool(key) ?? false;
        final result = !hasUserDismissed;
        
        if (kDebugMode) {
          debugPrint('🔍 [BannerManager] ${type.name} 사용량 한도 배너 표시 여부: $result');
          debugPrint('   설정 상태: $shouldShow');
          debugPrint('   확인 키: $key');
          debugPrint('   사용자 닫음: $hasUserDismissed');
        }
        
        return result;
      }
      
      // 프리미엄 만료, 체험 완료 배너는 플랜별 처리
      final planId = _bannerPlanIds[type];
      if (planId == null) {
        if (kDebugMode) {
          debugPrint('🔍 [BannerManager] ${type.name} 플랜 ID가 null → 표시 안함');
        }
        return false;
      }
      
      final dismissKey = '${_bannerKeys[type]!}$planId';
      final hasUserDismissed = prefs.getBool(dismissKey) ?? false;
      final result = !hasUserDismissed;
      
      if (kDebugMode) {
        debugPrint('🔍 [BannerManager] ${type.name} 플랜별 배너 표시 여부: $result');
        debugPrint('   설정 상태: $shouldShow');
        debugPrint('   플랜 ID: $planId');
        debugPrint('   확인 키: $dismissKey');
        debugPrint('   사용자 닫음: $hasUserDismissed');
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
      if (kDebugMode) {
        debugPrint('🚫 [BannerManager] dismissBanner 시작: ${type.name}');
      }
      
      final prefs = await SharedPreferences.getInstance();
      
      // 사용량 한도 배너는 단순 처리
      if (type == BannerType.usageLimitFree || type == BannerType.usageLimitPremium) {
        final key = _bannerKeys[type]!;
        await prefs.setBool(key, true);
        
        if (kDebugMode) {
          debugPrint('✅ [BannerManager] ${type.name} 사용량 한도 배너 닫기 완료');
          debugPrint('   저장된 키: $key');
          debugPrint('   저장된 값: true');
        }
        return;
      }
      
      // 프리미엄 만료, 체험 완료 배너는 플랜별 처리
      final planId = _bannerPlanIds[type];
      if (planId == null) {
        if (kDebugMode) {
          debugPrint('⚠️ [BannerManager] ${type.name} 플랜 ID가 없어서 닫기 처리 불가');
          debugPrint('   현재 _bannerPlanIds: $_bannerPlanIds');
        }
        return;
      }
      
      final dismissKey = '${_bannerKeys[type]!}$planId';
      await prefs.setBool(dismissKey, true);
      
      if (kDebugMode) {
        debugPrint('✅ [BannerManager] ${type.name} 플랜별 배너 닫기 완료');
        debugPrint('   플랜 ID: $planId');
        debugPrint('   저장된 키: $dismissKey');
        debugPrint('   저장된 값: true');
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [BannerManager] ${type.name} 배너 닫기 실패: $e');
        debugPrint('   에러 스택: ${e.toString()}');
      }
      rethrow; // 에러를 다시 던져서 HomeScreen에서 확인 가능하도록
    }
  }

  /// 배너 상태 초기화 (테스트용)
  Future<void> resetBannerState(BannerType type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 사용량 한도 배너
      if (type == BannerType.usageLimitFree || type == BannerType.usageLimitPremium) {
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

  /// 핵심: 모든 배너 결정 로직 실행 (PlanStatus 기반으로 리팩터링)
  Future<List<BannerType>> getActiveBanners({
    PlanStatus? planStatus,
    bool? hasEverUsedTrial,
    bool? hasEverUsedPremium,
  }) async {
    try {
      final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;
      if (kDebugMode) {
        debugPrint('🎯 [BannerManager] 배너 결정 시작 (PlanStatus 기반)');
      }

      // 1. 플랜 정보 준비 (PlanStatus 기반)
      PlanStatus finalPlanStatus = planStatus ?? PlanStatus.free;
      bool finalHasEverUsedTrial = hasEverUsedTrial ?? false;
      bool finalHasEverUsedPremium = hasEverUsedPremium ?? false;
      bool finalIsCancelled = !finalPlanStatus.isActive;
      bool finalAutoRenewStatus = finalPlanStatus.isActive; // 단순화

      // 2. 🚀 병렬 처리: 사용량 체크와 SharedPreferences 로드를 동시에 실행
      final futures = await Future.wait([
        // 사용량 상태 확인
        UsageLimitService().checkInitialLimitStatus(planType: finalPlanStatus.value),
        // SharedPreferences 미리 로드 (배치 처리)
        SharedPreferences.getInstance(),
        // 플랜 히스토리 확인 (필요한 경우만)
        _shouldCheckPlanHistory(finalPlanStatus.value, finalHasEverUsedTrial, finalHasEverUsedPremium) 
          ? DeletedUserService().getLastPlanInfo(forceRefresh: false).catchError((_) => null)
          : Future.value(null),
      ]);

      final usageLimitStatus = futures[0] as Map<String, bool>;
      final prefs = futures[1] as SharedPreferences;
      final lastPlanInfo = futures[2] as Map<String, dynamic>?;

      if (kDebugMode) {
        debugPrint('🚀 [BannerManager] 병렬 처리 완료 (${stopwatch?.elapsedMilliseconds}ms)');
      }

      // 3. 🎯 배너 결정 (PlanStatus 기반)
      final activeBanners = <BannerType>[];
      _decideUsageLimitBannersSync(activeBanners, finalPlanStatus, usageLimitStatus, prefs);
      _decidePlanStatusBannersSync(activeBanners, finalPlanStatus, finalHasEverUsedTrial, finalHasEverUsedPremium, prefs, lastPlanInfo);

      if (kDebugMode) {
        stopwatch?.stop();
        debugPrint('✅ [BannerManager] 배너 결정 완료 (${stopwatch?.elapsedMilliseconds}ms)');
        debugPrint('   활성 배너: ${activeBanners.map((e) => e.name).toList()}');
      }
      return activeBanners;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [BannerManager] 배너 결정 실패: $e');
      }
      return [];
    }
  }

  /// 사용량 한도 배너 결정 (PlanStatus 기반)
  void _decideUsageLimitBannersSync(List<BannerType> activeBanners, PlanStatus planStatus, Map<String, bool> usageLimitStatus, SharedPreferences prefs) {
    final ocrLimitReached = usageLimitStatus['ocrLimitReached'] ?? false;
    final ttsLimitReached = usageLimitStatus['ttsLimitReached'] ?? false;
    if (ocrLimitReached || ttsLimitReached) {
      if (planStatus.isPremium) {
        setBannerState(BannerType.usageLimitPremium, true);
        setBannerState(BannerType.usageLimitFree, false);
        if (_shouldShowBannerSync(BannerType.usageLimitPremium, prefs)) {
          activeBanners.add(BannerType.usageLimitPremium);
        }
      } else {
        setBannerState(BannerType.usageLimitFree, true);
        setBannerState(BannerType.usageLimitPremium, false);
        if (_shouldShowBannerSync(BannerType.usageLimitFree, prefs)) {
          activeBanners.add(BannerType.usageLimitFree);
        }
      }
    } else {
      setBannerState(BannerType.usageLimitFree, false);
      setBannerState(BannerType.usageLimitPremium, false);
    }
  }

  /// 플랜 상태 배너 결정 (PlanStatus 기반)
  void _decidePlanStatusBannersSync(List<BannerType> activeBanners, PlanStatus planStatus, bool hasEverUsedTrial, bool hasEverUsedPremium, SharedPreferences prefs, Map<String, dynamic>? lastPlanInfo) {
    final isTrialCancelled = planStatus == PlanStatus.trialCancelled;
    final planId = 'plan_${DateTime.now().millisecondsSinceEpoch}';

    // 현재 활성 프리미엄 사용자는 배너 표시 안함
    if (planStatus.isPremium && planStatus.isActive) {
      setBannerState(BannerType.premiumExpired, false);
      setBannerState(BannerType.trialCompleted, false);
      setBannerState(BannerType.trialCancelled, false);
      if (kDebugMode) {
        debugPrint('🎯 [BannerManager] 현재 활성 프리미엄 사용자 → 플랜 상태 배너 없음');
      }
      return;
    }

    // 체험 취소 배너 우선 처리
    if (isTrialCancelled) {
      setBannerState(BannerType.trialCancelled, true, planId: planId);
      setBannerState(BannerType.premiumExpired, false);
      setBannerState(BannerType.trialCompleted, false);
      if (_shouldShowBannerSync(BannerType.trialCancelled, prefs)) {
        activeBanners.add(BannerType.trialCancelled);
      }
      return;
    }

    if (lastPlanInfo != null) {
      final previousPlanType = lastPlanInfo['planType'] as String?;
      final previousIsFreeTrial = lastPlanInfo['isFreeTrial'] as bool? ?? false;
      if (previousPlanType == PLAN_PREMIUM) {
        if (previousIsFreeTrial) {
          setBannerState(BannerType.trialCompleted, true, planId: planId);
          setBannerState(BannerType.premiumExpired, false);
          if (_shouldShowBannerSync(BannerType.trialCompleted, prefs)) {
            activeBanners.add(BannerType.trialCompleted);
          }
        } else {
          setBannerState(BannerType.premiumExpired, true, planId: planId);
          setBannerState(BannerType.trialCompleted, false);
          if (_shouldShowBannerSync(BannerType.premiumExpired, prefs)) {
            activeBanners.add(BannerType.premiumExpired);
          }
        }
      } else {
        setBannerState(BannerType.premiumExpired, false);
        setBannerState(BannerType.trialCompleted, false);
        setBannerState(BannerType.trialCancelled, false);
      }
    } else {
      if (planStatus == PlanStatus.free && hasEverUsedPremium) {
        setBannerState(BannerType.premiumExpired, true, planId: planId);
        setBannerState(BannerType.trialCompleted, false);
        if (_shouldShowBannerSync(BannerType.premiumExpired, prefs)) {
          activeBanners.add(BannerType.premiumExpired);
        }
      } else if (planStatus == PlanStatus.free && hasEverUsedTrial) {
        setBannerState(BannerType.trialCompleted, true, planId: planId);
        setBannerState(BannerType.premiumExpired, false);
        if (_shouldShowBannerSync(BannerType.trialCompleted, prefs)) {
          activeBanners.add(BannerType.trialCompleted);
        }
      } else {
        setBannerState(BannerType.premiumExpired, false);
        setBannerState(BannerType.trialCompleted, false);
        setBannerState(BannerType.trialCancelled, false);
      }
    }
  }

  /// 플랜 히스토리 확인이 필요한지 판단 (성능 최적화)
  bool _shouldCheckPlanHistory(String currentPlan, bool hasEverUsedTrial, bool hasEverUsedPremium) {
    // 신규 사용자는 히스토리 확인 불필요
    if (currentPlan != PLAN_FREE && !hasEverUsedTrial && !hasEverUsedPremium) {
      return false;
    }
    return true;
  }

  /// 🚀 배너 표시 여부 확인 (동기 처리 - 성능 최적화)
  bool _shouldShowBannerSync(BannerType type, SharedPreferences prefs) {
    final shouldShow = _bannerStates[type] ?? false;
    if (!shouldShow) return false;

    // 사용량 한도 배너는 단순 처리
    if (type == BannerType.usageLimitFree || type == BannerType.usageLimitPremium) {
      final key = _bannerKeys[type]!;
      final hasUserDismissed = prefs.getBool(key) ?? false;
      return !hasUserDismissed;
    }
    
    // 프리미엄 만료, 체험 완료 배너는 플랜별 처리
    final planId = _bannerPlanIds[type];
    if (planId == null) return false;
    
    final dismissKey = '${_bannerKeys[type]!}$planId';
    final hasUserDismissed = prefs.getBool(dismissKey) ?? false;
    return !hasUserDismissed;
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