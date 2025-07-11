import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../common/banner_manager.dart';
import '../cache/cache_manager.dart';
import '../notification/notification_service.dart';
import 'unified_subscription_manager.dart';

/// 🚀 StoreKit 2 기반 구독 권한 관리 엔진
/// 
/// StoreKit 2의 Transaction.updates를 활용하여 실시간으로 사용자 권한을 관리하고,
/// App Store Server Notifications와 연동하여 완전한 권한 관리 시스템을 제공합니다.
/// 
/// 주요 기능:
/// - StoreKit 2 Transaction.updates 실시간 모니터링
/// - App Store Server Notifications 연동
/// - 자동 권한 갱신 및 캐시 관리
/// - 구매 완료 스트림 제공
class SubscriptionEntitlementEngine {
  static final SubscriptionEntitlementEngine _instance = SubscriptionEntitlementEngine._internal();
  factory SubscriptionEntitlementEngine() => _instance;
  SubscriptionEntitlementEngine._internal();

  // 🎯 StoreKit 2 기반 구독 시스템
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseStreamSubscription;
  StreamSubscription<DocumentSnapshot>? _webhookStreamSubscription;
  
  // 🎯 권한 관리 스트림
  final StreamController<Map<String, dynamic>> _entitlementStreamController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _purchaseCompletedStreamController = StreamController<String>.broadcast();
  
  // 🎯 상태 관리
  bool _isListening = false;
  bool _isInitialized = false;
  Map<String, dynamic>? _cachedEntitlements;
  DateTime? _lastEntitlementCheck;
  
  // 🎯 처리된 Transaction ID 추적 (중복 방지)
  final Set<String> _processedTransactionIds = {};
  
  // 🎯 캐시 관리
  final CacheManager _cacheManager = CacheManager();
  final Duration _cacheValidDuration = const Duration(minutes: 5);
  
  // 🎯 알림 서비스
  final NotificationService _notificationService = NotificationService();

  /// 🚀 StoreKit 2 Transaction Listener 시작
  Future<void> startTransactionListener() async {
    if (_isListening) {
    if (kDebugMode) {
        print('🔄 StoreKit 2 Transaction Listener 이미 활성화됨');
      }
      return;
    }

    try {
      if (kDebugMode) {
        print('🚀 StoreKit 2 Transaction Listener 시작');
      }

      // 🎯 Transaction.updates 실시간 모니터링 시작
      await _startTransactionMonitoring();
      
      // 🎯 App Store Server Notifications 모니터링 시작
      await _startWebhookMonitoring();
      
      _isListening = true;
      _isInitialized = true;
      
      if (kDebugMode) {
        print('✅ StoreKit 2 Transaction Listener 활성화 완료');
        print('   - Transaction.updates 실시간 모니터링: ON');
        print('   - App Store Server Notifications 연동: ON');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ StoreKit 2 Transaction Listener 시작 실패: $e');
      }
    }
  }

  /// 🎯 StoreKit 2 Transaction 실시간 모니터링
  Future<void> _startTransactionMonitoring() async {
    try {
      // 🚀 StoreKit 2 Transaction.updates 스트림 구독
      _purchaseStreamSubscription = _inAppPurchase.purchaseStream.listen(
        (List<PurchaseDetails> purchaseDetailsList) {
          _handleTransactionUpdates(purchaseDetailsList);
        },
        onError: (error) {
          if (kDebugMode) {
            print('❌ StoreKit 2 Transaction Stream 에러: $error');
          }
        },
        onDone: () {
          if (kDebugMode) {
            print('🔄 StoreKit 2 Transaction Stream 완료');
          }
        },
      );
      
      if (kDebugMode) {
        print('✅ StoreKit 2 Transaction 실시간 모니터링 시작됨');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ StoreKit 2 Transaction 모니터링 시작 실패: $e');
      }
    }
  }

  /// 🎯 App Store Server Notifications 실시간 모니터링
  Future<void> _startWebhookMonitoring() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // 🎯 사용자별 webhook 이벤트 실시간 모니터링
      final webhookRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('webhookEvents')
          .doc('latest');

      _webhookStreamSubscription = webhookRef.snapshots().listen(
        (DocumentSnapshot snapshot) {
          if (snapshot.exists) {
            _handleWebhookEvent(snapshot.data() as Map<String, dynamic>);
          }
        },
        onError: (error) {
          if (kDebugMode) {
            print('❌ Webhook 모니터링 에러: $error');
          }
        },
      );
      
      if (kDebugMode) {
        print('✅ App Store Server Notifications 실시간 모니터링 시작됨');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Webhook 모니터링 시작 실패: $e');
      }
    }
  }

  /// 🎯 StoreKit 2 Transaction 업데이트 처리
  void _handleTransactionUpdates(List<PurchaseDetails> purchaseDetailsList) async {
    if (kDebugMode) {
      print('📱 StoreKit 2 EntitlementEngine Transaction 업데이트: ${purchaseDetailsList.length}개');
    }

    for (final purchaseDetails in purchaseDetailsList) {
      final transactionId = purchaseDetails.purchaseID ?? '';
      
      // 🎯 중복 처리 방지
      if (transactionId.isEmpty || _processedTransactionIds.contains(transactionId)) {
        continue;
      }
      
      _processedTransactionIds.add(transactionId);
      
      if (kDebugMode) {
        print('🔄 Transaction 처리: ${purchaseDetails.productID}, 상태: ${purchaseDetails.status}');
      }

      if (purchaseDetails.status == PurchaseStatus.purchased) {
        // 🎉 구매 완료 - 권한 즉시 갱신
        await _handlePurchaseCompleted(purchaseDetails);
      } else if (purchaseDetails.status == PurchaseStatus.restored) {
        // 🔄 구매 복원 - 권한 갱신
        await _handlePurchaseRestored(purchaseDetails);
      }
    }
  }

  /// 🎯 App Store Server Notifications 이벤트 처리
  void _handleWebhookEvent(Map<String, dynamic> eventData) async {
    try {
      final notificationType = eventData['notification_type'] as String?;
      
      if (kDebugMode) {
        print('📡 Webhook 이벤트 수신: $notificationType');
      }

      // 🎯 구독 상태 변경 관련 이벤트 처리
      if (notificationType != null) {
        switch (notificationType) {
          case 'SUBSCRIBED':
          case 'INITIAL_BUY':
            await _handleSubscriptionActivated(eventData);
            break;
          case 'DID_RENEW':
            await _handleSubscriptionRenewed(eventData);
            break;
          case 'EXPIRED':
          case 'DID_FAIL_TO_RENEW':
            await _handleSubscriptionExpired(eventData);
            break;
          case 'REFUND':
            await _handleSubscriptionRefunded(eventData);
            break;
          case 'GRACE_PERIOD_EXPIRED':
            await _handleGracePeriodExpired(eventData);
            break;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Webhook 이벤트 처리 실패: $e');
      }
    }
  }

  /// 🎉 구매 완료 처리
  Future<void> _handlePurchaseCompleted(PurchaseDetails purchaseDetails) async {
      try {
        if (kDebugMode) {
        print('🎉 StoreKit 2 구매 완료 처리: ${purchaseDetails.productID}');
      }

      // 🎯 권한 즉시 갱신
      await getCurrentEntitlements(forceRefresh: true);
      
      // 🎯 구매 완료 알림
      _purchaseCompletedStreamController.add(purchaseDetails.productID);
      
      // 🎯 배너 업데이트
      await _updateBannerAfterPurchase(purchaseDetails.productID);
      
      // 🎯 무료체험 알림 스케줄링
      await _scheduleTrialNotificationsIfNeeded(purchaseDetails.productID);

        if (kDebugMode) {
        print('✅ StoreKit 2 구매 완료 처리 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ StoreKit 2 구매 완료 처리 실패: $e');
      }
    }
  }

  /// 🔄 구매 복원 처리
  Future<void> _handlePurchaseRestored(PurchaseDetails purchaseDetails) async {
    try {
        if (kDebugMode) {
        print('🔄 StoreKit 2 구매 복원 처리: ${purchaseDetails.productID}');
      }

      // 구매 복원도 구매 완료와 동일하게 처리
      await _handlePurchaseCompleted(purchaseDetails);
    } catch (e) {
      if (kDebugMode) {
        print('❌ StoreKit 2 구매 복원 처리 실패: $e');
      }
    }
  }

  /// 📡 구독 활성화 처리
  Future<void> _handleSubscriptionActivated(Map<String, dynamic> eventData) async {
    if (kDebugMode) {
      print('📡 구독 활성화 처리');
    }
    
    await getCurrentEntitlements(forceRefresh: true);
    await _updateBannerFromWebhook(eventData);
  }

  /// 📡 구독 갱신 처리
  Future<void> _handleSubscriptionRenewed(Map<String, dynamic> eventData) async {
    if (kDebugMode) {
      print('📡 구독 갱신 처리');
    }
    
    await getCurrentEntitlements(forceRefresh: true);
    await _updateBannerFromWebhook(eventData);
  }

  /// 📡 구독 만료 처리
  Future<void> _handleSubscriptionExpired(Map<String, dynamic> eventData) async {
    if (kDebugMode) {
      print('📡 구독 만료 처리');
    }
    
    await getCurrentEntitlements(forceRefresh: true);
    
    // 🎯 만료 관련 배너 표시
    final bannerManager = BannerManager();
    bannerManager.setBannerState(BannerType.premiumExpired, true);
    bannerManager.invalidateBannerCache();
  }

  /// 📡 구독 환불 처리
  Future<void> _handleSubscriptionRefunded(Map<String, dynamic> eventData) async {
    if (kDebugMode) {
      print('📡 구독 환불 처리');
    }
    
    await getCurrentEntitlements(forceRefresh: true);
    
    // 🎯 환불 관련 배너 표시
    final bannerManager = BannerManager();
    bannerManager.setBannerState(BannerType.premiumCancelled, true);
    bannerManager.invalidateBannerCache();
  }

  /// 📡 유예 기간 만료 처리
  Future<void> _handleGracePeriodExpired(Map<String, dynamic> eventData) async {
    if (kDebugMode) {
      print('📡 유예 기간 만료 처리');
    }
    
    await getCurrentEntitlements(forceRefresh: true);
  }

  /// 🎯 현재 권한 조회 (StoreKit 2 개선)
  Future<Map<String, dynamic>> getCurrentEntitlements({bool forceRefresh = false}) async {
    try {
      // 🎯 캐시 확인
      if (!forceRefresh && _cachedEntitlements != null && _lastEntitlementCheck != null) {
        final cacheAge = DateTime.now().difference(_lastEntitlementCheck!);
        if (cacheAge < _cacheValidDuration) {
          if (kDebugMode) {
            print('✅ 캐시된 권한 정보 반환 (${cacheAge.inSeconds}초 전)');
          }
          return _cachedEntitlements!;
        }
      }

      if (kDebugMode) {
        print('🔍 StoreKit 2 권한 조회 ${forceRefresh ? '(강제 갱신)' : ''}');
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return _getDefaultEntitlements();
      }

      // 🎯 서버에서 권한 조회 (Apple 공식 라이브러리 사용)
      final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
      final callable = functions.httpsCallable('checkSubscriptionStatus');
      
      final result = await callable.call({'userId': user.uid});
      final responseData = result.data as Map<String, dynamic>;
      
      // 🚀 새로운 Apple 공식 라이브러리 응답 필드 처리
      final serverVersion = responseData['version'] as String?;
      final dataSource = responseData['dataSource'] as String?;
      final timestamp = responseData['timestamp'] as String?;
      final libraryInfo = responseData['libraryInfo'] as Map<String, dynamic>?;
      
      if (kDebugMode) {
        print('📡 [EntitlementEngine] 서버 응답 메타데이터:');
        print('   - 서버 버전: ${serverVersion ?? "알 수 없음"}');
        print('   - 데이터 소스: ${dataSource ?? "알 수 없음"}');
        print('   - 응답 시간: ${timestamp ?? "알 수 없음"}');
        
        if (libraryInfo != null) {
          final isUsingOfficialLibrary = libraryInfo['isUsingOfficialLibrary'] as bool? ?? false;
          final benefits = libraryInfo['benefits'] as List<dynamic>? ?? [];
          
          print('🚀 [EntitlementEngine] Apple 공식 라이브러리 정보:');
          print('   - 공식 라이브러리 사용: ${isUsingOfficialLibrary ? "✅ 예" : "❌ 아니오"}');
          if (benefits.isNotEmpty) {
            print('   - 주요 개선사항:');
            for (final benefit in benefits) {
              print('     • $benefit');
            }
          }
        }
        
        // 🎯 데이터 소스별 특별 로깅
        if (dataSource == 'appstore-official-library') {
          print('🎉 [EntitlementEngine] Apple 공식 라이브러리 기반 응답 확인!');
        } else if (dataSource == 'test-account') {
          print('🧪 [EntitlementEngine] 테스트 계정 응답');
        } else if (dataSource == 'firestore-webhook') {
          print('📡 [EntitlementEngine] Webhook 기반 응답');
        }
      }
      
      // 🎯 실제 구독 정보 추출 (기존과 동일)
      final entitlements = responseData['subscription'] as Map<String, dynamic>? ?? responseData;
      
      // 🎯 캐시 업데이트 (메타데이터 포함)
      final enrichedEntitlements = Map<String, dynamic>.from(entitlements);
      enrichedEntitlements.addAll({
        '_serverVersion': serverVersion,
        '_dataSource': dataSource,
        '_timestamp': timestamp,
        '_libraryInfo': libraryInfo,
      });
      
      _cachedEntitlements = enrichedEntitlements;
      _lastEntitlementCheck = DateTime.now();
      
      // 🎯 권한 스트림 업데이트
      _entitlementStreamController.add(enrichedEntitlements);
      
      if (kDebugMode) {
        print('✅ StoreKit 2 권한 조회 완료 (Apple 공식 라이브러리)');
        print('   - Premium: ${entitlements['premium'] ?? entitlements['isPremium'] ?? false}');
        print('   - Trial: ${entitlements['trial'] ?? entitlements['isTrial'] ?? false}');
        print('   - Expired: ${entitlements['expired'] ?? entitlements['isExpired'] ?? false}');
      }
      
      return enrichedEntitlements;
    } catch (e) {
      if (kDebugMode) {
        print('❌ StoreKit 2 권한 조회 실패: $e');
        print('🔍 [EntitlementEngine] 서버 연결 또는 Apple 라이브러리 오류 가능성');
      }
      return _getDefaultEntitlements();
    }
  }

  /// 🎯 기본 권한 반환
  Map<String, dynamic> _getDefaultEntitlements() {
    return {
      'premium': false,
      'trial': false,
      'expired': false,
      'planId': null,
      'expiresAt': null,
      'originalTransactionId': null,
    };
  }

  /// 🎯 구매 후 배너 업데이트
  Future<void> _updateBannerAfterPurchase(String productId) async {
    final bannerManager = BannerManager();
    
    if (productId == 'premium_monthly_with_trial') {
      bannerManager.setBannerState(BannerType.trialStarted, true, planId: 'storekit2_trial');
    } else {
      bannerManager.setBannerState(BannerType.premiumStarted, true, planId: 'storekit2_premium');
    }
    
    bannerManager.invalidateBannerCache();
  }

  /// 🎯 Webhook 이벤트 기반 배너 업데이트
  Future<void> _updateBannerFromWebhook(Map<String, dynamic> eventData) async {
    final bannerManager = BannerManager();
    final planId = eventData['plan_id'] as String?;
    final notificationType = eventData['notification_type'] as String?;
    
    if (planId != null && notificationType != null) {
      switch (notificationType) {
        case 'SUBSCRIBED':
        case 'INITIAL_BUY':
          if (planId.contains('trial')) {
            bannerManager.setBannerState(BannerType.trialStarted, true, planId: planId);
          } else {
            bannerManager.setBannerState(BannerType.premiumStarted, true, planId: planId);
          }
          break;
        case 'DID_RENEW':
          // 갱신 시 기존 배너 사용
          bannerManager.setBannerState(BannerType.premiumStarted, true, planId: planId);
          break;
      }
      bannerManager.invalidateBannerCache();
    }
  }

  /// 🎯 무료체험 알림 스케줄링
  Future<void> _scheduleTrialNotificationsIfNeeded(String productId) async {
    if (productId == 'premium_monthly_with_trial') {
      try {
        await _notificationService.scheduleTrialEndNotifications(DateTime.now());
        if (kDebugMode) {
          print('✅ StoreKit 2 무료체험 알림 스케줄링 완료');
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ StoreKit 2 무료체험 알림 스케줄링 실패: $e');
        }
      }
    }
  }

  /// 🎯 캐시 무효화
  void invalidateCache() {
    _cachedEntitlements = null;
    _lastEntitlementCheck = null;
    
    if (kDebugMode) {
      print('🧹 StoreKit 2 권한 캐시 무효화');
    }
  }
  
  /// 🎯 서비스 종료
  void dispose() {
    _purchaseStreamSubscription?.cancel();
    _webhookStreamSubscription?.cancel();
    _entitlementStreamController.close();
    _purchaseCompletedStreamController.close();
    _processedTransactionIds.clear();
    _isListening = false;
    _isInitialized = false;
    
    if (kDebugMode) {
      print('🔄 StoreKit 2 EntitlementEngine 종료');
    }
  }

  /// 🎯 권한 변경 스트림
  Stream<Map<String, dynamic>> get entitlementStream => _entitlementStreamController.stream;

  /// 🎯 구매 완료 스트림
  Stream<String> get purchaseCompletedStream => _purchaseCompletedStreamController.stream;

  /// 🎯 현재 상태
  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;

  /// 🎯 즉시 사용 가능한 권한 정보 (캐시)
  Map<String, dynamic>? get cachedEntitlements => _cachedEntitlements;

  /// 🎯 Premium 권한 확인
  bool get isPremium => _cachedEntitlements?['premium'] ?? false;

  /// 🎯 Trial 권한 확인
  bool get isTrial => _cachedEntitlements?['trial'] ?? false;

  /// 🎯 만료 상태 확인
  bool get isExpired => _cachedEntitlements?['expired'] ?? false;

  /// 🎯 UnifiedSubscriptionManager 연동
  void notifySubscriptionChanged() {
    final unifiedManager = UnifiedSubscriptionManager();
    unifiedManager.invalidateCache();
  }

  /// 🎯 구매 완료 알림
  void notifyPurchaseCompleted(String productId) {
    _purchaseCompletedStreamController.add(productId);
  }
} 