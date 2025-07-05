import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../../models/subscription_state.dart';
import '../../models/plan_status.dart';
import '../common/banner_manager.dart';
import '../common/usage_limit_service.dart';

/// Firebase Functions 기반 App Store 구독 상태 관리 서비스
class AppStoreSubscriptionService {
  static final AppStoreSubscriptionService _instance = AppStoreSubscriptionService._internal();
  factory AppStoreSubscriptionService() => _instance;
  AppStoreSubscriptionService._internal();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  
  // 캐시된 구독 상태 (성능 최적화)
  SubscriptionStatus? _cachedStatus;
  DateTime? _lastCacheTime;
  static const Duration _cacheValidDuration = Duration(hours: 24);
  
  // 캐시된 통합 상태 (성능 최적화)
  SubscriptionState? _cachedUnifiedState;
  DateTime? _unifiedCacheTime;
  static const Duration _unifiedCacheValidDuration = Duration(hours: 24);
  
  // 🎯 통합 서비스들 (중복 호출 방지)
  final BannerManager _bannerManager = BannerManager();
  final UsageLimitService _usageLimitService = UsageLimitService();
  
  // 진행 중인 통합 요청 추적 (중복 방지)
  Future<SubscriptionState>? _ongoingUnifiedRequest;

  /// 서비스 초기화 (Firebase Functions 설정)
  Future<void> initialize() async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 [AppStoreSubscription] Firebase Functions 서비스 초기화');
      }

      // 🚨 릴리즈 준비: 항상 프로덕션 Firebase Functions 사용
      // 개발 환경에서도 프로덕션 서버 사용 (에뮬레이터 연결 문제 방지)
      // if (kDebugMode) {
      //   _functions.useFunctionsEmulator('localhost', 5001);
      // }

      if (kDebugMode) {
        debugPrint('✅ [AppStoreSubscription] 서비스 초기화 완료 (프로덕션 Firebase 사용)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AppStoreSubscription] 서비스 초기화 실패: $e');
      }
    }
  }

  /// 통합 구독 상태 확인 (App Store Connect 우선)
  Future<SubscriptionStatus> checkSubscriptionStatus({String? originalTransactionId, bool forceRefresh = false, bool isAppStart = false}) async {
    try {
      // 🎯 캐시 우선 사용 (앱 시작 시에도 캐시가 유효하면 사용)
      if (!forceRefresh && _isSubscriptionCacheValid()) {
        if (kDebugMode) {
          debugPrint('📦 [AppStoreSubscription] 유효한 캐시 사용 (앱시작: $isAppStart, 강제새로고침: $forceRefresh)');
          debugPrint('   캐시된 상태: ${_cachedStatus!.planStatus} (${_cachedStatus!.planType})');
        }
        return _cachedStatus!;
      }

      if (kDebugMode) {
        debugPrint('🔄 [AppStoreSubscription] App Store Connect 우선 구독 상태 확인 시작 (앱시작: $isAppStart)');
      }

      // 로그인 상태 확인
      final currentUser = _getCurrentUser(context: '구독 상태 확인');
      if (currentUser == null) {
        return SubscriptionStatus.notLoggedIn();
      }

      // 🎯 App Store Connect 우선 호출 (프리미엄/체험 정보)
      final callable = _functions.httpsCallable('sub_checkSubscriptionStatus');
      final result = await callable.call({
        if (originalTransactionId != null) 'originalTransactionId': originalTransactionId,
        'appStoreFirst': true, // App Store Connect 우선 요청
      }).timeout(
        const Duration(seconds: 10), // 10초 타임아웃 추가
        onTimeout: () {
          throw Exception('Firebase Functions 타임아웃 - Firestore 폴백으로 전환');
        },
      );

      // 안전한 타입 캐스팅으로 Firebase Functions 응답 처리
      final data = Map<String, dynamic>.from(result.data as Map);
      
      // 🔍 강제로 RAW JSON 로그 출력 (디버그용)
      debugPrint('🔍 [AppStoreSubscription] App Store Connect 우선 응답:');
      debugPrint('   성공 여부: ${data['success']}');
      debugPrint('   데이터 소스: ${data['dataSource'] ?? 'unknown'}'); // App Store vs Firebase
      debugPrint('🔍 === RAW JSON 응답 (전체) ===');
      debugPrint('$data');
      debugPrint('🔍 === RAW JSON 응답 끝 ===');
      if (data['subscription'] != null) {
        final sub = data['subscription'] as Map;
        debugPrint('   구독 정보: ${sub.toString()}');
        debugPrint('🔍 === RAW planStatus 값 ===');
        debugPrint('   - planStatus: "${sub['planStatus']}" (타입: ${sub['planStatus'].runtimeType})');
        debugPrint('🔍 === RAW planStatus 값 끝 ===');
        debugPrint('   - isActive: ${sub['isActive']}');
        debugPrint('   - expirationDate: ${sub['expirationDate']}');
        debugPrint('   - autoRenewStatus: ${sub['autoRenewStatus']}');
      } else {
        debugPrint('🔍 === subscription 데이터가 null입니다 ===');
      }
      
      if (data['success'] == true) {
        // 🔍 subscription 데이터 존재 여부 확인
        if (data['subscription'] != null) {
          final subscriptionData = Map<String, dynamic>.from(data['subscription'] as Map);
          final subscriptionStatus = _parseSubscriptionStatus(subscriptionData);
          _updateCache(subscriptionStatus);
          
          if (kDebugMode) {
            debugPrint('✅ [AppStoreSubscription] Firebase Functions 성공: ${subscriptionStatus.planType}');
            if (data['dataSource'] != null) {
              debugPrint('   데이터 소스: ${data['dataSource']}');
            }
          }

          return subscriptionStatus;
        } else {
          debugPrint('🚨 [AppStoreSubscription] success=true이지만 subscription 데이터가 null!');
          debugPrint('   전체 응답: $data');
          // Firestore 폴백으로 이동
          return await _handleFirestoreFallback(currentUser.uid, context: 'subscription 데이터 null');
        }
      } else {
        if (kDebugMode) {
          debugPrint('⚠️ [AppStoreSubscription] Firebase Functions에 데이터 없음 → Firestore 확인');
        }
        
        // Firebase Functions에 데이터 없으면 Firestore 확인
        return await _handleFirestoreFallback(currentUser.uid, context: 'Functions 데이터 없음');
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AppStoreSubscription] Firebase Functions 오류 → Firestore 확인');
      }
      
      // 사용자 확인 및 Firestore 폴백
      final currentUser = _getCurrentUser(context: 'Functions 오류 시');
      if (currentUser == null) {
        return SubscriptionStatus.notLoggedIn();
      }
      
      // Firebase Functions 오류 시 Firestore 확인
      return await _handleFirestoreFallback(currentUser.uid, context: 'Functions 오류');
    }
  }

  /// 상세 구독 정보 조회 (sub_getAllSubscriptionStatuses)
  Future<Map<String, dynamic>?> getAllSubscriptionStatuses(String originalTransactionId) async {
    // 로그인 상태 확인
    final currentUser = _getCurrentUser(context: '상세 구독 정보 조회');
    if (currentUser == null) return null;

    // Firebase Functions 호출
    final data = await _callFunction(
      'sub_getAllSubscriptionStatuses',
      {'originalTransactionId': originalTransactionId},
      context: '상세 구독 정보 조회',
    );
    
    if (data?['success'] == true) {
      return Map<String, dynamic>.from(data!['subscription'] as Map);
    }
    
    return null;
  }

  /// 개별 거래 정보 확인 (sub_getTransactionInfo)
  Future<Map<String, dynamic>?> getTransactionInfo(String transactionId) async {
    // 로그인 상태 확인
    final currentUser = _getCurrentUser(context: '거래 정보 조회');
    if (currentUser == null) return null;

    // Firebase Functions 호출
    final data = await _callFunction(
      'sub_getTransactionInfo',
      {'transactionId': transactionId},
      context: '거래 정보 조회',
    );
    
    if (data?['success'] == true) {
      return Map<String, dynamic>.from(data!['transaction'] as Map);
    }
    
    return null;
  }

  /// 현재 구독 상태 조회 (기존 호환성 유지)
  Future<SubscriptionStatus> getCurrentSubscriptionStatus({bool forceRefresh = false, bool isAppStart = false}) async {
    return await checkSubscriptionStatus(forceRefresh: forceRefresh, isAppStart: isAppStart);
  }

  /// 구매 완료 알림 (sub_notifyPurchaseComplete)
  Future<bool> notifyPurchaseComplete({
    required String transactionId,
    required String originalTransactionId,
    required String productId,
    String? purchaseDate,
    String? expirationDate,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🚀 === Firebase Functions 구매 완료 알림 시작 ===');
        debugPrint('📱 상품 ID: $productId');
        debugPrint('📱 transactionId: $transactionId');
        debugPrint('📱 originalTransactionId: $originalTransactionId');
        debugPrint('📱 purchaseDate: $purchaseDate');
        debugPrint('📱 expirationDate: $expirationDate');
      }

      // 로그인 상태 확인
      final currentUser = _getCurrentUser(context: '구매 완료 알림');
      if (currentUser == null) return false;

      if (kDebugMode) {
        debugPrint('✅ [AppStoreSubscription] 사용자 인증 확인: ${currentUser.email}');
      }

      // Firebase Functions 호출
      final requestData = {
        'transactionId': transactionId,
        'originalTransactionId': originalTransactionId,
        'productId': productId,
        if (purchaseDate != null) 'purchaseDate': purchaseDate,
        if (expirationDate != null) 'expirationDate': expirationDate,
      };
      
      if (kDebugMode) {
        debugPrint('🔄 [AppStoreSubscription] Firebase Functions 호출 데이터: $requestData');
      }
      
      final data = await _callFunction(
        'sub_notifyPurchaseComplete',
        requestData,
        context: '구매 완료 알림',
      );
      
      if (data?['success'] == true) {
        if (kDebugMode) {
          debugPrint('✅ [AppStoreSubscription] 구매 완료 알림 성공!');
          debugPrint('   응답 메시지: ${data!['message']}');
          debugPrint('   거래 ID: ${data['transactionId']}');
        }
        
        // 캐시 무효화
        invalidateCache();
        return true;
      } else {
        if (kDebugMode) {
          debugPrint('❌ [AppStoreSubscription] 구매 완료 알림 실패');
          debugPrint('   실패 이유: ${data?['error'] ?? '알 수 없음'}');
        }
        return false;
      }

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AppStoreSubscription] 구매 완료 알림 중 오류: $e');
        debugPrint('   오류 타입: ${e.runtimeType}');
        debugPrint('   오류 스택: ${e.toString()}');
      }
      return false;
    }
  }

  /// 무료 체험 사용 여부 확인
  Future<bool> hasUsedFreeTrial() async {
    try {
      final currentUser = _getCurrentUser(context: '무료 체험 사용 여부 확인');
      if (currentUser == null) return false;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) return false;

      final data = userDoc.data() as Map<String, dynamic>;
      return data['hasUsedFreeTrial'] as bool? ?? false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AppStoreSubscription] 무료 체험 사용 여부 확인 실패: $e');
      }
      return false;
    }
  }

  /// 서비스 정리
  void dispose() {
    invalidateCache();
    _ongoingUnifiedRequest = null;
    if (kDebugMode) {
      debugPrint('🗑️ [AppStoreSubscription] 서비스 정리 완료');
    }
  }

  /// 테스트 환경 지원: Firestore에서 직접 구독 정보 조회
  Future<SubscriptionStatus?> _getSubscriptionFromFirestore(String userId) async {
    try {
      if (kDebugMode) {
        debugPrint('🔍 [AppStoreSubscription] Firestore 직접 조회 시작: $userId');
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (!userDoc.exists) {
        if (kDebugMode) {
          debugPrint('❌ [AppStoreSubscription] 사용자 문서 없음');
        }
        return null;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      
      // 🎯 구독 정보 추출 (새로운 subscription 필드 구조)
      final subscriptionData = userData['subscription'] as Map<String, dynamic>?;
      if (subscriptionData == null) {
        if (kDebugMode) {
          debugPrint('❌ [AppStoreSubscription] Firestore에 구독 정보 없음 - 구조 확인 필요');
        }
        return null;
      }

      // 🎯 새로운 구독 상태 파싱 (plan, status, isFreeTrial 기반)
      final plan = subscriptionData['plan'] as String? ?? 'free';
      final subscriptionStatus = subscriptionData['status'] as String? ?? 'active';
      final isFreeTrial = subscriptionData['isFreeTrial'] as bool? ?? false;
      final isActive = subscriptionData['isActive'] as bool? ?? true;
      final autoRenewStatus = subscriptionData['autoRenewStatus'] as bool? ?? false;
      
      // planType 결정 (plan + isFreeTrial 조합)
      String planType = plan;
      if (isFreeTrial && plan == 'premium') {
        planType = 'trial';
      }
      
      DateTime? expirationDate;
      final expirationTimestamp = subscriptionData['expirationDate'];
      if (expirationTimestamp != null) {
        try {
          if (kDebugMode) {
            debugPrint('🔍 [AppStoreSubscription] Firestore 만료일 파싱 시도: $expirationTimestamp (타입: ${expirationTimestamp.runtimeType})');
          }
          
          if (expirationTimestamp is Timestamp) {
            expirationDate = expirationTimestamp.toDate();
          } else if (expirationTimestamp is String) {
            // 문자열 형태의 날짜 파싱 (다양한 형식 지원)
            if (expirationTimestamp.contains('T')) {
              // ISO 8601 형식
              expirationDate = DateTime.parse(expirationTimestamp);
            } else if (RegExp(r'^\d{13}$').hasMatch(expirationTimestamp)) {
              // 13자리 밀리초 타임스탬프
              expirationDate = DateTime.fromMillisecondsSinceEpoch(int.parse(expirationTimestamp));
            } else if (RegExp(r'^\d{10}$').hasMatch(expirationTimestamp)) {
              // 10자리 초 타임스탬프
              expirationDate = DateTime.fromMillisecondsSinceEpoch(int.parse(expirationTimestamp) * 1000);
            } else {
              // 기본 DateTime.parse 시도
              expirationDate = DateTime.parse(expirationTimestamp);
            }
          } else if (expirationTimestamp is int) {
            // 정수 타임스탬프
            if (expirationTimestamp > 9999999999) {
              // 밀리초 타임스탬프 (13자리)
              expirationDate = DateTime.fromMillisecondsSinceEpoch(expirationTimestamp);
            } else {
              // 초 타임스탬프 (10자리)
              expirationDate = DateTime.fromMillisecondsSinceEpoch(expirationTimestamp * 1000);
            }
          }
          
          if (kDebugMode) {
            debugPrint('✅ [AppStoreSubscription] Firestore 만료일 파싱 성공: $expirationDate');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ [AppStoreSubscription] Firestore 만료일 파싱 실패: $e');
            debugPrint('   원본 값: $expirationTimestamp');
            debugPrint('   값 타입: ${expirationTimestamp.runtimeType}');
          }
          expirationDate = null;
        }
      }

      final result = SubscriptionStatus(
        planStatus: PlanStatus.fromString(plan),
        planType: planType,
        isActive: isActive,
        expirationDate: expirationDate,
        autoRenewStatus: autoRenewStatus,
        subscriptionType: planType,
      );

      if (kDebugMode) {
        debugPrint('✅ [AppStoreSubscription] Firestore 구독 정보 파싱 완료:');
        debugPrint('   - 플랜: $planType');
        debugPrint('   - 활성: $isActive');
        debugPrint('   - 만료일: $expirationDate');
        debugPrint('   - 자동갱신: $autoRenewStatus');
      }

      return result;

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AppStoreSubscription] Firestore 조회 실패: $e');
      }
      return null;
    }
  }

  /// Firebase Functions 응답 파싱 (PlanStatus enum 적용)
  SubscriptionStatus _parseSubscriptionStatus(Map<String, dynamic> subscriptionData) {
    // Firebase Functions에서 planStatus 문자열로 받음
    final planStatusString = subscriptionData['planStatus'] as String? ?? 'free';
    
    // 🔍 강제로 planStatus 파싱 로그 출력 (디버그용)
    debugPrint('🔍 === planStatus 파싱 시작 ===');
    debugPrint('   받은 planStatus 문자열: "$planStatusString"');
    debugPrint('   PlanStatus enum 값들: ${PlanStatus.values.map((e) => e.value).toList()}');
    
    final planStatus = PlanStatus.fromString(planStatusString);
    
    debugPrint('   파싱된 PlanStatus: $planStatus (${planStatus.value})');
    debugPrint('   isTrial: ${planStatus.isTrial}');
    debugPrint('   isPremium: ${planStatus.isPremium}');
    debugPrint('   isActive: ${planStatus.isActive}');
    debugPrint('🔍 === planStatus 파싱 끝 ===');
    
    final autoRenewStatus = subscriptionData['autoRenewStatus'] as bool? ?? false;
    final subscriptionType = subscriptionData['subscriptionType'] as String? ?? '';
    final expirationDateString = subscriptionData['expirationDate'] as String?;
    
    DateTime? expirationDate;
    if (expirationDateString != null) {
      try {
        if (kDebugMode) {
          debugPrint('🔍 [AppStoreSubscription] 만료일 파싱 시도: "$expirationDateString" (타입: ${expirationDateString.runtimeType})');
        }
        
        // 다양한 날짜 형식 지원
        if (expirationDateString.contains('T')) {
          // ISO 8601 형식 (예: 2024-01-01T00:00:00Z)
          expirationDate = DateTime.parse(expirationDateString);
        } else if (RegExp(r'^\d{13}$').hasMatch(expirationDateString)) {
          // 13자리 밀리초 타임스탬프
          expirationDate = DateTime.fromMillisecondsSinceEpoch(int.parse(expirationDateString));
        } else if (RegExp(r'^\d{10}$').hasMatch(expirationDateString)) {
          // 10자리 초 타임스탬프
          expirationDate = DateTime.fromMillisecondsSinceEpoch(int.parse(expirationDateString) * 1000);
        } else {
          // 기본 DateTime.parse 시도
          expirationDate = DateTime.parse(expirationDateString);
        }
        
        if (kDebugMode) {
          debugPrint('✅ [AppStoreSubscription] 만료일 파싱 성공: $expirationDate');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ [AppStoreSubscription] 만료일 파싱 실패: $e');
          debugPrint('   원본 문자열: "$expirationDateString"');
          debugPrint('   문자열 길이: ${expirationDateString.length}');
          debugPrint('   문자열 타입: ${expirationDateString.runtimeType}');
        }
        // 파싱 실패 시 null로 설정
        expirationDate = null;
      }
    }

    return SubscriptionStatus(
      planStatus: planStatus,
      planType: planStatus.value,
      isActive: planStatus.isActive,
      expirationDate: expirationDate,
      autoRenewStatus: autoRenewStatus,
      subscriptionType: subscriptionType,
    );
  }

  /// 캐시 유효성 확인
  bool _isSubscriptionCacheValid() {
    if (_cachedStatus == null || _lastCacheTime == null) return false;
    final timeDiff = DateTime.now().difference(_lastCacheTime!);
    return timeDiff < _cacheValidDuration;
  }

  /// 현재 사용자 가져오기
  User? _getCurrentUser({String? context}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null && kDebugMode) {
      debugPrint('❌ [AppStoreSubscription] 사용자 로그인 필요${context != null ? ' ($context)' : ''}');
    }
    return user;
  }

  /// 캐시 업데이트
  void _updateCache(SubscriptionStatus status) {
    _cachedStatus = status;
    _lastCacheTime = DateTime.now();
  }

  /// 캐시 무효화
  void invalidateCache() {
    _cachedStatus = null;
    _lastCacheTime = null;
    _cachedUnifiedState = null;
    _unifiedCacheTime = null;
    _ongoingUnifiedRequest = null;
    
    if (kDebugMode) {
      debugPrint('🗑️ [AppStoreSubscription] 캐시 무효화');
    }
  }

  /// 통합 구독 상태 조회 (모든 정보 한 번에)
  /// HomeScreen, Settings, BannerManager 등에서 동시에 호출해도
  /// 단일 네트워크 요청만 실행됩니다.
  Future<SubscriptionState> getUnifiedSubscriptionState({bool forceRefresh = false}) async {
    // 🎯 캐시된 통합 상태가 있고 강제 새로고침이 아니면 캐시 사용
    if (!forceRefresh && _cachedUnifiedState != null && _isUnifiedCacheValid()) {
      if (kDebugMode) {
        debugPrint('📦 [AppStoreSubscription] 캐시된 통합 상태 사용');
      }
      return _cachedUnifiedState!;
    }
    
    // 이미 진행 중인 요청이 있으면 기다림 (중복 방지)
    if (_ongoingUnifiedRequest != null) {
      if (kDebugMode) {
        debugPrint('⏳ [AppStoreSubscription] 진행 중인 통합 요청 대기');
      }
      return await _ongoingUnifiedRequest!;
    }

    // 새로운 요청 시작
    _ongoingUnifiedRequest = _fetchUnifiedState(forceRefresh);
    
    try {
      final result = await _ongoingUnifiedRequest!;
      
      // 🎯 통합 상태 캐시 저장
      _cachedUnifiedState = result;
      _unifiedCacheTime = DateTime.now();
      
      return result;
    } finally {
      // 요청 완료 후 초기화
      _ongoingUnifiedRequest = null;
    }
  }

  /// 실제 통합 상태 조회 로직
  Future<SubscriptionState> _fetchUnifiedState(bool forceRefresh) async {
    if (kDebugMode) {
      debugPrint('🎯 [AppStoreSubscription] 통합 구독 상태 조회 시작 (forceRefresh: $forceRefresh)');
    }

    try {
      // 1. App Store 구독 상태 조회 (App Store Connect 우선)
      final appStoreStatus = await getCurrentSubscriptionStatus(forceRefresh: forceRefresh, isAppStart: true);
      
      if (kDebugMode) {
        debugPrint('📱 [AppStoreSubscription] App Store 상태: ${appStoreStatus.displayName}');
      }

      // 2. 사용량 한도 확인 (모든 플랜에서 확인)
      bool hasUsageLimitReached = false;
      try {
        final usageLimitStatus = await _usageLimitService.checkInitialLimitStatus(planType: appStoreStatus.planType);
        final ocrLimitReached = usageLimitStatus['ocrLimitReached'] ?? false;
        final ttsLimitReached = usageLimitStatus['ttsLimitReached'] ?? false;
        hasUsageLimitReached = ocrLimitReached || ttsLimitReached;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ [AppStoreSubscription] 사용량 한도 확인 실패: $e');
        }
      }

      // 3. 활성 배너 목록 조회 (이미 확인된 플랜 정보 전달)
      List<BannerType> activeBanners = [];
      try {
        activeBanners = await _bannerManager.getActiveBanners(
          planStatus: appStoreStatus.planStatus,
          hasEverUsedTrial: false, // TODO: App Store에서 이력 정보 가져오기
          hasEverUsedPremium: appStoreStatus.isPremium,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ [AppStoreSubscription] 배너 조회 실패: $e');
        }
      }

      // 4. 통합 상태 생성
      final subscriptionState = SubscriptionState(
        planStatus: appStoreStatus.planStatus,
        isTrial: appStoreStatus.isTrial,
        isTrialExpiringSoon: false, // App Store에서 자동 관리
        isPremium: appStoreStatus.isPremium,
        isExpired: appStoreStatus.isFree,
        hasUsageLimitReached: hasUsageLimitReached,
        daysRemaining: appStoreStatus.daysUntilExpiration,
        activeBanners: activeBanners,
        statusMessage: appStoreStatus.displayName,
      );

      if (kDebugMode) {
        debugPrint('✅ [AppStoreSubscription] 통합 상태 생성 완료');
        debugPrint('   플랜: ${subscriptionState.statusMessage}');
        debugPrint('   사용량 한도: ${subscriptionState.hasUsageLimitReached}');
        debugPrint('   활성 배너: ${activeBanners.map((e) => e.name).toList()}');
      }

      return subscriptionState;

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AppStoreSubscription] 통합 상태 조회 실패: $e');
      }
      
      // 에러 시 기본 상태 반환
      return SubscriptionState.defaultState();
    }
  }

  /// 캐시 유효성 확인
  bool _isUnifiedCacheValid() {
    if (_cachedUnifiedState == null || _unifiedCacheTime == null) return false;
    final timeDiff = DateTime.now().difference(_unifiedCacheTime!);
    return timeDiff < _unifiedCacheValidDuration;
  }

  /// Firebase Functions 호출 헬퍼
  Future<Map<String, dynamic>?> _callFunction(String functionName, Map<String, dynamic> data, {String? context}) async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 [AppStoreSubscription] $functionName 호출${context != null ? ' ($context)' : ''}');
      }

      final callable = _functions.httpsCallable(functionName);
      final result = await callable.call(data);
      final responseData = Map<String, dynamic>.from(result.data as Map);
      
      if (kDebugMode) {
        debugPrint('📥 [AppStoreSubscription] $functionName 응답: ${responseData['success'] == true ? '성공' : '실패'}');
      }
      
      return responseData;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AppStoreSubscription] $functionName 호출 중 오류: $e');
      }
      return null;
    }
  }

  /// Firestore 폴백 처리 헬퍼 (중복 제거)
  Future<SubscriptionStatus> _handleFirestoreFallback(String userId, {String? context}) async {
    final firestoreStatus = await _getSubscriptionFromFirestore(userId);
    if (firestoreStatus != null) {
      _updateCache(firestoreStatus);
      if (kDebugMode) {
        debugPrint('✅ [AppStoreSubscription] Firestore에서 플랜 조회 성공: ${firestoreStatus.planType}${context != null ? ' ($context)' : ''}');
      }
      return firestoreStatus;
    }
    
    // Firestore에도 없으면 무료 플랜
    if (kDebugMode) {
      debugPrint('🆓 [AppStoreSubscription] 구독 정보 없음 → 무료 플랜${context != null ? ' ($context)' : ''}');
    }
    final freeStatus = SubscriptionStatus.free();
    _updateCache(freeStatus);
    return freeStatus;
  }
}

/// 구독 상태 모델
class SubscriptionStatus {
  final PlanStatus planStatus;
  final String planType;
  final bool isActive;
  final DateTime? expirationDate;
  final bool autoRenewStatus;
  final String subscriptionType;

  SubscriptionStatus({
    required this.planStatus,
    required this.planType,
    required this.isActive,
    this.expirationDate,
    this.autoRenewStatus = false,
    this.subscriptionType = '',
  });

  /// 무료 플랜 상태
  factory SubscriptionStatus.free() {
    return SubscriptionStatus(
      planStatus: PlanStatus.free,
      planType: 'free',
      isActive: false,
      subscriptionType: '',
    );
  }

  /// 로그인되지 않은 상태
  factory SubscriptionStatus.notLoggedIn() {
    return SubscriptionStatus(
      planStatus: PlanStatus.free,
      planType: 'not_logged_in',
      isActive: false,
      subscriptionType: '',
    );
  }

  /// 프리미엄 기능 사용 가능 여부
  bool get canUsePremiumFeatures => isActive && planType != 'free';

  /// 무료 플랜 여부
  bool get isFree => planType == 'free' || !isActive;

  /// 프리미엄 플랜 여부
  bool get isPremium => isActive && planType == 'premium' && !isTrial;

  /// 무료체험 여부
  bool get isTrial => isActive && planType == 'trial';

  /// 구독 타입 (monthly/yearly)
  // subscriptionType 필드로 대체

  /// 표시용 이름
  String get displayName {
    switch (planStatus) {
      case PlanStatus.trialActive:
        // 체험 활성: '프리미엄 체험 (#일 남음)'
        final days = daysUntilExpiration;
        if (days > 0) {
          return '프리미엄 체험 ($days일 남음)';
        } else {
          return '프리미엄 체험';
        }
      
      case PlanStatus.trialCancelled:
        // 체험 취소: '프리미엄 체험 (#일 남음)'
        final days = daysUntilExpiration;
        if (days > 0) {
          return '프리미엄 체험 ($days일 남음)';
        } else {
          return '프리미엄 체험';
        }
      
      case PlanStatus.trialCompleted:
        // 체험 완료: '프리미엄 (monthly)'
        final subType = subscriptionType.isNotEmpty ? subscriptionType : 'monthly';
        return '프리미엄 ($subType)';
      
      case PlanStatus.premiumActive:
        // 프리미엄 활성: '프리미엄 (monthly/yearly)'
        final subType = subscriptionType.isNotEmpty ? subscriptionType : 'monthly';
        return '프리미엄 ($subType)';
      
      case PlanStatus.premiumGrace:
        // 프리미엄 유예: '프리미엄 (monthly) : 결제 확인 필요'
        final subType = subscriptionType.isNotEmpty ? subscriptionType : 'monthly';
        return '프리미엄 ($subType) : 결제 확인 필요';
      
      case PlanStatus.premiumCancelled:
        // 프리미엄 취소: '프리미엄 (#일 남음)(monthly)'
        final subType = subscriptionType.isNotEmpty ? subscriptionType : 'monthly';
        final days = daysUntilExpiration;
        if (days > 0) {
          return '프리미엄 ($days일 남음)($subType)';
        } else {
          return '프리미엄 ($subType)';
        }
        break;
      
      case PlanStatus.premiumExpired:
        // 프리미엄 만료: '무료'
        return '무료';
      
      case PlanStatus.refunded:
        // 환불: '무료'
        return '무료';
      
      case PlanStatus.free:
      default:
        // 무료: '무료'
        return '무료';
    }
  }

  /// 구독 만료까지 남은 일수
  int get daysUntilExpiration {
    if (expirationDate == null) return 0;
    final difference = expirationDate!.difference(DateTime.now());
    return difference.inDays;
  }

  @override
  String toString() {
    return 'SubscriptionStatus(planStatus: [33m$planStatus[0m, planType: $planType, isActive: $isActive, expirationDate: $expirationDate, autoRenewStatus: $autoRenewStatus, subscriptionType: $subscriptionType)';
  }
} 