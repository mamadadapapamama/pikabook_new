import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/banner_type.dart';
import '../../models/subscription_state.dart';
import 'dart:async';

import '../cache/event_cache_manager.dart';
import '../common/usage_limit_service.dart';
import '../payment/in_app_purchase_service.dart';

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

  // 🎯 실시간 스트림
  final StreamController<SubscriptionState> _subscriptionStateController = 
      StreamController<SubscriptionState>.broadcast();
  
  // 🔥 Firestore 실시간 리스너
  StreamSubscription<DocumentSnapshot>? _firestoreSubscription;

  Stream<SubscriptionState> get subscriptionStateStream => _subscriptionStateController.stream;
  
  /// 인증 상태 변경 처리 (중앙 오케스트레이터 역할)
  void _onAuthStateChanged(User? user) async {
    if (user != null) {
      if (_cachedUserId != user.uid) {
        if (kDebugMode) {
          debugPrint('🔄 [UnifiedSubscriptionManager] 사용자 변경 감지: ${user.uid}');
        }
        _clearAllUserCache(); // 이전 사용자 캐시 정리
        
        // 🎯 InAppPurchaseService 초기화
        await InAppPurchaseService().initialize();
        
        _setupFirestoreListener(user.uid); // 새 사용자를 위한 리스너 설정
        getSubscriptionState(forceRefresh: true); // 새 사용자 정보 즉시 로드
      }
    } else {
      if (kDebugMode) {
        debugPrint('🔒 [UnifiedSubscriptionManager] 사용자 로그아웃 감지. 모든 사용자 데이터 초기화.');
      }
      _clearAllUserCache(); // 로그아웃 시 모든 캐시 정리
      // 🎯 로그아웃 시 기본 상태를 스트림으로 방출
      _subscriptionStateController.add(SubscriptionState.defaultState());
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
      _clearAllUserCache();
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

  /// 🎯 캐시 초기화 (단순 내부 캐시)
  void invalidateCache() {
    _cachedServerResponse = null;
    _cacheTimestamp = null;
      if (kDebugMode) {
      debugPrint('🗑️ [UnifiedSubscriptionManager] 내부 캐시 무효화');
    }
  }

  /// 🎯 모든 사용자 관련 캐시 초기화 (로그아웃 및 사용자 변경 시)
  void _clearAllUserCache() {
    // 🎯 중복 호출 방지
    if (_cachedServerResponse == null && _cachedUserId == null) {
      if (kDebugMode) {
        debugPrint('⏭️ [UnifiedSubscriptionManager] 이미 캐시가 초기화됨 - 중복 호출 건너뜀');
      }
      return;
    }
    
    _cachedServerResponse = null;
    _cacheTimestamp = null;
    _cachedUserId = null;
    _firestoreSubscription?.cancel();
    _firestoreSubscription = null;
    
    // 🎯 다른 서비스들의 캐시도 여기서 중앙 관리
    UsageLimitService().clearUserCache();
    EventCacheManager().clearAllCache();
    
    if (kDebugMode) {
      debugPrint('🗑️ [UnifiedSubscriptionManager] 모든 사용자 캐시 및 리스너 초기화 완료');
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
    try {
      final serverResponse = await _getUnifiedServerResponse(forceRefresh: forceRefresh);
      final info = SubscriptionInfo.fromJson(serverResponse);
      
        return {
        'entitlement': info.entitlement.value,
        'subscriptionStatus': info.subscriptionStatus.value,
        'hasUsedTrial': info.hasUsedTrial,
        'isPremium': info.isPremium,
        'isTrial': info.isTrial,
        'isFree': info.entitlement.isFree,
        'expirationDate': info.expirationDate,
        'subscriptionType': info.subscriptionType?.value,
      };
    } catch (e) {
      if (kDebugMode) {
        print('❌ [U-Manager] getSubscriptionEntitlements 오류: $e. 기본값 반환.');
      }
      return _getDefaultEntitlements();
    }
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
      
    // 🎯 단순화된 배너 결정 로직
    final activeBanners = await _getActiveBanners(serverResponse);
    
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
  
  /// 🎯 단순화된 배너 결정 로직
  Future<List<BannerType>> _getActiveBanners(Map<String, dynamic> serverResponse) async {
    final activeBanners = <BannerType>[];
    final prefs = await SharedPreferences.getInstance();

    final subscription = _safeMapConversion(serverResponse['subscription']);
    if (subscription == null) return activeBanners;

    final entitlement = subscription['entitlement'] as String? ?? 'free';
    final subscriptionStatus = subscription['subscriptionStatus'] as String? ?? 'cancelled';
    final hasUsedTrial = subscription['hasUsedTrial'] as bool? ?? false;

    BannerType? bannerType;

    // 🎯 구매 직후 배너(trialStarted, premiumStarted)는 스낵바로 대체되었으므로 제거
    if (subscriptionStatus == 'active') {
      if (entitlement == 'premium' && hasUsedTrial) {
        // 무료체험 후 프리미엄으로 전환된 경우
        bannerType = BannerType.switchToPremium;
      }
    } else if (subscriptionStatus == 'cancelling') {
      bannerType = entitlement == 'trial' ? BannerType.trialCancelled : BannerType.premiumCancelled;
    } else if (subscriptionStatus == 'expired') {
      bannerType = (entitlement == 'trial' || hasUsedTrial) ? BannerType.switchToPremium : BannerType.free;
    }

    if (bannerType != null) {
      final key = 'banner_${bannerType.name}_dismissed';
      final hasDismissed = prefs.getBool(key) ?? false;
      if (!hasDismissed) {
        activeBanners.add(bannerType);
      }
    }

    return activeBanners;
  }

  /// 🎯 캐시된 구독 상태 조회 (배너 결정 없이)
  Future<SubscriptionState?> _getCachedSubscriptionState() async {
    if (_cachedServerResponse == null) return null;
    
    try {
      final subscription = _safeMapConversion(_cachedServerResponse!['subscription']);
      final entitlementString = subscription?['entitlement'] as String? ?? 'free';
      final subscriptionStatusString = subscription?['subscriptionStatus'] as String? ?? 'cancelled';
      final hasUsedTrial = subscription?['hasUsedTrial'] as bool? ?? false;
      
      // 🎯 캐시된 배너 정보는 별도로 저장하지 않으므로 빈 배열 반환
      return SubscriptionState(
        entitlement: Entitlement.fromString(entitlementString),
        subscriptionStatus: SubscriptionStatus.fromString(subscriptionStatusString),
        hasUsedTrial: hasUsedTrial,
        hasUsageLimitReached: false,
        activeBanners: [], // 배너는 매번 새로 계산해야 하므로 빈 배열
        statusMessage: "Status message based on entitlement and status",
      );
    } catch (e) {
      return null;
    }
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

  /// 🎯 사용자 변경 시 상태 초기화
  void clearUserCache() {
    _clearAllUserCache();
    // 수동 새로고침 후에는 다시 상태를 조회해야 리스너가 재설정됨
    getSubscriptionState(forceRefresh: true);
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