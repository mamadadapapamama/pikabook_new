import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../common/banner_manager.dart';
import '../../models/subscription_state.dart';
import 'dart:async';

/// 🎯 통합 구독 관리자 (중복 호출 제거 + 캐시 + 스트림)
/// 
/// **새로운 최적화:**
/// - 중복 Firebase Functions 호출 완전 제거
/// - 스마트 캐시 (10분 TTL + 사용자별 관리)
/// - 실시간 스트림 업데이트
/// - 단일 서버 호출로 모든 데이터 제공
/// 
/// **핵심 기능:**
/// - 단일 서버 호출로 구독상태 + 배너 동시 제공
/// - 캐시 기반 성능 최적화
/// - 실시간 구독 상태 변경 스트림
class UnifiedSubscriptionManager {
  static final UnifiedSubscriptionManager _instance = UnifiedSubscriptionManager._internal();
  factory UnifiedSubscriptionManager() => _instance;
  UnifiedSubscriptionManager._internal() {
    // 사용자 인증 상태 변경 감지
    FirebaseAuth.instance.authStateChanges().listen(_onAuthStateChanged);
  }

  // 🎯 통합 캐시 (10분 TTL)
  Map<String, dynamic>? _cachedServerResponse;
  DateTime? _cacheTimestamp;
  String? _cachedUserId;
  static const Duration _cacheTTL = Duration(minutes: 10);
  
  // 🎯 중복 요청 방지
  Future<Map<String, dynamic>>? _ongoingRequest;
  
  // 🎯 BannerManager 인스턴스
  final BannerManager _bannerManager = BannerManager();
  
  // 🎯 실시간 스트림
  final StreamController<SubscriptionState> _subscriptionStateController = 
      StreamController<SubscriptionState>.broadcast();
  
  // 🔥 Firestore 실시간 리스너
  StreamSubscription<DocumentSnapshot>? _firestoreSubscription;

  Stream<SubscriptionState> get subscriptionStateStream => _subscriptionStateController.stream;

  /// 認証状態の変更を処理する
  void _onAuthStateChanged(User? user) {
    if (user != null) {
      if (_cachedUserId != user.uid) {
        if (kDebugMode) {
          debugPrint('🔄 [UnifiedSubscriptionManager] 사용자 변경 감지 (인증 상태): ${user.uid}');
        }
        clearUserCache(); // 이전 사용자 캐시 정리
        _setupFirestoreListener(user.uid); // 새 사용자를 위한 리스너 설정
      }
    } else {
      if (kDebugMode) {
        debugPrint('🔒 [UnifiedSubscriptionManager] 사용자 로그아웃 감지');
      }
      clearUserCache(); // 로그아웃 시 캐시 및 리스너 정리
    }
  }
  
  /// 🔥 Firestore 실시간 리스너 설정
  void _setupFirestoreListener(String userId) {
    // 기존 리스너가 있다면 취소
    _firestoreSubscription?.cancel();
    
    if (kDebugMode) {
      debugPrint('🔥 [UnifiedSubscriptionManager] Firestore 리스너 설정 시작: users/$userId/private_data/subscription');
    }

    final docRef = FirebaseFirestore.instance
        .collection('users').doc(userId)
        .collection('private').doc('subscription');

    _firestoreSubscription = docRef.snapshots().listen((snapshot) {
      if (kDebugMode) {
        debugPrint('🔥 [UnifiedSubscriptionManager] Firestore 데이터 변경 감지!');
      }
      // 데이터 변경 시 강제로 상태 새로고침
      getSubscriptionState(forceRefresh: true);
    }, onError: (error) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedSubscriptionManager] Firestore 리스너 오류: $error');
      }
    });
  }

  /// 🎯 통합 서버 응답 조회 (모든 메서드의 기반)
  Future<Map<String, dynamic>> _getUnifiedServerResponse({bool forceRefresh = false}) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return _getDefaultServerResponse();
    }
    
    final currentUserId = currentUser.uid;
    
    // 🎯 캐시 확인
    if (!forceRefresh && _isValidCache(currentUserId)) {
      if (kDebugMode) {
        debugPrint('⚡ [UnifiedSubscriptionManager] 캐시 사용 - 성능 최적화');
      }
      return _cachedServerResponse!;
    }
    
    // 🎯 사용자 변경 감지
    if (_cachedUserId != currentUserId) {
      if (kDebugMode) {
        debugPrint('🔄 [UnifiedSubscriptionManager] 사용자 변경 감지');
      }
      _clearCache();
      _cachedUserId = currentUserId;
      _setupFirestoreListener(currentUserId); // 리스너 재설정
    }
    
    // 🎯 중복 요청 방지
    if (_ongoingRequest != null) {
      if (kDebugMode) {
        debugPrint('🔄 [UnifiedSubscriptionManager] 진행 중인 요청 대기');
      }
      return await _ongoingRequest!;
    }
    
    if (kDebugMode) {
      debugPrint('🔍 [UnifiedSubscriptionManager] 서버 조회 시작');
    }
    
    _ongoingRequest = _fetchFromServer();
    
    try {
      final result = await _ongoingRequest!;
      
      // 🎯 캐시 저장
      _cachedServerResponse = result;
      _cacheTimestamp = DateTime.now();
      _cachedUserId = currentUserId;
      
      if (kDebugMode) {
        debugPrint('✅ [UnifiedSubscriptionManager] 서버 응답 캐시 저장');
      }
      
      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedSubscriptionManager] 서버 조회 실패: $e');
      }
      return _getDefaultServerResponse();
    } finally {
      _ongoingRequest = null;
    }
  }

  /// 🎯 실제 서버 호출
  Future<Map<String, dynamic>> _fetchFromServer() async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
      final callable = functions.httpsCallable('subCheckSubscriptionStatus');
      
      final result = await callable.call({});
      
      final responseData = _safeMapConversion(result.data);
      if (responseData == null) {
        return _getDefaultServerResponse();
      }
      
      return responseData;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedSubscriptionManager] Firebase Functions 호출 실패: $e');
      }
      return _getDefaultServerResponse();
    }
  }

  /// 🎯 캐시 유효성 확인
  bool _isValidCache(String userId) {
    if (_cachedServerResponse == null || 
        _cacheTimestamp == null || 
        _cachedUserId != userId) {
      return false;
    }
    
    final age = DateTime.now().difference(_cacheTimestamp!);
    return age < _cacheTTL;
  }

  /// 🎯 캐시 초기화
  void _clearCache() {
    _cachedServerResponse = null;
    _cacheTimestamp = null;
    _cachedUserId = null;
    _firestoreSubscription?.cancel(); // 리스너도 함께 취소
    _firestoreSubscription = null;
    if (kDebugMode) {
      debugPrint('🗑️ [UnifiedSubscriptionManager] 캐시 및 리스너 초기화');
    }
  }

  /// 🎯 기본 서버 응답
  Map<String, dynamic> _getDefaultServerResponse() {
    return {
      'success': false,
      'subscription': {
        'entitlement': 'free',
        'subscriptionStatus': 'cancelled',
        'hasUsedTrial': false,
      }
    };
  }

  /// 🎯 구독 권한 조회 (통합 응답 기반)
  Future<Map<String, dynamic>> getSubscriptionEntitlements({bool forceRefresh = false}) async {
    final serverResponse = await _getUnifiedServerResponse(forceRefresh: forceRefresh);
    
    final subscription = _safeMapConversion(serverResponse['subscription']);
    if (subscription == null) {
      return _getDefaultEntitlements();
    }
    
    final entitlement = subscription['entitlement'] as String? ?? 'free';
    final subscriptionStatus = subscription['subscriptionStatus'] as String? ?? 'cancelled';
    final hasUsedTrial = subscription['hasUsedTrial'] as bool? ?? false;
    
    return {
      'entitlement': entitlement,
      'subscriptionStatus': subscriptionStatus,
      'hasUsedTrial': hasUsedTrial,
      'isPremium': entitlement == 'premium',
      'isTrial': entitlement == 'trial',
      'isFree': entitlement == 'free',
    };
  }

  /// 🎯 BannerManager용 전체 서버 응답 (통합 응답 기반)
  Future<Map<String, dynamic>> getRawServerResponse({bool forceRefresh = false}) async {
    return await _getUnifiedServerResponse(forceRefresh: forceRefresh);
  }

  /// 🎯 완전한 구독 상태 조회 (배너 포함)
  Future<SubscriptionState> getSubscriptionState({bool forceRefresh = false}) async {
    // 리스너가 설정 안됐으면 설정 (초기 실행 시)
    if (_firestoreSubscription == null && FirebaseAuth.instance.currentUser != null) {
      _setupFirestoreListener(FirebaseAuth.instance.currentUser!.uid);
    }

    final serverResponse = await _getUnifiedServerResponse(forceRefresh: forceRefresh);
    final entitlements = await getSubscriptionEntitlements(forceRefresh: false); // 캐시 재사용
    
    // 🎯 활성 배너 조회
    final activeBanners = await _bannerManager.getActiveBannersFromServerResponse(
      serverResponse
    );
    
    final subscription = _safeMapConversion(serverResponse['subscription']);
    final entitlementString = subscription?['entitlement'] as String? ?? 'free';
    final subscriptionStatusString = subscription?['subscriptionStatus'] as String? ?? 'cancelled';
    final hasUsedTrial = subscription?['hasUsedTrial'] as bool? ?? false;

    final state = SubscriptionState(
      entitlement: Entitlement.fromString(entitlementString),
      subscriptionStatus: SubscriptionStatus.fromString(subscriptionStatusString),
      hasUsedTrial: hasUsedTrial,
      hasUsageLimitReached: false, // This needs to be handled separately
      activeBanners: activeBanners,
      statusMessage: "Status message based on entitlement and status", // This needs a proper implementation.
    );
    
    // 🎯 스트림 업데이트 발생
    _emitSubscriptionStateChange(state);
    
    return state;
  }

  /// 🎯 구독 상태 변경 이벤트 발생
  void _emitSubscriptionStateChange(SubscriptionState state) {
    if (!_subscriptionStateController.isClosed) {
      _subscriptionStateController.add(state);
      if (kDebugMode) {
        debugPrint('🔔 [UnifiedSubscriptionManager] 구독 상태 변경 스트림 발생');
        debugPrint('   권한: ${state.entitlement.value}');
        debugPrint('   활성 배너: ${state.activeBanners.length}개');
      }
    }
  }

  /// 🎯 캐시 무효화 (수동 새로고침)
  void invalidateCache() {
    _clearCache();
    // 수동 새로고침 후에는 다시 상태를 조회해야 리스너가 재설정됨
    getSubscriptionState(forceRefresh: true);
  }

  /// 🎯 사용자 변경 시 상태 초기화
  void clearUserCache() {
    _clearCache();
    // 스트림에 기본 상태 전송
    _emitSubscriptionStateChange(
      SubscriptionState(
        entitlement: Entitlement.free,
        subscriptionStatus: SubscriptionStatus.cancelled,
        hasUsedTrial: false,
        hasUsageLimitReached: false,
        activeBanners: [],
        statusMessage: "로그아웃됨",
      )
    );
  }

  /// 🎯 안전한 Map 변환
  Map<String, dynamic>? _safeMapConversion(dynamic data) {
    if (data is Map<String, dynamic>) {
      return data;
    } else if (data is Map) {
      return Map<String, dynamic>.from(data);
    } else {
      return null;
    }
  }

  /// 🎯 기본 권한 응답
  Map<String, dynamic> _getDefaultEntitlements() {
    return {
      'entitlement': 'free',
      'subscriptionStatus': 'cancelled',
      'hasUsedTrial': false,
      'isPremium': false,
      'isTrial': false,
      'isFree': true,
    };
  }

  /// 🎯 리소스 정리
  void dispose() {
    _firestoreSubscription?.cancel();
    _subscriptionStateController.close();
  }
} 