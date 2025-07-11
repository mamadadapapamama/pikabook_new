import 'package:flutter/foundation.dart';
import 'dart:async';
import 'subscription_entitlement_engine.dart';
import '../common/banner_manager.dart';
import '../common/usage_limit_service.dart';
import '../../models/subscription_state.dart';
import '../../models/plan_status.dart';
import 'package:firebase_auth/firebase_auth.dart';

// 🎯 Apple 공식 라이브러리 기반 권한 결과 타입 정의
typedef EntitlementResult = Map<String, dynamic>;

// 🎯 EntitlementResult 편의 확장 메서드
extension EntitlementResultExtension on EntitlementResult {
  // 구독 상태 접근자
  bool get isPremium => this['premium'] as bool? ?? this['isPremium'] as bool? ?? false;
  bool get isTrial => this['trial'] as bool? ?? this['isTrial'] as bool? ?? false;
  bool get isExpired => this['expired'] as bool? ?? this['isExpired'] as bool? ?? false;
  
  // 플랜 상태 접근자
  PlanStatus get planStatus {
    final planStatusValue = this['planStatus'] as String? ?? 'free';
    return PlanStatus.fromString(planStatusValue);
  }
  
  // 상태 메시지 접근자
  String get statusMessage {
    if (isPremium) return '프리미엄';
    if (isTrial) return '무료 체험';
    return '무료';
  }
  
  // Apple 공식 라이브러리 메타데이터 접근자
  String? get serverVersion => this['_serverVersion'] as String?;
  String? get dataSource => this['_dataSource'] as String?;
  String? get timestamp => this['_timestamp'] as String?;
  Map<String, dynamic>? get libraryInfo => this['_libraryInfo'] as Map<String, dynamic>?;
  
  // Apple 공식 라이브러리 사용 여부 확인
  bool get isUsingOfficialLibrary {
    final libraryInfoData = libraryInfo;
    if (libraryInfoData == null) return false;
    return libraryInfoData['isUsingOfficialLibrary'] as bool? ?? false;
  }
}

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
  static const Duration _cacheValidDuration = Duration(minutes: 5); // 24시간 → 5분으로 단축하되 적극 활용
  
  // 🎯 중복 요청 방지 + 디바운싱
  Future<SubscriptionState>? _ongoingRequest;
  DateTime? _lastRequestTime;
  static const Duration _debounceDelay = Duration(milliseconds: 300); // 300ms 디바운싱

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
    if (kDebugMode) {
      debugPrint('🎯 [UnifiedSubscriptionManager] getSubscriptionState 호출 (forceRefresh: $forceRefresh)');
    }
    
    // 🚨 로그인 상태 우선 체크 (무한 반복 방지)
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (kDebugMode) {
        debugPrint('⚠️ [UnifiedSubscriptionManager] 로그인되지 않음 - 기본 상태 반환');
      }
      return SubscriptionState.defaultState();
    }
    
    // 🎯 디바운싱: 300ms 이내 연속 요청 방지
    final now = DateTime.now();
    if (_lastRequestTime != null && now.difference(_lastRequestTime!) < _debounceDelay) {
      if (kDebugMode) {
        debugPrint('⏱️ [UnifiedSubscriptionManager] 디바운싱: 너무 빠른 연속 요청 - 캐시 사용');
      }
      // 캐시가 있으면 캐시 반환, 없으면 기본값
      return _cachedState ?? SubscriptionState.defaultState();
    }
    _lastRequestTime = now;
    
    // 🎯 캐시 우선 사용 (forceRefresh가 false이거나 캐시가 매우 최신인 경우)
    if (_isStateValid()) {
      if (!forceRefresh) {
      if (kDebugMode) {
        debugPrint('📦 [UnifiedSubscriptionManager] 캐시된 상태 사용');
        debugPrint('   캐시된 상태: ${_cachedState!.statusMessage}');
        debugPrint('   캐시된 배너: ${_cachedState!.activeBanners.map((e) => e.name).toList()}');
      }
      return _cachedState!;
      } else {
        // forceRefresh=true여도 캐시가 1분 이내면 캐시 사용
        final cacheAge = DateTime.now().difference(_lastCacheTime!);
        if (cacheAge < Duration(minutes: 1)) {
          if (kDebugMode) {
            debugPrint('📦 [UnifiedSubscriptionManager] forceRefresh이지만 캐시가 너무 최신 (${cacheAge.inSeconds}초) - 캐시 사용');
            debugPrint('   캐시된 상태: ${_cachedState!.statusMessage}');
          }
          return _cachedState!;
        }
      }
    }
    
    if (kDebugMode) {
      if (forceRefresh) {
        debugPrint('🔄 [UnifiedSubscriptionManager] 강제 새로고침 요청');
      } else {
        debugPrint('🔄 [UnifiedSubscriptionManager] 캐시 만료로 새로고침');
      }
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
      
      if (kDebugMode) {
        debugPrint('✅ [UnifiedSubscriptionManager] 새로운 상태 캐시 업데이트 완료');
        debugPrint('   새 상태: ${result.statusMessage}');
        debugPrint('   새 배너: ${result.activeBanners.map((e) => e.name).toList()}');
      }
      
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
        debugPrint('   플랜 상태: ${entitlementResult.planStatus.value}');
        debugPrint('   플랜 상태 객체: ${entitlementResult.planStatus}');
      }
      
      // 🎯 플랜 상태에 따른 이력 정보 결정
      bool hasEverUsedTrial = false;
      bool hasEverUsedPremium = false;
      
      // 현재 상태나 과거 이력에 따라 판단
      switch (entitlementResult.planStatus) {
        case PlanStatus.trialActive:
        case PlanStatus.trialCancelled:
        case PlanStatus.trialCompleted:
          hasEverUsedTrial = true;
          break;
          
        case PlanStatus.premiumActive:
        case PlanStatus.premiumCancelled:
        case PlanStatus.premiumExpired:
        case PlanStatus.premiumGrace:
          hasEverUsedPremium = true;
          break;
          
        case PlanStatus.free:
        case PlanStatus.refunded:
          // 무료 상태나 환불 상태에서는 이력을 별도로 확인해야 함
          // 현재는 기본값 사용
          break;
      }
      
      if (kDebugMode) {
        debugPrint('🎯 [UnifiedSubscriptionManager] 배너 조회 파라미터:');
        debugPrint('   planStatus: ${entitlementResult.planStatus.value}');
        debugPrint('   hasEverUsedTrial: $hasEverUsedTrial');
        debugPrint('   hasEverUsedPremium: $hasEverUsedPremium');
      }
      
      final activeBanners = await _bannerManager.getActiveBanners(
        planStatus: entitlementResult.planStatus,
        hasEverUsedTrial: hasEverUsedTrial,
        hasEverUsedPremium: hasEverUsedPremium,
      );
      
      if (kDebugMode) {
        debugPrint('🎯 [UnifiedSubscriptionManager] BannerManager 응답 받음:');
        debugPrint('   활성 배너 개수: ${activeBanners.length}');
        debugPrint('   활성 배너 목록: ${activeBanners.map((e) => e.name).toList()}');
      }
      
      return activeBanners;
      
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
    
    // 🚨 로그인 상태 체크 (무한 반복 방지)
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (kDebugMode) {
        debugPrint('⚠️ [UnifiedSubscriptionManager] 구매 완료 알림 중단 - 사용자가 로그아웃됨');
      }
      return; // 로그아웃 상태면 재시도 스케줄링 안함
    }
    
    // 🎯 서버 웹훅 처리 대기 후 재시도 (5초 지연)
    _scheduleRetryAfterPurchase();
  }

  /// 🎯 구매 완료 후 서버 웹훅 처리 대기 및 적극적 재시도 (Sandbox 환경 대응)
  void _scheduleRetryAfterPurchase() {
    // 1차 재시도: 3초 후
    Future.delayed(const Duration(seconds: 3), () async {
      await _performRetryCheck('1차 (3초 후)');
    });
    
    // 2차 재시도: 8초 후
    Future.delayed(const Duration(seconds: 8), () async {
      await _performRetryCheck('2차 (8초 후)');
    });
    
    // 3차 재시도: 15초 후
    Future.delayed(const Duration(seconds: 15), () async {
      await _performRetryCheck('3차 (15초 후)');
    });
    
    // 4차 재시도: 30초 후 (최종)
    Future.delayed(const Duration(seconds: 30), () async {
      await _performRetryCheck('최종 (30초 후)');
    });
  }
  
  /// 재시도 체크 수행
  Future<void> _performRetryCheck(String retryLabel) async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 [UnifiedSubscriptionManager] $retryLabel 재시도 시작');
      }
      
      // 🚨 로그인 상태 먼저 체크 (무한 반복 방지)
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        if (kDebugMode) {
          debugPrint('⚠️ [UnifiedSubscriptionManager] $retryLabel 중단 - 사용자가 로그아웃됨');
        }
        return; // 로그아웃 상태면 재시도 중단
      }
      
      // 강제 새로고침으로 서버에서 업데이트된 구독 상태 조회
      final updatedState = await getSubscriptionState(forceRefresh: true);
      
      if (kDebugMode) {
        debugPrint('📊 [UnifiedSubscriptionManager] $retryLabel 결과:');
        debugPrint('   상태: ${updatedState.statusMessage}');
        debugPrint('   프리미엄: ${updatedState.isPremium}');
        debugPrint('   체험: ${updatedState.isTrial}');
      }
      
      // 🎯 프리미엄이나 체험 상태로 변경되었으면 성공
      if (updatedState.isPremium || updatedState.isTrial) {
        if (kDebugMode) {
          debugPrint('✅ [UnifiedSubscriptionManager] $retryLabel 성공 - 구독 상태 업데이트됨!');
        }
        return; // 성공하면 더 이상 재시도하지 않음
      }
      
      if (kDebugMode) {
        debugPrint('⚠️ [UnifiedSubscriptionManager] $retryLabel 아직 무료 상태');
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedSubscriptionManager] $retryLabel 실패: $e');
      }
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