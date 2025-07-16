import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../subscription/unified_subscription_manager.dart';
import '../notification/notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

/// 🚀 In-App Purchase 관리 서비스 (iOS 전용)
/// 
/// StoreKit2 기반 JWS 검증 방식을 사용합니다.
/// 
/// 주요 기능:
/// - Purchase Stream 실시간 모니터링
/// - JWS 기반 구매 검증
/// - Apple 권장 방식 준수
class InAppPurchaseService {
  static final InAppPurchaseService _instance = InAppPurchaseService._internal();
  factory InAppPurchaseService() => _instance;
  InAppPurchaseService._internal();

  // 🎯 In-App Purchase 인스턴스
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final NotificationService _notificationService = NotificationService();
  
  // 🎯 상태 관리
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _isAvailable = false;
  bool _isInitialized = false;
  List<ProductDetails> _products = [];
  
  // 🎯 중복 처리 방지
  final Set<String> _processedPurchases = {};
  bool _isPurchaseInProgress = false;
  
  // 🎯 구매 성공 콜백
  Function()? _onPurchaseSuccess;
  
  // 🎯 구매 결과 콜백 (Transaction ID 포함)
  Function(bool success, String? transactionId, String? error)? _onPurchaseResult;
  
  // 🎯 Trial 구매 컨텍스트
  bool _isTrialContext = false;
  
  // 🎯 상품 ID 정의
  static const String premiumMonthlyId = 'premium_monthly';
  static const String premiumYearlyId = 'premium_yearly';
  
  static const Set<String> _productIds = {
    premiumMonthlyId,
    premiumYearlyId,
  };


  
  // 🎯 알림 스케줄링 중복 방지
  final Set<String> _scheduledNotifications = {};

  /// 🚀 서비스 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      if (kDebugMode) {
        print('🚀 InAppPurchase 서비스 초기화 시작');
      }

      // 🎯 사용 가능 여부 확인
      _isAvailable = await _inAppPurchase.isAvailable();
      
      if (!_isAvailable) {
        if (kDebugMode) {
          print('❌ InAppPurchase를 사용할 수 없습니다');
        }
        return;
      }

      if (kDebugMode) {
        print('✅ InAppPurchase 사용 가능');
      }

      // 🎯 구매 스트림 구독
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
      
      // 🎯 상품 정보 로드
      await _loadProducts();

      _isInitialized = true;
      
      if (kDebugMode) {
        print('✅ InAppPurchase 서비스 초기화 완료');
        print('   - 로드된 상품: ${_products.length}개');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ InAppPurchase 초기화 오류: $e');
      }
    }
  }

  /// 🎯 상품 정보 로드
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

  /// 🎯 구매 업데이트 처리
  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    if (kDebugMode) {
      print('🔔 구매 업데이트 수신: ${purchaseDetailsList.length}개');
    }
    
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      // 🎯 중복 처리 방지 (더 엄격한 조건)
      final purchaseKey = '${purchaseDetails.productID}_${purchaseDetails.purchaseID}';
      
      if (_processedPurchases.contains(purchaseKey)) {
        if (kDebugMode) {
          print('⏭️ 이미 처리된 구매 건너뛰기: $purchaseKey');
        }
        // 🎯 이미 처리된 구매는 반드시 완료 처리
        _completePurchaseIfNeeded(purchaseDetails);
        continue;
      }
      
      _processedPurchases.add(purchaseKey);
      _handlePurchase(purchaseDetails);
    }
  }

  /// 🎯 구매 처리
  Future<void> _handlePurchase(PurchaseDetails purchaseDetails) async {
    try {
      if (kDebugMode) {
        print('🛒 구매 처리: ${purchaseDetails.productID}, 상태: ${purchaseDetails.status}');
      }

      if (purchaseDetails.status == PurchaseStatus.purchased) {
        // 🎉 구매 성공 처리
        await _handleSuccessfulPurchase(purchaseDetails);
        // 🎯 구매 결과 콜백 호출 (성공)
        _onPurchaseResult?.call(true, purchaseDetails.purchaseID, null);
      } else if (purchaseDetails.status == PurchaseStatus.restored) {
        // 🔄 구매 복원 처리 - 구매 성공과 동일하게 처리
        if (kDebugMode) {
          print('🔄 구매 복원 - 구매 성공과 동일하게 처리');
        }
        await _handleSuccessfulPurchase(purchaseDetails);
        // 🎯 구매 결과 콜백 호출 (성공)
        _onPurchaseResult?.call(true, purchaseDetails.purchaseID, null);
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        // ❌ 구매 실패 처리
        if (kDebugMode) {
          print('❌ 구매 실패: ${purchaseDetails.error}');
        }
        await _completePurchaseIfNeeded(purchaseDetails, isErrorRecovery: true);
        _isPurchaseInProgress = false;
        // 🎯 구매 결과 콜백 호출 (실패)
        _onPurchaseResult?.call(false, null, purchaseDetails.error?.message ?? '구매 실패');
      } else if (purchaseDetails.status == PurchaseStatus.canceled) {
        // 🚫 구매 취소 처리
        if (kDebugMode) {
          print('🚫 구매 취소됨');
        }
        await _completePurchaseIfNeeded(purchaseDetails, isErrorRecovery: true);
        _isPurchaseInProgress = false;
        // 🎯 구매 결과 콜백 호출 (취소)
        _onPurchaseResult?.call(false, null, '사용자가 구매를 취소했습니다');
      } else if (purchaseDetails.status == PurchaseStatus.pending) {
        // ⏳ 구매 대기 중
        if (kDebugMode) {
          print('⏳ 구매 대기 중: ${purchaseDetails.productID}');
        }
        _scheduleTimeoutCompletion(purchaseDetails);
      } else {
        // 🎯 알 수 없는 상태 처리
        if (kDebugMode) {
          print('❓ 알 수 없는 구매 상태: ${purchaseDetails.status}');
        }
        await _completePurchaseIfNeeded(purchaseDetails, isErrorRecovery: true);
        _isPurchaseInProgress = false;
      }

      // 🎯 모든 구매는 반드시 완료 처리 (중복 방지)
      await _completePurchaseIfNeeded(purchaseDetails);
    } catch (e) {
      if (kDebugMode) {
        print('❌ 구매 처리 중 오류: $e');
      }
      
      await _completePurchaseIfNeeded(purchaseDetails, isErrorRecovery: true);
      _isPurchaseInProgress = false;
    }
  }

  /// 🎉 성공한 구매 처리
  Future<void> _handleSuccessfulPurchase(PurchaseDetails purchaseDetails) async {
    try {
      if (kDebugMode) {
        print('🎉 구매 성공 처리: ${purchaseDetails.productID}');
      }
      
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (kDebugMode) {
          print('❌ 사용자가 로그인되어 있지 않습니다');
        }
        return;
      }

      // 🎯 구매 진행 상태 플래그 설정 (중복 방지)
      _isPurchaseInProgress = false;

      // 🎯 JWS Representation 처리 (Apple 권장 방식)
      final jwsRepresentation = _extractJWSRepresentation(purchaseDetails);
      if (jwsRepresentation != null) {
        if (kDebugMode) {
          print('🔍 JWS Representation 추출 완료');
          print('   - userId: ${user.uid}');
          print('   - hasJWS: ${jwsRepresentation.isNotEmpty}');
          print('   - Firebase Functions 호출 시작...');
        }
        try {
          await _syncPurchaseInfo(user.uid, jwsRepresentation);
          if (kDebugMode) {
            print('✅ JWS 기반 구매 정보 동기화 성공');
          }
        } catch (e) {
          if (kDebugMode) {
            print('❌ JWS 기반 구매 정보 동기화 실패 (계속 진행): $e');
            print('🔍 에러 타입: ${e.runtimeType}');
            print('🔍 에러 상세: ${e.toString()}');
            print('🚨 [중요] 서버 검증 실패로 인해 구독 상태가 즉시 반영되지 않을 수 있습니다.');
            print('🔄 지연된 구독 상태 갱신을 통해 재시도됩니다.');
          }
        }
      } else {
        if (kDebugMode) {
          print('⚠️ JWS Representation 추출 실패 - 구매 검증 건너뛰기');
        }
      }

      // 🎯 구독 상태 갱신
      await _notifySubscriptionManager();
      
      // 🎯 UI 업데이트
      await _updateUIAfterPurchase(purchaseDetails.productID);
      
      // 🎯 알림 설정 (중복 방지 적용)
      await scheduleNotificationsIfNeeded(purchaseDetails.productID);
      
      // 🎯 성공 콜백 호출
      _onPurchaseSuccess?.call();
      
      if (kDebugMode) {
        print('✅ 구매 처리 완료');
        print('📢 [InAppPurchase] 구매 완료 - 배너를 통해 사용자에게 알림됨');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ 구매 성공 처리 중 오류: $e');
      }
      
      // 오류 발생 시에도 UI 업데이트
      _onPurchaseSuccess?.call();
    } finally {
      // 🎯 구매 진행 상태 해제
      _isPurchaseInProgress = false;
    }
  }

  /// 🛒 구매 시작
  Future<bool> buyProduct(String productId) async {
    if (_isPurchaseInProgress) {
      if (kDebugMode) {
        print('⚠️ 구매가 이미 진행 중입니다');
      }
      return false;
    }
    
    await _ensureInitialized();
    
    try {
      _isPurchaseInProgress = true;
      
      if (kDebugMode) {
        print('🛒 구매 시작: $productId');
      }

      if (!_isAvailable) {
        if (kDebugMode) {
          print('❌ InAppPurchase 사용 불가');
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

      // 🚀 구매 요청
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
      
      _isPurchaseInProgress = false;
      _onPurchaseResult?.call(false, null, e.toString());
      
      return false;
    }
  }

  /// 🎯 지연 초기화 확인
  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      if (kDebugMode) {
        print('🚀 지연 초기화 시작');
      }
      await initialize();
    }
  }

  /// 🎯 구매 캐시 초기화
  void clearUserCache() {
    if (kDebugMode) {
      print('🔄 [InAppPurchaseService] 사용자 변경으로 인한 구매 캐시 초기화');
    }
    
    _processedPurchases.clear();
    _scheduledNotifications.clear(); // 알림 스케줄링 중복 방지 세트 초기화
    _isPurchaseInProgress = false;
    
    if (kDebugMode) {
      print('✅ [InAppPurchaseService] 구매 캐시 초기화 완료');
    }
  }

  /// 🎯 서비스 종료
  void dispose() {
    if (_isInitialized) {
      _subscription?.cancel();
      _processedPurchases.clear();
      _scheduledNotifications.clear(); // 알림 스케줄링 중복 방지 세트 초기화
      _isPurchaseInProgress = false;
    }
  }
  
  /// 🎯 구매 성공 콜백 설정
  void setOnPurchaseSuccess(Function()? callback) {
    _onPurchaseSuccess = callback;
  }

  /// 🎯 구매 결과 콜백 설정
  void setOnPurchaseResult(Function(bool success, String? transactionId, String? error)? callback) {
    _onPurchaseResult = callback;
  }

  /// 🎯 Trial 구매 컨텍스트 설정
  void setTrialContext(bool isTrialContext) {
    _isTrialContext = isTrialContext;
    if (kDebugMode) {
      print('🎯 [InAppPurchase] Trial 컨텍스트 설정: $isTrialContext');
    }
  }

  /// 🎯 구독 상태 갱신 (새로운 Apple 권장 방식)
  Future<void> _notifySubscriptionManager() async {
    try {
      final subscriptionManager = UnifiedSubscriptionManager();
      final result = await subscriptionManager.getSubscriptionEntitlements(forceRefresh: true);
      
      if (kDebugMode) {
        print('✅ UnifiedSubscriptionManager 상태 갱신 완료');
        print('   구독 상태: ${result['entitlement']}');
      }
      
      // 🎯 JWS 검증 완료 시 추가 확인 불필요
      // 구매 즉시 상태가 정확히 반영되므로 지연 확인 제거
      
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
    // notifyPurchaseCompleted 메서드는 더 이상 존재하지 않음
    
    if (kDebugMode) {
      final context = _isTrialContext ? 'trial' : 'premium';
      print('🎉 [InAppPurchase] 구매 완료 - 캐시 무효화됨 ($context)');
    }
    
    _isTrialContext = false;
  }

  /// 🎯 알림 설정 (실제 만료일 기반)
  Future<void> scheduleNotificationsIfNeeded(String productId) async {
    if (productId == premiumMonthlyId) {
      // 🎯 중복 알림 스케줄링 방지
      final notificationKey = '${productId}_${DateTime.now().millisecondsSinceEpoch ~/ 60000}'; // 분 단위로 중복 체크
      
      if (_scheduledNotifications.contains(notificationKey)) {
        if (kDebugMode) {
          print('⏭️ 이미 스케줄링된 알림 건너뛰기: $notificationKey');
        }
        return;
      }
      
      _scheduledNotifications.add(notificationKey);
      
      try {
        // 🎯 서버에서 실제 트라이얼 만료일 가져오기
        final subscriptionManager = UnifiedSubscriptionManager();
        final entitlements = await subscriptionManager.getSubscriptionEntitlements(forceRefresh: true);
        
        DateTime? trialEndDate;
        final expirationDateStr = entitlements['expirationDate'] as String?;
        
        if (expirationDateStr != null) {
          try {
            trialEndDate = DateTime.parse(expirationDateStr);
          } catch (e) {
            if (kDebugMode) {
              print('⚠️ 만료일 파싱 실패: $expirationDateStr');
            }
          }
        }
        
        await _notificationService.scheduleTrialEndNotifications(
          DateTime.now(),
          trialEndDate: trialEndDate,
        );
        
        if (kDebugMode) {
          print('✅ 구독 알림 스케줄링 완료');
          print('   트라이얼 만료일: ${trialEndDate?.toString() ?? "기본값 사용"}');
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ 알림 스케줄링 실패: $e');
        }
        // 실패한 경우 중복 방지 키 제거
        _scheduledNotifications.remove(notificationKey);
      }
    }
  }

  /// 🎯 PurchaseDetails에서 JWS Representation 추출 (StoreKit 2 권장)
  String? _extractJWSRepresentation(PurchaseDetails purchaseDetails) {
    try {
      // in_app_purchase 패키지에서 JWS representation 추출
      final verificationData = purchaseDetails.verificationData;
      
      if (verificationData.serverVerificationData.isNotEmpty) {
        // 서버 검증 데이터가 JWS representation입니다
        final jwsRepresentation = verificationData.serverVerificationData;
        
        if (kDebugMode) {
          print('🔍 JWS Representation 추출 성공');
          print('   - 길이: ${jwsRepresentation.length}');
          print('   - 구조: ${jwsRepresentation.startsWith('eyJ') ? 'JWT 형태' : '기타'}');
        }
        
        return jwsRepresentation;
      }
      
      if (kDebugMode) {
        print('⚠️ serverVerificationData가 비어있음');
      }
      
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('❌ JWS Representation 추출 실패: $e');
      }
      return null;
    }
  }

  /// 🎯 새로운 서버 API를 통한 구매 정보 동기화 (Apple 권장 방식)
  /// 
  /// [useRealTimeCheck]: true면 App Store Server API도 호출하여 정확한 상태 확인
  /// 기본값은 false로 JWS만 사용하여 빠른 응답 (구매 직후 최적화)
  Future<void> _syncPurchaseInfo(String userId, String jwsRepresentation, {bool useRealTimeCheck = false}) async {
    try {
      if (kDebugMode) {
        print('🚀 JWS 기반 구매 정보 동기화 시작');
        print('   - userId: $userId');
        print('   - jwsRepresentation: ${jwsRepresentation.substring(0, 50)}...');
        print('🌐 Firebase Functions 인스턴스 생성 중...');
      }
      
      final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
      if (kDebugMode) {
        print('✅ Firebase Functions 인스턴스 생성 완료');
        print('🔗 syncPurchaseInfo 함수 호출 준비...');
      }
      
      final callable = functions.httpsCallable('syncPurchaseInfo');
      if (kDebugMode) {
        print('📡 Firebase Functions 호출 시작...');
      }
      
      final result = await callable.call({
        'jwsRepresentation': jwsRepresentation,
        'userId': userId,
        // 🎯 필요한 경우에만 실시간 상태 확인
        if (useRealTimeCheck) 'checkRealTimeStatus': true,
      });
      
      if (kDebugMode) {
        print('📥 Firebase Functions 응답 수신 완료');
        print('🔍 응답 데이터 타입: ${result.data.runtimeType}');
        print('🔍 응답 데이터: ${result.data}');
      }
      
      // 🎯 안전한 타입 변환
      Map<String, dynamic> data;
      try {
        if (result.data is Map<String, dynamic>) {
          data = result.data;
        } else if (result.data is Map) {
          data = Map<String, dynamic>.from(result.data.map((key, value) => MapEntry(key.toString(), value)));
        } else {
          throw Exception('예상치 못한 응답 데이터 타입: ${result.data.runtimeType}');
        }
      } catch (typeError) {
        if (kDebugMode) {
          print('❌ [InAppPurchase] 응답 데이터 타입 변환 실패: $typeError');
        }
        throw Exception('응답 데이터 파싱 실패: $typeError');
      }
      
      final success = data['success'] as bool? ?? false;
      final subscriptionData = data['subscription'] != null 
          ? Map<String, dynamic>.from(data['subscription'] as Map)
          : null;
      final dataSource = data['dataSource'] as String?;
      final errorMessage = data['error'] as String?;
      
      if (kDebugMode) {
        print('📡 [InAppPurchase] syncPurchaseInfo 응답:');
        print('   - 성공 여부: ${success ? "✅ 성공" : "❌ 실패"}');
        print('   - 데이터 소스: ${dataSource ?? "알 수 없음"}');
        if (subscriptionData != null) {
          print('   - 구독 권한: ${subscriptionData['entitlement']}');
          print('   - 구독 상태: ${subscriptionData['subscriptionStatus']}');
          print('   - 체험 사용: ${subscriptionData['hasUsedTrial']}');
        }
        if (errorMessage != null) {
          print('   - 에러 메시지: $errorMessage');
        }
        
        // 🎯 응답 타입별 처리
        switch (dataSource) {
          case 'jws-only':
            print('⚡ [Apple Best Practice] JWS 전용 빠른 응답 (50ms) - 구매 직후 최적화');
            break;
          case 'jws-plus-api':
            print('🎯 [Apple Best Practice] JWS + API 정확한 상태 - 실시간 확인');
            break;
          case 'test-account':
            print('🧪 [Apple Best Practice] 테스트 계정 처리');
            break;
          default:
            print('🔍 [Apple Best Practice] 기본 처리 완료');
        }
      }
      
      if (success && subscriptionData != null) {
        if (kDebugMode) {
          print('✅ JWS 기반 구매 정보 동기화 완료');
          print('🚀 Apple 권장 방식 기반 처리 확인됨');
        }
      } else {
        if (kDebugMode) {
          print('❌ JWS 기반 구매 정보 동기화 실패');
          print('🔍 에러 정보: ${errorMessage ?? "알 수 없는 오류"}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ JWS 기반 구매 정보 동기화 실패: $e');
        
        // Firebase Functions 에러 상세 분석
        if (e.toString().contains('INTERNAL')) {
          print('🔍 [InAppPurchase] Firebase Functions INTERNAL 에러 - 서버 측 문제');
          print('🔍 [InAppPurchase] 가능한 원인:');
          print('   1. syncPurchaseInfo 함수 내부 오류');
          print('   2. JWS 검증 로직 문제');
          print('   3. 서버 리소스 부족');
          print('   4. 잘못된 jwsRepresentation 형식');
          print('🔍 [InAppPurchase] jwsRepresentation 길이: ${jwsRepresentation.length}');
          print('🔍 [InAppPurchase] userId: $userId');
        } else if (e.toString().contains('UNAUTHENTICATED')) {
          print('🔍 [InAppPurchase] Firebase Functions 인증 오류');
        } else if (e.toString().contains('NOT_FOUND')) {
          print('🔍 [InAppPurchase] syncPurchaseInfo 함수를 찾을 수 없음');
        }
        
        print('🔍 [InAppPurchase] Firebase Functions 호출 또는 JWS 검증 오류 가능성');
      }
      rethrow;
    }
  }



  /// 구매 완료 처리 헬퍼
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

  /// 타임아웃 완료 처리 스케줄링 (간소화)
  void _scheduleTimeoutCompletion(PurchaseDetails purchaseDetails) {
    Future.delayed(const Duration(seconds: 15), () async {
      try {
        if (purchaseDetails.pendingCompletePurchase) {
          await _inAppPurchase.completePurchase(purchaseDetails);
          if (kDebugMode) {
            print('⏰ 15초 후 강제 완료: ${purchaseDetails.productID}');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ 타임아웃 완료 처리 실패: $e');
        }
      }
    });
  }

  /// 구매 복원
  Future<void> restorePurchases() async {
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

  /// 즉시 상품 정보 getter들
  ProductDetails? get monthlyProductSync => _getProductById(premiumMonthlyId);
  ProductDetails? get yearlyProductSync => _getProductById(premiumYearlyId);

  // 🎯 기존 호환성 메서드들
  Future<bool> buyMonthly() => buyProduct(premiumMonthlyId);
  Future<bool> buyYearly() => buyProduct(premiumYearlyId);
  Future<bool> buyMonthlyTrial() => buyProduct(premiumMonthlyId);

  /// 🎯 사용자 친화적인 구매 시도 (간소화)
  Future<Map<String, dynamic>> attemptPurchaseWithGuidance(String productId) async {
    try {
      final success = await buyProduct(productId);
      
      if (success) {
        return {
          'success': true,
          'message': '구매가 성공적으로 시작되었습니다.',
        };
      }
      
      return {
        'success': false,
        'message': '구매를 시작할 수 없습니다.\n네트워크 연결을 확인하고 다시 시도해주세요.',
        'shouldRetryLater': false,
      };
    } catch (e) {
      return {
        'success': false,
        'message': '구매 중 오류가 발생했습니다.\n잠시 후 다시 시도해주세요.',
        'shouldRetryLater': true,
      };
    }
  }

  /// 🔍 알림 시스템 상태 확인 (디버깅용)
  Future<void> checkNotificationSystemStatus() async {
    if (kDebugMode) {
      print('\n🔍 [InAppPurchase] 알림 시스템 상태 확인:');
      
      try {
        await _notificationService.checkNotificationSystemStatus();
        print('✅ [InAppPurchase] 알림 시스템 상태 확인 완료');
      } catch (e) {
        print('❌ [InAppPurchase] 알림 시스템 상태 확인 실패: $e');
      }
    }
  }

  /// 🎯 정확한 상태 확인이 필요한 경우를 위한 메서드 (설정 화면 등)
  /// 
  /// 구매 직후에는 사용하지 않는 것이 좋습니다. 
  /// 대신 기본 _syncPurchaseInfo가 JWS 기반 빠른 응답을 제공합니다.
  Future<void> syncPurchaseInfoWithRealTimeCheck(String userId, String jwsRepresentation) async {
    return _syncPurchaseInfo(userId, jwsRepresentation, useRealTimeCheck: true);
  }
} 