import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:async';

/// Firebase Functions 기반 App Store 구독 상태 관리 서비스
class AppStoreSubscriptionService {
  static final AppStoreSubscriptionService _instance = AppStoreSubscriptionService._internal();
  factory AppStoreSubscriptionService() => _instance;
  AppStoreSubscriptionService._internal();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  
  // 캐시된 구독 상태 (성능 최적화)
  SubscriptionStatus? _cachedStatus;
  DateTime? _lastCacheTime;
  static const Duration _cacheValidDuration = Duration(minutes: 5);

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

  /// 통합 구독 상태 확인 (sub_checkSubscriptionStatus)
  Future<SubscriptionStatus> checkSubscriptionStatus({String? originalTransactionId, bool forceRefresh = false}) async {
    try {
      // 캐시 확인 (강제 새로고침이 아닌 경우)
      if (!forceRefresh && _isCacheValid()) {
        if (kDebugMode) {
          debugPrint('📦 [AppStoreSubscription] 캐시된 구독 상태 사용');
        }
        return _cachedStatus!;
      }

      if (kDebugMode) {
        debugPrint('🔄 [AppStoreSubscription] 통합 구독 상태 확인 시작');
      }

      // 로그인 상태 확인
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        return SubscriptionStatus.notLoggedIn();
      }

      // Firebase Functions 호출
      final callable = _functions.httpsCallable('sub_checkSubscriptionStatus');
      final result = await callable.call({
        if (originalTransactionId != null) 'originalTransactionId': originalTransactionId,
      });

      // 안전한 타입 캐스팅으로 Firebase Functions 응답 처리
      final data = Map<String, dynamic>.from(result.data as Map);
      
      if (kDebugMode) {
        debugPrint('🔍 [AppStoreSubscription] Firebase Functions 원본 응답:');
        debugPrint('   성공 여부: ${data['success']}');
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
          debugPrint('   - 플랜 타입: ${subscriptionStatus.planType}');
          debugPrint('   - 활성 상태: ${subscriptionStatus.isActive}');
          debugPrint('   - 프리미엄: ${subscriptionStatus.isPremium}');
          debugPrint('   - 체험: ${subscriptionStatus.isTrial}');
          debugPrint('   - 무료: ${subscriptionStatus.isFree}');
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
  Future<SubscriptionStatus> getCurrentSubscriptionStatus({bool forceRefresh = false}) async {
    return await checkSubscriptionStatus(forceRefresh: forceRefresh);
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

  /// 서비스 정리
  void dispose() {
    invalidateCache();
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

      return SubscriptionStatus(
        planType: currentPlan,
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