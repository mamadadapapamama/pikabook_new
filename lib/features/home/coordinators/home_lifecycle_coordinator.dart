import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/models/subscription_state.dart';
import '../../../core/services/subscription/unified_subscription_manager.dart';
import '../../../core/services/common/usage_limit_service.dart';
import '../../../core/services/authentication/user_preferences_service.dart';

import '../../../core/services/common/banner_manager.dart';

/// 🔄 HomeScreen 생명주기 관리 Coordinator
/// 
/// 책임:
/// - 온보딩 완료 여부로 신규/기존 사용자 구분
/// - 신규 사용자: 환영 모달 대기 (API 호출 없음)
/// - 기존 사용자: 구독 상태 확인 및 업데이트
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

  /// 🔄 기존 사용자 처리
  Future<void> _handleExistingUser() async {
    if (kDebugMode) {
      debugPrint('🔄 [HomeLifecycleCoordinator] 기존 사용자 처리 - Firestore에서 구독 상태 확인');
    }
    
    // 기존 사용자는 Firestore에서 구독 상태 확인 (API 호출 없음)
    await _loadSubscriptionStatusFromFirestore();
    
    // 사용량 스트림 구독 시작
    setupUsageLimitStream();
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

    // 3. 선택에 따른 처리
    if (userChoseTrial) {
      // 무료체험 구매 선택 - Webhook 대기 (Transaction ID는 InAppPurchaseService에서 자동 저장됨)
      await _waitForSubscriptionChange();
    } else {
      // 무료 플랜 선택 - 즉시 FREE 상태 설정
      await _setFreeStatus();
    }

    // 4. 사용량 스트림 구독 시작
    setupUsageLimitStream();
  }

  /// 🔄 구독 상태 변경 대기 (Firestore 실시간 감지)
  Future<void> _waitForSubscriptionChange() async {
    if (kDebugMode) {
      debugPrint('⏳ [HomeLifecycleCoordinator] 구독 상태 변경 대기 시작 (Webhook → Firestore)');
    }

    final currentUser = FirebaseAuth.instance.currentUser!;
    
    // 30초 타임아웃으로 구독 상태 변경 감지
    final completer = Completer<bool>();
    StreamSubscription? subscription;
    Timer? timeoutTimer;

    try {
      // Firestore에서 사용자 문서의 구독 상태 변경 감지
      subscription = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .snapshots()
          .listen((documentSnapshot) {
        
        if (documentSnapshot.exists) {
          final data = documentSnapshot.data() as Map<String, dynamic>;
          final entitlement = data['entitlement'] as String? ?? 'free';
          
          if (kDebugMode) {
            debugPrint('📱 [HomeLifecycleCoordinator] 사용자 구독 상태 변경 감지: $entitlement');
          }
          
          // trial 또는 premium으로 변경되면 성공
          if (entitlement == 'trial' || entitlement == 'premium') {
            if (!completer.isCompleted) {
              completer.complete(true);
            }
          }
        }
      });

      // 30초 타임아웃 설정
      timeoutTimer = Timer(Duration(seconds: 30), () {
        if (!completer.isCompleted) {
          if (kDebugMode) {
            debugPrint('⏰ [HomeLifecycleCoordinator] 구독 상태 변경 대기 타임아웃');
          }
          completer.complete(false);
        }
      });

      // 구독 상태 변경 대기
      final success = await completer.future;

      if (success) {
        // 성공: Firestore에서 최신 상태 로드 + 배너 업데이트
        await _loadSubscriptionStatusFromFirestore();
        await _updateBannersAfterSubscriptionChange();
        if (kDebugMode) {
          debugPrint('✅ [HomeLifecycleCoordinator] 구독 활성화 완료');
        }
      } else {
        // 타임아웃: 무료 플랜으로 폴백
        if (kDebugMode) {
          debugPrint('⚠️ [HomeLifecycleCoordinator] 구독 활성화 타임아웃 - 무료 플랜으로 폴백');
        }
        await _setFreeStatus();
      }

    } finally {
      subscription?.cancel();
      timeoutTimer?.cancel();
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

  /// 📱 Firestore에서 구독 상태 직접 확인 (기존 사용자용)
  Future<void> _loadSubscriptionStatusFromFirestore() async {
    try {
      if (kDebugMode) {
        debugPrint('📱 [HomeLifecycleCoordinator] Firestore에서 구독 상태 로드 시작');
      }

      final currentUser = FirebaseAuth.instance.currentUser!;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) {
        if (kDebugMode) {
          debugPrint('⚠️ [HomeLifecycleCoordinator] 사용자 문서가 없음 - 기본 상태로 설정');
        }
        _onSubscriptionStateChanged?.call(SubscriptionState.defaultState());
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      
      // Firestore에서 구독 상태 추출
      final entitlement = userData['entitlement'] as String? ?? 'free';
      final subscriptionStatus = userData['subscriptionStatus'] as String? ?? 'cancelled';
      final hasUsedTrial = userData['hasUsedTrial'] as bool? ?? false;

      if (kDebugMode) {
        debugPrint('📱 [HomeLifecycleCoordinator] Firestore 구독 상태:');
        debugPrint('   entitlement: $entitlement');
        debugPrint('   subscriptionStatus: $subscriptionStatus');
        debugPrint('   hasUsedTrial: $hasUsedTrial');
      }

      // 사용량 한도 확인
      final usageLimitStatus = await _usageLimitService.checkInitialLimitStatus(
        planType: entitlement,
      );
      final hasUsageLimitReached = (usageLimitStatus['ocrLimitReached'] ?? false) || 
                                  (usageLimitStatus['ttsLimitReached'] ?? false);

      // 활성 배너 확인
      final bannerManager = BannerManager();
      final serverResponse = {
        'subscription': {
          'entitlement': entitlement,
          'subscriptionStatus': subscriptionStatus,
          'hasUsedTrial': hasUsedTrial,
          'bannerMetadata': userData['bannerMetadata'],
        },
      };
      
      final activeBanners = await bannerManager.getActiveBannersFromServerResponse(
        serverResponse,
        forceRefresh: false,
      );

      // SubscriptionState 생성
      final subscriptionState = SubscriptionState(
        entitlement: Entitlement.fromString(entitlement),
        subscriptionStatus: SubscriptionStatus.fromString(subscriptionStatus),
        hasUsedTrial: hasUsedTrial,
        hasUsageLimitReached: hasUsageLimitReached,
        activeBanners: activeBanners,
        statusMessage: _getStatusMessage(entitlement, subscriptionStatus),
      );

      if (kDebugMode) {
        debugPrint('✅ [HomeLifecycleCoordinator] Firestore 구독 상태 로드 완료');
        debugPrint('   상태 메시지: ${subscriptionState.statusMessage}');
        debugPrint('   활성 배너: ${activeBanners.map((e) => e.name).toList()}');
      }

      // 콜백 호출
      _onSubscriptionStateChanged?.call(subscriptionState);

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [HomeLifecycleCoordinator] Firestore 구독 상태 로드 실패: $e');
      }
      
      // 실패 시 기본 상태 설정
      _onSubscriptionStateChanged?.call(SubscriptionState.defaultState());
    }
  }

  /// 상태 메시지 생성
  String _getStatusMessage(String entitlement, String subscriptionStatus) {
    if (entitlement == 'trial') {
      return subscriptionStatus == 'cancelling' ? '무료체험 (취소 예정)' : '무료체험 중';
    } else if (entitlement == 'premium') {
      return subscriptionStatus == 'cancelling' ? '프리미엄 (취소 예정)' : '프리미엄';
    } else {
      return '무료 플랜';
    }
  }

  /// 🎯 구독 상태 변경 후 배너 업데이트
  Future<void> _updateBannersAfterSubscriptionChange() async {
    try {
      if (kDebugMode) {
        debugPrint('🎯 [HomeLifecycleCoordinator] 구독 상태 변경 후 배너 업데이트 시작');
      }

      final currentUser = FirebaseAuth.instance.currentUser!;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) return;

      final userData = userDoc.data() as Map<String, dynamic>;
      final entitlement = userData['entitlement'] as String? ?? 'free';
      final bannerManager = BannerManager();

      // 기존 배너들 초기화
      bannerManager.invalidateBannerCache();

      // 구독 상태에 따른 배너 설정
      if (entitlement == 'trial') {
        // 무료체험 시작 배너 활성화
        bannerManager.setBannerState(BannerType.trialStarted, true, planId: 'welcome_trial');
        if (kDebugMode) {
          debugPrint('🎯 [HomeLifecycleCoordinator] 무료체험 시작 배너 활성화');
        }
      } else if (entitlement == 'premium') {
        // 프리미엄 시작 배너 활성화
        bannerManager.setBannerState(BannerType.premiumStarted, true, planId: 'welcome_premium');
        if (kDebugMode) {
          debugPrint('🎯 [HomeLifecycleCoordinator] 프리미엄 시작 배너 활성화');
        }
      }

      if (kDebugMode) {
        debugPrint('✅ [HomeLifecycleCoordinator] 배너 업데이트 완료');
      }

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [HomeLifecycleCoordinator] 배너 업데이트 실패: $e');
      }
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
        await _loadSubscriptionStatus(forceRefresh: true, context: '사용량변경');
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
  Future<void> _loadSubscriptionStatus({
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
      
      // 🎯 신규 사용자는 환영 모달 완료 전까지 구독 상태 체크 건너뜀
      // 이 메서드는 기존 사용자만 호출하도록 변경됨
      
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

  /// 🎯 온보딩 완료 후 구독 상태 로드 (Deprecated - 새로운 플로우에서는 사용하지 않음)
  @Deprecated('Use handleWelcomeModalCompleted instead')
  Future<void> loadSubscriptionStatusAfterOnboarding() async {
    if (kDebugMode) {
      debugPrint('[HomeLifecycleCoordinator] 🎉 환영 모달 완료 - 이제 정상적인 서비스 호출 시작');
    }
    await _loadSubscriptionStatus(
      forceRefresh: true,
      setupUsageStream: true,
      context: '온보딩완료',
    );
  }

  /// 🎯 포그라운드 복귀 시 구독 상태 로드
  Future<void> loadSubscriptionStatusAfterResume() async {
    await _loadSubscriptionStatus(
      forceRefresh: false,
      context: '포그라운드복귀',
    );
  }

  /// 🎯 구매 완료 후 구독 상태 로드
  Future<void> loadSubscriptionStatusAfterPurchase() async {
    await _loadSubscriptionStatus(
      forceRefresh: true,
      skipOnboardingCheck: true,
      context: '구매완료',
    );
  }

  /// 🎯 수동 새로고침
  Future<void> refreshSubscriptionStatus() async {
    await _loadSubscriptionStatus(
      context: '수동새로고침',
    );
  }

  /// 🎯 신규 사용자를 위한 초기화 (환영 모달용) (Deprecated - 새로운 플로우에서는 사용하지 않음)
  @Deprecated('Use _handleNewUser instead')
  void initializeForNewUser() {
    if (kDebugMode) {
      debugPrint('[HomeLifecycleCoordinator] 🆕 신규 사용자 초기화 - 환영 모달 완료 전까지 최소 서비스 호출');
    }
    // 신규 사용자는 기본 상태만 설정 (구독 상태 체크 없음)
    _onSubscriptionStateChanged?.call(SubscriptionState.defaultState());
  }

  /// 🎯 기존 사용자를 위한 초기화
  Future<void> initializeForExistingUser() async {
    if (kDebugMode) {
      debugPrint('[HomeLifecycleCoordinator] 🔄 기존 사용자 초기화 - 사용량 스트림 구독 및 구독 상태 로드');
    }
    await _loadSubscriptionStatus(
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