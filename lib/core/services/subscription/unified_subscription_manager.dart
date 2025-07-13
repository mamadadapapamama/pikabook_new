import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../notification/notification_service.dart';
import '../../models/subscription_state.dart';
import '../../events/subscription_events.dart';

// 🎯 Apple 공식 라이브러리 기반 권한 결과 타입 정의
typedef EntitlementResult = Map<String, dynamic>;

// 🎯 EntitlementResult 편의 확장 메서드 (v4-simplified)
extension EntitlementResultExtension on EntitlementResult {
  // 새로운 v4-simplified 필드 접근자
  String get entitlement => this['entitlement'] as String? ?? 'free';
  String get subscriptionStatus => this['subscriptionStatus'] as String? ?? 'cancelled';
  bool get hasUsedTrial => this['hasUsedTrial'] as bool? ?? false;
  
  // 기존 호환성 접근자
  bool get isPremium => entitlement == 'premium';
  bool get isTrial => entitlement == 'trial';
  bool get isExpired => subscriptionStatus == 'expired';
  bool get isActive => subscriptionStatus == 'active';
  bool get isCancelling => subscriptionStatus == 'cancelling';
  
  // 상태 메시지 접근자
  String get statusMessage {
    if (isTrial) {
      return isCancelling ? '무료체험 (취소 예정)' : '무료체험 중';
    } else if (isPremium) {
      return isCancelling ? '프리미엄 (취소 예정)' : '프리미엄';
    } else {
      return '무료 플랜';
    }
  }
  
  // 메타데이터 접근자
  String? get version => this['_version'] as String?;
  String? get dataSource => this['_dataSource'] as String?;
  String? get timestamp => this['_timestamp'] as String?;
  
  // 배너 메타데이터 접근자 (테스트 계정용)
  Map<String, dynamic>? get bannerMetadata => this['bannerMetadata'] as Map<String, dynamic>?;
}

/// 🚀 통합 구독 관리자 (StoreKit 2 + 이벤트 중심)
/// 
/// 🎯 **핵심 책임 (Core Responsibilities):**
/// 
/// 1️⃣ **StoreKit 2 Transaction 실시간 모니터링**
///    - purchaseStream.listen()으로 구매/복원 감지
///    - 중복 거래 방지 (_processedTransactionIds)
///    - 구매 완료시 자동 이벤트 발행
/// 
/// 2️⃣ **App Store Server Notifications 연동**  
///    - Firestore webhookEvents 실시간 모니터링
///    - 서버 측 구독 상태 변경 (만료, 환불, 갱신) 감지
///    - Webhook 이벤트를 앱 내 이벤트로 변환
/// 
/// 3️⃣ **구독 권한 상태 조회 및 캐싱**
///    - Firebase Functions 'sub_checkSubscriptionStatus' 호출
///    - v4-simplified 응답 구조 처리 (entitlement, subscriptionStatus, hasUsedTrial)
///    - 5분 캐싱으로 성능 최적화
///    - 사용자 변경시 자동 캐시 무효화
/// 
/// 4️⃣ **이벤트 발행 트리거** 
///    - 구독 상태 변경 감지시 SubscriptionEventManager.emitXXX() 호출
///    - 다른 서비스들(BannerManager 등)이 이벤트를 받아 반응
///    - 중앙화된 이벤트 아키텍처의 출발점
/// 
/// 5️⃣ **구매 실패시 재시도 및 에러 처리**
///    - 2회 재시도 (3초, 8초)
///    - 최종 실패시 errorStream으로 UI 알림
///    - 무료체험 알림 스케줄링
/// 
/// 🚫 **담당하지 않는 책임 (Non-Responsibilities):**
/// - ❌ 사용량 한도 확인 → UsageLimitService에서 직접 처리
/// - ❌ 배너 관리 → BannerManager가 이벤트 리스너로 처리  
/// - ❌ UI 로직 → 각 화면에서 개별 처리
/// 
/// 🔄 **사용 패턴:**
/// ```dart
/// // 1. 앱 시작시 한 번 초기화
/// await UnifiedSubscriptionManager().initialize();
/// 
/// // 2. 권한 확인 (어디서든)
/// final entitlements = await manager.getSubscriptionEntitlements();
/// bool canUse = entitlements['isPremium'] || entitlements['isTrial'];
/// 
/// // 3. 구매 완료 알림 (InAppPurchaseService에서)
/// manager.notifyPurchaseCompleted();
/// 
/// // 4. 에러 UI 구독 (HomeScreen 등에서)
/// manager.errorStream.listen((error) => showSnackBar(error));
/// ```
/// 
/// 📊 **데이터 흐름:**
/// ```
/// StoreKit/Webhook → UnifiedSubscriptionManager → SubscriptionEventManager 
///                                            ↓
/// BannerManager ← SubscriptionEvent ← EventManager
/// ```
class UnifiedSubscriptionManager {
  static final UnifiedSubscriptionManager _instance = UnifiedSubscriptionManager._internal();
  factory UnifiedSubscriptionManager() => _instance;
  UnifiedSubscriptionManager._internal();

  // 🎯 서비스 의존성 (단순화)
  final NotificationService _notificationService = NotificationService();
  
  // 🎯 StoreKit 2 관리 (필요함 - 중복 거래 방지 및 상태 관리)
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseStreamSubscription;
  StreamSubscription<DocumentSnapshot>? _webhookStreamSubscription;
  bool _isListening = false;
  bool _isInitialized = false;
  final Set<String> _processedTransactionIds = {}; // 🎯 중복 거래 방지 (필수)
  
  // 🎯 단일 권한 캐싱 (UI 로직 제거, 권한만)
  Map<String, dynamic>? _cachedEntitlements;
  DateTime? _lastEntitlementCheck;
  static const Duration _cacheValidDuration = Duration(minutes: 5);
  
  // 🎯 중복 요청 방지
  Future<Map<String, dynamic>>? _ongoingEntitlementRequest;
  DateTime? _lastRequestTime;
  static const Duration _debounceDelay = Duration(milliseconds: 300);
  
  // 🎯 사용자 변경 감지용
  String? _lastUserId;
  
  // 🎯 이벤트 스트림 (중앙화)
  final StreamController<Map<String, dynamic>> _entitlementStreamController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _purchaseCompletedStreamController = StreamController<String>.broadcast();
  final StreamController<String> _errorStreamController = StreamController<String>.broadcast();
  
  // 🎯 구독 이벤트 스트림 (SubscriptionEventManager 대체)
  final StreamController<SubscriptionEvent> _subscriptionEventController = StreamController<SubscriptionEvent>.broadcast();
  
  // 🎯 재시도 관리 (단순화)
  int _retryCount = 0;
  static const int _maxRetries = 2;
  static const List<int> _retryDelays = [3, 8];

  /// 🚀 앱 시작 시 초기화 (한 번만 호출)
  /// App.dart에서 initialize() 호출하여 백그라운드 모니터링 시작
  Future<void> initialize() async {
    if (_isInitialized) {
      if (kDebugMode) {
        debugPrint('🔄 [UnifiedSubscriptionManager] 이미 초기화됨');
      }
      return;
    }

    if (kDebugMode) {
      debugPrint('🚀 [UnifiedSubscriptionManager] 통합 초기화 시작');
    }
    
    try {
      // 🎯 StoreKit 2 Transaction.updates 실시간 모니터링 시작
      await _startTransactionMonitoring();
      
      // 🎯 App Store Server Notifications 모니터링 시작
      await _startWebhookMonitoring();
      
      _isListening = true;
      _isInitialized = true;
      
      if (kDebugMode) {
        debugPrint('✅ [UnifiedSubscriptionManager] 통합 초기화 완료');
        debugPrint('   - StoreKit 2 Transaction 모니터링: ON');
        debugPrint('   - Webhook 모니터링: ON');
        debugPrint('   - 권한 중심 캐싱: ON');
        debugPrint('   - 중앙화된 이벤트 발행: ON');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedSubscriptionManager] 초기화 실패: $e');
      }
      _emitError('구독 시스템 초기화에 실패했습니다.');
    }
  }

  /// 🎯 StoreKit 2 Transaction 실시간 모니터링
  /// 구매, 복원, 업그레이드 등 모든 거래를 실시간 감지
  Future<void> _startTransactionMonitoring() async {
    try {
      if (kDebugMode) {
        debugPrint('🎯 [UnifiedSubscriptionManager] StoreKit 2 Transaction 모니터링 시작');
      }

      _purchaseStreamSubscription = _inAppPurchase.purchaseStream.listen(
        (List<PurchaseDetails> purchaseDetailsList) {
          _handleTransactionUpdates(purchaseDetailsList);
        },
        onError: (error) {
          if (kDebugMode) {
            debugPrint('❌ [UnifiedSubscriptionManager] Transaction Stream 에러: $error');
          }
          _emitError('구매 정보 수신 중 오류가 발생했습니다.');
        },
      );
      
      if (kDebugMode) {
        debugPrint('✅ [UnifiedSubscriptionManager] StoreKit 2 Transaction 모니터링 활성화');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedSubscriptionManager] Transaction 모니터링 시작 실패: $e');
      }
      throw e;
    }
  }

  /// 🎯 App Store Server Notifications 실시간 모니터링
  /// 서버에서 전송되는 구독 상태 변경 알림을 실시간 감지
  Future<void> _startWebhookMonitoring() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      if (kDebugMode) {
        debugPrint('🎯 [UnifiedSubscriptionManager] Webhook 모니터링 시작');
      }

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
            debugPrint('❌ [UnifiedSubscriptionManager] Webhook 모니터링 에러: $error');
          }
          _emitError('서버 알림 수신 중 오류가 발생했습니다.');
        },
      );
      
      if (kDebugMode) {
        debugPrint('✅ [UnifiedSubscriptionManager] Webhook 모니터링 활성화');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedSubscriptionManager] Webhook 모니터링 시작 실패: $e');
      }
      throw e;
    }
  }

  /// 🎯 StoreKit 2 Transaction 업데이트 처리
  /// 중복 거래 방지 후 이벤트 발행 트리거
  void _handleTransactionUpdates(List<PurchaseDetails> purchaseDetailsList) async {
    if (kDebugMode) {
      debugPrint('📱 [UnifiedSubscriptionManager] Transaction 업데이트: ${purchaseDetailsList.length}개');
    }

    for (final purchaseDetails in purchaseDetailsList) {
      final transactionId = purchaseDetails.purchaseID ?? '';
      
      // 🎯 중복 처리 방지 (StoreKit 2에서도 필수!)
      if (transactionId.isEmpty || _processedTransactionIds.contains(transactionId)) {
        continue;
      }
      
      _processedTransactionIds.add(transactionId);
      
      if (kDebugMode) {
        debugPrint('🔄 [UnifiedSubscriptionManager] Transaction 처리: ${purchaseDetails.productID}, 상태: ${purchaseDetails.status}');
      }

      if (purchaseDetails.status == PurchaseStatus.purchased) {
        await _handlePurchaseCompleted(purchaseDetails);
      } else if (purchaseDetails.status == PurchaseStatus.restored) {
        await _handlePurchaseRestored(purchaseDetails);
      }
    }
  }

  /// 🎯 App Store Server Notifications 이벤트 처리
  /// Webhook 데이터를 파싱하여 적절한 이벤트 발행
  void _handleWebhookEvent(Map<String, dynamic> eventData) async {
    try {
      final notificationType = eventData['notification_type'] as String?;
      
      if (kDebugMode) {
        debugPrint('📡 [UnifiedSubscriptionManager] Webhook 이벤트 수신: $notificationType');
      }

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
        debugPrint('❌ [UnifiedSubscriptionManager] Webhook 이벤트 처리 실패: $e');
      }
      _emitError('서버 알림 처리 중 오류가 발생했습니다.');
    }
  }

  /// 🎉 구매 완료 처리
  /// 구매 완료시 캐시 무효화, 이벤트 발행, 알림 스케줄링, 재시도 시작
  Future<void> _handlePurchaseCompleted(PurchaseDetails purchaseDetails) async {
    try {
      if (kDebugMode) {
        debugPrint('🎉 [UnifiedSubscriptionManager] 구매 완료 처리: ${purchaseDetails.productID}');
      }

      // 🎯 캐시 무효화 및 상태 갱신
      invalidateCache();
      
      // 🎯 구매 완료 스트림 알림
      _purchaseCompletedStreamController.add(purchaseDetails.productID);
      
      // 🎯 이벤트 발행 (SubscriptionEventManager 사용)
      if (purchaseDetails.productID == 'premium_monthly_with_trial') {
        await _emitTrialStartedEvent(
          context: 'purchase_trial',
          metadata: {'productId': purchaseDetails.productID, 'transactionId': purchaseDetails.purchaseID},
        );
      } else {
        await _emitPurchaseCompletedEvent(
          context: 'purchase_premium',
          metadata: {'productId': purchaseDetails.productID, 'transactionId': purchaseDetails.purchaseID},
        );
      }
      
      // 🎯 무료체험 알림 스케줄링
      await _scheduleTrialNotificationsIfNeeded(purchaseDetails.productID);
      
      // 🎯 단순화된 재시도 시작
      _startSimplifiedRetry();

      if (kDebugMode) {
        debugPrint('✅ [UnifiedSubscriptionManager] 구매 완료 처리 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedSubscriptionManager] 구매 완료 처리 실패: $e');
      }
      _emitError('구매 완료 처리 중 오류가 발생했습니다.');
    }
  }

  /// 🔄 구매 복원 처리
  Future<void> _handlePurchaseRestored(PurchaseDetails purchaseDetails) async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 [UnifiedSubscriptionManager] 구매 복원 처리: ${purchaseDetails.productID}');
      }

      await _handlePurchaseCompleted(purchaseDetails);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedSubscriptionManager] 구매 복원 처리 실패: $e');
      }
      _emitError('구매 복원 처리 중 오류가 발생했습니다.');
    }
  }

  /// 📡 Webhook 이벤트 처리 메서드들
  Future<void> _handleSubscriptionActivated(Map<String, dynamic> eventData) async {
    if (kDebugMode) {
      debugPrint('📡 [UnifiedSubscriptionManager] 구독 활성화 처리');
    }
    
    invalidateCache();
    
    final planId = eventData['plan_id'] as String?;
    if (planId?.contains('trial') == true) {
      await _emitTrialStartedEvent(context: 'webhook_trial', metadata: eventData);
    } else {
      await _emitPurchaseCompletedEvent(context: 'webhook_purchase', metadata: eventData);
    }
  }

  Future<void> _handleSubscriptionRenewed(Map<String, dynamic> eventData) async {
    if (kDebugMode) {
      debugPrint('📡 [UnifiedSubscriptionManager] 구독 갱신 처리');
    }
    
    invalidateCache();
    await _emitWebhookReceivedEvent(context: 'webhook_renewed', metadata: eventData);
  }

  Future<void> _handleSubscriptionExpired(Map<String, dynamic> eventData) async {
    if (kDebugMode) {
      debugPrint('📡 [UnifiedSubscriptionManager] 구독 만료 처리');
    }
    
    invalidateCache();
    await _emitExpiredEvent(context: 'webhook_expired', metadata: eventData);
  }

  Future<void> _handleSubscriptionRefunded(Map<String, dynamic> eventData) async {
    if (kDebugMode) {
      debugPrint('📡 [UnifiedSubscriptionManager] 구독 환불 처리');
    }
    
    invalidateCache();
    await _emitRefundedEvent(context: 'webhook_refunded', metadata: eventData);
  }

  Future<void> _handleGracePeriodExpired(Map<String, dynamic> eventData) async {
    if (kDebugMode) {
      debugPrint('📡 [UnifiedSubscriptionManager] 유예 기간 만료 처리');
    }
    
    invalidateCache();
    await _emitWebhookReceivedEvent(context: 'webhook_grace_expired', metadata: eventData);
  }

  /// 🎯 단순한 구독 상태 조회 (권한만, UI 로직 제거)
  /// 
  /// **사용법:**
  /// ```dart
  /// final entitlements = await manager.getSubscriptionEntitlements();
  /// 
  /// // 권한 확인
  /// bool isPremium = entitlements['isPremium']; 
  /// bool isTrial = entitlements['isTrial'];
  /// String entitlement = entitlements['entitlement']; // 'free', 'trial', 'premium'
  /// String status = entitlements['subscriptionStatus']; // 'active', 'cancelled', 'expired'
  /// bool hasUsedTrial = entitlements['hasUsedTrial'];
  /// 
  /// // 메타데이터
  /// String? dataSource = entitlements['_dataSource']; // 'appstore-official-library', 'firestore-webhook'
  /// ```
  Future<Map<String, dynamic>> getSubscriptionEntitlements({bool forceRefresh = false}) async {
    if (kDebugMode) {
      debugPrint('🎯 [UnifiedSubscriptionManager] 구독 권한 조회 (forceRefresh: $forceRefresh)');
    }
    
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return _getDefaultEntitlements();
    }
    
    final currentUserId = currentUser.uid;
    
    // 🎯 사용자 변경 감지 (캐시 무효화)
    if (_lastUserId != currentUserId) {
      if (kDebugMode) {
        debugPrint('🔄 [UnifiedSubscriptionManager] 사용자 변경 감지: $currentUserId');
      }
      invalidateCache();
      forceRefresh = true;
      _lastUserId = currentUserId;
    }
    
    // 🎯 디바운싱
    final now = DateTime.now();
    if (_lastRequestTime != null && now.difference(_lastRequestTime!) < _debounceDelay) {
      if (kDebugMode) {
        debugPrint('⏱️ [UnifiedSubscriptionManager] 디바운싱 - 캐시 사용');
      }
      return _cachedEntitlements ?? _getDefaultEntitlements();
    }
    _lastRequestTime = now;
    
    // 🎯 캐시 우선 사용
    if (!forceRefresh && _cachedEntitlements != null && _lastEntitlementCheck != null) {
      final cacheAge = DateTime.now().difference(_lastEntitlementCheck!);
      if (cacheAge < _cacheValidDuration) {
        if (kDebugMode) {
          debugPrint('📦 [UnifiedSubscriptionManager] 캐시된 권한 반환 (${cacheAge.inSeconds}초 전)');
        }
        return _cachedEntitlements!;
      }
    }
    
    // 🎯 중복 요청 방지
    if (_ongoingEntitlementRequest != null) {
      return await _ongoingEntitlementRequest!;
    }

    if (kDebugMode) {
      debugPrint('🔍 [UnifiedSubscriptionManager] 서버 권한 조회 ${forceRefresh ? '(강제 갱신)' : ''}');
    }

    _ongoingEntitlementRequest = _fetchEntitlementsFromServer(currentUserId);
    
    try {
      final result = await _ongoingEntitlementRequest!;
      
      // 캐시 업데이트
      _cachedEntitlements = result;
      _lastEntitlementCheck = DateTime.now();
      
      // 권한 스트림 업데이트
      _entitlementStreamController.add(result);
      
      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedSubscriptionManager] 권한 조회 실패: $e');
      }
      _emitError('구독 상태 조회에 실패했습니다.');
      return _getDefaultEntitlements();
    } finally {
      _ongoingEntitlementRequest = null;
    }
  }

  /// 🎯 서버에서 권한 조회
  /// Firebase Functions의 'sub_checkSubscriptionStatus' 호출
  Future<Map<String, dynamic>> _fetchEntitlementsFromServer(String userId) async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
      final callable = functions.httpsCallable('sub_checkSubscriptionStatus');
      
      final result = await callable.call({
        'userId': userId,
        'appStoreFirst': true, // Apple Store Connect API 우선 확인
      });
      
      Map<String, dynamic> responseData;
      if (result.data is Map) {
        responseData = Map<String, dynamic>.from(result.data as Map);
      } else {
        if (kDebugMode) {
          debugPrint('❌ [UnifiedSubscriptionManager] 예상치 못한 응답 타입: ${result.data.runtimeType}');
        }
        return _getDefaultEntitlements();
      }
      
      final version = responseData['version'] is String ? responseData['version'] as String : null;
      final dataSource = responseData['dataSource'] is String ? responseData['dataSource'] as String : null;
      
      Map<String, dynamic>? subscription;
      final subscriptionRaw = responseData['subscription'];
      if (subscriptionRaw is Map) {
        subscription = Map<String, dynamic>.from(subscriptionRaw);
      }
      
      if (kDebugMode) {
        debugPrint('📡 [UnifiedSubscriptionManager] v4-simplified 응답:');
        debugPrint('   - 버전: ${version ?? "알 수 없음"}');
        debugPrint('   - 데이터 소스: ${dataSource ?? "알 수 없음"}');
        if (subscription != null) {
          debugPrint('   - entitlement: ${subscription['entitlement']}');
          debugPrint('   - subscriptionStatus: ${subscription['subscriptionStatus']}');
          debugPrint('   - hasUsedTrial: ${subscription['hasUsedTrial']}');
        }
      }
      
      if (subscription == null) {
        return _getDefaultEntitlements();
      }
      
      // v4-simplified 구조를 기존 형식으로 변환
      final entitlement = subscription['entitlement'] is String ? subscription['entitlement'] as String : 'free';
      final subscriptionStatus = subscription['subscriptionStatus'] is String ? subscription['subscriptionStatus'] as String : 'cancelled';
      final hasUsedTrial = subscription['hasUsedTrial'] is bool ? subscription['hasUsedTrial'] as bool : false;
      
      final compatibleFormat = {
        'entitlement': entitlement,
        'subscriptionStatus': subscriptionStatus,
        'hasUsedTrial': hasUsedTrial,
        'autoRenewEnabled': subscription['autoRenewEnabled'] is bool ? subscription['autoRenewEnabled'] : false,
        'expirationDate': subscription['expirationDate'] is String ? subscription['expirationDate'] : null,
        'subscriptionType': subscription['subscriptionType'] is String ? subscription['subscriptionType'] : null,
        'originalTransactionId': subscription['originalTransactionId'] is String ? subscription['originalTransactionId'] : null,
        'bannerMetadata': subscription['bannerMetadata'] is Map ? Map<String, dynamic>.from(subscription['bannerMetadata']) : null,
        
        // 기존 호환성 필드들
        'premium': entitlement == 'premium',
        'trial': entitlement == 'trial',
        'expired': subscriptionStatus == 'expired',
        'isPremium': entitlement == 'premium',
        'isTrial': entitlement == 'trial',
        'isExpired': subscriptionStatus == 'expired',
        
        // 메타데이터
        '_version': version,
        '_dataSource': dataSource,
        '_timestamp': DateTime.now().toIso8601String(),
      };
      
      return compatibleFormat;
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedSubscriptionManager] 서버 권한 조회 실패: $e');
      }
      throw e;
    }
  }

  /// 🎯 기본 권한 반환 (서버 호출 실패시)
  Map<String, dynamic> _getDefaultEntitlements() {
    return {
      'entitlement': 'free',
      'subscriptionStatus': 'cancelled',
      'hasUsedTrial': false,
      'autoRenewEnabled': false,
      'expirationDate': null,
      'subscriptionType': null,
      'originalTransactionId': null,
      'bannerMetadata': null,
      
      'premium': false,
      'trial': false,
      'expired': false,
      'isPremium': false,
      'isTrial': false,
      'isExpired': false,
      
      '_version': 'v4-simplified',
      '_dataSource': 'default',
      '_timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// 🎯 무료체험 알림 스케줄링
  Future<void> _scheduleTrialNotificationsIfNeeded(String productId) async {
    if (productId == 'premium_monthly_with_trial') {
      try {
        await _notificationService.scheduleTrialEndNotifications(DateTime.now());
        if (kDebugMode) {
          debugPrint('✅ [UnifiedSubscriptionManager] 무료체험 알림 스케줄링 완료');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ [UnifiedSubscriptionManager] 무료체험 알림 스케줄링 실패: $e');
        }
      }
    }
  }

  /// 🎯 단순화된 재시도 로직 (2번)
  /// 구매 완료 후 서버 동기화를 위한 재시도
  void _startSimplifiedRetry() {
    _retryCount = 0;
    
    if (kDebugMode) {
      debugPrint('🔄 [UnifiedSubscriptionManager] 단순화된 재시도 시작 (최대 ${_maxRetries}번)');
    }
    
    for (int i = 0; i < _maxRetries; i++) {
      final delay = _retryDelays[i];
      Future.delayed(Duration(seconds: delay), () async {
        await _performRetryCheck(i + 1, delay);
      });
    }
  }
  
  /// 재시도 체크 수행 (에러 UI 포함)
  Future<void> _performRetryCheck(int retryNumber, int delay) async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 [UnifiedSubscriptionManager] ${retryNumber}차 재시도 (${delay}초 후)');
      }
      
      final updatedEntitlements = await getSubscriptionEntitlements(forceRefresh: true);
      
      if (kDebugMode) {
        debugPrint('📊 [UnifiedSubscriptionManager] ${retryNumber}차 재시도 결과: ${updatedEntitlements['entitlement']} (${updatedEntitlements['subscriptionStatus']})');
      }
      
      if (updatedEntitlements['isPremium'] == true || updatedEntitlements['isTrial'] == true) {
        if (kDebugMode) {
          debugPrint('✅ [UnifiedSubscriptionManager] ${retryNumber}차 재시도 성공!');
        }
        return;
      }
      
      // 🎯 최종 재시도 실패 시 에러 UI 표시
      if (retryNumber == _maxRetries) {
        if (kDebugMode) {
          debugPrint('❌ [UnifiedSubscriptionManager] 모든 재시도 실패 - 에러 UI 표시');
        }
        _emitError('구독 상태 업데이트에 실패했습니다. 잠시 후 다시 시도해주세요.');
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UnifiedSubscriptionManager] ${retryNumber}차 재시도 실패: $e');
      }
      
      if (retryNumber == _maxRetries) {
        _emitError('구독 상태 확인 중 오류가 발생했습니다.');
      }
    }
  }

  /// 🎯 간단한 권한 확인 (UI에서 자주 사용)
  /// 
  /// **사용법:**
  /// ```dart
  /// if (await manager.canUsePremiumFeatures()) {
  ///   // 프리미엄 기능 사용 가능
  /// }
  /// ```
  Future<bool> canUsePremiumFeatures() async {
    final entitlements = await getSubscriptionEntitlements();
    return entitlements['isPremium'] == true || entitlements['isTrial'] == true;
  }

  /// 🎯 구매 완료 후 캐시 무효화 (기존 호환성)
  /// InAppPurchaseService에서 호출
  void notifyPurchaseCompleted() {
    invalidateCache();
    
    if (kDebugMode) {
      debugPrint('🛒 [UnifiedSubscriptionManager] 구매 완료 - 캐시 무효화');
    }
    
    _startSimplifiedRetry();
  }

  /// 🎯 이벤트 발행 헬퍼 메서드들 (직접 발행)
  /// 구독 상태를 조회한 후 직접 SubscriptionEvent 발행
  
  /// 기본 이벤트 발행
  void _emitSubscriptionEvent(SubscriptionEvent event) {
    if (kDebugMode) {
      debugPrint('📡 [UnifiedSubscriptionManager] 이벤트 발행: ${event.type} (${event.context})');
      debugPrint('   상태: ${event.state.entitlement.value} / ${event.state.subscriptionStatus.value}');
    }
    
    _subscriptionEventController.add(event);
  }
  
  /// 구독 상태와 함께 이벤트 발행
  void _emitWithState({
    required SubscriptionEventType eventType,
    required SubscriptionState state,
    String context = 'unknown',
    Map<String, dynamic>? metadata,
  }) {
    final event = SubscriptionEvent(
      type: eventType,
      state: state,
      context: context,
      metadata: metadata,
    );
    
    _emitSubscriptionEvent(event);
  }

  Future<void> _emitPurchaseCompletedEvent({String context = 'purchase', Map<String, dynamic>? metadata}) async {
    final entitlements = await getSubscriptionEntitlements(forceRefresh: true);
    final state = _createSubscriptionState(entitlements);
    
    _emitWithState(
      eventType: SubscriptionEventType.purchased,
      state: state,
      context: context,
      metadata: metadata,
    );
  }

  Future<void> _emitTrialStartedEvent({String context = 'trial', Map<String, dynamic>? metadata}) async {
    final entitlements = await getSubscriptionEntitlements(forceRefresh: true);
    final state = _createSubscriptionState(entitlements);
    
    _emitWithState(
      eventType: SubscriptionEventType.trialStarted,
      state: state,
      context: context,
      metadata: metadata,
    );
  }

  Future<void> _emitExpiredEvent({String context = 'webhook', Map<String, dynamic>? metadata}) async {
    final entitlements = await getSubscriptionEntitlements(forceRefresh: true);
    final state = _createSubscriptionState(entitlements);
    
    _emitWithState(
      eventType: SubscriptionEventType.expired,
      state: state,
      context: context,
      metadata: metadata,
    );
  }

  Future<void> _emitRefundedEvent({String context = 'webhook', Map<String, dynamic>? metadata}) async {
    final entitlements = await getSubscriptionEntitlements(forceRefresh: true);
    final state = _createSubscriptionState(entitlements);
    
    _emitWithState(
      eventType: SubscriptionEventType.refunded,
      state: state,
      context: context,
      metadata: metadata,
    );
  }

  Future<void> _emitWebhookReceivedEvent({String context = 'webhook', Map<String, dynamic>? metadata}) async {
    final entitlements = await getSubscriptionEntitlements(forceRefresh: true);
    final state = _createSubscriptionState(entitlements);
    
    _emitWithState(
      eventType: SubscriptionEventType.webhookReceived,
      state: state,
      context: context,
      metadata: metadata,
    );
  }

  /// 🎯 권한 정보로 SubscriptionState 생성 (이벤트용)
  SubscriptionState _createSubscriptionState(Map<String, dynamic> entitlements) {
    return SubscriptionState(
      entitlement: Entitlement.fromString(entitlements['entitlement']),
      subscriptionStatus: SubscriptionStatus.fromString(entitlements['subscriptionStatus']),
      hasUsedTrial: entitlements['hasUsedTrial'],
      hasUsageLimitReached: false, // 🎯 각 화면에서 개별 확인
      activeBanners: [], // 🎯 BannerManager 이벤트 리스너에서 처리
      statusMessage: (entitlements as EntitlementResult).statusMessage,
    );
  }

  /// 🎯 에러 UI 알림
  /// errorStream.listen()으로 UI에서 구독하여 스낵바 등으로 표시
  void _emitError(String message) {
    _errorStreamController.add(message);
    if (kDebugMode) {
      debugPrint('🚨 [UnifiedSubscriptionManager] 에러 UI 알림: $message');
    }
  }

  /// 캐시 관리
  void invalidateCache() {
    _cachedEntitlements = null;
    _lastEntitlementCheck = null;
    _ongoingEntitlementRequest = null;
    
    if (kDebugMode) {
      debugPrint('🗑️ [UnifiedSubscriptionManager] 권한 캐시 무효화');
    }
  }

  /// 🎯 스트림 접근자들
  Stream<Map<String, dynamic>> get entitlementStream => _entitlementStreamController.stream;
  Stream<String> get purchaseCompletedStream => _purchaseCompletedStreamController.stream;
  Stream<String> get errorStream => _errorStreamController.stream;
  /// 구독 이벤트 스트림 (SubscriptionEventManager 대체)
  Stream<SubscriptionEvent> get subscriptionEventStream => _subscriptionEventController.stream;

  /// 🎯 현재 상태 접근자들
  bool get isListening => _isListening;
  bool get isInitialized => _isInitialized;
  Map<String, dynamic>? get cachedEntitlements => _cachedEntitlements;
  bool get isPremium => _cachedEntitlements?['premium'] ?? false;
  bool get isTrial => _cachedEntitlements?['trial'] ?? false;
  bool get isExpired => _cachedEntitlements?['expired'] ?? false;

  void dispose() {
    _purchaseStreamSubscription?.cancel();
    _webhookStreamSubscription?.cancel();
    _entitlementStreamController.close();
    _purchaseCompletedStreamController.close();
    _errorStreamController.close();
    _processedTransactionIds.clear();
    invalidateCache();
    _isListening = false;
    _isInitialized = false;
    
    if (kDebugMode) {
      debugPrint('🔄 [UnifiedSubscriptionManager] 통합 서비스 종료');
    }
  }
} 