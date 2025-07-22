import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/subscription_state.dart';
import '../../models/plan.dart';
import '../../models/plan_status.dart';
import '../../constants/subscription_constants.dart';
import '../../constants/feature_flags.dart';

/// 🎯 구독 상태를 통합적으로 관리하는 서비스 (심사용 단순화 버전)
/// 
/// **주요 책임:**
/// 1. Feature Flag에 따라 구독 기능 비활성화
/// 2. 기본 무료 상태 또는 수동 프리미엄 상태만 관리
/// 3. Firestore 의존성 최소화
class UnifiedSubscriptionManager {
  static final UnifiedSubscriptionManager _instance =
      UnifiedSubscriptionManager._internal();
  factory UnifiedSubscriptionManager() => _instance;

  // 🎯 의존성
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 🎯 상태 관리
  final StreamController<SubscriptionState> _subscriptionStateController = 
      StreamController<SubscriptionState>.broadcast();
  Stream<SubscriptionState> get subscriptionStateStream =>
      _subscriptionStateController.stream;
  
  // 🎯 내부 상태
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<DocumentSnapshot>? _firestoreSubscription;
  String? _cachedUserId;
  SubscriptionState? _currentState; // 현재 상태만 메모리에 보관

  // 🎯 App.dart에서 현재 상태를 주입받기 위한 콜백
  SubscriptionState Function()? _getCurrentStateFromApp;

  /// ---------------------------------------------------
  /// 🎯 초기화 및 생명주기
  /// ---------------------------------------------------

  UnifiedSubscriptionManager._internal() {
    _authSubscription = _auth.authStateChanges().listen(_onAuthStateChanged);
  }

  void dispose() {
    _authSubscription?.cancel();
    _firestoreSubscription?.cancel();
    _subscriptionStateController.close();
  }

  /// 🎯 App.dart에서 현재 상태를 가져오는 콜백 설정
  void setCurrentStateProvider(SubscriptionState Function()? provider) {
    _getCurrentStateFromApp = provider;
    if (kDebugMode && FeatureFlags.SUBSCRIPTION_DEBUG_LOGS) {
      debugPrint('🔗 [UnifiedSubscriptionManager] App.dart 상태 제공자 ${provider != null ? '설정' : '해제'}');
    }
  }

  /// ---------------------------------------------------
  /// 🎯 상태 변경 감지
  /// ---------------------------------------------------

  void _onAuthStateChanged(User? user) async {
    if (user != null) {
      if (_cachedUserId != user.uid) {
        if (kDebugMode && FeatureFlags.SUBSCRIPTION_DEBUG_LOGS) {
          debugPrint('🔄 [UnifiedSubscriptionManager] 사용자 변경: ${user.uid}');
        }
        _clearUserData();
        _cachedUserId = user.uid;
        
        // 🎯 Feature Flag에 따라 Firestore 리스너 설정 여부 결정
        if (FeatureFlags.FIRESTORE_SUBSCRIPTION_SYNC_ENABLED) {
          _setupFirestoreListener(user.uid);
        } else {
          // 기본 무료 상태로 설정
          _updateState(_getDefaultSubscriptionState());
        }
      }
    } else {
      if (kDebugMode && FeatureFlags.SUBSCRIPTION_DEBUG_LOGS) {
        debugPrint('🔒 [UnifiedSubscriptionManager] 사용자 로그아웃');
      }
      _clearUserData();
      _updateState(SubscriptionState.defaultState());
    }
  }

  void _setupFirestoreListener(String userId) {
    _firestoreSubscription?.cancel();
    
    if (kDebugMode && FeatureFlags.SUBSCRIPTION_DEBUG_LOGS) {
      debugPrint('🔥 [UnifiedSubscriptionManager] Firestore 리스너 설정: users/$userId');
    }
    
    final docRef = _firestore.collection('users').doc(userId);
    _firestoreSubscription = docRef.snapshots().listen(
      _handleFirestoreSnapshot,
      onError: (error) {
        if (kDebugMode && FeatureFlags.SUBSCRIPTION_DEBUG_LOGS) {
          debugPrint('❌ [UnifiedSubscriptionManager] Firestore 리스너 오류: $error');
        }
      }
    );
  }

  /// 🔥 Firestore 스냅샷 처리 (Feature Flag에 따라 비활성화 가능)
  void _handleFirestoreSnapshot(DocumentSnapshot snapshot) {
    if (!FeatureFlags.FIRESTORE_SUBSCRIPTION_SYNC_ENABLED) {
      return; // Firestore 동기화 비활성화됨
    }

    try {
      if (kDebugMode && FeatureFlags.SUBSCRIPTION_DEBUG_LOGS) {
        debugPrint('🔥 [UnifiedSubscriptionManager] Firestore 데이터 수신');
      }
      
      if (snapshot.exists && snapshot.data() != null) {
        final userData = snapshot.data()! as Map<String, dynamic>;
        final subscriptionData = userData['subscriptionData'] as Map<String, dynamic>?;
        
        if (subscriptionData != null) {
          final newState = SubscriptionState.fromFirestore(subscriptionData);
          _updateState(newState);
          
          if (kDebugMode && FeatureFlags.SUBSCRIPTION_DEBUG_LOGS) {
            debugPrint('✅ [UnifiedSubscriptionManager] 상태 업데이트: ${newState.plan.name} / ${newState.status.name}');
          }
        } else {
          _updateState(_getDefaultSubscriptionState());
        }
      } else {
        _updateState(_getDefaultSubscriptionState());
      }
    } catch (e) {
      if (kDebugMode && FeatureFlags.SUBSCRIPTION_DEBUG_LOGS) {
        debugPrint('❌ [UnifiedSubscriptionManager] Firestore 처리 오류: $e');
      }
    }
  }

  /// 🛒 InAppPurchase 서버 응답 처리 (Feature Flag에 따라 비활성화)
  void updateStateWithServerResponse(Map<String, dynamic> serverData) {
    if (!FeatureFlags.AUTO_SUBSCRIPTION_UPDATE_ENABLED) {
      if (kDebugMode) {
        debugPrint('🚫 [UnifiedSubscriptionManager] 자동 구독 업데이트 비활성화됨');
      }
      return;
    }

    try {
      if (kDebugMode && FeatureFlags.SUBSCRIPTION_DEBUG_LOGS) {
        debugPrint('🛒 [UnifiedSubscriptionManager] 서버 응답 수신');
      }
      
      final newState = SubscriptionState.fromServerResponse(serverData);
      _updateState(newState);
      
      if (kDebugMode && FeatureFlags.SUBSCRIPTION_DEBUG_LOGS) {
        debugPrint('✅ [UnifiedSubscriptionManager] 서버 응답 반영: ${newState.plan.name}');
      }
    } catch (e) {
      if (kDebugMode && FeatureFlags.SUBSCRIPTION_DEBUG_LOGS) {
        debugPrint('❌ [UnifiedSubscriptionManager] 서버 응답 처리 오류: $e');
      }
    }
  }

  /// 📝 상태 업데이트 (단일 메서드)
  void _updateState(SubscriptionState newState) {
    _currentState = newState;
    _subscriptionStateController.add(newState);
  }

  /// 🎯 기본 구독 상태 반환 (Feature Flag에 따라 결정)
  SubscriptionState _getDefaultSubscriptionState() {
    // 강제 상태 설정이 있는 경우
    if (FeatureFlags.FORCE_SUBSCRIPTION_STATE != null) {
      if (FeatureFlags.FORCE_SUBSCRIPTION_STATE == 'premium_manual') {
        return SubscriptionState(
          plan: Plan.premiumMonthly(), // 수동 프리미엄은 월간으로 설정
          status: PlanStatus.active,
          hasUsedTrial: false,
          timestamp: DateTime.now(),
        );
      }
    }
    
    // 기본값: 무료 상태
    return SubscriptionState.defaultState();
  }

  /// ---------------------------------------------------
  /// 🎯 Public API
  /// ---------------------------------------------------

  /// 현재 구독 상태 조회 (단순화됨)
  Future<SubscriptionState> getSubscriptionState() async {
    // 🎯 Feature Flag에 따른 단순화된 로직
    if (!FeatureFlags.FIRESTORE_SUBSCRIPTION_SYNC_ENABLED) {
      // Firestore 동기화 비활성화 시 기본 상태만 반환
      final defaultState = _getDefaultSubscriptionState();
      if (kDebugMode) {
        debugPrint('✅ [UnifiedSubscriptionManager] 기본 구독 상태 반환: ${defaultState.plan.name}');
      }
      return defaultState;
    }

    // 🎯 1순위: App.dart에서 현재 상태 가져오기
    if (_getCurrentStateFromApp != null) {
      try {
        final appState = _getCurrentStateFromApp!();
        if (kDebugMode && FeatureFlags.SUBSCRIPTION_DEBUG_LOGS) {
          debugPrint('✅ [UnifiedSubscriptionManager] App.dart에서 구독 정보 반환: ${appState.plan.name}');
        }
        return appState;
      } catch (e) {
        if (kDebugMode && FeatureFlags.SUBSCRIPTION_DEBUG_LOGS) {
          debugPrint('⚠️ [UnifiedSubscriptionManager] App.dart 상태 가져오기 실패, 폴백 사용: $e');
        }
      }
    }

    // 🎯 2순위: Firestore에서 직접 로드 (최신 상태 보장)
    final userId = _auth.currentUser?.uid;
    if (userId != null) {
      return _fetchFromFirestore(userId);
    }

    // 🎯 3순위: 메모리 캐시 (마지막 수단)
    if (_currentState != null) {
      if (kDebugMode && FeatureFlags.SUBSCRIPTION_DEBUG_LOGS) {
        debugPrint('✅ [UnifiedSubscriptionManager] 메모리에서 구독 정보 반환: ${_currentState!.plan.name}');
      }
      return _currentState!;
    }

    // 🎯 최후: 기본 상태
    return _getDefaultSubscriptionState();
  }

  /// Firestore에서 직접 조회 (Feature Flag에 따라 비활성화 가능)
  Future<SubscriptionState> _fetchFromFirestore(String userId) async {
    if (!FeatureFlags.FIRESTORE_SUBSCRIPTION_SYNC_ENABLED) {
      return _getDefaultSubscriptionState();
    }

    try {
      if (kDebugMode && FeatureFlags.SUBSCRIPTION_DEBUG_LOGS) {
        debugPrint('☁️ [UnifiedSubscriptionManager] Firestore에서 구독 정보 로드');
      }

      final docRef = _firestore.collection('users').doc(userId);
      final snapshot = await docRef.get();
      
      if (snapshot.exists && snapshot.data() != null) {
        final userData = snapshot.data()! as Map<String, dynamic>;
        final subscriptionData = userData['subscriptionData'] as Map<String, dynamic>?;
        
        if (subscriptionData != null) {
          final state = SubscriptionState.fromFirestore(subscriptionData);
          _updateState(state);
          return state;
        }
      }
      
      final defaultState = _getDefaultSubscriptionState();
      _updateState(defaultState);
      return defaultState;
    } catch (e) {
      if (kDebugMode && FeatureFlags.SUBSCRIPTION_DEBUG_LOGS) {
        debugPrint('❌ [UnifiedSubscriptionManager] Firestore 로드 실패: $e');
      }
      return _getDefaultSubscriptionState();
    }
  }

  /// 강제 새로고침 (Feature Flag에 따라 비활성화 가능)
  Future<void> invalidateCache() async {
    if (!FeatureFlags.FIRESTORE_SUBSCRIPTION_SYNC_ENABLED) {
      if (kDebugMode) {
        debugPrint('🚫 [UnifiedSubscriptionManager] Firestore 동기화 비활성화로 인한 캐시 무효화 스킵');
      }
      return;
    }

    if (kDebugMode && FeatureFlags.SUBSCRIPTION_DEBUG_LOGS) {
      debugPrint('🔄 [UnifiedSubscriptionManager] 강제 새로고침');
    }
    
    final userId = _auth.currentUser?.uid;
    if (userId != null) {
      await _fetchFromFirestore(userId);
    }
  }

  /// ---------------------------------------------------
  /// 🎯 헬퍼 메서드
  /// ---------------------------------------------------

  void _clearUserData() {
    _firestoreSubscription?.cancel();
    _firestoreSubscription = null;
    _cachedUserId = null;
    _currentState = null;
  }

  /// 현재 상태 즉시 반환 (스트림용)
  SubscriptionState? get currentState => _currentState;

  /// 현재 플랜 조회
  Future<Plan> getCurrentPlan() async {
    final state = await getSubscriptionState();
    return state.plan;
  }
} 