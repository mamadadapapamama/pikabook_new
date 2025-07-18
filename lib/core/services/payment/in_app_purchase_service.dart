import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:collection/collection.dart';

import '../subscription/unified_subscription_manager.dart';
import '../notification/notification_service.dart';
import '../common/usage_limit_service.dart';
import '../cache/event_cache_manager.dart';

/// 🎯 구매 상태 관리
class PurchaseState {
  final bool isInitialized;
  final bool isAvailable;
  final List<ProductDetails> products;
  final bool isPurchasing;
  final Set<String> scheduledNotifications;
  
  const PurchaseState({
    this.isInitialized = false,
    this.isAvailable = false,
    this.products = const [],
    this.isPurchasing = false,
    this.scheduledNotifications = const {},
  });
  
  PurchaseState copyWith({
    bool? isInitialized,
    bool? isAvailable,
    List<ProductDetails>? products,
    bool? isPurchasing,
    Set<String>? scheduledNotifications,
  }) {
    return PurchaseState(
      isInitialized: isInitialized ?? this.isInitialized,
      isAvailable: isAvailable ?? this.isAvailable,
      products: products ?? this.products,
      isPurchasing: isPurchasing ?? this.isPurchasing,
      scheduledNotifications: scheduledNotifications ?? this.scheduledNotifications,
    );
  }
}

/// 📝 구매 로거
class PurchaseLogger {
  static const _tag = '[InAppPurchase]';
  
  static void info(String message) {
    if (kDebugMode) print('$_tag INFO: $message');
  }
  
  static void warning(String message) {
    if (kDebugMode) print('$_tag WARNING: $message');
  }
  
  static void error(String message) {
    if (kDebugMode) print('$_tag ERROR: $message');
  }
}

/// 🔧 에러 처리
class PurchaseErrorHandler {
  static void handleSyncError(dynamic error, String userId, int jwsLength) {
    final errorType = _categorizeError(error);
    PurchaseLogger.error('Sync failed: $errorType - $error');
    
    if (errorType == 'SERVER_ERROR') {
      PurchaseLogger.error('Server error details: userId=$userId, jwsLength=$jwsLength');
    }
  }
  
  static String _categorizeError(dynamic error) {
    final errorStr = error.toString();
    if (errorStr.contains('INTERNAL')) return 'SERVER_ERROR';
    if (errorStr.contains('UNAUTHENTICATED')) return 'AUTH_ERROR';
    if (errorStr.contains('NOT_FOUND')) return 'FUNCTION_NOT_FOUND';
    return 'UNKNOWN';
  }
}

/// 🛒 구매 결과 콜백
typedef PurchaseResultCallback = void Function(bool success, String? transactionId, String? error);

/// 🚀 In-App Purchase 서비스 (최적화된 버전)
class InAppPurchaseService {
  static final InAppPurchaseService _instance = InAppPurchaseService._internal();
  factory InAppPurchaseService() => _instance;
  InAppPurchaseService._internal();

  // 🎯 의존성
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final NotificationService _notificationService = NotificationService();
  
  // 🎯 상태 관리
  PurchaseState _state = const PurchaseState();
  
  // 🎯 활성 구매 추적
  final Map<String, Completer<bool>> _activePurchases = {};
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  
  // 🎯 처리된 거래 추적 (무한 루프 방지)
  final Set<String> _processedTransactions = {};
  
  // 🎯 콜백
  PurchaseResultCallback? _onPurchaseResult;
  GlobalKey<ScaffoldMessengerState>? _scaffoldMessengerKey;
  
  // 🎯 상품 ID
  static const String premiumMonthlyId = 'premium_monthly';
  static const String premiumYearlyId = 'premium_yearly';
  static const Set<String> _productIds = {premiumMonthlyId, premiumYearlyId};

  // 🎯 Getters
  bool get isInitialized => _state.isInitialized;
  bool get isAvailable => _state.isAvailable;
  bool get isPurchasing => _state.isPurchasing;
  List<ProductDetails> get products => _state.products;
  
  ProductDetails? get monthlyProduct => _getProductById(premiumMonthlyId);
  ProductDetails? get yearlyProduct => _getProductById(premiumYearlyId);

  /// 🚀 초기화
  Future<void> initialize() async {
    if (_state.isInitialized) return;
    
    try {
      PurchaseLogger.info('Initializing InAppPurchase service');
      
      final isAvailable = await _inAppPurchase.isAvailable();
      if (!isAvailable) {
        PurchaseLogger.warning('InAppPurchase not available');
        return;
      }

      await _loadProducts();

      // 지속적인 구매 감지 리스너 시작
      _startContinuousPurchaseListener();

      _state = _state.copyWith(
        isInitialized: true,
        isAvailable: isAvailable,
      );
      
      PurchaseLogger.info('InAppPurchase service initialized successfully');
    } catch (e) {
      PurchaseLogger.error('Failed to initialize: $e');
    }
  }

  /// 📦 상품 로드
  Future<void> _loadProducts() async {
    try {
      final response = await _inAppPurchase.queryProductDetails(_productIds);
      
      if (response.error != null) {
        PurchaseLogger.error('Failed to load products: ${response.error}');
        return;
      }

      _state = _state.copyWith(products: response.productDetails);
      PurchaseLogger.info('Loaded ${response.productDetails.length} products');
    } catch (e) {
      PurchaseLogger.error('Error loading products: $e');
    }
  }

  /// 🛒 구매 실행
  Future<bool> buyProduct(String productId) async {
    await _ensureInitialized();
    
    // 중복 구매 방지
    if (_activePurchases.containsKey(productId)) {
      PurchaseLogger.warning('Purchase already in progress for $productId');
      return _activePurchases[productId]!.future;
    }
    
    final completer = Completer<bool>();
    _activePurchases[productId] = completer;
    
    try {
      _state = _state.copyWith(isPurchasing: true);
      await _executePurchase(productId, completer);
      return await completer.future;
    } catch (e) {
      PurchaseLogger.error('Purchase execution failed: $e');
      if (!completer.isCompleted) completer.complete(false);
      return false;
    } finally {
      _activePurchases.remove(productId);
      _state = _state.copyWith(isPurchasing: false);
    }
  }

  /// ⚡ 구매 실행 로직
  Future<void> _executePurchase(String productId, Completer<bool> completer) async {
    final product = _getProductById(productId);
    if (product == null) {
      PurchaseLogger.error('Product not found: $productId');
      completer.complete(false);
        return;
      }

    // 구매 시작 시간을 기준으로 최신 거래만 처리하기 위함
    final purchaseStartTime = DateTime.now();

    // 구매 결과 리스너 설정
    _setupPurchaseResultListener(productId, completer, purchaseStartTime);
    
    // 구매 시작
    final success = await _inAppPurchase.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
    
    if (!success) {
      PurchaseLogger.error('Failed to start purchase for $productId');
      _purchaseSubscription?.cancel();
      _purchaseSubscription = null;
      completer.complete(false);
    }
  }

  /// 🎧 구매 결과 리스너 설정
  void _setupPurchaseResultListener(String productId, Completer<bool> completer, DateTime purchaseStartTime) {
    _purchaseSubscription?.cancel();
    
    _purchaseSubscription = _inAppPurchase.purchaseStream.listen(
      (purchaseDetails) => _handlePurchaseUpdates(purchaseDetails, productId, completer, purchaseStartTime),
      onError: (error) {
        PurchaseLogger.error('Purchase stream error: $error');
        if (!completer.isCompleted) completer.complete(false);
      },
    );
  }

  /// 🎧 지속적인 구매 감지 리스너 (외부 구독 변경 감지용)
  void _startContinuousPurchaseListener() {
    _purchaseSubscription = _inAppPurchase.purchaseStream.listen(
      (purchaseDetailsList) {
        for (var details in purchaseDetailsList) {
          _handleContinuousPurchaseUpdate(details);
        }
      },
      onError: (error) {
        PurchaseLogger.error('Continuous purchase stream error: $error');
      },
      onDone: () {
        PurchaseLogger.info('Continuous purchase stream closed. Restarting...');
        _startContinuousPurchaseListener();
      },
    );
    PurchaseLogger.info('🎧 Continuous purchase listener started.');
  }

  /// 🔄 지속적인 구매 업데이트 처리 (웹훅처럼 동작)
  Future<void> _handleContinuousPurchaseUpdate(PurchaseDetails details) async {
    PurchaseLogger.info('[Continuous] Detected purchase update for ${details.productID}, status: ${details.status}');
    
    // 구매 완료, 복원, 보류 중인 구매 모두 처리
    if (details.status == PurchaseStatus.purchased || details.status == PurchaseStatus.restored) {
        final purchaseId = details.purchaseID;
        if (purchaseId != null && _processedTransactions.contains(purchaseId)) {
            return; // 이미 처리된 거래는 무시
        }

        PurchaseLogger.info('[Continuous] New successful purchase detected: ${details.purchaseID}');
        await _handlePurchaseSuccess(details);

        if (purchaseId != null) {
            _processedTransactions.add(purchaseId);
        }
    }
    
    // App Store에서 온 모든 거래는 완료 처리(complete)하여 결제 대기열에서 제거
    await _completePurchase(details);
  }


  /// 🔄 구매 업데이트 처리
  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchaseDetails,
    String productId,
    Completer<bool> completer,
    DateTime purchaseStartTime,
  ) async {
    for (final details in purchaseDetails) {
      if (details.productID != productId) continue;
      
      // 오래된 거래는 현재 구매 흐름에 영향을 주지 않도록 처리
      final transactionTimeMillis = int.tryParse(details.transactionDate ?? '');
      if (transactionTimeMillis != null) {
        final transactionTime = DateTime.fromMillisecondsSinceEpoch(transactionTimeMillis);
        // 기기와 서버 시간 차이를 고려해 2초 여유시간을 둠
        if (transactionTime.isBefore(purchaseStartTime.subtract(const Duration(seconds: 2)))) {
          PurchaseLogger.info("Ignoring stale transaction: ${details.purchaseID}");
          continue;
        }
      }

      // 이미 처리된 거래인지 확인 (purchaseID 사용)
      final transactionId = details.purchaseID;
      if (transactionId != null && _processedTransactions.contains(transactionId)) {
        PurchaseLogger.info('Transaction already processed: $transactionId');
        continue;
      }
      
      switch (details.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _handlePurchaseSuccess(details);
          if (!completer.isCompleted) completer.complete(true);
          break;
        case PurchaseStatus.error:
          PurchaseLogger.error('Purchase error: ${details.error}');
          if (!completer.isCompleted) completer.complete(false);
          break;
        case PurchaseStatus.canceled:
          PurchaseLogger.info('Purchase canceled by user');
          if (!completer.isCompleted) completer.complete(false);
          break;
        case PurchaseStatus.pending:
          PurchaseLogger.info('Purchase pending');
          break;
      }
      
      // 구매 완료 처리
      await _completePurchase(details);
      
      // 처리된 거래로 표시
      if (transactionId != null) {
        _processedTransactions.add(transactionId);
      }
    }
    
    // 구매 완료 후 스트림 구독 해제 -> 이제 지속적 리스너로 전환
    // _purchaseSubscription?.cancel();
    // _purchaseSubscription = null;
  }

  /// 🎉 구매 성공 처리
  Future<void> _handlePurchaseSuccess(PurchaseDetails details) async {
    PurchaseLogger.info('Purchase successful: ${details.productID}');
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      PurchaseLogger.error('User not authenticated');
      return;
    }
    
    final jwsRepresentation = _extractJWSRepresentation(details);
    if (jwsRepresentation == null) {
      PurchaseLogger.error('Failed to extract JWS representation');
      return;
    }
    
    // 서버 동기화 먼저 수행
    final syncSuccess = await _syncPurchaseInfo(user.uid, jwsRepresentation);
    
    // 서버 동기화 성공 시에만 성공 스낵바 표시
    if (syncSuccess) {
      _showSuccessSnackBar(details);
    } else {
      _showErrorSnackBar('구매 확인 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.');
    }
    
    // UI 업데이트와 알림 스케줄링은 병렬로 처리
    await Future.wait([
      _updateUIAfterPurchase(details.productID),
      _scheduleNotifications(details),
    ]);
  }

  /// 📱 성공 스낵바 표시
  void _showSuccessSnackBar(PurchaseDetails details) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final message = details.productID == premiumMonthlyId
          ? '프리미엄 월간 플랜이 시작되었습니다!'
          : '프리미엄 연간 플랜이 시작되었습니다!';
      
      _scaffoldMessengerKey?.currentState?.showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
    });
  }

  /// 📱 에러 스낵바 표시
  void _showErrorSnackBar(String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scaffoldMessengerKey?.currentState?.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    });
  }

  /// 🔄 서버 동기화
  Future<bool> _syncPurchaseInfo(String userId, String jwsRepresentation) async {
    try {
      PurchaseLogger.info('Syncing purchase info');
      
      final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
      final result = await functions.httpsCallable('syncPurchaseInfo').call({
        'jwsRepresentation': jwsRepresentation,
        'userId': userId,
      });
      
      final success = result.data['success'] as bool? ?? false;
      if (success) {
        PurchaseLogger.info('Purchase sync successful');
        return true;
      } else {
        PurchaseLogger.error('Purchase sync failed: ${result.data['error']}');
        return false;
      }
    } catch (e) {
      PurchaseErrorHandler.handleSyncError(e, userId, jwsRepresentation.length);
      return false;
    }
  }

  /// 🔄 UI 업데이트
  Future<void> _updateUIAfterPurchase(String productId) async {
    final subscriptionManager = UnifiedSubscriptionManager();
    subscriptionManager.invalidateCache();
    
    // 다른 서비스 캐시도 무효화
    UsageLimitService().clearUserCache();
    EventCacheManager().clearAllCache();
    
    PurchaseLogger.info('UI updated after purchase');
  }

  /// 🔔 알림 스케줄링
  Future<void> _scheduleNotifications(PurchaseDetails details) async {
    if (details.productID != premiumMonthlyId) return;

    // Use transaction ID for idempotent check
    final transactionId = details.purchaseID;
    if (transactionId == null || transactionId.isEmpty) {
      PurchaseLogger.warning('Cannot schedule notifications without a purchase ID.');
      return;
    }
    
    if (_state.scheduledNotifications.contains(transactionId)) {
        PurchaseLogger.info('Notifications already scheduled for transaction: $transactionId');
        return;
    }
      
    try {
      await _notificationService.scheduleTrialEndNotifications(DateTime.now());
      
      _state = _state.copyWith(
        scheduledNotifications: {..._state.scheduledNotifications, transactionId},
      );
      
      PurchaseLogger.info('Notifications scheduled');
    } catch (e) {
      PurchaseLogger.error('Failed to schedule notifications: $e');
    }
  }

  /// 🔍 JWS 추출
  String? _extractJWSRepresentation(PurchaseDetails details) {
    try {
      final verificationData = details.verificationData;
      if (verificationData.serverVerificationData.isNotEmpty) {
        return verificationData.serverVerificationData;
      }
      return null;
    } catch (e) {
      PurchaseLogger.error('Failed to extract JWS: $e');
      return null;
    }
  }

  /// ✅ 구매 완료 처리
  Future<void> _completePurchase(PurchaseDetails details) async {
    try {
      if (details.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(details);
        PurchaseLogger.info('Purchase completed: ${details.productID}');
      }
    } catch (e) {
      PurchaseLogger.error('Failed to complete purchase: $e');
    }
  }

  /// 🎯 헬퍼 메서드들
  Future<void> _ensureInitialized() async {
    if (!_state.isInitialized) {
      await initialize();
    }
  }

  ProductDetails? _getProductById(String productId) => 
      _state.products.firstWhereOrNull((product) => product.id == productId);

  /// 🎯 설정 메서드들
  void setScaffoldMessengerKey(GlobalKey<ScaffoldMessengerState> key) {
    _scaffoldMessengerKey = key;
  }

  void setOnPurchaseResult(PurchaseResultCallback? callback) {
    _onPurchaseResult = callback;
  }

  /// 🧹 정리
  void dispose() {
    PurchaseLogger.info('Disposing InAppPurchase service');
    _purchaseSubscription?.cancel();
    _activePurchases.clear();
    _processedTransactions.clear();
    _state = const PurchaseState();
    _onPurchaseResult = null;
  }

  /// 🎯 편의 메서드들
  Future<bool> buyMonthly() => buyProduct(premiumMonthlyId);
  Future<bool> buyYearly() => buyProduct(premiumYearlyId);

  /// 🔄 구매 복원
  Future<void> restorePurchases() async {
    await _ensureInitialized();
    try {
      PurchaseLogger.info('Restoring purchases...');
      await _inAppPurchase.restorePurchases();
      PurchaseLogger.info('Restore purchases successful');
    } catch (e) {
      PurchaseLogger.error('Failed to restore purchases: $e');
    }
  }

  /// 🧹 미완료 거래 정리 (디버그용)
  Future<void> clearPendingTransactions() async {
    PurchaseLogger.info('Clearing all pending transactions...');
    
    try {
      if (!_state.isAvailable) {
        final isAvailable = await _inAppPurchase.isAvailable();
        if (!isAvailable) {
          PurchaseLogger.warning('InAppPurchase not available, cannot clear transactions.');
          return;
        }
      }

      final completer = Completer<void>();
      late StreamSubscription<List<PurchaseDetails>> subscription;

      final timeout = Timer(const Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          PurchaseLogger.warning('Clearing pending transactions timed out after 5 seconds.');
          subscription.cancel();
          completer.complete();
        }
      });

      subscription = _inAppPurchase.purchaseStream.listen(
        (detailsList) async {
          if (detailsList.isEmpty) {
            PurchaseLogger.info('No more pending transactions to clear.');
            if (!completer.isCompleted) {
              timeout.cancel();
              subscription.cancel();
              completer.complete();
            }
            return;
          }

          PurchaseLogger.info('Found ${detailsList.length} pending transactions. Clearing...');
          for (final details in detailsList) {
            await _completePurchase(details);
          }
          
          if (!completer.isCompleted) {
            PurchaseLogger.info('Finished clearing batch of transactions.');
            timeout.cancel(); // Reset timer after processing a batch
            subscription.cancel();
            completer.complete();
          }
        },
        onDone: () {
          PurchaseLogger.info('Purchase stream closed during cleanup.');
          if (!completer.isCompleted) {
            timeout.cancel();
            completer.complete();
          }
        },
        onError: (error) {
          PurchaseLogger.error('Error during transaction cleanup: $error');
          if (!completer.isCompleted) {
            timeout.cancel();
            subscription.cancel();
            completer.completeError(error);
          }
        },
      );

      return completer.future;

      } catch (e) {
      PurchaseLogger.error('Exception during transaction cleanup: $e');
    }
  }
} 