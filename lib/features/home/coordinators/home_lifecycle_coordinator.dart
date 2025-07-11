import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/models/subscription_state.dart';
import '../../../core/services/subscription/unified_subscription_manager.dart';
import '../../../core/services/common/usage_limit_service.dart';
import '../../../core/services/authentication/user_preferences_service.dart';

/// 🔄 HomeScreen 생명주기 관리 Coordinator
/// 
/// 책임:
/// - 온보딩 상태 체크
/// - 사용자 변경 감지
/// - 스트림 구독 관리
/// - 구독 상태 로드 통합 관리
class HomeLifecycleCoordinator {
  // 🔧 서비스 인스턴스
  final UsageLimitService _usageLimitService = UsageLimitService();
  final UnifiedSubscriptionManager _subscriptionManager = UnifiedSubscriptionManager();
  final UserPreferencesService _userPreferencesService = UserPreferencesService();

  // 📡 실시간 스트림 구독
  StreamSubscription<Map<String, dynamic>>? _limitStatusSubscription;
  StreamSubscription<User?>? _authStateSubscription;
  
  // 🎯 상태 관리
  bool _hasInitialLoad = false;
  
  // 🔄 콜백들
  Function(SubscriptionState)? _onSubscriptionStateChanged;
  Function()? _onUserChanged;

  /// 초기화
  void initialize({
    Function(SubscriptionState)? onSubscriptionStateChanged,
    Function()? onUserChanged,
  }) {
    _onSubscriptionStateChanged = onSubscriptionStateChanged;
    _onUserChanged = onUserChanged;
    
    // 인증 상태 스트림만 우선 구독
    _setupAuthStateStream();
  }

  /// 📡 인증 상태 스트림 구독 설정 (사용자 변경 감지용)
  void _setupAuthStateStream() {
    // 🔄 기존 구독이 있으면 취소 (중복 구독 방지)
    _authStateSubscription?.cancel();
    
    // 🎯 인증 상태 변경 스트림 구독 (로그인/로그아웃 감지)
    _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen(
      (User? user) async {
        if (kDebugMode) {
          debugPrint('🔔 [HomeLifecycleCoordinator] 인증 상태 변경 감지: ${user?.uid ?? "로그아웃"}');
        }
        
        // 🚨 로그아웃된 경우에는 처리 안함
        if (user == null) {
          if (kDebugMode) {
            debugPrint('⚠️ [HomeLifecycleCoordinator] 로그아웃 감지 - 처리 건너뜀');
          }
          return;
        }
        
        // 🎯 사용자 변경 시 상태 초기화
        _hasInitialLoad = false;
        _onUserChanged?.call();
        
        if (kDebugMode) {
          debugPrint('🔄 [HomeLifecycleCoordinator] 사용자 변경 - 상태 초기화 완료');
        }
        
        // 🔄 온보딩 상태 확인 후 구독 상태 로드 여부 결정
        await loadSubscriptionStatus(
          forceRefresh: true,
          setupUsageStream: true,
          context: '사용자변경',
        );
      },
      onError: (error) {
        if (kDebugMode) {
          debugPrint('❌ [HomeLifecycleCoordinator] 인증 상태 스트림 오류: $error');
        }
      },
    );
    
    if (kDebugMode) {
      debugPrint('✅ [HomeLifecycleCoordinator] 인증 상태 스트림 구독 완료');
    }
  }

  /// 📊 사용량 한도 스트림 구독 설정 (온보딩 완료 후에만)
  void setupUsageLimitStream() {
    // 🔄 기존 구독이 있으면 취소 (중복 구독 방지)
    _limitStatusSubscription?.cancel();
    
    // 📊 사용량 한도 상태 변경 스트림 구독
    _limitStatusSubscription = _usageLimitService.limitStatusStream.listen(
      (limitStatus) async {
        if (kDebugMode) {
          debugPrint('🔔 [HomeLifecycleCoordinator] 실시간 사용량 한도 상태 변경: $limitStatus');
        }
        
        // 🚨 사용량 한도 도달 시 상태 업데이트
        final shouldShowUsageLimit = limitStatus['ocrLimitReached'] == true || 
                                    limitStatus['ttsLimitReached'] == true;
        
        // 구독 상태 다시 로드
        await loadSubscriptionStatus(forceRefresh: true, context: '사용량변경');
      },
      onError: (error) {
        if (kDebugMode) {
          debugPrint('❌ [HomeLifecycleCoordinator] 사용량 한도 스트림 오류: $error');
        }
      },
    );
    
    if (kDebugMode) {
      debugPrint('✅ [HomeLifecycleCoordinator] 사용량 한도 스트림 구독 완료');
    }
  }

  /// 🎯 통합 구독 상태 로드 (모든 시나리오 처리)
  Future<void> loadSubscriptionStatus({
    bool forceRefresh = false,
    bool skipOnboardingCheck = false,
    bool setupUsageStream = false,
    String? context,
  }) async {
    try {
      final contextMsg = context ?? '일반';
      if (kDebugMode) {
        debugPrint('[HomeLifecycleCoordinator] 🔄 구독 상태 로드 시작 [$contextMsg] (forceRefresh: $forceRefresh)');
      }
      
      // 🚨 온보딩 완료 여부 확인 (skipOnboardingCheck가 true면 건너뛰기)
      if (!skipOnboardingCheck) {
        final preferences = await _userPreferencesService.getPreferences();
        final hasCompletedOnboarding = preferences.onboardingCompleted;
        
        if (!hasCompletedOnboarding) {
          if (kDebugMode) {
            debugPrint('[HomeLifecycleCoordinator] ⚠️ 온보딩 미완료 사용자 - 구독 상태 체크 건너뜀 [$contextMsg]');
          }
          // 기본 상태로 콜백 호출
          _onSubscriptionStateChanged?.call(SubscriptionState.defaultState());
          return;
        }
        
        if (kDebugMode) {
          debugPrint('[HomeLifecycleCoordinator] ✅ 온보딩 완료된 사용자 - 구독 상태 체크 진행 [$contextMsg]');
        }
      }
      
      // 🚨 사용자 변경 후에는 항상 강제 새로고침 (캐시 사용 금지)
      bool shouldForceRefresh = forceRefresh;
      
      // 초기 로드가 아직 완료되지 않았다면 강제 새로고침
      if (!_hasInitialLoad) {
        shouldForceRefresh = true;
        if (kDebugMode) {
          debugPrint('[HomeLifecycleCoordinator] 초기 로드 - 강제 새로고침으로 변경 [$contextMsg]');
        }
      }
      
      // 🆕 사용량 스트림 구독이 필요한 경우
      if (setupUsageStream) {
        setupUsageLimitStream();
        if (kDebugMode) {
          debugPrint('[HomeLifecycleCoordinator] 사용량 스트림 구독 완료 [$contextMsg]');
        }
      }
      
      // 🎯 UnifiedSubscriptionManager 사용 (Core Service)
      final subscriptionState = await _subscriptionManager.getSubscriptionState(
        forceRefresh: shouldForceRefresh,
      );
      
      // 초기 로드 완료 표시
      if (!_hasInitialLoad) {
        _hasInitialLoad = true;
        if (kDebugMode) {
          debugPrint('✅ [HomeLifecycleCoordinator] 초기 로드 완료 [$contextMsg]');
        }
      }
      
      // 🔄 결과를 콜백으로 전달
      _onSubscriptionStateChanged?.call(subscriptionState);
      
      if (kDebugMode) {
        debugPrint('[HomeLifecycleCoordinator] ✅ 구독 상태 업데이트 완료 [$contextMsg]');
        debugPrint('   상태: ${subscriptionState.statusMessage}');
        debugPrint('   활성 배너: ${subscriptionState.activeBanners.map((e) => e.name).toList()}');
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[HomeLifecycleCoordinator] ❌ 구독 상태 로드 실패 [$context]: $e');
      }
    }
  }

  /// 🎯 온보딩 완료 후 구독 상태 로드
  Future<void> loadSubscriptionStatusAfterOnboarding() async {
    await loadSubscriptionStatus(
      forceRefresh: true,
      setupUsageStream: true,
      context: '온보딩완료',
    );
  }

  /// 🎯 포그라운드 복귀 시 구독 상태 로드
  Future<void> loadSubscriptionStatusAfterResume() async {
    await loadSubscriptionStatus(
      forceRefresh: false,
      context: '포그라운드복귀',
    );
  }

  /// 🎯 구매 완료 후 구독 상태 로드
  Future<void> loadSubscriptionStatusAfterPurchase() async {
    await loadSubscriptionStatus(
      forceRefresh: true,
      skipOnboardingCheck: true,
      context: '구매완료',
    );
  }

  /// 🎯 수동 새로고침
  Future<void> refreshSubscriptionStatus() async {
    await loadSubscriptionStatus(
      context: '수동새로고침',
    );
  }

  /// 🎯 신규 사용자를 위한 초기화 (환영 모달용)
  void initializeForNewUser() {
    if (kDebugMode) {
      debugPrint('[HomeLifecycleCoordinator] 🆕 신규 사용자 초기화 - 사용량 스트림 구독 없이 진행');
    }
    // 신규 사용자는 기본 상태만 설정
    _onSubscriptionStateChanged?.call(SubscriptionState.defaultState());
  }

  /// 🎯 기존 사용자를 위한 초기화
  Future<void> initializeForExistingUser() async {
    if (kDebugMode) {
      debugPrint('[HomeLifecycleCoordinator] 🔄 기존 사용자 초기화 - 사용량 스트림 구독 및 구독 상태 로드');
    }
    await loadSubscriptionStatus(
      setupUsageStream: true,
      context: '기존사용자초기화',
    );
  }

  /// 정리
  void dispose() {
    _limitStatusSubscription?.cancel();
    _authStateSubscription?.cancel();
    
    if (kDebugMode) {
      debugPrint('🔄 [HomeLifecycleCoordinator] 리소스 정리 완료');
    }
  }
} 