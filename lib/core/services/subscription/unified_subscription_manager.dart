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
  SubscriptionState? _currentState; // 현재 상태 캐싱
  DateTime? _lastCacheTime; // 캐시 시간 추적

  // 🎯 상수
  static const String _cacheKey = 'main_subscription_state';
  static const Duration _cacheDuration = Duration(minutes: 5); // 캐시 만료 시간을 5분으로 단축
  static const Duration _unverifiedRetryDelay = Duration(seconds: 10); // UNVERIFIED 상태 재시도 간격

  // 🎯 UNVERIFIED 상태 관리
  Timer? _unverifiedRetryTimer;
  int _unverifiedRetryCount = 0;
  static const int maxUnverifiedRetries = 3;

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
    _unverifiedRetryTimer?.cancel();
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
      final defaultState = SubscriptionState.defaultState();
      _updateCurrentState(defaultState);
  }
  }

  void _setupFirestoreListener(String userId) {
    _firestoreSubscription?.cancel();
    if (kDebugMode) {
      debugPrint('🔥 [UnifiedSubscriptionManager] Firestore 리스너 설정 시작: users/$userId');
    }
    
    // 🎯 수정: 올바른 경로로 변경 (users/{userId} 문서)
    final docRef = _firestore.collection('users').doc(userId);

    _firestoreSubscription = docRef.snapshots().listen((snapshot) {
      if (kDebugMode) {
        debugPrint('🔥 [UnifiedSubscriptionManager] Firestore 데이터 변경 감지!');
      }
      // 🔥 중요: Firestore 변경 시 직접 상태 처리 (무한 루프 방지)
      _handleFirestoreSnapshot(snapshot);
    }, onError: (error) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedSubscriptionManager] Firestore 리스너 오류: $error');
      }
    });
  }

  /// 🎯 서버 응답 데이터로 직접 상태 업데이트 (InAppPurchaseService에서 호출)
  void updateStateWithServerResponse(Map<String, dynamic> serverData) {
    if (kDebugMode) {
      debugPrint('⚡️ [UnifiedSubscriptionManager] 서버 응답으로 직접 상태 업데이트 시작');
      debugPrint('서버 데이터: $serverData');
    }
    try {
      final newState = SubscriptionState.fromServerResponse(serverData);
      
      if (kDebugMode) {
        debugPrint('✅ [UnifiedSubscriptionManager] 파싱된 새 상태:');
        debugPrint('   - Plan: ${newState.plan.name}');
        debugPrint('   - Status: ${newState.status.name}');
        debugPrint('   - IsPremium: ${newState.isPremiumOrTrial}');
        debugPrint('   - ExpiresDate: ${newState.expiresDate}');
        debugPrint('   - HasUsedTrial: ${newState.hasUsedTrial}');
        debugPrint('   - Timestamp: ${newState.timestamp}');
      }
      
      // 🎯 기존 상태와 timestamp 비교 - 더 최신 응답만 처리
      if (_currentState != null) {
        final currentTimestamp = _currentState!.timestamp;
        final newTimestamp = newState.timestamp;
        
        if (currentTimestamp != null && newTimestamp != null) {
          if (!newTimestamp.isAfter(currentTimestamp)) {
            if (kDebugMode) {
              debugPrint('⏭️ [UnifiedSubscriptionManager] 더 오래된 응답 무시');
              debugPrint('   - 현재: $currentTimestamp');
              debugPrint('   - 새로운: $newTimestamp');
            }
            return;
          }
        }
      }
      
      // 🎯 PREMIUM entitlement 우선 처리
      final entitlement = serverData['entitlement'] as String?;
      if (_currentState != null && entitlement == 'FREE') {
        // 현재 상태가 프리미엄이고 새 응답이 FREE라면 timestamp 차이 확인
        if (_currentState!.isPremiumOrTrial) {
          final timeDiff = newState.timestamp != null && _currentState!.timestamp != null 
              ? newState.timestamp!.difference(_currentState!.timestamp!).inSeconds.abs()
              : 0;
          
          // 5초 이내의 응답이면 PREMIUM을 우선
          if (timeDiff <= 5) {
            if (kDebugMode) {
              debugPrint('⏭️ [UnifiedSubscriptionManager] FREE 응답 무시 - 현재 PREMIUM 상태 유지 (${timeDiff}초 차이)');
            }
            return;
          }
        }
      }
      
      _updateCurrentState(newState, fromServer: true);
      
      if (kDebugMode) {
        debugPrint('✅ [UnifiedSubscriptionManager] 상태 업데이트 완료: ${newState.plan.name}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedSubscriptionManager] 서버 응답 처리 중 오류: $e');
        debugPrint('서버 데이터: $serverData');
      }
    }
  }

  /// 📝 상태 업데이트 통합 메서드
  void _updateCurrentState(SubscriptionState newState, {bool fromServer = false}) {
    _currentState = newState;
    _lastCacheTime = DateTime.now();
    
    // 캐시에 저장
    _cache.set(_cacheKey, newState.toJson());
    
    // 스트림에 전파
    _subscriptionStateController.add(newState);
    
    if (kDebugMode) {
      final source = fromServer ? '서버' : 'Firestore';
      debugPrint('📝 [UnifiedSubscriptionManager] 상태 업데이트 ($source): ${newState.plan.name} / ${newState.status}');
    }
  }

  /// 🔥 Firestore 스냅샷 직접 처리 (개선됨)
  void _handleFirestoreSnapshot(DocumentSnapshot snapshot) {
    try {
      if (snapshot.exists && snapshot.data() != null) {
        final userData = snapshot.data()! as Map<String, dynamic>;
        // 🎯 수정: subscriptionData 필드에서 데이터 추출
        final subscriptionData = userData['subscriptionData'] as Map<String, dynamic>?;
        
        if (subscriptionData == null) {
          if (kDebugMode) {
            debugPrint('⚠️ [UnifiedSubscriptionManager] subscriptionData 필드가 없음 - 기본 상태 사용');
          }
          final defaultState = SubscriptionState.defaultState();
          _updateCurrentState(defaultState);
          return;
        }

        if (kDebugMode) {
          debugPrint('✅ [UnifiedSubscriptionManager] Firestore 스냅샷 처리');
          debugPrint('   - entitlement: ${subscriptionData['entitlement']}');
          debugPrint('   - subscriptionStatus: ${subscriptionData['subscriptionStatus']}');
          debugPrint('   - productId: ${subscriptionData['productId']}');
        }

        final newState = SubscriptionState.fromFirestore(subscriptionData);

        // ✅ UNVERIFIED 상태 처리 개선
        if (newState.status == PlanStatus.unverified) {
          _handleUnverifiedState(newState);
          return;
        }
        
        // 정상 상태일 때 UNVERIFIED 재시도 초기화
        _resetUnverifiedRetry();
        _updateCurrentState(newState);
      } else {
        // Firestore에 문서가 없으면 기본 상태로 간주
        if (kDebugMode) {
          debugPrint('⚠️ [UnifiedSubscriptionManager] 사용자 문서가 존재하지 않음 - 기본 상태 사용');
        }
        final defaultState = SubscriptionState.defaultState();
        _updateCurrentState(defaultState);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedSubscriptionManager] Firestore 스냅샷 처리 중 오류: $e');
      }
    }
  }

  /// 🤔 UNVERIFIED 상태 처리 개선
  void _handleUnverifiedState(SubscriptionState newState) {
    if (kDebugMode) {
      debugPrint('🤔 [UnifiedSubscriptionManager] 구독 상태 미확인(UNVERIFIED). 재시도 횟수: $_unverifiedRetryCount');
    }

    // 최대 재시도 횟수 초과 시 기본 상태로 처리
    if (_unverifiedRetryCount >= maxUnverifiedRetries) {
      if (kDebugMode) {
        debugPrint('⚠️ [UnifiedSubscriptionManager] UNVERIFIED 상태 최대 재시도 횟수 초과. 기본 상태로 처리.');
      }
      final defaultState = SubscriptionState.defaultState();
      _updateCurrentState(defaultState);
      return;
    }

    // 첫 번째 시도에서만 구매 복원 실행
    if (_unverifiedRetryCount == 0) {
      InAppPurchaseService().restorePurchases();
    }

    // 배너 없는 상태로 임시 업데이트
    final stateWithoutBanners = newState.copyWith(activeBanners: []);
    _updateCurrentState(stateWithoutBanners);

    // 재시도 타이머 설정
    _unverifiedRetryTimer?.cancel();
    _unverifiedRetryTimer = Timer(_unverifiedRetryDelay, () {
      _unverifiedRetryCount++;
      if (kDebugMode) {
        debugPrint('🔄 [UnifiedSubscriptionManager] UNVERIFIED 상태 재확인 시도: $_unverifiedRetryCount');
      }
      // 캐시 무효화를 통한 강제 새로고침
      invalidateCache();
    });
  }

  /// 🔄 UNVERIFIED 재시도 초기화
  void _resetUnverifiedRetry() {
    _unverifiedRetryTimer?.cancel();
    _unverifiedRetryTimer = null;
    _unverifiedRetryCount = 0;
  }

  /// ---------------------------------------------------
  /// 🎯 Public API (외부에서 사용)
  /// ---------------------------------------------------

  /// 현재 구독 상태 조회 (개선됨)
  Future<SubscriptionState> getSubscriptionState({bool forceRefresh = false}) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      return SubscriptionState.defaultState();
    }

    // 강제 새로고침이 아니고 현재 상태가 있으며 캐시가 유효한 경우
    if (!forceRefresh && _currentState != null && _isCacheValid()) {
      if (kDebugMode) {
        debugPrint('✅ [UnifiedSubscriptionManager] 메모리 캐시에서 구독 정보 반환');
      }
      return _currentState!;
    }

    // 캐시에서 확인 (forceRefresh가 아닌 경우만)
    if (!forceRefresh) {
      final cachedData = await _cache.get(_cacheKey);
      if (cachedData != null) {
        if (kDebugMode) {
          debugPrint('✅ [UnifiedSubscriptionManager] 로컬 캐시에서 구독 정보 로드');
        }
        final state = SubscriptionState.fromFirestore(cachedData);
        _currentState = state;
        _lastCacheTime = DateTime.now();
        return state;
      }
    }
    
    // 캐시 없거나 만료 시 Firestore에서 로드
    return _fetchFromFirestore(userId);
  }

  /// 🕐 캐시 유효성 확인
  bool _isCacheValid() {
    if (_lastCacheTime == null) return false;
    return DateTime.now().difference(_lastCacheTime!) < _cacheDuration;
  }
  
  /// 🗑️ 캐시 무효화 및 상태 새로고침 (외부 호출용)
  Future<void> invalidateCache() async {
    if (kDebugMode) {
      debugPrint('🔄 [UnifiedSubscriptionManager] 캐시 무효화 및 강제 새로고침');
    }
    _currentState = null;
    _lastCacheTime = null;
    await _cache.clear();
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
      // 🎯 수정: 올바른 경로로 변경 (users/{userId} 문서의 subscriptionData 필드)
      final docRef = _firestore.collection('users').doc(userId);

      final snapshot = await docRef.get();
      
      if (!snapshot.exists) {
        if (kDebugMode) {
          debugPrint('⚠️ [UnifiedSubscriptionManager] 사용자 문서가 존재하지 않음');
        }
        return SubscriptionState.defaultState();
      }

      final userData = snapshot.data() as Map<String, dynamic>?;
      final subscriptionData = userData?['subscriptionData'] as Map<String, dynamic>?;
      
      if (subscriptionData == null) {
        if (kDebugMode) {
          debugPrint('⚠️ [UnifiedSubscriptionManager] subscriptionData 필드가 없음');
        }
        return SubscriptionState.defaultState();
      }

      if (kDebugMode) {
        debugPrint('✅ [UnifiedSubscriptionManager] Firestore 데이터 로드 성공');
        debugPrint('   - entitlement: ${subscriptionData['entitlement']}');
        debugPrint('   - subscriptionStatus: ${subscriptionData['subscriptionStatus']}');
        debugPrint('   - productId: ${subscriptionData['productId']}');
      }

      final state = SubscriptionState.fromFirestore(subscriptionData);
      _updateCurrentState(state);
      
      return state;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedSubscriptionManager] Firestore 로드 실패: $e');
      }
      return SubscriptionState.defaultState();
    }
  }

  void _clearAllUserCache() {
    _firestoreSubscription?.cancel();
    _firestoreSubscription = null;
    _unverifiedRetryTimer?.cancel();
    _unverifiedRetryTimer = null;
    _cache.clear();
    _cachedUserId = null;
    _currentState = null;
    _lastCacheTime = null;
    _unverifiedRetryCount = 0;
    if (kDebugMode) {
      debugPrint('🗑️ [UnifiedSubscriptionManager] 모든 사용자 캐시/리스너 정리 완료');
    }
  }

  // 헬퍼: 현재 Plan 객체 가져오기 (UI에서 사용)
  Future<Plan> getCurrentPlan() async {
    final state = await getSubscriptionState();
    return state.plan;
  }

  /// 🎯 현재 상태 즉시 반환 (스트림 용)
  SubscriptionState? get currentState => _currentState;

  /// 🎯 강제 상태 새로고침 (디버그용)
  Future<void> forceRefresh() async {
    if (kDebugMode) {
      debugPrint('🔄 [UnifiedSubscriptionManager] 강제 새로고침 실행');
    }
    await invalidateCache();
  }
} 