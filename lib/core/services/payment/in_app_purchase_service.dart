import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart';
import '../common/plan_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// In-App Purchase 관리 서비스
class InAppPurchaseService {
  static final InAppPurchaseService _instance = InAppPurchaseService._internal();
  factory InAppPurchaseService() => _instance;
  InAppPurchaseService._internal();

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final PlanService _planService = PlanService();
  
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  bool _isAvailable = false;
  List<ProductDetails> _products = [];
  
  // 상품 ID 정의
  static const String premiumMonthlyId = 'premium_monthly';
  static const String premiumYearlyId = 'premium_yearly';
  
  static const Set<String> _productIds = {
    premiumMonthlyId,
    premiumYearlyId,
  };

  /// 서비스 초기화
  Future<void> initialize() async {
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

      if (kDebugMode) {
        print('✅ In-App Purchase 서비스 초기화 완료 (자동 구매 복원 비활성화)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ In-App Purchase 초기화 오류: $e');
      }
    }
  }

  /// 서비스 종료
  void dispose() {
    _subscription.cancel();
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
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (kDebugMode) {
          print('❌ 사용자가 로그인되어 있지 않습니다');
        }
        return;
      }

      // 구매 영수증 검증 (서버에서 처리하는 것이 권장됨)
      if (!await _verifyPurchase(purchaseDetails)) {
        if (kDebugMode) {
          print('❌ 구매 영수증 검증 실패');
        }
        return;
      }

      // 구독 기간 계산
      DateTime expiryDate;
      if (purchaseDetails.productID == premiumMonthlyId) {
        expiryDate = DateTime.now().add(const Duration(days: 30));
      } else if (purchaseDetails.productID == premiumYearlyId) {
        expiryDate = DateTime.now().add(const Duration(days: 365));
      } else {
        if (kDebugMode) {
          print('❌ 알 수 없는 상품 ID: ${purchaseDetails.productID}');
        }
        return;
      }

      // 프리미엄 플랜으로 업그레이드
      final success = await _planService.upgradeToPremium(
        user.uid,
        expiryDate: expiryDate,
      );

      if (success) {
        if (kDebugMode) {
          print('✅ 프리미엄 플랜 업그레이드 성공');
        }
      } else {
        if (kDebugMode) {
          print('❌ 프리미엄 플랜 업그레이드 실패');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ 성공한 구매 처리 중 오류: $e');
      }
    }
  }

  /// 구매 영수증 검증 (간단한 클라이언트 검증)
  Future<bool> _verifyPurchase(PurchaseDetails purchaseDetails) async {
    // 실제 프로덕션에서는 서버에서 Apple/Google 서버와 통신하여 검증해야 함
    // 여기서는 간단한 클라이언트 검증만 수행
    return purchaseDetails.verificationData.localVerificationData.isNotEmpty;
  }

  /// 구매 시작
  Future<bool> buyProduct(String productId) async {
    try {
      if (!_isAvailable) {
        if (kDebugMode) {
          print('❌ In-App Purchase를 사용할 수 없습니다');
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

      if (kDebugMode) {
        print('🛒 구매 시작: ${productDetails.title}');
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

  /// 구매 복원 (사용자 요청시 호출)
  Future<void> restorePurchases() async {
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
} 