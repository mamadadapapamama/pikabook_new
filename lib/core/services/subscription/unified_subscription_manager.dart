import 'package:flutter/foundation.dart';
import 'dart:async';
import 'subscription_entitlement_engine.dart';
import '../common/banner_manager.dart';
import '../common/usage_limit_service.dart';
import '../../models/subscription_state.dart';

/// 통합 구독 상태 매니저 (단순화)
/// 모든 구독 관련 기능을 하나의 인터페이스로 제공
class UnifiedSubscriptionManager {
  static final UnifiedSubscriptionManager _instance = UnifiedSubscriptionManager._internal();
  factory UnifiedSubscriptionManager() => _instance;
  UnifiedSubscriptionManager._internal();

  final SubscriptionEntitlementEngine _entitlementEngine = SubscriptionEntitlementEngine();
  final BannerManager _bannerManager = BannerManager();
  final UsageLimitService _usageLimitService = UsageLimitService();
  
  // 🎯 단일 통합 상태 캐시
  SubscriptionState? _cachedState;
  DateTime? _lastCacheTime;
  static const Duration _cacheValidDuration = Duration(hours: 24);
  
  // 🎯 중복 요청 방지
  Future<SubscriptionState>? _ongoingRequest;

  /// 🎯 앱 시작 시 초기화 (한 번만 호출)
  Future<void> initialize() async {
    if (kDebugMode) {
      debugPrint('🔄 [UnifiedSubscriptionManager] 초기화 시작');
    }
    
    // Transaction Listener 시작 (표준 방식)
    await _entitlementEngine.startTransactionListener();
    
    if (kDebugMode) {
      debugPrint('✅ [UnifiedSubscriptionManager] 초기화 완료');
    }
  }

  /// 🎯 통합 구독 상태 조회 (모든 화면에서 사용)
  /// HomeScreen, Settings, BannerManager 등에서 호출
  Future<SubscriptionState> getSubscriptionState({bool forceRefresh = false}) async {
    // 🎯 캐시 우선 사용
    if (!forceRefresh && _isStateValid()) {
      if (kDebugMode) {
        debugPrint('📦 [UnifiedSubscriptionManager] 캐시된 상태 사용');
      }
      return _cachedState!;
    }
    
    // 🎯 중복 요청 방지
    if (_ongoingRequest != null) {
      if (kDebugMode) {
        debugPrint('⏳ [UnifiedSubscriptionManager] 진행 중인 요청 대기');
      }
      return await _ongoingRequest!;
    }

    // 새로운 요청 시작
    _ongoingRequest = _fetchUnifiedState(forceRefresh);
    
    try {
      final result = await _ongoingRequest!;
      _updateStateCache(result);
      return result;
    } finally {
      _ongoingRequest = null;
    }
  }

  /// 실제 통합 상태 조회 로직
  Future<SubscriptionState> _fetchUnifiedState(bool forceRefresh) async {
    if (kDebugMode) {
      debugPrint('🎯 [UnifiedSubscriptionManager] 통합 상태 조회 시작');
    }

    try {
      // Step 1: 권한 조회 (Entitlement Engine)
      final entitlementResult = await _entitlementEngine.getCurrentEntitlements(
        forceRefresh: forceRefresh,
      );
      
      if (kDebugMode) {
        debugPrint('📱 [UnifiedSubscriptionManager] 권한 결과: ${entitlementResult.statusMessage}');
      }

      // Step 2: 사용량 한도 확인 (병렬 처리)
      final usageLimitFuture = _checkUsageLimit(entitlementResult);
      
      // Step 3: 활성 배너 조회 (병렬 처리)
      final bannersFuture = _getActiveBanners(entitlementResult);
      
      // 병렬 실행 완료 대기
      final results = await Future.wait([usageLimitFuture, bannersFuture]);
      final hasUsageLimitReached = results[0] as bool;
      final activeBanners = results[1] as List<BannerType>;

      // Step 4: 통합 상태 생성
      final subscriptionState = SubscriptionState(
        planStatus: entitlementResult.planStatus,
        isTrial: entitlementResult.isTrial,
        isTrialExpiringSoon: false, // App Store에서 자동 관리
        isPremium: entitlementResult.isPremium,
        isExpired: entitlementResult.isExpired,
        hasUsageLimitReached: hasUsageLimitReached,
        daysRemaining: 0, // App Store에서 자동 관리
        activeBanners: activeBanners,
        statusMessage: entitlementResult.statusMessage,
      );

      if (kDebugMode) {
        debugPrint('✅ [UnifiedSubscriptionManager] 통합 상태 생성 완료');
        debugPrint('   플랜: ${subscriptionState.statusMessage}');
        debugPrint('   사용량 한도: ${subscriptionState.hasUsageLimitReached}');
        debugPrint('   활성 배너: ${activeBanners.map((e) => e.name).toList()}');
      }

      return subscriptionState;

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedSubscriptionManager] 통합 상태 조회 실패: $e');
      }
      
      // 에러 시 기본 상태 반환
      return SubscriptionState.defaultState();
    }
  }

  /// 사용량 한도 확인 (비동기)
  Future<bool> _checkUsageLimit(EntitlementResult entitlementResult) async {
    try {
      String planType = 'free';
      if (entitlementResult.isTrial) {
        planType = 'trial';
      } else if (entitlementResult.isPremium) {
        planType = 'premium';
      }

      final usageLimitStatus = await _usageLimitService.checkInitialLimitStatus(
        planType: planType,
      );
      
      final ocrLimitReached = usageLimitStatus['ocrLimitReached'] ?? false;
      final ttsLimitReached = usageLimitStatus['ttsLimitReached'] ?? false;
      
      return ocrLimitReached || ttsLimitReached;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [UnifiedSubscriptionManager] 사용량 한도 확인 실패: $e');
      }
      return false;
    }
  }

  /// 활성 배너 조회 (비동기)
  Future<List<BannerType>> _getActiveBanners(EntitlementResult entitlementResult) async {
    try {
      if (kDebugMode) {
        debugPrint('🎯 [UnifiedSubscriptionManager] 배너 조회 시작');
        debugPrint('   현재 플랜: ${entitlementResult.isTrial ? 'trial' : entitlementResult.isPremium ? 'premium' : 'free'}');
        debugPrint('   무료 체험: ${entitlementResult.isTrial}');
        debugPrint('   프리미엄: ${entitlementResult.isPremium}');
      }
      
      return await _bannerManager.getActiveBanners(
        planStatus: entitlementResult.planStatus,
        hasEverUsedTrial: false, // TODO: 이력 정보는 별도 서비스에서 관리
        hasEverUsedPremium: false, // 🎯 수정: 현재 프리미엄 사용자는 이력이 아님
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [UnifiedSubscriptionManager] 배너 조회 실패: $e');
      }
      return [];
    }
  }

  /// 🎯 간단한 권한 확인 (UI에서 자주 사용)
  Future<bool> canUsePremiumFeatures() async {
    final state = await getSubscriptionState();
    return state.canUsePremiumFeatures;
  }

  /// 🎯 노트 생성 가능 여부 (사용량 한도 포함)
  Future<bool> canCreateNote() async {
    final state = await getSubscriptionState();
    return state.canCreateNote;
  }

  /// 🎯 구매 완료 후 캐시 무효화
  void notifyPurchaseCompleted() {
    _entitlementEngine.invalidateCache();
    invalidateCache();
    
    if (kDebugMode) {
      debugPrint('🛒 [UnifiedSubscriptionManager] 구매 완료 - 캐시 무효화');
    }
  }

  /// 캐시 관리
  bool _isStateValid() {
    if (_cachedState == null || _lastCacheTime == null) return false;
    final timeDiff = DateTime.now().difference(_lastCacheTime!);
    return timeDiff < _cacheValidDuration;
  }

  void _updateStateCache(SubscriptionState state) {
    _cachedState = state;
    _lastCacheTime = DateTime.now();
  }

  void invalidateCache() {
    _cachedState = null;
    _lastCacheTime = null;
    _ongoingRequest = null;
    
    if (kDebugMode) {
      debugPrint('🗑️ [UnifiedSubscriptionManager] 캐시 무효화');
    }
  }

  void dispose() {
    invalidateCache();
    _entitlementEngine.dispose();
  }
} 