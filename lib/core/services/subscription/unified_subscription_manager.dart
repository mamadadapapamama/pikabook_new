import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../cache/local_cache_storage.dart';
import '../../models/subscription_state.dart';
import '../../models/plan.dart';
import '../../models/plan_status.dart';
import '../payment/in_app_purchase_service.dart';

/// 🎯 구독 상태를 통합적으로 관리하는 서비스 (SubscriptionRepository 역할)
/// 
/// **주요 책임:**
/// 1. Firestore에서 구독 정보 실시간 수신
/// 2. 로컬 캐시를 활용하여 빠른 응답 및 오프라인 지원
/// 3. 구독 상태 변경 시 Stream을 통해 앱 전체에 알림
/// 4. In-App Purchase 성공 시 서버 응답을 직접 받아 상태 즉시 업데이트
class UnifiedSubscriptionManager {
  static final UnifiedSubscriptionManager _instance =
      UnifiedSubscriptionManager._internal();
  factory UnifiedSubscriptionManager() => _instance;

  // 🎯 의존성
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocalCacheStorage<Map<String, dynamic>> _cache =
      LocalCacheStorage(
        namespace: 'subscription',
        maxSize: 1 * 1024 * 1024, // 1MB
        maxItems: 10,
        fromJson: (json) => json,
        toJson: (data) => data,
      );

  // 🎯 상태 관리
  final StreamController<SubscriptionState> _subscriptionStateController = 
      StreamController<SubscriptionState>.broadcast();
  Stream<SubscriptionState> get subscriptionStateStream =>
      _subscriptionStateController.stream;
  
  // 🎯 내부 상태
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot>? _firestoreSubscription;
  String? _cachedUserId;

  // 🎯 상수
  static const String _cacheKey = 'main_subscription_state';
  static const Duration _cacheDuration = Duration(hours: 1);

  /// ---------------------------------------------------
  /// 🎯 초기화 및 생명주기
  /// ---------------------------------------------------

  UnifiedSubscriptionManager._internal() {
    _authSubscription = _auth.authStateChanges().listen(_onAuthStateChanged);
    _initializeOnFirstAuth();
  }

  void _initializeOnFirstAuth() async {
    // 앱 시작 시 첫 인증 상태 확인
    await _cache.initialize(); // 캐시 초기화 추가
    final currentUser = _auth.currentUser;
    if (currentUser != null) {
      _onAuthStateChanged(currentUser);
      }
  }

  void dispose() {
    _authSubscription?.cancel();
    _firestoreSubscription?.cancel();
    _subscriptionStateController.close();
  }

  /// ---------------------------------------------------
  /// 🎯 상태 변경 감지
  /// ---------------------------------------------------

  void _onAuthStateChanged(User? user) async {
    if (user != null) {
      if (_cachedUserId != user.uid) {
        if (kDebugMode) {
          debugPrint(
              '🔄 [UnifiedSubscriptionManager] 사용자 변경 감지: ${user.uid}');
        }
        _clearAllUserCache();
        _cachedUserId = user.uid;

        // InAppPurchaseService 초기화 (구매 가능 상태 확인)
        await InAppPurchaseService().initialize();

        _setupFirestoreListener(user.uid);
        getSubscriptionState(forceRefresh: true);
      }
      } else {
      if (kDebugMode) {
        debugPrint(
            '🔒 [UnifiedSubscriptionManager] 사용자 로그아웃 감지. 모든 사용자 데이터 초기화.');
      }
      _clearAllUserCache();
      _subscriptionStateController.add(SubscriptionState.defaultState());
  }
  }

  void _setupFirestoreListener(String userId) {
    _firestoreSubscription?.cancel();
    if (kDebugMode) {
      debugPrint(
          '🔥 [UnifiedSubscriptionManager] Firestore 리스너 설정 시작: users/$userId/private/subscription');
    }
    
    final docRef = _firestore
        .collection('users')
        .doc(userId)
        .collection('private')
        .doc('subscription');

    _firestoreSubscription = docRef.snapshots().listen((snapshot) {
      if (kDebugMode) {
        debugPrint('🔥 [UnifiedSubscriptionManager] Firestore 데이터 변경 감지!');
        }
      getSubscriptionState(forceRefresh: true);
    }, onError: (error) {
      if (kDebugMode) {
        debugPrint(
            '❌ [UnifiedSubscriptionManager] Firestore 리스너 오류: $error');
      }
    });
  }

  /// 🎯 서버 응답 데이터로 직접 상태 업데이트 (InAppPurchaseService에서 호출)
  void updateStateWithServerResponse(Map<String, dynamic> serverData) {
    if (kDebugMode) {
      debugPrint(
          '⚡️ [UnifiedSubscriptionManager] 서버 응답으로 직접 상태 업데이트 시작');
    }
    try {
      final newState = SubscriptionState.fromServerResponse(serverData);
      _cache.set(_cacheKey, newState.toJson());
      _subscriptionStateController.add(newState);
      
      if (kDebugMode) {
        debugPrint(
            '✅ [UnifiedSubscriptionManager] 상태 업데이트 완료: ${newState.plan.name}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedSubscriptionManager] 서버 응답 처리 중 오류: $e');
      }
    }
  }

  /// ---------------------------------------------------
  /// 🎯 Public API (외부에서 사용)
  /// ---------------------------------------------------

  /// 현재 구독 상태 조회
  Future<SubscriptionState> getSubscriptionState(
      {bool forceRefresh = false}) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      return SubscriptionState.defaultState();
  }

    // 캐시 확인
    if (!forceRefresh) {
      final cachedData = await _cache.get(_cacheKey);
      if (cachedData != null) {
        // TODO: 캐시 만료 로직 추가 필요 (LocalCacheStorage에 TTL 기능이 없다면)
        if (kDebugMode) {
          debugPrint('✅ [UnifiedSubscriptionManager] 캐시에서 구독 정보 로드');
        }
        final state = SubscriptionState.fromFirestore(cachedData);
        _subscriptionStateController.add(state); // 스트림에 최신 상태 전파
        return state;
      }
    }
    
    // 캐시 없거나 만료 시 Firestore에서 로드
    return _fetchFromFirestore(userId);
  }
  
  /// 캐시 무효화 및 상태 새로고침 (외부 호출용)
  Future<void> invalidateCache() async {
    if (kDebugMode) {
      debugPrint('🔄 [UnifiedSubscriptionManager] 캐시 무효화 및 강제 새로고침');
    }
    await getSubscriptionState(forceRefresh: true);
  }

  /// ---------------------------------------------------
  /// 🎯 내부 로직
  /// ---------------------------------------------------

  Future<SubscriptionState> _fetchFromFirestore(String userId) async {
    if (kDebugMode) {
      debugPrint('☁️ [UnifiedSubscriptionManager] Firestore에서 구독 정보 로드');
    }
    try {
      final docRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('private')
          .doc('subscription');

      final snapshot = await docRef.get();

      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data()!;
        final newState = SubscriptionState.fromFirestore(data);

        // ✅ JWS 정보가 없는 UNVERIFIED 상태일 때, 구매 복원 로직 실행
        if (newState.status == PlanStatus.unverified) {
          if (kDebugMode) {
            debugPrint('🤔 [UnifiedSubscriptionManager] 구독 상태 미확인(UNVERIFIED). 구매 정보 복원을 시도합니다.');
          }
          InAppPurchaseService().restorePurchases();
          
          // 🚦 중요: unverified 상태에서는 배너를 표시하지 않음.
          // restorePurchases가 완료되고 실제 상태가 스트림으로 들어올 때까지 기다립니다.
          final stateWithoutBanners = newState.copyWith(activeBanners: []);
          _cache.set(_cacheKey, stateWithoutBanners.toJson());
          _subscriptionStateController.add(stateWithoutBanners);
          return stateWithoutBanners;
        }
        
        _cache.set(_cacheKey, newState.toJson()); // 캐시 업데이트
        _subscriptionStateController.add(newState);
        return newState;
      } else {
        // Firestore에 문서가 없으면 기본 상태로 간주
        final defaultState = SubscriptionState.defaultState();
        _cache.set(_cacheKey, defaultState.toJson());
        _subscriptionStateController.add(defaultState);
        return defaultState;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '❌ [UnifiedSubscriptionManager] Firestore 로드 실패: $e');
      }
      return SubscriptionState.defaultState();
    }
  }

  void _clearAllUserCache() {
    _firestoreSubscription?.cancel();
    _firestoreSubscription = null;
    _cache.clear();
    _cachedUserId = null;
    if (kDebugMode) {
      debugPrint('🗑️ [UnifiedSubscriptionManager] 모든 사용자 캐시/리스너 정리 완료');
    }
  }

  // 헬퍼: 현재 Plan 객체 가져오기 (UI에서 사용)
  Future<Plan> getCurrentPlan() async {
    final state = await getSubscriptionState();
    return state.plan;
  }
} 