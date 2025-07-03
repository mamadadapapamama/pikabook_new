import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../common/plan_service.dart';
import '../subscription/app_store_subscription_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// In-App Purchase 관리 서비스
/// 사용자가 "구독" 버튼을 눌렀을 때 App Store 결제 다이얼로그 띄우기
/// apple/결제 시스템 연동 - in_app_purchase 패키지를 통한 네이티브 결제 및 구매 완료 알림 - 서버에 구매 완료 사실 전달

class InAppPurchaseService {
  static final InAppPurchaseService _instance = InAppPurchaseService._internal();
  factory InAppPurchaseService() => _instance;
  InAppPurchaseService._internal();

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final PlanService _planService = PlanService();
  
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  bool _isAvailable = false;
  bool _isInitialized = false;
  List<ProductDetails> _products = [];
  
  // 구매 성공 콜백
  Function()? _onPurchaseSuccess;
  

  
  // 상품 ID 정의
  static const String premiumMonthlyId = 'premium_monthly';
  static const String premiumYearlyId = 'premium_yearly';
  
  // 무료체험 포함 상품 ID (앱스토어 설정 후 활성화)
  static const String premiumMonthlyWithTrialId = 'premium_monthly_with_trial';
  static const String premiumYearlyWithTrialId = 'premium_yearly_with_trial';
  
  static const Set<String> _productIds = {
    premiumMonthlyId,
    premiumYearlyId,
    premiumMonthlyWithTrialId,
    premiumYearlyWithTrialId,
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

      // 미완료 구매 복원 (Apple ID 다이얼로그 방지를 위해 비활성화)
      // 구매 복원은 사용자가 명시적으로 요청할 때만 실행
      // await _restorePurchases();

      _isInitialized = true;
      
      if (kDebugMode) {
        print('✅ In-App Purchase 서비스 초기화 완료 (자동 구매 복원 비활성화)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ In-App Purchase 초기화 오류: $e');
      }
    }
  }

  /// 지연 초기화 확인
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  /// 서비스 종료
  void dispose() {
    if (_isInitialized) {
      _subscription.cancel();
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
    
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      _handlePurchase(purchaseDetails);
    }
  }

  /// 개별 구매 처리
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
      } else if (purchaseDetails.status == PurchaseStatus.canceled) {
        // 구매 취소 처리
        if (kDebugMode) {
          print('🚫 구매 취소됨');
        }
      }

      // 구매 완료 처리
      if (purchaseDetails.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchaseDetails);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ 구매 처리 중 오류: $e');
      }
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

      if (kDebugMode) {
        print('🔄 Firebase Functions로 구매 완료 처리: ${purchaseDetails.productID}');
      }

      // 거래 ID 추출 (단순화)
      final transactionId = purchaseDetails.purchaseID ?? '';
      final originalTransactionId = purchaseDetails.purchaseID ?? '';

      // Firebase Functions를 통한 구매 완료 알림
      final appStoreService = AppStoreSubscriptionService();
      final notifySuccess = await appStoreService.notifyPurchaseComplete(
        transactionId: transactionId ?? '',
        originalTransactionId: originalTransactionId ?? '',
        productId: purchaseDetails.productID,
        purchaseDate: DateTime.now().toIso8601String(),
        // expirationDate는 App Store Connect에서 자동 계산됨
      );

      if (notifySuccess) {
        if (kDebugMode) {
          print('✅ Firebase Functions 구매 완료 알림 성공');
        }
        
        // 플랜 캐시 무효화 (서버에서 업데이트된 구독 상태 반영)
        _planService.notifyPlanChanged('premium', userId: user.uid);
        
        // 구매 성공 콜백 호출
        _onPurchaseSuccess?.call();
      } else {
        if (kDebugMode) {
          print('❌ Firebase Functions 구매 완료 알림 실패');
        }
        
        // Firebase Functions 실패 시에도 UI 업데이트는 수행
        // (실제 구독 상태는 다음 앱 시작 시 서버에서 동기화됨)
        _onPurchaseSuccess?.call();
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
    // 실제 구매 시점에 초기화
    await _ensureInitialized();
    
    try {
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
      return false;
    }
  }

  /// 무료체험 구매 시작 (월간)
  Future<bool> buyMonthlyTrial() async {
    return await buyProduct(premiumMonthlyWithTrialId);
  }

  /// 무료체험 구매 시작 (연간)
  Future<bool> buyYearlyTrial() async {
    return await buyProduct(premiumYearlyWithTrialId);
  }

  /// 연간 구독 구매 시작 (일반)
  Future<bool> buyYearly() async {
    return await buyProduct(premiumYearlyId);
  }

  /// 월간 구독 구매 시작 (일반)
  Future<bool> buyMonthly() async {
    return await buyProduct(premiumMonthlyId);
  }

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

  /// 사용 가능한 상품 목록 반환
  List<ProductDetails> get availableProducts => _products;

  /// In-App Purchase 사용 가능 여부
  bool get isAvailable => _isAvailable;

  /// 월간 구독 상품 정보
  ProductDetails? get monthlyProduct => _products
      .where((product) => product.id == premiumMonthlyId)
      .firstOrNull;

  /// 연간 구독 상품 정보
  ProductDetails? get yearlyProduct => _products
      .where((product) => product.id == premiumYearlyId)
      .firstOrNull;

  /// 월간 무료체험 상품 정보
  ProductDetails? get monthlyTrialProduct => _products
      .where((product) => product.id == premiumMonthlyWithTrialId)
      .firstOrNull;

  /// 연간 무료체험 상품 정보
  ProductDetails? get yearlyTrialProduct => _products
      .where((product) => product.id == premiumYearlyWithTrialId)
      .firstOrNull;
} 