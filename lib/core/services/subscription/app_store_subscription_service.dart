import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';

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

  /// 현재 구독 상태 조회 (Firebase Functions 기반)
  Future<SubscriptionStatus> getCurrentSubscriptionStatus({bool forceRefresh = false}) async {
    try {
      // 캐시 확인
      if (!forceRefresh && _isCacheValid()) {
        if (kDebugMode) {
          debugPrint('📦 [AppStoreSubscription] 캐시된 구독 상태 사용');
        }
        return _cachedStatus!;
      }

      if (kDebugMode) {
        debugPrint('🔄 [AppStoreSubscription] Firebase Functions에서 구독 상태 조회 시작');
      }

      // 로그인 상태 확인
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        return SubscriptionStatus.notLoggedIn();
      }

      // Firebase Functions 호출
      final callable = _functions.httpsCallable('getSubscriptionStatus');
      final result = await callable.call({
        'forceRefresh': forceRefresh,
      });

      final data = result.data as Map<String, dynamic>;
      final subscriptionStatus = _parseSubscriptionStatus(data);
      _updateCache(subscriptionStatus);
      
      if (kDebugMode) {
        debugPrint('✅ [AppStoreSubscription] 구독 상태 조회 완료: ${subscriptionStatus.planType}');
      }

      return subscriptionStatus;
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AppStoreSubscription] 구독 상태 조회 실패: $e');
      }
      return SubscriptionStatus.free(); // 오류 시 무료 플랜으로 처리
    }
  }

  /// Receipt 검증 요청 (Firebase Functions로 전송)
  Future<bool> validateReceipt() async {
    try {
      if (kDebugMode) {
        debugPrint('🔍 [AppStoreSubscription] Receipt 검증 시작');
      }

      // iOS에서만 Receipt 가져오기 가능
      if (!Platform.isIOS) {
        if (kDebugMode) {
          debugPrint('⚠️ [AppStoreSubscription] iOS가 아닌 플랫폼에서는 Receipt 검증 불가');
        }
        return false;
      }

      // iOS Receipt 데이터 가져오기
      final receiptData = await _getLocalReceiptData();
      if (receiptData == null) {
        if (kDebugMode) {
          debugPrint('❌ [AppStoreSubscription] Receipt 데이터를 가져올 수 없음');
        }
        return false;
      }

      // Firebase Functions로 Receipt 검증 요청
      final callable = _functions.httpsCallable('validateAppStoreReceipt');
      final result = await callable.call({
        'receiptData': receiptData,
      });

      final data = result.data as Map<String, dynamic>;
      
      if (data['success'] == true) {
        if (kDebugMode) {
          debugPrint('✅ [AppStoreSubscription] Receipt 검증 성공');
        }
        
        // 캐시 무효화 (새로운 구독 상태 반영)
        invalidateCache();
        
        return true;
      } else {
        if (kDebugMode) {
          debugPrint('❌ [AppStoreSubscription] Receipt 검증 실패: ${data['error']}');
        }
        return false;
      }

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AppStoreSubscription] Receipt 검증 중 오류: $e');
      }
      return false;
    }
  }

  /// 구독 구매 완료 알림 (Firebase Functions로 전송)
  Future<bool> notifyPurchaseComplete(String productId, String transactionId) async {
    try {
      if (kDebugMode) {
        debugPrint('📱 [AppStoreSubscription] 구매 완료 알림: $productId');
      }

      final callable = _functions.httpsCallable('notifyPurchaseComplete');
      final result = await callable.call({
        'productId': productId,
        'transactionId': transactionId,
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

  /// iOS Receipt 데이터 가져오기
  Future<String?> _getLocalReceiptData() async {
    try {
      const platform = MethodChannel('app_store_receipt');
      final receiptData = await platform.invokeMethod('getReceiptData');
      
      if (kDebugMode) {
        debugPrint('📱 [AppStoreSubscription] 로컬 Receipt 데이터 획득');
      }
      
      return receiptData as String?;
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AppStoreSubscription] 로컬 Receipt 데이터 가져오기 실패: $e');
      }
      return null;
    }
  }

  /// Firebase Functions 응답을 SubscriptionStatus로 변환
  SubscriptionStatus _parseSubscriptionStatus(Map<String, dynamic> data) {
    final planType = data['planType'] as String? ?? 'free';
    final isActive = data['isActive'] as bool? ?? false;
    final isTrial = data['isTrial'] as bool? ?? false;
    final subscriptionType = data['subscriptionType'] as String? ?? '';

    if (planType == 'free') {
      return SubscriptionStatus.free();
    } else if (planType == 'premium') {
      if (isTrial) {
        return subscriptionType == 'yearly' 
            ? SubscriptionStatus.trialYearly()
            : SubscriptionStatus.trialMonthly();
      } else {
        return subscriptionType == 'yearly'
            ? SubscriptionStatus.premiumYearly()
            : SubscriptionStatus.premiumMonthly();
      }
    }

    return SubscriptionStatus.free();
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
      debugPrint('🗑️ [AppStoreSubscription] 캐시 무효화 완료');
    }
  }

  /// 무료체험 사용 여부 확인 (로컬 저장소 기반)
  Future<bool> hasUsedFreeTrial() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasUsed = prefs.getBool('has_used_free_trial') ?? false;
      
      if (kDebugMode) {
        debugPrint('📱 [AppStoreSubscription] 로컬 무료체험 이력: $hasUsed');
      }
      
      return hasUsed;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AppStoreSubscription] 무료체험 이력 확인 실패: $e');
      }
      return false;
    }
  }

  /// 무료체험 사용 기록
  Future<void> markTrialAsUsed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_used_free_trial', true);
      
      if (kDebugMode) {
        debugPrint('✅ [AppStoreSubscription] 무료체험 사용 기록 저장');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AppStoreSubscription] 무료체험 사용 기록 실패: $e');
      }
    }
  }

  /// 서비스 종료 (리소스 정리)
  void dispose() {
    if (kDebugMode) {
      debugPrint('🗑️ [AppStoreSubscription] 서비스 종료');
    }
  }
}

/// 구독 상태 모델
class SubscriptionStatus {
  final String planType;
  final bool isActive;
  final bool isTrial;
  final String subscriptionType;
  
  const SubscriptionStatus({
    required this.planType,
    required this.isActive,
    required this.isTrial,
    required this.subscriptionType,
  });

  // Factory constructors
  factory SubscriptionStatus.free() => const SubscriptionStatus(
    planType: 'free',
    isActive: false,
    isTrial: false,
    subscriptionType: '',
  );

  factory SubscriptionStatus.notLoggedIn() => const SubscriptionStatus(
    planType: 'not_logged_in',
    isActive: false,
    isTrial: false,
    subscriptionType: '',
  );

  factory SubscriptionStatus.premiumMonthly() => const SubscriptionStatus(
    planType: 'premium',
    isActive: true,
    isTrial: false,
    subscriptionType: 'monthly',
  );

  factory SubscriptionStatus.premiumYearly() => const SubscriptionStatus(
    planType: 'premium',
    isActive: true,
    isTrial: false,
    subscriptionType: 'yearly',
  );

  factory SubscriptionStatus.trialMonthly() => const SubscriptionStatus(
    planType: 'premium',
    isActive: true,
    isTrial: true,
    subscriptionType: 'monthly',
  );

  factory SubscriptionStatus.trialYearly() => const SubscriptionStatus(
    planType: 'premium',
    isActive: true,
    isTrial: true,
    subscriptionType: 'yearly',
  );

  // Getters
  bool get isPremium => planType == 'premium' && isActive;
  bool get isFree => planType == 'free';
  bool get isNotLoggedIn => planType == 'not_logged_in';
  
  String get displayName {
    if (isNotLoggedIn) return '로그인 필요';
    if (isFree) return '무료 플랜';
    if (isTrial) return '프리미엄 체험 ($subscriptionType)';
    return '프리미엄 ($subscriptionType)';
  }

  /// 무료체험 사용 여부 확인 (호환성을 위한 메서드)
  Future<bool> hasUsedFreeTrial() async {
    final service = AppStoreSubscriptionService();
    return await service.hasUsedFreeTrial();
  }

  @override
  String toString() {
    return 'SubscriptionStatus(planType: $planType, isActive: $isActive, isTrial: $isTrial, subscriptionType: $subscriptionType)';
  }
} 