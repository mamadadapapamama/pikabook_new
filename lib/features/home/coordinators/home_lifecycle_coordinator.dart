import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/subscription_state.dart';
import '../../../core/services/subscription/unified_subscription_manager.dart';
import '../../../core/services/common/usage_limit_service.dart';
import '../../../core/services/authentication/user_preferences_service.dart';
import '../../../core/events/subscription_events.dart';

/// 🔄 HomeScreen 생명주기 관리 Coordinator (단순화 버전)
/// 
/// 🎯 **핵심 책임 (축소):**
/// - 신규/기존 사용자 구분 및 환영 모달 관리
/// - 구독 이벤트 구독하여 UI 업데이트 (reactive)
/// - 사용량 한도 구독
/// 
/// 🚫 **더 이상 담당하지 않음:**
/// - ❌ 구독 상태 수동 조회 → UnifiedSubscriptionManager가 자동 처리
/// - ❌ StoreKit/Webhook 모니터링 → UnifiedSubscriptionManager가 실시간 처리  
/// - ❌ 구독 상태 캐싱 → UnifiedSubscriptionManager가 중앙 관리
/// - ❌ 배너 관리 → UnifiedSubscriptionManager가 BannerManager와 통합 처리
class HomeLifecycleCoordinator {
  // 🔧 서비스 인스턴스
  final UsageLimitService _usageLimitService = UsageLimitService();
  final UnifiedSubscriptionManager _subscriptionManager = UnifiedSubscriptionManager();
  final UserPreferencesService _userPreferencesService = UserPreferencesService();

  // 📡 실시간 스트림 구독 (단순화)
  StreamSubscription<Map<String, dynamic>>? _limitStatusSubscription;
  StreamSubscription<User?>? _authStateSubscription;
  StreamSubscription<SubscriptionEvent>? _subscriptionEventSubscription;
  
  // 🎯 상태 관리 (단순화)
  bool _hasInitialLoad = false;
  
  // 🔄 콜백들
  Function(SubscriptionState)? _onSubscriptionStateChanged;
  Function()? _onUserChanged;
  Function(bool)? _onUserStatusDetermined; // 신규/기존 사용자 상태 콜백

  /// 초기화 - 기기별 트라이얼 이력을 확인하여 신규/기존 사용자 구분
  void initialize({
    Function(SubscriptionState)? onSubscriptionStateChanged,
    Function()? onUserChanged,
    Function(bool)? onUserStatusDetermined, // 신규=true, 기존=false
  }) {
    _onSubscriptionStateChanged = onSubscriptionStateChanged;
    _onUserChanged = onUserChanged;
    _onUserStatusDetermined = onUserStatusDetermined;
    
    // 🎯 기기별 트라이얼 이력을 확인하여 신규/기존 사용자 구분
    _determineUserStatus();
    
    // 인증 상태 스트림 구독
    _setupAuthStateStream();
  }

  /// 🎯 사용자 상태 결정 - 환영 모달 본 적 있는지 확인
  Future<void> _determineUserStatus() async {
    try {
      // 홈화면 진입 = 이미 로그인됨 + 온보딩 완료됨이 보장됨
      
      // 🎯 환영 모달 본 적 있는지 확인
      final currentUser = FirebaseAuth.instance.currentUser!;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      
      bool hasSeenWelcomeModal = false;
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        hasSeenWelcomeModal = userData['hasSeenWelcomeModal'] as bool? ?? false;
      }
      
      // 환영 모달을 본 적이 없으면 신규 사용자로 처리
      final shouldShowWelcomeModal = !hasSeenWelcomeModal;
      
      if (kDebugMode) {
        debugPrint('🔍 [HomeLifecycleCoordinator] 환영 모달 확인:');
        debugPrint('   환영 모달 본 적 있음: $hasSeenWelcomeModal');
        debugPrint('   환영 모달 표시 여부: $shouldShowWelcomeModal');
      }

      // 신규/기존 사용자에 따라 처리
      if (shouldShowWelcomeModal) {
        _handleNewUser();
      } else {
        _handleExistingUser();
      }

      // 상태 콜백 호출 (환영 모달 표시 여부를 신규 사용자 여부로 전달)
      _onUserStatusDetermined?.call(shouldShowWelcomeModal);

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [HomeLifecycleCoordinator] 사용자 상태 결정 실패: $e');
      }
      
      // 오류 시 안전한 기본값으로 환영 모달 표시
      _handleNewUser();
      _onUserStatusDetermined?.call(true);
    }
  }

  /// 🆕 신규 사용자 처리
  void _handleNewUser() {
    if (kDebugMode) {
      debugPrint('🆕 [HomeLifecycleCoordinator] 신규 사용자 처리 - 환영 모달 대기');
    }
    
    // 신규 사용자는 기본 상태만 설정 (API 호출 없음)
    _onSubscriptionStateChanged?.call(SubscriptionState.defaultState());
  }

  /// 🔄 기존 사용자 처리 (이벤트 기반)
  void _handleExistingUser() {
    if (kDebugMode) {
      debugPrint('🔄 [HomeLifecycleCoordinator] 기존 사용자 처리 - 이벤트 기반 구독 시작');
    }
    
    // 🎯 구독 이벤트 구독 시작 (UnifiedSubscriptionManager가 자동 관리)
    _setupSubscriptionEventStream();
    
    // 🎯 사용량 스트림 구독 시작
    _setupUsageLimitStream();
    
    // 🎯 초기 상태는 UnifiedSubscriptionManager에서 가져오기
    _loadInitialSubscriptionState();
  }

  /// 🎯 구독 이벤트 스트림 구독 (새로운 핵심 기능)
  void _setupSubscriptionEventStream() {
    // 🔄 기존 구독이 있으면 취소
    _subscriptionEventSubscription?.cancel();
    
    // 🎯 이벤트 스트림이 더 이상 존재하지 않으므로 단순화
    if (kDebugMode) {
      debugPrint('⚠️ [HomeLifecycleCoordinator] 구독 이벤트 스트림 기능 제거됨 - 단순화된 구조');
    }
  }

  /// 🎯 초기 구독 상태 로드 (한 번만)
  Future<void> _loadInitialSubscriptionState() async {
    try {
      if (_hasInitialLoad) return;
      
      if (kDebugMode) {
        debugPrint('🔍 [HomeLifecycleCoordinator] 초기 구독 상태 로드');
      }
      
      // 🎯 UnifiedSubscriptionManager에서 배너 포함 완전한 상태 가져오기
      final subscriptionState = await _subscriptionManager.getSubscriptionStateWithBanners();
      
      _hasInitialLoad = true;
      _onSubscriptionStateChanged?.call(subscriptionState);
      
      if (kDebugMode) {
        debugPrint('✅ [HomeLifecycleCoordinator] 초기 구독 상태 로드 완료');
        debugPrint('   활성 배너: ${subscriptionState.activeBanners.length}개');
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [HomeLifecycleCoordinator] 초기 구독 상태 로드 실패: $e');
      }
      // 실패시 기본 상태
      _onSubscriptionStateChanged?.call(SubscriptionState.defaultState());
    }
  }

  /// 🎯 환영 모달 완료 후 처리 (신규 사용자 → 기존 사용자 전환)
  Future<void> handleWelcomeModalCompleted({
    required bool userChoseTrial,
  }) async {
    if (kDebugMode) {
      debugPrint('🎉 [HomeLifecycleCoordinator] 환영 모달 완료');
      debugPrint('   무료체험 선택: $userChoseTrial');
    }

    // 1. 환영 모달 본 것으로 표시
    final currentUser = FirebaseAuth.instance.currentUser!;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .set({
      'hasSeenWelcomeModal': true,
      'welcomeModalSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 2. 온보딩 완료 상태 저장
    final preferences = await _userPreferencesService.getPreferences();
    await _userPreferencesService.savePreferences(
      preferences.copyWith(onboardingCompleted: true),
    );

    // 3. 이벤트 기반 처리 시작 (UnifiedSubscriptionManager가 구매/상태 변경 자동 감지)
    _setupSubscriptionEventStream();
    _setupUsageLimitStream();

    if (userChoseTrial) {
      // 🎯 무료체험 구매 선택 - UnifiedSubscriptionManager가 자동으로 감지할 예정
      if (kDebugMode) {
        debugPrint('🎯 [HomeLifecycleCoordinator] 무료체험 구매 대기 - UnifiedSubscriptionManager가 자동 처리');
      }
    } else {
      // 🎯 무료 플랜 선택 - 즉시 FREE 상태 설정
      await _setFreeStatus();
    }
  }

  /// 🆓 무료 플랜 상태 설정
  Future<void> _setFreeStatus() async {
    if (kDebugMode) {
      debugPrint('🆓 [HomeLifecycleCoordinator] 무료 플랜 상태 설정');
    }

    // Firestore에 무료 플랜 상태 저장
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .set({
        'planStatus': 'free',
        'subscriptionStatus': 'cancelled',
        'entitlement': 'free',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    // 기본 상태 설정
    _onSubscriptionStateChanged?.call(SubscriptionState.defaultState());
  }

  /// 📊 사용량 한도 스트림 구독 설정 (단순화)
  void _setupUsageLimitStream() {
    // �� 사용량 한도 상태 변경 스트림 구독
    _limitStatusSubscription = _usageLimitService.limitStatusStream.listen(
      (limitStatus) {
        if (kDebugMode) {
          debugPrint('🔔 [HomeLifecycleCoordinator] 실시간 사용량 한도 상태 변경: $limitStatus');
        }
        
        // 🎯 사용량 한도 변경은 별도 처리 (구독 상태와 무관)
        // UI에서 필요시 UsageLimitService를 직접 구독하도록 변경 권장
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
        
        // 🎯 사용자 변경 시 기존 사용자로 처리 (인증 상태 변경 = 이미 온보딩 완료)
        _handleExistingUser();
        _onUserStatusDetermined?.call(false); // 기존 사용자
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

  /// 정리
  void dispose() {
    _limitStatusSubscription?.cancel();
    _authStateSubscription?.cancel();
    _subscriptionEventSubscription?.cancel();
    
    if (kDebugMode) {
      debugPrint('🔄 [HomeLifecycleCoordinator] 리소스 정리 완료');
    }
  }
} 