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

      // 🎯 기존 미완료 구매 정리 (테스트 환경 대응)
      await _clearPendingPurchases();
      
      // 🎯 추가 정리: 초기화 후 한번 더 정리
      Future.delayed(const Duration(seconds: 1), () async {
        try {
          await _finishPendingTransactions();
          if (kDebugMode) {
            print('🧹 추가 미완료 거래 정리 완료');
          }
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ 추가 정리 중 오류: $e');
          }
        }
      });

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
      } else if (purchaseDetails.status == PurchaseStatus.canceled) {
        // 구매 취소 처리
        if (kDebugMode) {
          print('🚫 구매 취소됨');
        }
      } else if (purchaseDetails.status == PurchaseStatus.pending) {
        // 구매 대기 중
        if (kDebugMode) {
          print('⏳ 구매 대기 중: ${purchaseDetails.productID}');
        }
        
        // 🎯 pending 상태도 일정 시간 후 강제 완료 처리 고려
        _scheduleTimeoutCompletion(purchaseDetails);
      }

      // 🎯 모든 상태의 구매에 대해 완료 처리 (pending transaction 방지)
      await _completePurchaseIfNeeded(purchaseDetails);
    } catch (e) {
      if (kDebugMode) {
        print('❌ 구매 처리 중 오류: $e');
      }
      
      // 🎯 오류 발생 시에도 완료 처리 시도
      await _completePurchaseIfNeeded(purchaseDetails, isErrorRecovery: true);
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

      // Firebase Functions를 통한 구매 완료 알림
      final appStoreService = AppStoreSubscriptionService();
      final notifySuccess = await appStoreService.notifyPurchaseComplete(
        transactionId: transactionId,
        originalTransactionId: originalTransactionId,
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
    // 🎯 이미 구매가 진행 중이면 방지
    if (_isPurchaseInProgress) {
      if (kDebugMode) {
        print('⚠️ 구매가 이미 진행 중입니다. 중복 호출 방지');
      }
      return false;
    }
    
    // 실제 구매 시점에 초기화
    await _ensureInitialized();
    
    // 🎯 구매 시작 전 pending transaction 확인 및 처리
    final hasPendingTransactions = await handlePendingTransactionsForUser();
    if (hasPendingTransactions) {
      if (kDebugMode) {
        print('⚠️ 미완료 거래가 있어 구매를 진행할 수 없습니다. 잠시 후 다시 시도해주세요.');
      }
      return false;
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
      
      // 🎯 pending transaction 에러 처리 - 더 강력한 처리
      if (e.toString().contains('pending transaction') || 
          e.toString().contains('storekit_duplicate_product_object')) {
        if (kDebugMode) {
          print('🔧 미완료 거래 감지, 강력한 정리 후 재시도');
        }
        
        try {
          // 1차: 미완료 거래 정리
          await _finishPendingTransactions();
          
          // 2차: 더 긴 대기 시간
          await Future.delayed(const Duration(seconds: 3));
          
          // 3차: 다시 한번 정리
          await _finishPendingTransactions();
          
          if (kDebugMode) {
            print('🔄 강력한 정리 후 재시도');
          }
          
          // 재시도
          final bool retrySuccess = await _inAppPurchase.buyNonConsumable(
            purchaseParam: PurchaseParam(productDetails: _products
                .where((product) => product.id == productId)
                .first),
          );
          
          if (kDebugMode) {
            print('🔄 재시도 결과: $retrySuccess');
          }
          
          return retrySuccess;
        } catch (retryError) {
          if (kDebugMode) {
            print('❌ 재시도 실패: $retryError');
            print('💡 사용자에게 몇 분 후 재시도 안내 필요');
          }
          return false;
        }
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

  /// 사용 가능한 상품 목록 반환
  List<ProductDetails> get availableProducts => _products;

  /// In-App Purchase 사용 가능 여부
  bool get isAvailable => _isAvailable;

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

  /// 월간 구독 상품 정보
  ProductDetails? get monthlyProduct => _getProductById(premiumMonthlyId);

  /// 연간 구독 상품 정보  
  ProductDetails? get yearlyProduct => _getProductById(premiumYearlyId);

  /// 월간 무료체험 상품 정보
  ProductDetails? get monthlyTrialProduct => _getProductById(premiumMonthlyWithTrialId);



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
      
      // 2. 실패한 경우 pending transaction 확인
      final hasPending = await handlePendingTransactionsForUser();
      
      if (hasPending) {
        return {
          'success': false,
          'message': '이전 구매가 아직 처리 중입니다.\n잠시 기다린 후 다시 시도해주세요.',
          'shouldRetryLater': true,
        };
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
  Future<bool> handlePendingTransactionsForUser() async {
    try {
      if (kDebugMode) {
        print('🔍 사용자용 미완료 거래 확인 시작');
      }
      
      // 구매 복원을 통해 pending transaction 확인
      await _inAppPurchase.restorePurchases();
      
      // 잠시 대기하여 pending transaction이 스트림으로 들어오는지 확인
      await Future.delayed(const Duration(seconds: 1));
      
      // 현재 진행 중인 구매가 있다면 사용자에게 안내
      if (_isPurchaseInProgress) {
        if (kDebugMode) {
          print('⚠️ 미완료 거래가 있습니다. 잠시 기다려주세요.');
        }
        return true; // pending transaction이 있음을 알림
      }
      
      return false; // pending transaction이 없음
    } catch (e) {
      if (kDebugMode) {
        print('❌ 미완료 거래 확인 실패: $e');
      }
      return false;
    }
  }
} 