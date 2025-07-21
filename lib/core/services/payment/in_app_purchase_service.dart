import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../subscription/unified_subscription_manager.dart';
import '../notification/notification_service.dart';
import '../../constants/subscription_constants.dart';

/// 🎯 구매 결과 모델
class PurchaseResult {
  final bool success;
  final String? transactionId;
  final String? productId;
  final String? errorMessage;
  final String? successMessage;
  final Map<String, dynamic>? serverResponse;
  
  const PurchaseResult({
    required this.success,
    this.transactionId,
    this.productId,
    this.errorMessage,
    this.successMessage,
    this.serverResponse,
  });
  
  factory PurchaseResult.success({
    required String transactionId,
    required String productId,
    String? successMessage,
    Map<String, dynamic>? serverResponse,
  }) {
    return PurchaseResult(
      success: true,
      transactionId: transactionId,
      productId: productId,
      successMessage: successMessage ?? SubscriptionConstants.getPurchaseSuccessMessage(productId),
      serverResponse: serverResponse,
    );
  }
  
  factory PurchaseResult.failure({
    String? transactionId,
    String? productId,
    required String errorMessage,
  }) {
    return PurchaseResult(
      success: false,
      transactionId: transactionId,
      productId: productId,
      errorMessage: errorMessage,
    );
  }
}

/// 🎯 구매 성공 처리 핸들러 (책임 분리)
class PurchaseSuccessHandler {
  final UnifiedSubscriptionManager _subscriptionManager;
  final NotificationService _notificationService;
  
  PurchaseSuccessHandler({
    UnifiedSubscriptionManager? subscriptionManager,
    NotificationService? notificationService,
  }) : _subscriptionManager = subscriptionManager ?? UnifiedSubscriptionManager(),
       _notificationService = notificationService ?? NotificationService();
  
  /// 구매 성공 시 상태 업데이트 및 알림 처리
  Future<PurchaseResult> handleSuccess(
    PurchaseDetails details,
    Map<String, dynamic> serverResponse,
  ) async {
    try {
      // 1. 상태 업데이트
      _subscriptionManager.updateStateWithServerResponse(serverResponse);
      
      // 2. 알림 스케줄링 (무료체험 구매 시에만)
      if (_shouldScheduleNotifications(details.productID, serverResponse)) {
        await _scheduleNotifications(details);
      }
      
      return PurchaseResult.success(
        transactionId: details.purchaseID ?? '',
        productId: details.productID,
        serverResponse: serverResponse,
      );
    } catch (e) {
      PurchaseLogger.error('Purchase success handling failed: $e');
      return PurchaseResult.failure(
        transactionId: details.purchaseID,
        productId: details.productID,
        errorMessage: '구매 처리 중 오류가 발생했습니다.',
      );
    }
  }
  
  /// 알림 스케줄링이 필요한지 확인 (무료체험 구매 시에만)
  bool _shouldScheduleNotifications(String productId, Map<String, dynamic> serverResponse) {
    // 🎯 월간 구독이 아니면 알림 설정 안 함
    if (productId != InAppPurchaseService.premiumMonthlyId) {
      return false;
    }
    
    // 🎯 서버 응답에서 무료체험 여부 확인
    final entitlement = serverResponse['entitlement'] as String?;
    final subscriptionStatus = serverResponse['subscriptionStatus'];
    
    // entitlement가 'TRIAL'이거나 subscriptionStatus가 8(TRIAL)인 경우에만 알림 설정
    final isTrial = entitlement?.toUpperCase() == 'TRIAL' || subscriptionStatus == 8;
    
    if (kDebugMode) {
      PurchaseLogger.info('🔔 알림 스케줄링 체크:');
      PurchaseLogger.info('   - productId: $productId');
      PurchaseLogger.info('   - entitlement: $entitlement');
      PurchaseLogger.info('   - subscriptionStatus: $subscriptionStatus');
      PurchaseLogger.info('   - isTrial: $isTrial');
    }
    
    return isTrial;
  }
  
  /// 알림 스케줄링
  Future<void> _scheduleNotifications(PurchaseDetails details) async {
    try {
      await _notificationService.scheduleTrialEndNotifications(DateTime.now());
      PurchaseLogger.info('Notifications scheduled for ${details.productID}');
    } catch (e) {
      PurchaseLogger.error('Failed to schedule notifications: $e');
      // 알림 실패는 구매 성공에 영향을 주지 않음
    }
  }
}

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



/// 🚀 In-App Purchase 서비스 (리팩토링된 버전)
class InAppPurchaseService {
  static final InAppPurchaseService _instance = InAppPurchaseService._internal();
  factory InAppPurchaseService() => _instance;
  InAppPurchaseService._internal();

  // 🎯 의존성
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final PurchaseSuccessHandler _successHandler = PurchaseSuccessHandler();
  
  // 🎯 상태 관리
  PurchaseState _state = const PurchaseState();
  
  // 🎯 구매 스트림 관리
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  
  // 🎯 처리된 거래 추적 (중복 방지)
  final Map<String, int> _processingAttempts = {};
  final Map<String, DateTime> _lastProcessTime = {};
  final Set<String> _successfullyProcessed = {};
  final Map<String, String> _processedJWS = {}; // JWS 해시 -> 거래 ID
  
  static const int maxRetryAttempts = 3;
  static const Duration retryInterval = Duration(minutes: 5);
  
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

      // 🔄 앱 시작 시 미완료 거래 정리 (항상 실행)
      await clearPendingTransactions();

      // 🧹 처리 기록 초기화
      _clearProcessingRecords();

      await _loadProducts();
      _startPurchaseListener();

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

  /// 🛒 구매 실행 (단순화된 버전)
  Future<PurchaseResult> buyProduct(String productId) async {
    await _ensureInitialized();
    
    if (_state.isPurchasing) {
      return PurchaseResult.failure(
        productId: productId,
        errorMessage: '이미 구매가 진행 중입니다.',
      );
    }
    
    final product = _getProductById(productId);
    if (product == null) {
      return PurchaseResult.failure(
        productId: productId,
        errorMessage: '상품을 찾을 수 없습니다.',
      );
    }

    try {
      _state = _state.copyWith(isPurchasing: true);
      PurchaseLogger.info('Starting purchase for: $productId');
      
      // 🎯 단순화: purchaseStream에서 결과를 기다림
      final success = await _inAppPurchase.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
      );
      
      if (!success) {
        return PurchaseResult.failure(
          productId: productId,
          errorMessage: '구매를 시작할 수 없습니다.',
        );
      }
      
      // 🎯 구매 시작 성공 - 실제 결과는 purchaseStream에서 처리
      return PurchaseResult.success(
        transactionId: '', // purchaseStream에서 업데이트됨
        productId: productId,
        successMessage: '구매가 시작되었습니다.',
      );
      
    } catch (e) {
      PurchaseLogger.error('Purchase failed: $e');
      return PurchaseResult.failure(
        productId: productId,
        errorMessage: '구매 중 오류가 발생했습니다.',
      );
    } finally {
      _state = _state.copyWith(isPurchasing: false);
    }
  }

  /// 🎧 구매 스트림 리스너 (단순화됨)
  void _startPurchaseListener() {
    _purchaseSubscription = _inAppPurchase.purchaseStream.listen(
      (purchaseDetailsList) {
        for (final details in purchaseDetailsList) {
          _handlePurchaseUpdate(details);
        }
      },
      onError: (error) {
        PurchaseLogger.error('Purchase stream error: $error');
      },
    );
    PurchaseLogger.info('🎧 Purchase listener started');
  }

  /// 🔄 구매 업데이트 처리 (restored 구매 개선)
  Future<void> _handlePurchaseUpdate(PurchaseDetails details) async {
    final purchaseId = details.purchaseID;
    if (purchaseId == null) {
      PurchaseLogger.warning('Purchase ID is null, skipping: ${details.productID}');
      return;
    }

    if (kDebugMode) {
      PurchaseLogger.info('🔄 Processing purchase: $purchaseId (${details.status})');
    }

    // 🎯 Restored 구매 특별 처리 (중복 방지 강화)
    if (details.status == PurchaseStatus.restored) {
      if (kDebugMode) {
        PurchaseLogger.info('🔄 Restored purchase detected: $purchaseId');
      }
      
      // Restored 구매는 이미 처리된 경우 즉시 스킵
      if (_successfullyProcessed.contains(purchaseId)) {
        if (kDebugMode) {
          PurchaseLogger.info('⏭️ Restored purchase already processed, skipping: $purchaseId');
        }
        // 구매 완료 처리만 하고 서버 동기화는 스킵
        if (details.pendingCompletePurchase) {
          await _completePurchase(details);
        }
        return;
      }
    }

    // 🚨 일반 중복 처리 방지
    if (!_shouldProcessPurchase(purchaseId)) {
      return;
    }

    // 처리 시도 기록
    _processingAttempts[purchaseId] = (_processingAttempts[purchaseId] ?? 0) + 1;
    _lastProcessTime[purchaseId] = DateTime.now();

    try {
      switch (details.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _processSuccessfulPurchase(details);
          break;
        case PurchaseStatus.error:
          PurchaseLogger.error('Purchase error: ${details.error?.message}');
          break;
        case PurchaseStatus.canceled:
          PurchaseLogger.info('Purchase canceled by user');
          break;
        case PurchaseStatus.pending:
          PurchaseLogger.info('Purchase pending');
          break;
      }

      // 구매 완료 처리
      if (details.pendingCompletePurchase) {
        await _completePurchase(details);
      }
    } catch (e) {
      PurchaseLogger.error('Error processing purchase $purchaseId: $e');
      // 에러 시 재시도를 위해 시도 횟수 감소
      _processingAttempts[purchaseId] = (_processingAttempts[purchaseId] ?? 1) - 1;
    }
  }

  /// 🎉 구매 성공 처리 (단순화됨)
  Future<void> _processSuccessfulPurchase(PurchaseDetails details) async {
    PurchaseLogger.info('Processing successful purchase: ${details.productID}');

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      PurchaseLogger.error('User not authenticated');
      return;
    }

    final jwsRepresentation = _extractJWSRepresentation(details);
    if (jwsRepresentation == null) {
      PurchaseLogger.error('Failed to extract JWS');
      return;
    }

    // 🚨 JWS 중복 처리 방지
    final jwsHash = jwsRepresentation.hashCode.toString();
    if (_processedJWS.containsKey(jwsHash)) {
      PurchaseLogger.info('JWS already processed: $jwsHash');
      return;
    }

    // 서버 동기화
    final serverResponse = await _syncPurchaseInfo(user.uid, jwsRepresentation);
    if (serverResponse == null) {
      PurchaseLogger.error('Server sync failed');
      return;
    }

    // 🎯 성공 처리를 PurchaseSuccessHandler에 위임
    final result = await _successHandler.handleSuccess(details, serverResponse);
    
    if (result.success) {
      // JWS 처리 기록
      if (details.purchaseID != null) {
        _processedJWS[jwsHash] = details.purchaseID!;
        _successfullyProcessed.add(details.purchaseID!);
      }
      
      // 처리 기록 정리
      _processingAttempts.remove(details.purchaseID);
      _lastProcessTime.remove(details.purchaseID);
      
      // 🎯 Restored 구매의 경우 추가 로깅
      if (details.status == PurchaseStatus.restored) {
        PurchaseLogger.info('Restored purchase processed successfully: ${details.productID} (${details.purchaseID})');
      } else {
        PurchaseLogger.info('Purchase processed successfully: ${details.productID}');
      }
    } else {
      PurchaseLogger.error('Purchase success handling failed: ${result.errorMessage}');
    }
  }
  


  /// 🧹 처리 기록 초기화
  void _clearProcessingRecords() {
    _processingAttempts.clear();
    _lastProcessTime.clear();
    _successfullyProcessed.clear();
    _processedJWS.clear();
  }

  /// 🔍 구매 처리 여부 판단
  bool _shouldProcessPurchase(String purchaseId) {
    // 🚨 1. 이미 성공적으로 처리된 거래는 완전 차단
    if (_successfullyProcessed.contains(purchaseId)) {
      PurchaseLogger.info('Skipping already successfully processed purchase: $purchaseId');
      return false;
    }
    
    final attempts = _processingAttempts[purchaseId] ?? 0;
    final lastProcessed = _lastProcessTime[purchaseId];
    
    // 🚨 2. 최대 재시도 횟수 초과 시 건너뛰기
    if (attempts >= maxRetryAttempts) {
      PurchaseLogger.warning('Purchase $purchaseId exceeded max retry attempts: $attempts');
      return false;
    }
    
    // 🚨 3. 최근에 처리했다면 일정 시간 후에 재시도
    if (lastProcessed != null && 
        DateTime.now().difference(lastProcessed) < retryInterval) {
      final remainingTime = retryInterval - DateTime.now().difference(lastProcessed);
      PurchaseLogger.info('Purchase $purchaseId still in cooldown. Remaining: ${remainingTime.inMinutes}m ${remainingTime.inSeconds % 60}s');
      return false;
    }
    
    return true;
  }

  /// 🔄 서버 동기화
  Future<Map<String, dynamic>?> _syncPurchaseInfo(String userId, String jwsRepresentation) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        PurchaseLogger.error('User not authenticated during sync');
        return null;
      }
      
      PurchaseLogger.info('Syncing purchase info for user: $userId');
      
      final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
      final result = await functions.httpsCallable('syncPurchaseInfo').call({
        'jwsRepresentation': jwsRepresentation,
        'userId': userId,
        'userEmail': user.email,
        'firebaseUid': user.uid,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
      
      final success = result.data['success'] as bool? ?? false;
      if (success) {
        PurchaseLogger.info('Purchase sync successful for user: $userId');
        return result.data as Map<String, dynamic>;
      } else {
        PurchaseLogger.error('Purchase sync failed for user $userId: ${result.data['error']}');
        return null;
      }
    } catch (e) {
      PurchaseErrorHandler.handleSyncError(e, userId, jwsRepresentation.length);
      return null;
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



  /// 🧹 정리
  void dispose() {
    PurchaseLogger.info('Disposing InAppPurchase service');
    _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    _clearProcessingRecords();
    _state = const PurchaseState();
  }

  /// 🎯 편의 메서드들 (PurchaseResult 반환으로 변경)
  Future<PurchaseResult> buyMonthly() => buyProduct(premiumMonthlyId);
  Future<PurchaseResult> buyYearly() => buyProduct(premiumYearlyId);

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

  /// 🧹 미완료 거래 정리 (Restored 구매 대응 강화)
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
      int processedCount = 0;

      final timeout = Timer(const Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          PurchaseLogger.warning('Clearing pending transactions timed out after 10 seconds.');
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
            // 🎯 Restored 구매는 즉시 성공 처리 기록에 추가하여 중복 방지
            if (details.status == PurchaseStatus.restored && details.purchaseID != null) {
              _successfullyProcessed.add(details.purchaseID!);
              PurchaseLogger.info('Pre-marked restored purchase as processed: ${details.purchaseID}');
            }
            
            await _completePurchase(details);
            processedCount++;
          }
          
          if (!completer.isCompleted) {
            PurchaseLogger.info('Finished clearing batch of $processedCount transactions.');
            timeout.cancel();
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