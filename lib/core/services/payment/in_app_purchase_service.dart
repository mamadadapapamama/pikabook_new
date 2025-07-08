import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../common/support_service.dart';
import '../subscription/unified_subscription_manager.dart';
import '../notification/notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../common/banner_manager.dart';

/// In-App Purchase 관리 서비스
/// 사용자가 "구독" 버튼을 눌렀을 때 App Store 결제 다이얼로그 띄우기
/// apple/결제 시스템 연동 - in_app_purchase 패키지를 통한 네이티브 결제 및 구매 완료 알림 - 서버에 구매 완료 사실 전달

class InAppPurchaseService {
  static final InAppPurchaseService _instance = InAppPurchaseService._internal();
  factory InAppPurchaseService() => _instance;
  InAppPurchaseService._internal();

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  // PlanService 제거됨 - 플랜 변경 알림은 UnifiedSubscriptionManager에서 처리
  final NotificationService _notificationService = NotificationService();
  
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  bool _isAvailable = false;
  bool _isInitialized = false;
  List<ProductDetails> _products = [];
  
  // 🎯 중복 구매 처리 방지
  final Set<String> _processedPurchases = {};
  bool _isPurchaseInProgress = false;
  
  // 구매 성공 콜백
  Function()? _onPurchaseSuccess;
  

  
  // 상품 ID 정의
  static const String premiumMonthlyId = 'premium_monthly';
  static const String premiumYearlyId = 'premium_yearly';
  
  // 무료체험 포함 상품 ID (앱스토어 설정 후 활성화)
  static const String premiumMonthlyWithTrialId = 'premium_monthly_with_trial';
  
  static const Set<String> _productIds = {
    premiumMonthlyId,
    premiumYearlyId,
    premiumMonthlyWithTrialId,
  };

  /// 서비스 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      if (kDebugMode) {
        print('🛒 In-App Purchase 서비스 초기화 시작');
      }

      // In-App Purchase 사용 가능 여부 확인
      _isAvailable = await _inAppPurchase.isAvailable();
      
      if (!_isAvailable) {
        if (kDebugMode) {
          print('❌ In-App Purchase를 사용할 수 없습니다');
        }
        return;
      }

      if (kDebugMode) {
        print('✅ In-App Purchase 사용 가능');
      }

      // 🎯 미완료 구매 정리 (간소화)
      await _clearPendingPurchases();

      // 구매 스트림 구독
      _subscription = _inAppPurchase.purchaseStream.listen(
        _onPurchaseUpdate,
        onDone: () {
          if (kDebugMode) {
            print('🔄 구매 스트림 완료');
          }
        },
        onError: (error) {
          if (kDebugMode) {
            print('❌ 구매 스트림 오류: $error');
          }
        },
      );

      // 상품 정보 로드
      await _loadProducts();

      // 🚨 구매 복원 완전 비활성화 (테스트 환경에서 중복 구매 방지)
      // await _restorePurchases(); // 주석 처리

      _isInitialized = true;
      
      if (kDebugMode) {
        print('✅ In-App Purchase 서비스 초기화 완료 (구매 복원 비활성화)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ In-App Purchase 초기화 오류: $e');
      }
    }
  }

  /// 지연 초기화 확인 (모든 구매 기능 호출 전에 실행)
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      if (kDebugMode) {
        print('🛒 [InAppPurchase] 지연 초기화 시작 (첫 구매 시도)');
      }
      await initialize();
    } else {
      if (kDebugMode) {
        print('✅ [InAppPurchase] 이미 초기화됨, 중복 초기화 방지');
      }
    }
  }

  /// 서비스 종료
  void dispose() {
    if (_isInitialized) {
      _subscription.cancel();
      
      // 🎯 서비스 종료 시 미완료 거래 정리
      _finishPendingTransactions().catchError((error) {
        if (kDebugMode) {
          print('⚠️ 서비스 종료 시 미완료 거래 정리 실패: $error');
        }
      });
      
    _processedPurchases.clear();
      _isPurchaseInProgress = false;
    }
  }
  
  /// 구매 성공 콜백 설정
  void setOnPurchaseSuccess(Function()? callback) {
    _onPurchaseSuccess = callback;
  }



  /// 상품 정보 로드
  Future<void> _loadProducts() async {
    try {
      if (kDebugMode) {
        print('📦 상품 정보 로드 시작');
      }

      final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails(_productIds);
      
      if (response.error != null) {
        if (kDebugMode) {
          print('❌ 상품 정보 로드 오류: ${response.error}');
        }
        return;
      }

      _products = response.productDetails;
      
      if (kDebugMode) {
        print('✅ 상품 정보 로드 완료: ${_products.length}개');
        for (final product in _products) {
          print('   - ${product.id}: ${product.title} (${product.price})');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ 상품 정보 로드 중 오류: $e');
      }
    }
  }

  /// 구매 업데이트 처리
  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    if (kDebugMode) {
      print('🔔 구매 업데이트 수신: ${purchaseDetailsList.length}개');
    }
    
    // 피카북에서는 기간별 구독만 하므로 일반적으로 하나의 구매만 들어옴
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      // 🎯 중복 처리 방지: 이미 처리된 구매는 건너뛰기
      final purchaseKey = '${purchaseDetails.productID}_${purchaseDetails.purchaseID}';
      
      if (_processedPurchases.contains(purchaseKey)) {
      if (kDebugMode) {
          print('⏭️ 이미 처리된 구매 건너뛰기: $purchaseKey');
        }
        continue;
      }
      
      // 처리 목록에 추가
      _processedPurchases.add(purchaseKey);
      
      _handlePurchase(purchaseDetails);
    }
  }

  /// 구매 처리
  Future<void> _handlePurchase(PurchaseDetails purchaseDetails) async {
    try {
      if (kDebugMode) {
        print('🛒 구매 처리: ${purchaseDetails.productID}, 상태: ${purchaseDetails.status}');
      }

      if (purchaseDetails.status == PurchaseStatus.purchased) {
        // 구매 성공 처리
        await _handleSuccessfulPurchase(purchaseDetails);
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        // 구매 실패 처리
        if (kDebugMode) {
          print('❌ 구매 실패: ${purchaseDetails.error}');
        }
        // 🎯 구매 실패 시 즉시 완료 처리하여 pending transaction 방지
        await _completePurchaseIfNeeded(purchaseDetails, isErrorRecovery: true);
        _isPurchaseInProgress = false; // 구매 진행 상태 즉시 해제
      } else if (purchaseDetails.status == PurchaseStatus.canceled) {
        // 구매 취소 처리
        if (kDebugMode) {
          print('🚫 구매 취소됨');
        }
        // 🎯 구매 취소 시 즉시 완료 처리하여 pending transaction 방지
        await _completePurchaseIfNeeded(purchaseDetails, isErrorRecovery: true);
        _isPurchaseInProgress = false; // 구매 진행 상태 즉시 해제
      } else if (purchaseDetails.status == PurchaseStatus.pending) {
        // 구매 대기 중
        if (kDebugMode) {
          print('⏳ 구매 대기 중: ${purchaseDetails.productID}');
        }

        // 🎯 pending 상태도 일정 시간 후 강제 완료 처리 고려
        _scheduleTimeoutCompletion(purchaseDetails);
      } else {
        // 🎯 알 수 없는 상태도 완료 처리
        if (kDebugMode) {
          print('❓ 알 수 없는 구매 상태: ${purchaseDetails.status}');
        }
        await _completePurchaseIfNeeded(purchaseDetails, isErrorRecovery: true);
        _isPurchaseInProgress = false;
      }

      // 🎯 성공한 구매가 아닌 경우 완료 처리 (pending transaction 방지)
      if (purchaseDetails.status != PurchaseStatus.purchased) {
        await _completePurchaseIfNeeded(purchaseDetails);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ 구매 처리 중 오류: $e');
      }
      
      // 🎯 오류 발생 시에도 완료 처리 시도
      await _completePurchaseIfNeeded(purchaseDetails, isErrorRecovery: true);
      _isPurchaseInProgress = false; // 구매 진행 상태 해제
    }
  }

  /// 성공한 구매 처리
  Future<void> _handleSuccessfulPurchase(PurchaseDetails purchaseDetails) async {
    try {
        if (kDebugMode) {
        print('🎯 구매 성공 처리: ${purchaseDetails.productID}');
      }
      
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (kDebugMode) {
          print('❌ 사용자가 로그인되어 있지 않습니다');
        }
        return;
      }

      // 🎯 Firebase Functions 중복 호출 방지
      final transactionId = purchaseDetails.purchaseID ?? '';
      final functionsKey = 'functions_${transactionId}_${purchaseDetails.productID}';
      
      if (_processedPurchases.contains(functionsKey)) {
        if (kDebugMode) {
          print('⏭️ Firebase Functions 이미 호출됨, 건너뛰기: $functionsKey');
        }
        return;
      }

      _processedPurchases.add(functionsKey);
        
        if (kDebugMode) {
        print('🔄 Firebase Functions로 구매 완료 처리: ${purchaseDetails.productID}');
      }

      // 거래 ID 추출 (단순화)
      final originalTransactionId = purchaseDetails.purchaseID ?? '';

      // 🎯 웹훅이 사용자를 찾을 수 있도록 originalTransactionId 저장
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'subscription.originalTransactionId': originalTransactionId,
          'subscription.lastPurchaseDate': FieldValue.serverTimestamp(),
        });
        
        if (kDebugMode) {
          print('✅ [InAppPurchase] originalTransactionId 저장 완료: $originalTransactionId');
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ [InAppPurchase] originalTransactionId 저장 실패: $e');
        }
      }

      // 🎯 App Store 웹훅이 실시간으로 구독 상태를 업데이트하므로
      // 클라이언트에서는 캐시 무효화만 수행하고 UI 업데이트 처리
      if (kDebugMode) {
        print('✅ 구매 완료 - App Store 웹훅이 구독 상태를 실시간 업데이트합니다');
      }
      
      // 🎯 구매 완료 후 구독 상태 캐시 무효화
      final unifiedManager = UnifiedSubscriptionManager();
      unifiedManager.invalidateCache();
      
      // 🎯 구매 완료 알림 (UnifiedSubscriptionManager 사용)
      unifiedManager.notifyPurchaseCompleted();
      
      // 🎯 구매 완료 즉시 배너 표시 (서버 웹훅 처리 전까지 임시)
      final bannerManager = BannerManager();
      final planId = 'temp_purchase_${DateTime.now().millisecondsSinceEpoch}';
      
      // 🎯 구매한 상품에 따라 적절한 배너 설정
      if (purchaseDetails.productID == premiumMonthlyWithTrialId) {
        // 무료체험 포함 월간 구독
        bannerManager.setBannerState(BannerType.trialStarted, true, planId: planId);
        if (kDebugMode) {
          print('🎉 [InAppPurchase] 무료체험 구매 완료 - trialStarted 배너 설정');
        }
      } else if (purchaseDetails.productID == premiumMonthlyId || purchaseDetails.productID == premiumYearlyId) {
        // 일반 프리미엄 구독 (월간/연간)
        bannerManager.setBannerState(BannerType.premiumStarted, true, planId: planId);
        if (kDebugMode) {
          print('💎 [InAppPurchase] 프리미엄 구매 완료 - premiumStarted 배너 설정');
        }
      } else {
        if (kDebugMode) {
          print('❓ [InAppPurchase] 알 수 없는 상품 구매: ${purchaseDetails.productID}');
        }
      }
      
      bannerManager.invalidateBannerCache(); // 배너 캐시 무효화
      
      // 🎯 서버 웹훅 처리 대기 후 재조회 (5초 지연)
      Future.delayed(const Duration(seconds: 5), () async {
        try {
          if (kDebugMode) {
            print('🔄 [InAppPurchase] 서버 웹훅 처리 완료 대기 후 구독 상태 재조회 (캐시 활용)');
          }
          
          // 캐시를 활용한 구독 상태 조회 (불필요한 Firebase Functions 호출 방지)
          await unifiedManager.getSubscriptionState(forceRefresh: false); // forceRefresh를 false로 변경
          
          if (kDebugMode) {
            print('✅ [InAppPurchase] 서버 웹훅 반영 완료 (캐시 활용)');
          }
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ [InAppPurchase] 지연된 구독 상태 재조회 실패: $e');
          }
        }
      });
      
      // 🎯 구매 완료 시점에서 알림 스케줄링 (무료체험인 경우에만)
      await _scheduleTrialNotificationsIfNeeded(purchaseDetails.productID);
      
      // 플랜 변경 알림은 UnifiedSubscriptionManager에서 자동 처리됨
      
      // 구매 성공 콜백 호출
      _onPurchaseSuccess?.call();
      
      // 🎯 사용자에게 상태 업데이트 진행 중임을 안내
      if (kDebugMode) {
        print('📢 [InAppPurchase] 구매 완료 - 서버에서 구독 상태 업데이트 중...');
        print('💡 [InAppPurchase] 상태 반영까지 최대 30초 소요될 수 있습니다 (Sandbox 환경)');
      }
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ 성공한 구매 처리 중 오류: $e');
      }
      
      // 오류 발생 시에도 UI 업데이트는 수행
      // (실제 구독 상태는 서버에서 관리됨)
      _onPurchaseSuccess?.call();
    }
  }



  /// 구매 시작
  Future<bool> buyProduct(String productId) async {
    // 🎯 이미 구매가 진행 중이면 방지
    if (_isPurchaseInProgress) {
      if (kDebugMode) {
        print('⚠️ 구매가 이미 진행 중입니다. 중복 호출 방지');
      }
      return false;
    }
    
    // 실제 구매 시점에 초기화
    await _ensureInitialized();
    
    // 🎯 구매 진행 상태 초기화 (pending transaction 정리 없이)
    _isPurchaseInProgress = false;
    if (kDebugMode) {
      print('🔄 구매 진행 상태 초기화 완료');
    }
    
    try {
      _isPurchaseInProgress = true;
      
      if (kDebugMode) {
        print('🛒 구매 시작: $productId');
      }

      if (!_isAvailable) {
        if (kDebugMode) {
          print('❌ In-App Purchase 사용 불가');
        }
        return false;
      }

      final ProductDetails? productDetails = _products
          .where((product) => product.id == productId)
          .firstOrNull;

      if (productDetails == null) {
        if (kDebugMode) {
          print('❌ 상품을 찾을 수 없습니다: $productId');
        }
        return false;
      }

      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: productDetails,
      );

      final bool success = await _inAppPurchase.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      if (kDebugMode) {
        print('🛒 구매 요청 결과: $success');
      }

      return success;
    } catch (e) {
      if (kDebugMode) {
        print('❌ 구매 시작 중 오류: $e');
      }
      
      // 🎯 pending transaction 에러 처리 - 사용자 안내 중심
      if (e.toString().contains('pending transaction') || 
          e.toString().contains('storekit_duplicate_product_object')) {
        if (kDebugMode) {
          print('🔧 미완료 거래 감지 - 사용자 안내 필요');
          print('💡 Apple Sandbox 환경에서 흔한 문제입니다');
        }
        
        // 사용자에게 명확한 안내 제공을 위해 특별한 에러 코드 반환
        throw Exception('PENDING_TRANSACTION_ERROR');
      }

      return false;
    } finally {
      // 🎯 구매 완료 후 상태 초기화 (지연 후)
      Future.delayed(const Duration(seconds: 3), () {
        _isPurchaseInProgress = false;
      });
    }
  }

  // 🎯 간소화된 구매 메서드들 (중복 제거)
  
  /// 무료체험 구매 (가이던스 포함)
  Future<Map<String, dynamic>> buyMonthlyTrialWithGuidance() => 
      attemptPurchaseWithGuidance(premiumMonthlyWithTrialId);

  /// 월간 구독 구매 (가이던스 포함)  
  Future<Map<String, dynamic>> buyMonthlyWithGuidance() => 
      attemptPurchaseWithGuidance(premiumMonthlyId);

  /// 연간 구독 구매 (가이던스 포함)
  Future<Map<String, dynamic>> buyYearlyWithGuidance() => 
      attemptPurchaseWithGuidance(premiumYearlyId);

  /// 무료체험 구매 (기존 호환성)
  Future<bool> buyMonthlyTrial() => buyProduct(premiumMonthlyWithTrialId);

  /// 월간 구독 구매 (기존 호환성)
  Future<bool> buyMonthly() => buyProduct(premiumMonthlyId);

  /// 연간 구독 구매 (기존 호환성)
  Future<bool> buyYearly() => buyProduct(premiumYearlyId);

  /// 구매 복원 (사용자 요청시 호출)
  Future<void> restorePurchases() async {
    // 구매 복원 시점에 초기화
    await _ensureInitialized();
    
    try {
      if (kDebugMode) {
        print('🔄 구매 복원 시작');
      }

      await _inAppPurchase.restorePurchases();

      if (kDebugMode) {
        print('✅ 구매 복원 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ 구매 복원 중 오류: $e');
      }
    }
  }

  /// 사용 가능한 상품 목록 반환 (지연 초기화 포함)
  Future<List<ProductDetails>> get availableProducts async {
    await _ensureInitialized();
    return _products;
  }

  /// In-App Purchase 사용 가능 여부 (지연 초기화 포함)
  Future<bool> get isAvailable async {
    await _ensureInitialized();
    return _isAvailable;
  }
  
  /// 즉시 사용 가능한 상품 목록 (초기화 없이)
  List<ProductDetails> get availableProductsSync => _products;

  /// 즉시 사용 가능 여부 (초기화 없이)
  bool get isAvailableSync => _isAvailable;

  // 🎯 간소화된 상품 정보 getter들 (중복 제거)
  
  /// 상품 정보 조회 헬퍼
  ProductDetails? _getProductById(String productId) => 
      _products.where((product) => product.id == productId).firstOrNull;

  /// 구매 완료 처리 헬퍼 (중복 제거)
  Future<void> _completePurchaseIfNeeded(PurchaseDetails purchaseDetails, {bool isErrorRecovery = false}) async {
    try {
      if (purchaseDetails.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchaseDetails);
        if (kDebugMode) {
          final prefix = isErrorRecovery ? '🔧 오류 후 강제' : '✅';
          print('$prefix 구매 완료 처리됨: ${purchaseDetails.productID}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        final prefix = isErrorRecovery ? '강제 완료' : '완료';
        print('❌ $prefix 처리 실패: $e');
      }
    }
  }

  /// 타임아웃 완료 처리 스케줄링 헬퍼 (중복 제거)
  void _scheduleTimeoutCompletion(PurchaseDetails purchaseDetails) {
    Future.delayed(const Duration(seconds: 30), () async {
      try {
        if (purchaseDetails.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchaseDetails);
          if (kDebugMode) {
            print('⏰ 타임아웃 후 강제 완료: ${purchaseDetails.productID}');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ 타임아웃 완료 처리 실패: $e');
        }
      }
    });
  }

  /// 월간 구독 상품 정보 (지연 초기화 포함)
  Future<ProductDetails?> get monthlyProduct async {
    await _ensureInitialized();
    return _getProductById(premiumMonthlyId);
  }

  /// 연간 구독 상품 정보 (지연 초기화 포함)
  Future<ProductDetails?> get yearlyProduct async {
    await _ensureInitialized();
    return _getProductById(premiumYearlyId);
  }

  /// 월간 무료체험 상품 정보 (지연 초기화 포함)
  Future<ProductDetails?> get monthlyTrialProduct async {
    await _ensureInitialized();
    return _getProductById(premiumMonthlyWithTrialId);
  }
  
  /// 즉시 월간 구독 상품 정보 (초기화 없이)
  ProductDetails? get monthlyProductSync => _getProductById(premiumMonthlyId);

  /// 즉시 연간 구독 상품 정보 (초기화 없이)
  ProductDetails? get yearlyProductSync => _getProductById(premiumYearlyId);

  /// 즉시 월간 무료체험 상품 정보 (초기화 없이)
  ProductDetails? get monthlyTrialProductSync => _getProductById(premiumMonthlyWithTrialId);

  /// 🎯 구매 완료 시점에서 무료체험 알림 스케줄링
  Future<void> _scheduleTrialNotificationsIfNeeded(String productId) async {
    try {
      // 무료체험 상품인 경우에만 알림 스케줄링
      if (productId == premiumMonthlyWithTrialId || productId == premiumMonthlyId) {
        if (kDebugMode) {
          print('🔔 무료체험 알림 스케줄링 시작: $productId');
        }
        
        // 현재 시점을 체험 시작 시점으로 설정
        await _notificationService.scheduleTrialEndNotifications(DateTime.now());
        
        if (kDebugMode) {
          print('✅ 무료체험 알림 스케줄링 완료');
        }
      } else {
        if (kDebugMode) {
          print('⏭️ 무료체험 상품이 아니므로 알림 스케줄링 건너뛰기: $productId');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ 무료체험 알림 스케줄링 실패: $e');
      }
    }
  }

  /// 🎯 사용자 친화적인 구매 시도 (pending transaction 자동 처리 포함)
  Future<Map<String, dynamic>> attemptPurchaseWithGuidance(String productId) async {
    try {
      // 1. 기본 구매 시도
      final success = await buyProduct(productId);
      
      if (success) {
        return {
          'success': true,
          'message': '구매가 성공적으로 시작되었습니다.',
        };
      }
      
      // 2. 실패한 경우 pending transaction 정리 시도
      try {
        await handlePendingTransactionsForUser();
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ 미완료 거래 정리 실패: $e');
        }
      }
      
      return {
        'success': false,
        'message': '구매를 시작할 수 없습니다.\n네트워크 연결을 확인하고 다시 시도해주세요.',
        'shouldRetryLater': false,
      };
      
    } catch (e) {
      if (kDebugMode) {
        print('❌ 구매 시도 중 오류: $e');
      }
      
      return {
        'success': false,
        'message': '구매 중 오류가 발생했습니다.\n잠시 후 다시 시도해주세요.',
        'shouldRetryLater': true,
      };
    }
  }

  /// 🎯 기존 미완료 구매 정리 (테스트 환경 대응)
  Future<void> _clearPendingPurchases() async {
    try {
      if (kDebugMode) {
        print('🧹 기존 미완료 구매 정리 시작');
      }
      
      // 기존 처리 목록 초기화
      _processedPurchases.clear();
      _isPurchaseInProgress = false;
      
      // 🎯 미완료 거래 강제 완료 처리
      await _finishPendingTransactions();
      
      if (kDebugMode) {
        print('✅ 미완료 구매 정리 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ 미완료 구매 정리 중 오류: $e');
      }
    }
  }
  
  /// 🎯 미완료 거래 강제 완료 처리
  Future<void> _finishPendingTransactions() async {
    try {
      if (kDebugMode) {
        print('🔧 미완료 거래 강제 완료 시작');
      }
      
      // 1. 구매 복원을 통해 pending transaction들이 스트림으로 들어오도록 함
      await _inAppPurchase.restorePurchases();
      
      // 2. 잠시 대기하여 pending transaction들이 처리되도록 함
      await Future.delayed(const Duration(seconds: 2));
      
      if (kDebugMode) {
        print('✅ 미완료 거래 강제 완료 처리');
      }
      
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ 미완료 거래 완료 중 오류: $e');
      }
    }
  }
  
  /// 🎯 사용자 친화적인 pending transaction 처리
  Future<void> handlePendingTransactionsForUser() async {
    try {
      if (kDebugMode) {
        print('🔍 사용자용 미완료 거래 확인 시작');
      }
      
      // 🎯 간단한 pending transaction 정리 (중복 호출 방지)
      // 이미 _clearPendingPurchases에서 정리했으므로 추가 정리는 최소화
      _isPurchaseInProgress = false; // 구매 진행 상태 초기화
      
      if (kDebugMode) {
        print('🧹 미완료 거래 상태 초기화 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ 미완료 거래 확인 실패: $e');
      }
    }
  }
} 