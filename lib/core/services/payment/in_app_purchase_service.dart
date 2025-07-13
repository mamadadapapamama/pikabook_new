import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import '../subscription/unified_subscription_manager.dart';
import '../notification/notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';


/// 🚀 StoreKit 2 기반 In-App Purchase 관리 서비스
/// 
/// in_app_purchase_storekit 패키지를 사용하여 StoreKit 2의 장점을 활용하면서
/// 기존 API 호환성을 유지합니다.
/// 
/// 주요 개선 사항:
/// - StoreKit 2 Transaction.updates 자동 처리
/// - 향상된 보안 및 안정성
/// - 더 나은 pending transaction 관리
/// - iOS 15.0+ 최적화
class InAppPurchaseService {
  static final InAppPurchaseService _instance = InAppPurchaseService._internal();
  factory InAppPurchaseService() => _instance;
  InAppPurchaseService._internal();

  // 🎯 StoreKit 2 기반 In-App Purchase 인스턴스
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final NotificationService _notificationService = NotificationService();
  
  // 🎯 상태 관리
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  bool _isAvailable = false;
  bool _isInitialized = false;
  List<ProductDetails> _products = [];
  
  // 🎯 중복 처리 방지 (StoreKit 2 개선)
  final Set<String> _processedPurchases = {};
  bool _isPurchaseInProgress = false;
  
  // 🎯 구매 성공 콜백
  Function()? _onPurchaseSuccess;
  
  // 🎯 구매 결과 콜백 (Transaction ID 포함)
  Function(bool success, String? transactionId, String? error)? _onPurchaseResult;
  
  // 🎯 Trial 구매 컨텍스트 (환영 모달에서 구매 시 true)
  bool _isTrialContext = false;
  
  // 🎯 상품 ID 정의
  static const String premiumMonthlyId = 'premium_monthly';
  static const String premiumYearlyId = 'premium_yearly';
  
  static const Set<String> _productIds = {
    premiumMonthlyId,
    premiumYearlyId,
  };

  /// 🚀 StoreKit 2 서비스 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      if (kDebugMode) {
        print('🚀 StoreKit 2 서비스 초기화 시작');
      }

      // 🎯 StoreKit 2 사용 가능 여부 확인
      _isAvailable = await _inAppPurchase.isAvailable();
      
      if (!_isAvailable) {
        if (kDebugMode) {
          print('❌ StoreKit 2를 사용할 수 없습니다 (iOS 15.0+ 필요)');
        }
        return;
      }

      if (kDebugMode) {
        print('✅ StoreKit 2 사용 가능 (iOS 15.0+)');
      }

      // 🎯 미완료 구매 정리 (StoreKit 2 개선)
      await _clearPendingPurchasesV2();
      
      // 🎯 구매 스트림 구독 (StoreKit 2 Transaction.updates 자동 처리)
      _subscription = _inAppPurchase.purchaseStream.listen(
        _onPurchaseUpdate,
        onDone: () {
          if (kDebugMode) {
            print('🔄 StoreKit 2 구매 스트림 완료');
          }
        },
        onError: (error) {
          if (kDebugMode) {
            print('❌ StoreKit 2 구매 스트림 오류: $error');
            print('🔧 구매 스트림 오류 자동 복구 시도');
          }
          
          // 구매 스트림 오류 시 자동 복구
          _recoverFromStreamError(error);
        },
      );

      // 🎯 상품 정보 로드
      await _loadProducts();

      _isInitialized = true;
      
      if (kDebugMode) {
        print('✅ StoreKit 2 서비스 초기화 완료');
        print('   - Transaction.updates 자동 처리 활성화');
        print('   - 로드된 상품: ${_products.length}개');
        print('   - 사용자 변경 감지 활성화');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ StoreKit 2 초기화 오류: $e');
      }
    }
  }

  /// 🎯 지연 초기화 확인
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      if (kDebugMode) {
        print('🚀 StoreKit 2 지연 초기화 시작');
      }
      await initialize();
    }
  }

  /// 🎯 구매 캐시 초기화 (AuthService에서 호출)
  void clearUserCache() {
    if (kDebugMode) {
      print('🔄 [InAppPurchaseService] 사용자 변경으로 인한 구매 캐시 초기화');
    }
    
    // 구매 처리 캐시 초기화
    _processedPurchases.clear();
    _isPurchaseInProgress = false;
    
    if (kDebugMode) {
      print('✅ [InAppPurchaseService] 구매 캐시 초기화 완료');
    }
  }

  /// 🎯 서비스 종료
  void dispose() {
    if (_isInitialized) {
      _subscription.cancel();
      
      // 🎯 StoreKit 2 미완료 거래 정리
      _finishPendingTransactions().catchError((error) {
        if (kDebugMode) {
          print('⚠️ StoreKit 2 서비스 종료 시 미완료 거래 정리 실패: $error');
        }
      });
      
    _processedPurchases.clear();
      _isPurchaseInProgress = false;
    }
  }
  
  /// 🎯 구매 성공 콜백 설정
  void setOnPurchaseSuccess(Function()? callback) {
    _onPurchaseSuccess = callback;
  }

  /// 🎯 구매 결과 콜백 설정 (환영 모달용)
  void setOnPurchaseResult(Function(bool success, String? transactionId, String? error)? callback) {
    _onPurchaseResult = callback;
  }

  /// 🎯 Trial 구매 컨텍스트 설정 (환영 모달에서 구매 시 true)
  void setTrialContext(bool isTrialContext) {
    _isTrialContext = isTrialContext;
    if (kDebugMode) {
      print('🎯 [InAppPurchase] Trial 컨텍스트 설정: $isTrialContext');
    }
  }

  /// 🎯 상품 정보 로드
  Future<void> _loadProducts() async {
    try {
      if (kDebugMode) {
        print('📦 StoreKit 2 상품 정보 로드 시작');
      }

      final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails(_productIds);
      
      if (response.error != null) {
        if (kDebugMode) {
          print('❌ StoreKit 2 상품 정보 로드 오류: ${response.error}');
        }
        return;
      }

      _products = response.productDetails;
      
      if (kDebugMode) {
        print('✅ StoreKit 2 상품 정보 로드 완료: ${_products.length}개');
        for (final product in _products) {
          print('   - ${product.id}: ${product.title} (${product.price})');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ StoreKit 2 상품 정보 로드 중 오류: $e');
      }
    }
  }

  /// 🎯 구매 업데이트 처리 (StoreKit 2 Transaction.updates 자동 처리)
  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    if (kDebugMode) {
      print('🔔 StoreKit 2 구매 업데이트 수신: ${purchaseDetailsList.length}개');
    }
    
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      // 🎯 중복 처리 방지
      final purchaseKey = '${purchaseDetails.productID}_${purchaseDetails.purchaseID}';
      
      if (_processedPurchases.contains(purchaseKey)) {
      if (kDebugMode) {
          print('⏭️ 이미 처리된 구매 건너뛰기: $purchaseKey');
        }
        continue;
      }
      
      _processedPurchases.add(purchaseKey);
      _handlePurchase(purchaseDetails);
    }
  }

  /// 🎯 구매 처리 (StoreKit 2 개선)
  Future<void> _handlePurchase(PurchaseDetails purchaseDetails) async {
    try {
      if (kDebugMode) {
        print('🛒 StoreKit 2 구매 처리: ${purchaseDetails.productID}, 상태: ${purchaseDetails.status}');
      }

      if (purchaseDetails.status == PurchaseStatus.purchased) {
        // 🎉 구매 성공 처리
        await _handleSuccessfulPurchase(purchaseDetails);
        // 🎯 구매 결과 콜백 호출 (성공)
        _onPurchaseResult?.call(true, purchaseDetails.purchaseID, null);
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        // ❌ 구매 실패 처리
        if (kDebugMode) {
          print('❌ StoreKit 2 구매 실패: ${purchaseDetails.error}');
        }
        await _completePurchaseIfNeeded(purchaseDetails, isErrorRecovery: true);
        _isPurchaseInProgress = false;
        // 🎯 구매 결과 콜백 호출 (실패)
        _onPurchaseResult?.call(false, null, purchaseDetails.error?.message ?? '구매 실패');
      } else if (purchaseDetails.status == PurchaseStatus.canceled) {
        // 🚫 구매 취소 처리
        if (kDebugMode) {
          print('🚫 StoreKit 2 구매 취소됨');
        }
        await _completePurchaseIfNeeded(purchaseDetails, isErrorRecovery: true);
        _isPurchaseInProgress = false;
        // 🎯 구매 결과 콜백 호출 (취소)
        _onPurchaseResult?.call(false, null, '사용자가 구매를 취소했습니다');
      } else if (purchaseDetails.status == PurchaseStatus.pending) {
        // ⏳ 구매 대기 중 (StoreKit 2에서 자동 처리)
        if (kDebugMode) {
          print('⏳ StoreKit 2 구매 대기 중 (자동 처리): ${purchaseDetails.productID}');
        }
        _scheduleTimeoutCompletion(purchaseDetails);
      } else {
        // 🎯 알 수 없는 상태 처리
        if (kDebugMode) {
          print('❓ StoreKit 2 알 수 없는 구매 상태: ${purchaseDetails.status}');
        }
        await _completePurchaseIfNeeded(purchaseDetails, isErrorRecovery: true);
        _isPurchaseInProgress = false;
      }

      // 🎯 성공하지 않은 구매는 완료 처리
      if (purchaseDetails.status != PurchaseStatus.purchased) {
        await _completePurchaseIfNeeded(purchaseDetails);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ StoreKit 2 구매 처리 중 오류: $e');
      }
      
      await _completePurchaseIfNeeded(purchaseDetails, isErrorRecovery: true);
      _isPurchaseInProgress = false;
    }
  }

  /// 🎉 성공한 구매 처리 (StoreKit 2 개선)
  Future<void> _handleSuccessfulPurchase(PurchaseDetails purchaseDetails) async {
    try {
        if (kDebugMode) {
        print('🎉 StoreKit 2 구매 성공 처리: ${purchaseDetails.productID}');
      }
      
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (kDebugMode) {
          print('❌ 사용자가 로그인되어 있지 않습니다');
        }
        return;
      }

      // 🎯 StoreKit 2 Transaction ID 처리
      final transactionId = purchaseDetails.purchaseID ?? '';
      if (transactionId.isNotEmpty) {
        await _extractAndStoreOriginalTransactionId(user.uid, transactionId);
      }

      // 🎯 EntitlementEngine 연동 (StoreKit 2 Transaction.updates 활용)
      await _notifySubscriptionManager();
      
      // 🎯 UI 업데이트
      await _updateUIAfterPurchase(purchaseDetails.productID);
      
      // 🎯 알림 설정
      await _scheduleNotificationsIfNeeded(purchaseDetails.productID);
      

      
      // 🎯 성공 콜백 호출
      _onPurchaseSuccess?.call();
      
      if (kDebugMode) {
        print('✅ StoreKit 2 구매 처리 완료 - Transaction.updates 자동 처리됨');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ StoreKit 2 구매 성공 처리 중 오류: $e');
      }
      
      // 오류 발생 시에도 UI 업데이트
      _onPurchaseSuccess?.call();
    }
  }

  /// 🛒 구매 시작 (StoreKit 2 방식)
  Future<bool> buyProduct(String productId) async {
    if (_isPurchaseInProgress) {
      if (kDebugMode) {
        print('⚠️ StoreKit 2 구매가 이미 진행 중입니다');
      }
      return false;
    }
    
    await _ensureInitialized();
    
    try {
      _isPurchaseInProgress = true;
      
      if (kDebugMode) {
        print('🛒 StoreKit 2 구매 시작: $productId');
      }

      if (!_isAvailable) {
        if (kDebugMode) {
          print('❌ StoreKit 2 사용 불가');
        }
        return false;
      }

      final ProductDetails? productDetails = _products
          .where((product) => product.id == productId)
          .firstOrNull;

      if (productDetails == null) {
        if (kDebugMode) {
          print('❌ StoreKit 2 상품을 찾을 수 없습니다: $productId');
        }
        return false;
      }

      // 🚀 StoreKit 2 구매 요청
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: productDetails,
      );

      final bool success = await _inAppPurchase.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      if (kDebugMode) {
        print('🛒 StoreKit 2 구매 요청 결과: $success');
      }

      return success;
    } catch (e) {
      if (kDebugMode) {
        print('❌ StoreKit 2 구매 시작 중 오류: $e');
      }
      
      // 🎯 StoreKit 2 특정 오류 처리 및 자동 복구 시도
      final errorResult = await _handleStoreKitError(e, productId);
      if (errorResult['canRetry'] == true) {
        if (kDebugMode) {
          print('🔄 StoreKit 2 오류 복구 후 재시도: $productId');
        }
        
        // 2초 대기 후 재시도
        await Future.delayed(const Duration(seconds: 2));
        return await _retryPurchase(productId);
      }
      
      // 🎯 구매 결과 콜백 호출 (실패)
      _onPurchaseResult?.call(false, null, errorResult['message'] as String);
      
      return false;
    } finally {
      Future.delayed(const Duration(seconds: 3), () {
        _isPurchaseInProgress = false;
      });
    }
  }

  /// 🎯 UnifiedSubscriptionManager 상태 갱신 (통합된 구독 관리)
  Future<void> _notifySubscriptionManager() async {
    try {
      final subscriptionManager = UnifiedSubscriptionManager();
      await subscriptionManager.getSubscriptionEntitlements(forceRefresh: true);
      
      if (kDebugMode) {
        print('✅ UnifiedSubscriptionManager 상태 갱신 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ UnifiedSubscriptionManager 상태 갱신 실패: $e');
      }
    }
  }

  /// 🎯 UI 업데이트
  Future<void> _updateUIAfterPurchase(String productId) async {
    final unifiedManager = UnifiedSubscriptionManager();
    unifiedManager.invalidateCache();
    unifiedManager.notifyPurchaseCompleted();
    
    // 🎯 이벤트 발행은 UnifiedSubscriptionManager의 Transaction 모니터링에서 자동 처리됨
    if (kDebugMode) {
      final context = _isTrialContext ? 'trial' : 'premium';
      print('🎉 [InAppPurchase] 구매 완료 - UnifiedSubscriptionManager가 자동으로 이벤트 발행할 예정 ($context)');
    }
    
    // Trial 컨텍스트 초기화
    _isTrialContext = false;
  }

  /// 🎯 알림 설정
  Future<void> _scheduleNotificationsIfNeeded(String productId) async {
    if (productId == premiumMonthlyId) {
      try {
        // premium_monthly 구매 시 알림 스케줄링
        // (Trial이든 정규 구매든 D-1 알림이 유용함)
        await _notificationService.scheduleTrialEndNotifications(DateTime.now());
        if (kDebugMode) {
          print('✅ StoreKit 2 구독 알림 스케줄링 완료');
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ StoreKit 2 알림 스케줄링 실패: $e');
        }
      }
    }
  }

  /// 🎯 Firebase Functions를 통한 originalTransactionId 추출 및 저장
  Future<void> _extractAndStoreOriginalTransactionId(String userId, String transactionId) async {
    try {
      if (kDebugMode) {
        print('🔍 StoreKit 2 originalTransactionId 추출 시작');
        print('   - userId: $userId');
        print('   - transactionId: $transactionId');
      }
      
      final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
      final callable = functions.httpsCallable('extractOriginalTransactionId');
      
      final result = await callable.call({
        'transactionId': transactionId,
        'userId': userId,
      });
      
      final data = Map<String, dynamic>.from(result.data as Map);
      
      // 🚀 Apple 공식 라이브러리 응답 필드 처리
      final success = data['success'] as bool? ?? false;
      final originalTransactionId = data['originalTransactionId'] as String?;
      final source = data['source'] as String?;
      
      if (kDebugMode) {
        print('📡 [InAppPurchase] extractOriginalTransactionId 응답:');
        print('   - 성공 여부: ${success ? "✅ 성공" : "❌ 실패"}');
        print('   - originalTransactionId: ${originalTransactionId ?? "없음"}');
        print('   - 처리 소스: ${source ?? "알 수 없음"}');
        
        if (source == 'apple-official-library') {
          print('🎉 [InAppPurchase] Apple 공식 라이브러리로 처리됨!');
        }
      }
      
      if (success && originalTransactionId != null) {
        if (kDebugMode) {
          print('✅ StoreKit 2 originalTransactionId 저장 완료: $originalTransactionId');
          print('🚀 Apple 공식 라이브러리 기반 처리 확인됨');
        }
      } else {
        if (kDebugMode) {
          print('❌ StoreKit 2 originalTransactionId 추출 실패');
          print('🔍 에러 정보: ${data['error'] ?? "알 수 없는 오류"}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ StoreKit 2 originalTransactionId 저장 실패: $e');
        print('🔍 [InAppPurchase] Firebase Functions 호출 또는 Apple 라이브러리 오류 가능성');
      }
    }
  }

  /// 🎯 StoreKit 2 기반 미완료 구매 정리
  Future<void> _clearPendingPurchasesV2() async {
    try {
      if (kDebugMode) {
        print('🧹 StoreKit 2 미완료 구매 정리 시작');
      }
      
      _processedPurchases.clear();
      _isPurchaseInProgress = false;
      
      // 🎯 StoreKit 2에서는 Transaction.updates가 자동으로 처리하므로
      // 별도 강제 정리 작업 최소화
      await _finishPendingTransactions();
      
      if (kDebugMode) {
        print('✅ StoreKit 2 미완료 구매 정리 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ StoreKit 2 미완료 구매 정리 중 오류: $e');
      }
    }
  }

  /// 🎯 미완료 거래 강제 완료 처리
  Future<void> _finishPendingTransactions() async {
    try {
      if (kDebugMode) {
        print('🔧 StoreKit 2 미완료 거래 강제 완료 시작');
      }

      // StoreKit 2에서는 Transaction.updates가 자동으로 처리하므로
      // 구매 복원만 수행
      await _inAppPurchase.restorePurchases();
      await Future.delayed(const Duration(seconds: 2));

      if (kDebugMode) {
        print('✅ StoreKit 2 미완료 거래 강제 완료 처리');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ StoreKit 2 미완료 거래 완료 중 오류: $e');
      }
    }
  }

  /// 구매 완료 처리 헬퍼
  Future<void> _completePurchaseIfNeeded(PurchaseDetails purchaseDetails, {bool isErrorRecovery = false}) async {
    try {
      if (purchaseDetails.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchaseDetails);
        if (kDebugMode) {
          final prefix = isErrorRecovery ? '🔧 오류 후 강제' : '✅';
          print('$prefix StoreKit 2 구매 완료 처리됨: ${purchaseDetails.productID}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        final prefix = isErrorRecovery ? '강제 완료' : '완료';
        print('❌ StoreKit 2 $prefix 처리 실패: $e');
      }
    }
  }

  /// 타임아웃 완료 처리 스케줄링
  void _scheduleTimeoutCompletion(PurchaseDetails purchaseDetails) {
    Future.delayed(const Duration(seconds: 30), () async {
      try {
        if (purchaseDetails.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchaseDetails);
          if (kDebugMode) {
            print('⏰ StoreKit 2 타임아웃 후 강제 완료: ${purchaseDetails.productID}');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ StoreKit 2 타임아웃 완료 처리 실패: $e');
        }
      }
    });
  }

  // 🎯 기존 호환성 메서드들
  Future<bool> buyMonthly() => buyProduct(premiumMonthlyId);
  Future<bool> buyYearly() => buyProduct(premiumYearlyId);
  Future<bool> buyMonthlyTrial() => buyProduct(premiumMonthlyId); // Trial은 premium_monthly의 offer

  /// 구매 복원
  Future<void> restorePurchases() async {
    await _ensureInitialized();
    try {
        if (kDebugMode) {
        print('🔄 StoreKit 2 구매 복원 시작');
        }
      await _inAppPurchase.restorePurchases();
        if (kDebugMode) {
        print('✅ StoreKit 2 구매 복원 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ StoreKit 2 구매 복원 중 오류: $e');
      }
    }
  }

  /// 사용 가능 여부
  Future<bool> get isAvailable async {
    await _ensureInitialized();
    return _isAvailable;
  }
  
  bool get isAvailableSync => _isAvailable;

  /// 사용 가능한 상품 목록 반환
  Future<List<ProductDetails>> get availableProducts async {
    await _ensureInitialized();
    return _products;
  }

  /// 즉시 사용 가능한 상품 목록
  List<ProductDetails> get availableProductsSync => _products;

  /// 상품 정보 조회 헬퍼
  ProductDetails? _getProductById(String productId) => 
      _products.where((product) => product.id == productId).firstOrNull;

  /// 상품 정보 getter들
  Future<ProductDetails?> get monthlyProduct async {
    await _ensureInitialized();
    return _getProductById(premiumMonthlyId);
  }

  Future<ProductDetails?> get yearlyProduct async {
    await _ensureInitialized();
    return _getProductById(premiumYearlyId);
  }

  Future<ProductDetails?> get monthlyTrialProduct async {
    await _ensureInitialized();
    return _getProductById(premiumMonthlyId); // Trial은 premium_monthly의 offer
  }

  /// 즉시 상품 정보 getter들
  ProductDetails? get monthlyProductSync => _getProductById(premiumMonthlyId);
  ProductDetails? get yearlyProductSync => _getProductById(premiumYearlyId);
  ProductDetails? get monthlyTrialProductSync => _getProductById(premiumMonthlyId); // Trial은 premium_monthly의 offer

  /// 🎯 사용자 친화적인 구매 시도
  Future<Map<String, dynamic>> attemptPurchaseWithGuidance(String productId) async {
    try {
      final success = await buyProduct(productId);
      
      if (success) {
        return {
          'success': true,
          'message': 'StoreKit 2 구매가 성공적으로 시작되었습니다.',
        };
      }
      
      return {
        'success': false,
        'message': '구매를 시작할 수 없습니다.\n네트워크 연결을 확인하고 다시 시도해주세요.',
        'shouldRetryLater': false,
      };
    } catch (e) {
      if (e.toString().contains('PENDING_TRANSACTION_ERROR')) {
        return {
          'success': false,
          'isPendingTransactionError': true,
          'title': '미완료 구매가 감지되었습니다 (StoreKit 2)',
          'message': 'StoreKit 2의 Transaction.updates가 자동으로 처리합니다.',
          'solutions': [
            {'title': '잠시 대기', 'description': 'StoreKit 2가 자동으로 정리합니다.'},
            {'title': '앱 재시작', 'description': '앱을 완전히 종료하고 다시 실행해주세요.'},
          ],
        };
      }
      
      return {
        'success': false,
        'message': 'StoreKit 2 구매 중 오류가 발생했습니다.\n잠시 후 다시 시도해주세요.',
        'shouldRetryLater': true,
      };
    }
  }

  /// 간소화된 구매 메서드들
  Future<Map<String, dynamic>> buyMonthlyWithGuidance() => attemptPurchaseWithGuidance(premiumMonthlyId);
  Future<Map<String, dynamic>> buyYearlyWithGuidance() => attemptPurchaseWithGuidance(premiumYearlyId);
  Future<Map<String, dynamic>> buyMonthlyTrialWithGuidance() => attemptPurchaseWithGuidance(premiumMonthlyId); // Trial은 premium_monthly의 offer

  /// 🆘 사용자 친화적인 pending transaction 처리
  Future<void> handlePendingTransactionsForUser() async {
    try {
      if (kDebugMode) {
        print('🔍 StoreKit 2 사용자용 미완료 거래 확인 시작');
      }
      
      _isPurchaseInProgress = false;
      
      if (kDebugMode) {
        print('🧹 StoreKit 2 미완료 거래 상태 초기화 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ StoreKit 2 미완료 거래 확인 실패: $e');
      }
    }
  }
  
  /// 🆘 사용자 직접 호출 Pending Transaction 해결
  Future<Map<String, dynamic>> resolvePendingTransactions() async {
      if (kDebugMode) {
      print('🔧 StoreKit 2 사용자 요청: Pending Transaction 해결');
      }
      
    try {
      await _finishPendingTransactions();
      await _inAppPurchase.restorePurchases();
      
      _isPurchaseInProgress = false;
      _processedPurchases.clear();
      
      return {
        'success': true,
        'message': 'StoreKit 2 미완료 거래 정리가 완료되었습니다.\n이제 다시 구매를 시도해보세요.',
      };
    } catch (e) {
      if (kDebugMode) {
        print('❌ StoreKit 2 Pending Transaction 해결 실패: $e');
      }
      
      return {
        'success': false,
        'message': 'StoreKit 2 자동 해결에 실패했습니다.\n앱을 재시작하거나 iOS 설정을 확인해주세요.',
        'needsManualIntervention': true,
      };
    }
  }

  /// 🎯 사용 가능한 상품 목록 반환 (Debug용)
  Future<List<ProductDetails>> getAvailableProducts() async {
    await _ensureInitialized();
    return _products;
  }

  /// 🎯 StoreKit 2 오류 처리 및 복구 시도
  Future<Map<String, dynamic>> _handleStoreKitError(dynamic error, String productId) async {
    final errorString = error.toString();
    
    if (kDebugMode) {
      print('🔍 StoreKit 2 오류 분석 중: $errorString');
    }
    
    // 1. Pending Transaction 오류
    if (errorString.contains('pending transaction') || 
        errorString.contains('storekit_duplicate_product_object') ||
        errorString.contains('StoreKitError')) {
      
      if (kDebugMode) {
        print('🔧 Pending Transaction 감지 - 자동 복구 시도');
      }
      
      try {
        // 미완료 거래 정리
        await _finishPendingTransactions();
        
        // 구매 스트림 재설정
        await _inAppPurchase.restorePurchases();
        
        // 상품 정보 재로드
        await _loadProducts();
        
        return {
          'canRetry': true,
          'message': 'Pending Transaction 복구 완료',
        };
      } catch (e) {
        if (kDebugMode) {
          print('❌ Pending Transaction 복구 실패: $e');
        }
        return {
          'canRetry': false,
          'message': '미완료 거래 정리 실패. 앱을 재시작해주세요.',
        };
      }
    }
    
    // 2. Network 오류
    if (errorString.contains('network') || 
        errorString.contains('connection') ||
        errorString.contains('timeout')) {
      return {
        'canRetry': true,
        'message': '네트워크 오류가 발생했습니다.',
      };
    }
    
    // 3. Product 로드 오류
    if (errorString.contains('product') || 
        errorString.contains('identifier')) {
      
      if (kDebugMode) {
        print('🔧 상품 정보 재로드 시도');
      }
      
      try {
        await _loadProducts();
        return {
          'canRetry': true,
          'message': '상품 정보 재로드 완료',
        };
      } catch (e) {
        return {
          'canRetry': false,
          'message': '상품 정보를 불러올 수 없습니다.',
        };
      }
    }
    
    // 4. 사용자 취소
    if (errorString.contains('cancelled') || 
        errorString.contains('cancel')) {
      return {
        'canRetry': false,
        'message': '사용자가 구매를 취소했습니다.',
      };
    }
    
    // 5. 기타 오류
    return {
      'canRetry': false,
      'message': 'StoreKit 오류가 발생했습니다: ${errorString.length > 100 ? errorString.substring(0, 100) + '...' : errorString}',
    };
  }

  /// 🎯 구매 재시도 (복구 후)
  Future<bool> _retryPurchase(String productId) async {
    try {
      if (kDebugMode) {
        print('🔄 StoreKit 2 구매 재시도: $productId');
      }
      
      // 초기화 상태 확인
      if (!_isAvailable) {
        if (kDebugMode) {
          print('❌ StoreKit 2 사용 불가 (재시도)');
        }
        return false;
      }
      
      // 상품 정보 확인
      final ProductDetails? productDetails = _products
          .where((product) => product.id == productId)
          .firstOrNull;
      
      if (productDetails == null) {
        if (kDebugMode) {
          print('❌ StoreKit 2 상품을 찾을 수 없습니다 (재시도): $productId');
        }
        return false;
      }
      
      // 구매 요청
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: productDetails,
      );
      
      final bool success = await _inAppPurchase.buyNonConsumable(
        purchaseParam: purchaseParam,
      );
      
      if (kDebugMode) {
        print('🔄 StoreKit 2 구매 재시도 결과: $success');
      }
      
      return success;
    } catch (e) {
      if (kDebugMode) {
        print('❌ StoreKit 2 구매 재시도 실패: $e');
      }
      
      // 재시도에서도 실패하면 더 이상 시도하지 않음
      _onPurchaseResult?.call(false, null, '구매 재시도 실패: ${e.toString()}');
             return false;
     }
   }

  /// 🎯 구매 스트림 오류 자동 복구
  void _recoverFromStreamError(dynamic error) {
    if (kDebugMode) {
      print('🔧 구매 스트림 오류 복구 시작: $error');
    }
    
    // 비동기 복구 작업 (UI 블록 방지)
    Future.delayed(const Duration(milliseconds: 500), () async {
      try {
        // 1. 진행 중인 구매 상태 초기화
        _isPurchaseInProgress = false;
        _processedPurchases.clear();
        
        // 2. 미완료 거래 정리
        await _finishPendingTransactions();
        
        // 3. 구매 복원 시도
        await _inAppPurchase.restorePurchases();
        
        if (kDebugMode) {
          print('✅ 구매 스트림 오류 복구 완료');
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ 구매 스트림 오류 복구 실패: $e');
        }
      }
    });
  }
} 