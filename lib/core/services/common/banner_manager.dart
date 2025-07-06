import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'usage_limit_service.dart';
import '../authentication/deleted_user_service.dart';
import '../subscription/subscription_entitlement_engine.dart';
import '../../models/plan_status.dart';

/// 배너 타입 열거형
enum BannerType {
  trialStarted,       // 🆕 트라이얼 시작
  trialCancelled,     // 프리미엄 체험 취소
  trialCompleted,     // 트라이얼 완료
  premiumExpired,     // 프리미엄 만료
  premiumGrace,       // 🆕 Grace Period
  usageLimitFree,     // 무료 플랜 사용량 한도 → 업그레이드 모달
  usageLimitPremium,  // 프리미엄 플랜 사용량 한도 → 문의 폼
}

extension BannerTypeExtension on BannerType {
  String get name {
    switch (this) {
      case BannerType.trialStarted:
        return 'trialStarted';
      case BannerType.trialCancelled:
        return 'trialCancelled';
      case BannerType.trialCompleted:
        return 'trialCompleted';
      case BannerType.premiumExpired:
        return 'premiumExpired';
      case BannerType.premiumGrace:
        return 'premiumGrace';
      case BannerType.usageLimitFree:
        return 'usageLimitFree';
      case BannerType.usageLimitPremium:
        return 'usageLimitPremium';
    }
  }

  String get title {
    switch (this) {
      case BannerType.trialStarted:
        return '🎉 프리미엄 체험 시작';
      case BannerType.trialCancelled:
        return '⏰ 프리미엄 구독 전환 취소됨';
      case BannerType.trialCompleted:
        return '⏰ 프리미엄 체험 종료';
      case BannerType.premiumExpired:
        return '💎 프리미엄 만료';
      case BannerType.premiumGrace:
        return '⚠️ 결제 확인 필요';
      case BannerType.usageLimitFree:
        return '⚠️ 사용량 한도 도달';
      case BannerType.usageLimitPremium:
        return '⚠️ 사용량 한도 도달';
    }
  }

  String get subtitle {
    switch (this) {
      case BannerType.trialStarted:
        return '7일간 프리미엄 기능을 여유있게 사용해보세요';
      case BannerType.trialCancelled:
        return '체험 기간 종료 시 무료 플랜으로 전환됩니다. 계속 사용하려면 구독하세요';
      case BannerType.trialCompleted:
        return '프리미엄 체험이 종료되어 무료 플랜으로 전환되었습니다. 프리미엄을 계속 사용하려면 업그레이드하세요';
      case BannerType.premiumExpired:
        return '프리미엄 혜택이 만료되었습니다. 계속 사용하려면 다시 구독하세요';
      case BannerType.premiumGrace:
        return 'App Store에서 결제 정보를 확인해주세요. 확인되지 않으면 구독이 취소될 수 있습니다';
      case BannerType.usageLimitFree:
        return '프리미엄으로 업그레이드하여 무제한으로 사용하세요';
      case BannerType.usageLimitPremium:
        return '추가 사용량이 필요하시면 문의해 주세요';
    }
  }
}

/// 통합 배너 관리 서비스
/// 구독 상태에 따른 배너 표시/숨김 관리 (사용자별 분리)
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

  // 🔄 사용자별 SharedPreferences 키 생성
  static const Map<BannerType, String> _bannerKeyPrefixes = {
    BannerType.trialStarted: 'trial_started_banner_dismissed_',
    BannerType.trialCancelled: 'trial_cancelled_banner_dismissed_',
    BannerType.trialCompleted: 'trial_completed_banner_dismissed_',
    BannerType.premiumExpired: 'premium_expired_banner_dismissed_',
    BannerType.premiumGrace: 'premium_grace_banner_dismissed_',
    BannerType.usageLimitFree: 'usage_limit_free_banner_shown_',
    BannerType.usageLimitPremium: 'usage_limit_premium_banner_shown_',
  };

  // 🆔 현재 사용자 ID 가져오기
  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  // 🔑 사용자별 배너 키 생성
  String _getUserBannerKey(BannerType type, {String? planId}) {
    final userId = _currentUserId ?? 'anonymous';
    final keyPrefix = _bannerKeyPrefixes[type]!;
    
    if (planId != null) {
      return '${keyPrefix}${userId}_$planId';
    } else {
      return '${keyPrefix}$userId';
    }
  }

  /// 구독 상태에 따른 배너 상태 설정
  void setBannerState(BannerType type, bool shouldShow, {String? planId}) {
    _bannerStates[type] = shouldShow;
    
    // 플랜 ID가 필요한 배너들
    if (type == BannerType.trialStarted || type == BannerType.trialCancelled || 
        type == BannerType.trialCompleted || type == BannerType.premiumExpired || 
        type == BannerType.premiumGrace) {
      _bannerPlanIds[type] = planId ?? '${type.name}_${DateTime.now().millisecondsSinceEpoch}';
    }
    
    if (kDebugMode) {
      debugPrint('🎯 [BannerManager] ${type.name} 상태 설정: $shouldShow${planId != null ? ' (플랜ID: $planId)' : ''}');
    }
  }

  /// 배너 표시 여부 확인 (사용자별)
  Future<bool> shouldShowBanner(BannerType type) async {
    try {
      if (kDebugMode) {
        debugPrint('🔍 [BannerManager] shouldShowBanner 확인: ${type.name} (사용자: ${_currentUserId ?? 'anonymous'})');
      }
      
      final shouldShow = _bannerStates[type] ?? false;
      if (!shouldShow) {
        if (kDebugMode) {
          debugPrint('🔍 [BannerManager] ${type.name} 배너 상태가 false → 표시 안함');
        }
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      
      // 사용량 한도 배너는 단순 처리 (사용자별)
      if (type == BannerType.usageLimitFree || type == BannerType.usageLimitPremium) {
        final key = _getUserBannerKey(type);
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
      
      // 상태별 배너는 플랜별 처리 (사용자별)
      final planId = _bannerPlanIds[type];
      if (planId == null) {
        if (kDebugMode) {
          debugPrint('🔍 [BannerManager] ${type.name} 플랜 ID가 null → 표시 안함');
        }
        return false;
      }
      
      final dismissKey = _getUserBannerKey(type, planId: planId);
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

  /// 배너 닫기 (사용자가 X 버튼 클릭 시) - 사용자별
  Future<void> dismissBanner(BannerType type) async {
    try {
      if (kDebugMode) {
        debugPrint('🚫 [BannerManager] dismissBanner 시작: ${type.name} (사용자: ${_currentUserId ?? 'anonymous'})');
      }
      
      final prefs = await SharedPreferences.getInstance();
      
      // 사용량 한도 배너는 단순 처리 (사용자별)
      if (type == BannerType.usageLimitFree || type == BannerType.usageLimitPremium) {
        final key = _getUserBannerKey(type);
        await prefs.setBool(key, true);
        
        if (kDebugMode) {
          debugPrint('✅ [BannerManager] ${type.name} 사용량 한도 배너 닫기 완료');
          debugPrint('   저장된 키: $key');
          debugPrint('   저장된 값: true');
        }
        return;
      }
      
      // 상태별 배너는 플랜별 처리 (사용자별)
      final planId = _bannerPlanIds[type];
      if (planId == null) {
        if (kDebugMode) {
          debugPrint('⚠️ [BannerManager] ${type.name} 플랜 ID가 없어서 닫기 처리 불가');
          debugPrint('   현재 _bannerPlanIds: $_bannerPlanIds');
        }
        return;
      }
      
      final dismissKey = _getUserBannerKey(type, planId: planId);
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

  /// 배너 상태 초기화 (테스트용) - 사용자별
  Future<void> resetBannerState(BannerType type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _currentUserId ?? 'anonymous';
      
      // 사용량 한도 배너
      if (type == BannerType.usageLimitFree || type == BannerType.usageLimitPremium) {
        final key = _getUserBannerKey(type);
        await prefs.remove(key);
      } else {
        // 프리미엄 만료, 체험 완료 배너 - 해당 사용자의 모든 플랜 ID 관련 키 제거
        final keyPrefix = _bannerKeyPrefixes[type]! + userId + '_';
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
        debugPrint('🎯 [BannerManager] ${type.name} 상태 초기화 (사용자: $userId)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [BannerManager] ${type.name} 상태 초기화 실패: $e');
      }
    }
  }

  /// 모든 배너 상태 초기화 (테스트용) - 현재 사용자만
  Future<void> resetAllBannerStates() async {
    for (final type in BannerType.values) {
      await resetBannerState(type);
    }
    
    if (kDebugMode) {
      debugPrint('🎯 [BannerManager] 모든 배너 상태 초기화 완료 (사용자: ${_currentUserId ?? 'anonymous'})');
    }
  }

  /// 🆕 로그아웃 시 배너 상태 초기화 (메모리만)
  void clearUserBannerStates() {
    _bannerStates.clear();
    _bannerPlanIds.clear();
    
    if (kDebugMode) {
      debugPrint('🔄 [BannerManager] 로그아웃으로 인한 메모리 배너 상태 초기화');
    }
  }

  /// 🆕 특정 사용자의 모든 배너 기록 삭제 (탈퇴 시)
  Future<void> deleteUserBannerData(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      
      // 해당 사용자의 모든 배너 키 찾아서 삭제
      for (final key in allKeys) {
        for (final bannerType in BannerType.values) {
          final keyPrefix = _bannerKeyPrefixes[bannerType]! + userId;
          if (key.startsWith(keyPrefix)) {
            await prefs.remove(key);
            if (kDebugMode) {
              debugPrint('🗑️ [BannerManager] 사용자 배너 데이터 삭제: $key');
            }
          }
        }
      }
      
      if (kDebugMode) {
        debugPrint('✅ [BannerManager] 사용자 $userId의 모든 배너 데이터 삭제 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [BannerManager] 사용자 배너 데이터 삭제 실패: $e');
      }
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
    final planId = 'plan_${DateTime.now().millisecondsSinceEpoch}';

    if (kDebugMode) {
      debugPrint('🎯 [BannerManager] 플랜 상태 배너 결정: ${planStatus.value}');
    }

    // 모든 배너 상태 초기화
    _resetAllBannerStates();

    // 상태별 배너 결정
    switch (planStatus) {
      case PlanStatus.trialActive:
        // 트라이얼 시작 배너 표시
        setBannerState(BannerType.trialStarted, true, planId: planId);
        if (_shouldShowBannerSync(BannerType.trialStarted, prefs)) {
          activeBanners.add(BannerType.trialStarted);
        }
        break;

      case PlanStatus.trialCancelled:
        // 트라이얼 취소 배너 표시
        setBannerState(BannerType.trialCancelled, true, planId: planId);
        if (_shouldShowBannerSync(BannerType.trialCancelled, prefs)) {
          activeBanners.add(BannerType.trialCancelled);
        }
        break;

      case PlanStatus.trialCompleted:
        // 트라이얼 완료 배너 표시
        setBannerState(BannerType.trialCompleted, true, planId: planId);
        if (_shouldShowBannerSync(BannerType.trialCompleted, prefs)) {
          activeBanners.add(BannerType.trialCompleted);
        }
        break;

      case PlanStatus.premiumExpired:
        // 프리미엄 만료 배너 표시
        setBannerState(BannerType.premiumExpired, true, planId: planId);
        if (_shouldShowBannerSync(BannerType.premiumExpired, prefs)) {
          activeBanners.add(BannerType.premiumExpired);
        }
        break;

      case PlanStatus.premiumGrace:
        // Grace Period 배너 표시
        setBannerState(BannerType.premiumGrace, true, planId: planId);
        if (_shouldShowBannerSync(BannerType.premiumGrace, prefs)) {
          activeBanners.add(BannerType.premiumGrace);
        }
        break;

      case PlanStatus.premiumActive:
      case PlanStatus.premiumCancelled:
        // 활성 프리미엄 사용자는 배너 표시 안함
        if (kDebugMode) {
          debugPrint('🎯 [BannerManager] 프리미엄 사용자 → 플랜 상태 배너 없음');
        }
        break;

      case PlanStatus.free:
        // 무료 사용자 - 과거 이력에 따라 배너 결정
        if (hasEverUsedPremium) {
          setBannerState(BannerType.premiumExpired, true, planId: planId);
          if (_shouldShowBannerSync(BannerType.premiumExpired, prefs)) {
            activeBanners.add(BannerType.premiumExpired);
          }
        } else if (hasEverUsedTrial) {
          setBannerState(BannerType.trialCompleted, true, planId: planId);
          if (_shouldShowBannerSync(BannerType.trialCompleted, prefs)) {
            activeBanners.add(BannerType.trialCompleted);
          }
        }
        break;

      default:
        if (kDebugMode) {
          debugPrint('🎯 [BannerManager] 알 수 없는 플랜 상태: ${planStatus.value}');
        }
        break;
    }

    if (kDebugMode) {
      debugPrint('🎯 [BannerManager] 플랜 상태 배너 결정 완료: ${activeBanners.map((e) => e.name).toList()}');
    }
  }

  /// 모든 플랜 상태 배너 초기화
  void _resetAllBannerStates() {
    setBannerState(BannerType.trialStarted, false);
    setBannerState(BannerType.trialCancelled, false);
    setBannerState(BannerType.trialCompleted, false);
    setBannerState(BannerType.premiumExpired, false);
    setBannerState(BannerType.premiumGrace, false);
  }

  /// 플랜 히스토리 확인이 필요한지 판단 (성능 최적화)
  bool _shouldCheckPlanHistory(String currentPlan, bool hasEverUsedTrial, bool hasEverUsedPremium) {
    // 신규 사용자는 히스토리 확인 불필요
    if (currentPlan != PLAN_FREE && !hasEverUsedTrial && !hasEverUsedPremium) {
      return false;
    }
    return true;
  }

  /// 🚀 배너 표시 여부 확인 (동기 처리 - 성능 최적화) - 사용자별
  bool _shouldShowBannerSync(BannerType type, SharedPreferences prefs) {
    final shouldShow = _bannerStates[type] ?? false;
    if (!shouldShow) return false;

    // 사용량 한도 배너는 단순 처리 (사용자별)
    if (type == BannerType.usageLimitFree || type == BannerType.usageLimitPremium) {
      final key = _getUserBannerKey(type);
      final hasUserDismissed = prefs.getBool(key) ?? false;
      return !hasUserDismissed;
    }
    
    // 프리미엄 만료, 체험 완료 배너는 플랜별 처리 (사용자별)
    final planId = _bannerPlanIds[type];
    if (planId == null) return false;
    
    final dismissKey = _getUserBannerKey(type, planId: planId);
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