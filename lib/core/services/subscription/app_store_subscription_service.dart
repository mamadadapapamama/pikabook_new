import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:async';
import '../../models/subscription_state.dart';
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
  static const Duration _cacheValidDuration = Duration(minutes: 30);
  
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
      // 🎯 앱 시작 시에는 캐시 무시하고 App Store Connect부터 확인
      if (!isAppStart && !forceRefresh && _isCacheValid()) {
        if (kDebugMode) {
          debugPrint('📦 [AppStoreSubscription] 캐시된 구독 상태 사용');
        }
        return _cachedStatus!;
      }

      if (kDebugMode) {
        debugPrint('🔄 [AppStoreSubscription] App Store Connect 우선 구독 상태 확인 시작 (앱시작: $isAppStart)');
      }

      // 로그인 상태 확인
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        return SubscriptionStatus.notLoggedIn();
      }

      // 🎯 App Store Connect 우선 호출 (프리미엄/체험 정보)
      final callable = _functions.httpsCallable('sub_checkSubscriptionStatus');
      final result = await callable.call({
        if (originalTransactionId != null) 'originalTransactionId': originalTransactionId,
        'appStoreFirst': true, // App Store Connect 우선 요청
      });

      // 안전한 타입 캐스팅으로 Firebase Functions 응답 처리
      final data = Map<String, dynamic>.from(result.data as Map);
      
      if (kDebugMode) {
        debugPrint('🔍 [AppStoreSubscription] App Store Connect 우선 응답:');
        debugPrint('   성공 여부: ${data['success']}');
        debugPrint('   데이터 소스: ${data['dataSource'] ?? 'unknown'}'); // App Store vs Firebase
        if (data['subscription'] != null) {
          final sub = data['subscription'] as Map;
          debugPrint('   구독 정보: ${sub.toString()}');
          debugPrint('   - currentPlan: ${sub['currentPlan']}');
          debugPrint('   - isActive: ${sub['isActive']}');
          debugPrint('   - expirationDate: ${sub['expirationDate']}');
          debugPrint('   - autoRenewStatus: ${sub['autoRenewStatus']}');
        }
      }
      
      if (data['success'] == true) {
        final subscriptionData = Map<String, dynamic>.from(data['subscription'] as Map);
        final subscriptionStatus = _parseSubscriptionStatus(subscriptionData);
        _updateCache(subscriptionStatus);
        
        if (kDebugMode) {
          debugPrint('✅ [AppStoreSubscription] 구독 상태 파싱 완료:');
          debugPrint('   - 데이터 소스: ${data['dataSource'] ?? 'unknown'}');
          debugPrint('   - 플랜 타입: ${subscriptionStatus.planType}');
          debugPrint('   - 활성 상태: ${subscriptionStatus.isActive}');
          debugPrint('   - 프리미엄: ${subscriptionStatus.isPremium}');
          debugPrint('   - 체험: ${subscriptionStatus.isTrial}');
          debugPrint('   - 무료: ${subscriptionStatus.isFree}');
          debugPrint('   🗄️ 캐시 저장됨 (30분 유효)');
        }

        return subscriptionStatus;
      } else {
        if (kDebugMode) {
          debugPrint('❌ [AppStoreSubscription] 구독 상태 확인 실패');
        }
        return SubscriptionStatus.free();
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AppStoreSubscription] 구독 상태 확인 중 오류: $e');
      }
      
      // 🚨 에러 발생 시: 캐시가 있으면 캐시 사용, 없으면 무료 플랜
      if (_cachedStatus != null) {
        if (kDebugMode) {
          debugPrint('📦 [AppStoreSubscription] 에러 발생, 캐시된 상태 사용: ${_cachedStatus!.planType}');
        }
        return _cachedStatus!;
      } else {
        if (kDebugMode) {
          debugPrint('🆓 [AppStoreSubscription] 에러 발생, 무료 플랜으로 처리');
        }
        final freeStatus = SubscriptionStatus.free();
        _updateCache(freeStatus);
        return freeStatus;
      }
    }
  }

  /// 상세 구독 정보 조회 (sub_getAllSubscriptionStatuses)
  Future<Map<String, dynamic>?> getAllSubscriptionStatuses(String originalTransactionId) async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 [AppStoreSubscription] 상세 구독 정보 조회 시작');
      }

      // 로그인 상태 확인
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        if (kDebugMode) {
          debugPrint('❌ [AppStoreSubscription] 로그인이 필요합니다');
        }
        return null;
      }

      // Firebase Functions 호출
      final callable = _functions.httpsCallable('sub_getAllSubscriptionStatuses');
      final result = await callable.call({
        'originalTransactionId': originalTransactionId,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      
      if (data['success'] == true) {
        if (kDebugMode) {
          debugPrint('✅ [AppStoreSubscription] 상세 구독 정보 조회 완료');
        }
        return Map<String, dynamic>.from(data['subscription'] as Map);
      } else {
        if (kDebugMode) {
          debugPrint('❌ [AppStoreSubscription] 상세 구독 정보 조회 실패');
        }
        return null;
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AppStoreSubscription] 상세 구독 정보 조회 중 오류: $e');
      }
      return null;
    }
  }

  /// 개별 거래 정보 확인 (sub_getTransactionInfo)
  Future<Map<String, dynamic>?> getTransactionInfo(String transactionId) async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 [AppStoreSubscription] 거래 정보 조회 시작: $transactionId');
      }

      // 로그인 상태 확인
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        if (kDebugMode) {
          debugPrint('❌ [AppStoreSubscription] 로그인이 필요합니다');
        }
        return null;
      }

      // Firebase Functions 호출
      final callable = _functions.httpsCallable('sub_getTransactionInfo');
      final result = await callable.call({
        'transactionId': transactionId,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      
      if (data['success'] == true) {
        if (kDebugMode) {
          debugPrint('✅ [AppStoreSubscription] 거래 정보 조회 완료');
        }
        return Map<String, dynamic>.from(data['transaction'] as Map);
      } else {
        if (kDebugMode) {
          debugPrint('❌ [AppStoreSubscription] 거래 정보 조회 실패');
        }
        return null;
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AppStoreSubscription] 거래 정보 조회 중 오류: $e');
      }
      return null;
    }
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
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        if (kDebugMode) {
          debugPrint('❌ [AppStoreSubscription] 로그인이 필요합니다');
        }
        return false;
      }

      if (kDebugMode) {
        debugPrint('✅ [AppStoreSubscription] 사용자 인증 확인: ${currentUser.email}');
      }

      // Firebase Functions 호출
      final callable = _functions.httpsCallable('sub_notifyPurchaseComplete');
      
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
      
      final result = await callable.call(requestData);

      final data = Map<String, dynamic>.from(result.data as Map);
      
      if (kDebugMode) {
        debugPrint('📥 [AppStoreSubscription] Firebase Functions 응답: $data');
      }
      
      if (data['success'] == true) {
        if (kDebugMode) {
          debugPrint('✅ [AppStoreSubscription] 구매 완료 알림 성공!');
          debugPrint('   응답 메시지: ${data['message']}');
          debugPrint('   거래 ID: ${data['transactionId']}');
        }
        
        // 캐시 무효화
        invalidateCache();
        
        return true;
      } else {
        if (kDebugMode) {
          debugPrint('❌ [AppStoreSubscription] 구매 완료 알림 실패');
          debugPrint('   실패 이유: ${data['error'] ?? '알 수 없음'}');
          debugPrint('   전체 응답: $data');
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

  /// 캐시 유효성 확인
  bool _isCacheValid() {
    if (_cachedStatus == null || _lastCacheTime == null) {
      return false;
    }
    
    final now = DateTime.now();
    final timeDifference = now.difference(_lastCacheTime!);
    
    return timeDifference < _cacheValidDuration;
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
    
    if (kDebugMode) {
      debugPrint('🗑️ [AppStoreSubscription] 캐시 무효화');
    }
  }

  /// 🚨 외부에서 캐시 업데이트 (PlanService에서 성공한 결과 공유용)
  void updateCacheFromExternal(SubscriptionStatus status) {
    _updateCache(status);
    if (kDebugMode) {
      debugPrint('📦 [AppStoreSubscription] 외부에서 캐시 업데이트: ${status.planType}');
    }
  }

  /// 무료체험 사용 이력 확인
  Future<bool> hasUsedFreeTrial() async {
    try {
      // Firebase Functions에서 체험 이력 확인
      final callable = _functions.httpsCallable('sub_hasUsedFreeTrial');
      final result = await callable.call();
      
      final data = Map<String, dynamic>.from(result.data as Map);
      return data['hasUsedTrial'] as bool? ?? false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AppStoreSubscription] 무료체험 이력 확인 중 오류: $e');
      }
      return false;
    }
  }

  /// 🎯 통합 구독 상태 조회 (모든 정보 한 번에)
  /// HomeScreen, Settings, BannerManager 등에서 동시에 호출해도
  /// 단일 네트워크 요청만 실행됩니다.
  Future<SubscriptionState> getUnifiedSubscriptionState({bool forceRefresh = false}) async {
    // 이미 진행 중인 요청이 있으면 기다림 (중복 방지)
    if (!forceRefresh && _ongoingUnifiedRequest != null) {
      if (kDebugMode) {
        debugPrint('⏳ [AppStoreSubscription] 진행 중인 통합 요청 대기');
      }
      return await _ongoingUnifiedRequest!;
    }

    // 새로운 요청 시작
    _ongoingUnifiedRequest = _fetchUnifiedState(forceRefresh);
    
    try {
      final result = await _ongoingUnifiedRequest!;
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
          currentPlan: appStoreStatus.planType,
          isFreeTrial: appStoreStatus.isTrial,
          hasEverUsedTrial: false, // TODO: App Store에서 이력 정보 가져오기
          hasEverUsedPremium: appStoreStatus.isPremium,
          isCancelled: !appStoreStatus.autoRenewStatus,
          autoRenewStatus: appStoreStatus.autoRenewStatus,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ [AppStoreSubscription] 배너 조회 실패: $e');
        }
      }

      // 4. 통합 상태 생성
      final subscriptionState = SubscriptionState(
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

  /// 서비스 정리
  void dispose() {
    invalidateCache();
    _ongoingUnifiedRequest = null;
    if (kDebugMode) {
      debugPrint('🗑️ [AppStoreSubscription] 서비스 정리 완료');
    }
  }

  /// Firebase Functions 응답 파싱
  SubscriptionStatus _parseSubscriptionStatus(Map<String, dynamic> data) {
    try {
      final isActive = data['isActive'] as bool? ?? false;
      final currentPlan = data['currentPlan'] as String? ?? 'free';
      final expirationDate = data['expirationDate'] as String?;
      final autoRenewStatus = data['autoRenewStatus'] as bool? ?? false;
      
      // 🚨 추가: 체험/프리미엄 이력 확인
      final hasEverUsedTrial = data['hasEverUsedTrial'] as bool? ?? false;
      final hasEverUsedPremium = data['hasEverUsedPremium'] as bool? ?? false;

      DateTime? expiration;
      if (expirationDate != null) {
        try {
          expiration = DateTime.fromMillisecondsSinceEpoch(int.parse(expirationDate));
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ [AppStoreSubscription] 만료일 파싱 실패: $e');
          }
        }
      }
      
      // 🚨 수정: 체험 만료 → 프리미엄 전환 케이스 처리
      String finalPlanType = currentPlan;
      if (currentPlan == 'free' && hasEverUsedTrial && !hasEverUsedPremium) {
        // 체험 만료 후 무료 플랜 → 실제로는 프리미엄으로 전환되어야 하는 케이스
        finalPlanType = 'premium';
        if (kDebugMode) {
          debugPrint('🔄 [AppStoreSubscription] 체험 만료 → 프리미엄 전환 감지');
          debugPrint('   원본 플랜: $currentPlan → 수정된 플랜: $finalPlanType');
        }
      }

      return SubscriptionStatus(
        planType: finalPlanType,
        isActive: isActive,
        expirationDate: expiration,
        autoRenewStatus: autoRenewStatus,
      );
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AppStoreSubscription] 구독 상태 파싱 실패: $e');
      }
      return SubscriptionStatus.free();
    }
  }
}

/// 구독 상태 모델
class SubscriptionStatus {
  final String planType;
  final bool isActive;
  final DateTime? expirationDate;
  final bool autoRenewStatus;

  SubscriptionStatus({
    required this.planType,
    required this.isActive,
    this.expirationDate,
    this.autoRenewStatus = false,
  });

  /// 무료 플랜 상태
  factory SubscriptionStatus.free() {
    return SubscriptionStatus(
      planType: 'free',
      isActive: false,
    );
  }

  /// 로그인되지 않은 상태
  factory SubscriptionStatus.notLoggedIn() {
    return SubscriptionStatus(
      planType: 'not_logged_in',
      isActive: false,
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
  String get subscriptionType {
    if (planType == 'premium_monthly') return 'monthly';
    if (planType == 'premium_yearly') return 'yearly';
    if (planType == 'trial') return 'monthly'; // 체험은 monthly 기반
    return '';
  }

  /// 표시용 이름
  String get displayName {
    if (isTrial) return '무료 체험';
    if (isPremium) return '프리미엄';
    return '무료';
  }

  /// 구독 만료까지 남은 일수
  int get daysUntilExpiration {
    if (expirationDate == null) return 0;
    final difference = expirationDate!.difference(DateTime.now());
    return difference.inDays;
  }

  @override
  String toString() {
    return 'SubscriptionStatus(planType: $planType, isActive: $isActive, expirationDate: $expirationDate, autoRenewStatus: $autoRenewStatus)';
  }
} 