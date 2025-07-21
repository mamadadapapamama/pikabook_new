import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/subscription_state.dart';
import '../../models/plan.dart';
import '../../models/plan_status.dart';
import '../../constants/subscription_constants.dart';

/// 🎯 구독 상태를 통합적으로 관리하는 서비스 (간소화 버전)
/// 
/// **주요 책임:**
/// 1. Firestore에서 구독 정보 실시간 수신 (주요 경로)
/// 2. InAppPurchase 서버 응답 즉시 반영 (빠른 UI 반응)
/// 3. 구독 상태 변경 시 Stream을 통해 앱 전체에 알림
/// 4. App.dart의 최신 상태를 우선적으로 사용
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
    if (kDebugMode) {
      debugPrint('🔗 [UnifiedSubscriptionManager] App.dart 상태 제공자 ${provider != null ? '설정' : '해제'}');
    }
  }

  /// ---------------------------------------------------
  /// 🎯 상태 변경 감지
  /// ---------------------------------------------------

  void _onAuthStateChanged(User? user) async {
    if (user != null) {
      if (_cachedUserId != user.uid) {
        if (kDebugMode) {
          debugPrint('🔄 [UnifiedSubscriptionManager] 사용자 변경: ${user.uid}');
        }
        _clearUserData();
        _cachedUserId = user.uid;
        _setupFirestoreListener(user.uid);
      }
    } else {
      if (kDebugMode) {
        debugPrint('🔒 [UnifiedSubscriptionManager] 사용자 로그아웃');
      }
      _clearUserData();
      _updateState(SubscriptionState.defaultState());
    }
  }

  void _setupFirestoreListener(String userId) {
    _firestoreSubscription?.cancel();
    
    if (kDebugMode) {
      debugPrint('🔥 [UnifiedSubscriptionManager] Firestore 리스너 설정: users/$userId');
    }
    
    final docRef = _firestore.collection('users').doc(userId);
    _firestoreSubscription = docRef.snapshots().listen(
      _handleFirestoreSnapshot,
      onError: (error) {
        if (kDebugMode) {
          debugPrint('❌ [UnifiedSubscriptionManager] Firestore 리스너 오류: $error');
        }
      }
    );
  }

  /// 🔥 Firestore 스냅샷 처리 (주요 경로)
  void _handleFirestoreSnapshot(DocumentSnapshot snapshot) {
    try {
      if (kDebugMode) {
        debugPrint('🔥 [UnifiedSubscriptionManager] Firestore 데이터 수신');
      }
      
      if (snapshot.exists && snapshot.data() != null) {
        final userData = snapshot.data()! as Map<String, dynamic>;
        final subscriptionData = userData['subscriptionData'] as Map<String, dynamic>?;
        
        if (subscriptionData != null) {
          final newState = SubscriptionState.fromFirestore(subscriptionData);
          _updateState(newState);
          
          if (kDebugMode) {
            debugPrint('✅ [UnifiedSubscriptionManager] 상태 업데이트: ${newState.plan.name} / ${newState.status.name}');
          }
        } else {
          _updateState(SubscriptionState.defaultState());
        }
      } else {
        _updateState(SubscriptionState.defaultState());
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedSubscriptionManager] Firestore 처리 오류: $e');
      }
    }
  }

  /// 🛒 InAppPurchase 서버 응답 처리 (빠른 UI 반응)
  void updateStateWithServerResponse(Map<String, dynamic> serverData) {
    try {
      if (kDebugMode) {
        debugPrint('🛒 [UnifiedSubscriptionManager] 서버 응답 수신');
      }
      
      final newState = SubscriptionState.fromServerResponse(serverData);
      _updateState(newState);
      
      if (kDebugMode) {
        debugPrint('✅ [UnifiedSubscriptionManager] 서버 응답 반영: ${newState.plan.name}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedSubscriptionManager] 서버 응답 처리 오류: $e');
      }
    }
  }

  /// 📝 상태 업데이트 (단일 메서드)
  void _updateState(SubscriptionState newState) {
    _currentState = newState;
    _subscriptionStateController.add(newState);
  }

  /// ---------------------------------------------------
  /// 🎯 Public API
  /// ---------------------------------------------------

  /// 현재 구독 상태 조회 (App.dart 우선)
  Future<SubscriptionState> getSubscriptionState() async {
    // 🎯 1순위: App.dart에서 현재 상태 가져오기
    if (_getCurrentStateFromApp != null) {
      try {
        final appState = _getCurrentStateFromApp!();
        if (kDebugMode) {
          debugPrint('✅ [UnifiedSubscriptionManager] App.dart에서 구독 정보 반환: ${appState.plan.name}');
        }
        return appState;
      } catch (e) {
        if (kDebugMode) {
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
      if (kDebugMode) {
        debugPrint('✅ [UnifiedSubscriptionManager] 메모리에서 구독 정보 반환: ${_currentState!.plan.name}');
      }
      return _currentState!;
    }

    // 🎯 최후: 기본 상태
    return SubscriptionState.defaultState();
  }

  /// Firestore에서 직접 조회
  Future<SubscriptionState> _fetchFromFirestore(String userId) async {
    try {
      if (kDebugMode) {
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
      
      final defaultState = SubscriptionState.defaultState();
      _updateState(defaultState);
      return defaultState;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedSubscriptionManager] Firestore 로드 실패: $e');
      }
      return SubscriptionState.defaultState();
    }
  }

  /// 강제 새로고침
  Future<void> invalidateCache() async {
    if (kDebugMode) {
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