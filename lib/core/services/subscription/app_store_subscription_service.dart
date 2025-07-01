import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../payment/in_app_purchase_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// App Store 기반 구독 상태 관리 서비스
class AppStoreSubscriptionService {
  static final AppStoreSubscriptionService _instance = AppStoreSubscriptionService._internal();
  factory AppStoreSubscriptionService() => _instance;
  AppStoreSubscriptionService._internal();

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  
  // 캐시된 구독 상태 (성능 최적화)
  SubscriptionStatus? _cachedStatus;
  DateTime? _lastCacheTime;
  static const Duration _cacheValidDuration = Duration(minutes: 5);

  /// 현재 구독 상태 조회 (App Store 기반)
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
        debugPrint('🔄 [AppStoreSubscription] App Store에서 구독 상태 조회 시작');
      }

      // 로그인 상태 확인
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        return SubscriptionStatus.notLoggedIn();
      }

      // App Store에서 구독 상태 확인
      final activePurchases = await _getActivePurchases();
      
      if (activePurchases.isEmpty) {
        // 활성 구독 없음 → 무료 플랜
        final status = SubscriptionStatus.free();
        _updateCache(status);
        return status;
      }

      // 활성 구독이 있는 경우 분석
      final subscriptionStatus = _analyzeActivePurchases(activePurchases);
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

  /// App Store에서 활성 구매 목록 가져오기
  Future<List<PurchaseDetails>> _getActivePurchases() async {
    try {
      if (kDebugMode) {
        debugPrint('🔍 [AppStoreSubscription] App Store에서 활성 구매 조회 시작');
      }

      // 구매 복원 실행
      await _inAppPurchase.restorePurchases();
      
      if (kDebugMode) {
        debugPrint('✅ [AppStoreSubscription] 구매 복원 완료');
      }

      // 현재 활성 구독을 찾기 위해 구매 스트림 확인
      final activePurchases = <PurchaseDetails>[];
      
      // 구매 스트림을 통해 활성 구독 확인
      // 참고: 실제로는 InAppPurchaseService에서 관리하는 구매 스트림을 활용해야 함
      
      // 임시 구현: InAppPurchaseService에서 현재 활성 구독 정보 가져오기
      final inAppPurchaseService = InAppPurchaseService();
      
      // 현재 활성 구독이 있는지 Firebase에서 확인 (임시적으로)
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        try {
          final firestore = FirebaseFirestore.instance;
          final userDoc = await firestore.collection('users').doc(currentUser.uid).get();
          
          if (userDoc.exists) {
            final data = userDoc.data() as Map<String, dynamic>;
            final subscriptionData = data['subscription'] as Map<String, dynamic>?;
            
            if (subscriptionData != null) {
              final plan = subscriptionData['plan'] as String?;
              final status = subscriptionData['status'] as String?;
              final expiryDate = subscriptionData['expiryDate'] as Timestamp?;
              final isFreeTrial = subscriptionData['isFreeTrial'] as bool? ?? false;
              final subscriptionType = subscriptionData['subscriptionType'] as String?;
              
              // 만료되지 않은 프리미엄 구독이 있는 경우
              if (plan == 'premium' && expiryDate != null) {
                final expiry = expiryDate.toDate();
                final now = DateTime.now();
                
                if (expiry.isAfter(now)) {
                  // 활성 구독 발견 - 가상의 PurchaseDetails 생성
                  String productId;
                  if (isFreeTrial) {
                    productId = subscriptionType == 'yearly' 
                        ? InAppPurchaseService.premiumYearlyWithTrialId
                        : InAppPurchaseService.premiumMonthlyWithTrialId;
                  } else {
                    productId = subscriptionType == 'yearly'
                        ? InAppPurchaseService.premiumYearlyId
                        : InAppPurchaseService.premiumMonthlyId;
                  }
                  
                  // 실제 App Store에서 가져온 것처럼 처리
                  if (kDebugMode) {
                    debugPrint('📦 [AppStoreSubscription] Firebase에서 활성 구독 발견: $productId');
                    debugPrint('   만료일: $expiry');
                    debugPrint('   체험 여부: $isFreeTrial');
                    debugPrint('   구독 타입: $subscriptionType');
                  }
                  
                  // 가상의 PurchaseDetails 생성 (실제로는 App Store에서 제공)
                  // 참고: 실제 구현에서는 App Store에서 받은 PurchaseDetails를 사용해야 함
                  
                  return []; // 임시로 빈 리스트 반환 (실제 구현 필요)
                }
              }
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ [AppStoreSubscription] Firebase 구독 확인 중 오류: $e');
          }
        }
      }
      
      if (kDebugMode) {
        debugPrint('📦 [AppStoreSubscription] 활성 구매 없음');
      }
      
      return activePurchases;
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AppStoreSubscription] 활성 구매 조회 실패: $e');
      }
      return [];
    }
  }

  /// 활성 구매 분석하여 구독 상태 결정
  SubscriptionStatus _analyzeActivePurchases(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased) {
        return _mapProductToSubscriptionStatus(purchase.productID);
      }
    }
    
    return SubscriptionStatus.free();
  }

  /// 상품 ID를 구독 상태로 매핑
  SubscriptionStatus _mapProductToSubscriptionStatus(String productId) {
    switch (productId) {
      case InAppPurchaseService.premiumMonthlyId:
        return SubscriptionStatus.premiumMonthly();
      case InAppPurchaseService.premiumYearlyId:
        return SubscriptionStatus.premiumYearly();
      case InAppPurchaseService.premiumMonthlyWithTrialId:
        return SubscriptionStatus.trialMonthly();
      case InAppPurchaseService.premiumYearlyWithTrialId:
        return SubscriptionStatus.trialYearly();
      default:
        return SubscriptionStatus.free();
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
      debugPrint('🗑️ [AppStoreSubscription] 캐시 무효화 완료');
    }
  }

  /// 무료체험 사용 여부 확인 (로컬 저장소 기반)
  Future<bool> hasUsedFreeTrial() async {
    // SharedPreferences나 Keychain을 사용하여 로컬에 저장
    // App Store 구독과 별개로 무료체험 사용 이력만 추적
    
    // TODO: 실제 구현 필요
    return false;
  }

  /// 무료체험 사용 기록
  Future<void> markTrialAsUsed() async {
    // TODO: 로컬 저장소에 무료체험 사용 기록
  }
}

/// 구독 상태 모델 (단순화)
class SubscriptionStatus {
  final String planType;
  final bool isActive;
  final bool isTrial;
  final String subscriptionType; // monthly/yearly
  
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

  @override
  String toString() {
    return 'SubscriptionStatus(planType: $planType, isActive: $isActive, isTrial: $isTrial, subscriptionType: $subscriptionType)';
  }
} 