import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../subscription/unified_subscription_manager.dart';
import '../notification/notification_service.dart';
import '../../constants/subscription_constants.dart';

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
  
  // 🎯 처리된 거래 추적 (재시도 가능하도록 개선)
  final Map<String, int> _processingAttempts = {}; // 거래별 시도 횟수
  final Map<String, DateTime> _lastProcessTime = {}; // 마지막 처리 시간
  static const int maxRetryAttempts = 3;
  static const Duration retryInterval = Duration(minutes: 1);
  
  // 🎯 콜백
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

      // 🔄 (디버그용) 앱 시작 시 미완료 거래를 정리하여 무한 루프 방지
      if (kDebugMode) {
        await clearPendingTransactions();
      }

      // 🧹 오래된 처리 기록 정리 (메모리 누수 방지)
      _processingAttempts.clear();
      _lastProcessTime.clear();

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

    // 구매 시작
    final success = await _inAppPurchase.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
    
    if (!success) {
      PurchaseLogger.error('Failed to start purchase for $productId');
      completer.complete(false);
    }
  }

  /// 🎧 단일 통합 구매 감지 리스너
  void _startContinuousPurchaseListener() {
    _purchaseSubscription = _inAppPurchase.purchaseStream.listen(
      (purchaseDetailsList) {
        // 🚨 중요: 여러 구매가 동시에 들어올 때 순차적으로 처리하여 경쟁 상태 방지
        Future.forEach<PurchaseDetails>(purchaseDetailsList, (details) async {
          await _handlePurchaseUpdate(details);
        });
      },
      onError: (error) {
        PurchaseLogger.error('Purchase stream error: $error');
      },
      onDone: () {
        PurchaseLogger.info('Purchase stream closed. Restarting...');
        // 스트림이 닫히면 자동으로 재시작
        _startContinuousPurchaseListener();
      },
    );
    PurchaseLogger.info('🎧 Single unified purchase listener started.');
  }

  /// 🔄 모든 구매 업데이트를 처리하는 단일 핸들러 (개선됨)
  Future<void> _handlePurchaseUpdate(PurchaseDetails details) async {
    final purchaseId = details.purchaseID;
    if (purchaseId == null) return;

    // 🚨 개선: 재시도 로직으로 처리 상태 확인
    if (!_shouldProcessPurchase(purchaseId)) {
      PurchaseLogger.info('Skipping purchase $purchaseId (max retries exceeded or recently processed)');
      return;
    }

    // 처리 시도 기록
    _processingAttempts[purchaseId] = (_processingAttempts[purchaseId] ?? 0) + 1;
    _lastProcessTime[purchaseId] = DateTime.now();
    
    final activePurchaseCompleter = _activePurchases[details.productID];
    final isDirectPurchase = activePurchaseCompleter != null;

    try {
      switch (details.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final success = await _processSuccessfulPurchase(details, showSnackbar: isDirectPurchase);
          if (success && isDirectPurchase && !activePurchaseCompleter.isCompleted) {
            activePurchaseCompleter.complete(true);
          } else if (!success && isDirectPurchase && !activePurchaseCompleter.isCompleted) {
            activePurchaseCompleter.complete(false);
          }
          break;
        case PurchaseStatus.error:
          PurchaseLogger.error('Purchase error: ${details.error?.message}');
          if (isDirectPurchase && !activePurchaseCompleter.isCompleted) {
            activePurchaseCompleter.complete(false);
          }
          break;
        case PurchaseStatus.canceled:
          PurchaseLogger.info('Purchase canceled by user.');
          if (isDirectPurchase && !activePurchaseCompleter.isCompleted) {
            activePurchaseCompleter.complete(false);
          }
          break;
        case PurchaseStatus.pending:
          PurchaseLogger.info('Purchase pending for ${details.productID}.');
          break;
      }

      if (details.pendingCompletePurchase) {
        await _completePurchase(details);
      }
    } catch (e) {
      PurchaseLogger.error('Error processing purchase $purchaseId: $e');
      // 에러 발생 시 재시도를 위해 시도 횟수 감소
      _processingAttempts[purchaseId] = (_processingAttempts[purchaseId] ?? 1) - 1;
      
      // 활성 구매가 있다면 실패로 처리
      if (isDirectPurchase && !activePurchaseCompleter.isCompleted) {
        activePurchaseCompleter.complete(false);
      }
    }
  }

  /// 🔍 구매 처리 여부 판단 (개선됨)
  bool _shouldProcessPurchase(String purchaseId) {
    final attempts = _processingAttempts[purchaseId] ?? 0;
    final lastProcessed = _lastProcessTime[purchaseId];
    
    // 최대 재시도 횟수 초과 시 건너뛰기
    if (attempts >= maxRetryAttempts) {
      return false;
    }
    
    // 최근에 처리했다면 일정 시간 후에 재시도
    if (lastProcessed != null && 
        DateTime.now().difference(lastProcessed) < retryInterval) {
      return false;
    }
    
    return true;
  }

  /// 🎉 구매 성공 처리를 위한 통합 메서드 (개선됨)
  Future<bool> _processSuccessfulPurchase(PurchaseDetails details, {required bool showSnackbar}) async {
    PurchaseLogger.info(
        'Processing successful purchase: ${details.productID}, Show Snackbar: $showSnackbar');

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      PurchaseLogger.error('User not authenticated for purchase processing.');
      return false;
    }

    final jwsRepresentation = _extractJWSRepresentation(details);
    if (jwsRepresentation == null) {
      PurchaseLogger.error('Failed to extract JWS for purchase.');
      return false;
    }

    final serverResponse = await _syncPurchaseInfo(user.uid, jwsRepresentation);

    if (serverResponse != null) {
      PurchaseLogger.info('서버 동기화 성공. 응답 데이터로 상태 업데이트 중...');
      if (kDebugMode) {
        PurchaseLogger.info('서버 응답: $serverResponse');
      }
      
      // 🎯 중요: 서버 응답 후 즉시 상태 업데이트 (한 번만!)
      UnifiedSubscriptionManager().updateStateWithServerResponse(serverResponse);
      
      if (showSnackbar) {
        _showSuccessSnackBar(details);
      }
      await _scheduleNotifications(details);
      
      // 성공 시 처리 기록 정리
      _processingAttempts.remove(details.purchaseID);
      _lastProcessTime.remove(details.purchaseID);
      
      return true;
    } else {
      PurchaseLogger.error('서버 동기화 실패 - 응답이 null입니다.');
      if (showSnackbar) {
        _showErrorSnackBar('구매 확인 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요.');
      }
      return false;
    }
  }
  
  /// 📱 성공 스낵바 표시 (중앙화된 메시지 사용)
  void _showSuccessSnackBar(PurchaseDetails details) {
    final scaffoldMessenger = _scaffoldMessengerKey?.currentState;
    if (scaffoldMessenger == null) return;

    // 🎯 중앙화된 상수에서 메시지 가져오기
    final message = SubscriptionConstants.getPurchaseSuccessMessage(details.productID);
    
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
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
  Future<Map<String, dynamic>?> _syncPurchaseInfo(String userId, String jwsRepresentation) async {
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
        // 성공 시 전체 응답 데이터 반환
        return result.data as Map<String, dynamic>;
      } else {
        PurchaseLogger.error('Purchase sync failed: ${result.data['error']}');
        return null;
      }
    } catch (e) {
      PurchaseErrorHandler.handleSyncError(e, userId, jwsRepresentation.length);
      return null;
    }
  }

  /// 🔄 UI 업데이트 -> 이제 UnifiedSubscriptionManager가 담당하므로 제거
  // Future<void> _updateUIAfterPurchase(String productId) async { ... }

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

  ProductDetails? _getProductById(String productId) {
    try {
      return _state.products.firstWhere((product) => product.id == productId);
    } catch (e) {
      return null;
    }
  }

  /// 🎯 설정 메서드들
  void setScaffoldMessengerKey(GlobalKey<ScaffoldMessengerState> key) {
    _scaffoldMessengerKey = key;
  }

  void setOnPurchaseResult(PurchaseResultCallback? callback) {
    // This callback is no longer used, but keeping it for now as per instructions.
    // If it's truly unused, it should be removed.
  }

  /// 🧹 정리
  void dispose() {
    PurchaseLogger.info('Disposing InAppPurchase service');
    _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    _activePurchases.clear();
    _processingAttempts.clear();
    _lastProcessTime.clear();
    _state = const PurchaseState();
    _scaffoldMessengerKey = null;
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