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

      // 개발 환경에서는 로컬 에뮬레이터 사용
      if (kDebugMode) {
        _functions.useFunctionsEmulator('localhost', 5001);
      }

      if (kDebugMode) {
        debugPrint('✅ [AppStoreSubscription] 서비스 초기화 완료');
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

      final data = result.data as Map<String, dynamic>;
      
      if (data['success'] == true) {
        final subscriptionData = data['subscription'] as Map<String, dynamic>;
        final subscriptionStatus = _parseSubscriptionStatus(subscriptionData);
        _updateCache(subscriptionStatus);
        
        if (kDebugMode) {
          debugPrint('✅ [AppStoreSubscription] 구독 상태 확인 완료: ${subscriptionStatus.planType}');
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
      return SubscriptionStatus.free(); // 오류 시 무료 플랜으로 처리
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

      final data = result.data as Map<String, dynamic>;
      
      if (data['success'] == true) {
        if (kDebugMode) {
          debugPrint('✅ [AppStoreSubscription] 상세 구독 정보 조회 완료');
        }
        return data['subscription'] as Map<String, dynamic>;
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

      final data = result.data as Map<String, dynamic>;
      
      if (data['success'] == true) {
        if (kDebugMode) {
          debugPrint('✅ [AppStoreSubscription] 거래 정보 조회 완료');
        }
        return data['transaction'] as Map<String, dynamic>;
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
        debugPrint('📱 [AppStoreSubscription] 구매 완료 알림: $productId');
      }

      // 로그인 상태 확인
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        if (kDebugMode) {
          debugPrint('❌ [AppStoreSubscription] 로그인이 필요합니다');
        }
        return false;
      }

      // Firebase Functions 호출
      final callable = _functions.httpsCallable('sub_notifyPurchaseComplete');
      final result = await callable.call({
        'transactionId': transactionId,
        'originalTransactionId': originalTransactionId,
        'productId': productId,
        if (purchaseDate != null) 'purchaseDate': purchaseDate,
        if (expirationDate != null) 'expirationDate': expirationDate,
      });

      final data = result.data as Map<String, dynamic>;
      
      if (data['success'] == true) {
        if (kDebugMode) {
          debugPrint('✅ [AppStoreSubscription] 구매 완료 알림 성공');
        }
        
        // 캐시 무효화
        invalidateCache();
        
        return true;
      } else {
        if (kDebugMode) {
          debugPrint('❌ [AppStoreSubscription] 구매 완료 알림 실패');
        }
        return false;
      }

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AppStoreSubscription] 구매 완료 알림 중 오류: $e');
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

  /// 구독 만료 여부
  bool get isExpired {
    if (expirationDate == null) return false;
    return DateTime.now().isAfter(expirationDate!);
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