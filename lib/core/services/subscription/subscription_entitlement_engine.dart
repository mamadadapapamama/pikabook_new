import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../../models/plan_status.dart';

/// 표준 Entitlement Engine 패턴 구현
/// Apple WWDC 2020 "Architecting for Subscriptions" 기반
class SubscriptionEntitlementEngine {
  static final SubscriptionEntitlementEngine _instance = SubscriptionEntitlementEngine._internal();
  factory SubscriptionEntitlementEngine() => _instance;
  SubscriptionEntitlementEngine._internal();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  
  // 🎯 단일 캐시 시스템
  EntitlementResult? _cachedResult;
  DateTime? _lastCacheTime;
  static const Duration _cacheValidDuration = Duration(hours: 24);
  
  // 🎯 중복 요청 방지
  Future<EntitlementResult>? _ongoingRequest;

  /// 🎯 Step 1: 트랜잭션 수신 (Transaction Listener)
  /// 앱 시작 시 한 번만 호출
  Future<void> startTransactionListener() async {
    if (kDebugMode) {
      debugPrint('🔄 [EntitlementEngine] Transaction Listener 시작');
    }
    
    // StoreKit 2의 Transaction.updates 역할
    // 여기서는 Firebase Functions의 실시간 알림으로 대체
    // TODO: App Store Server Notifications V2 연동
  }

  /// 🎯 Step 2: 현재 권한 상태 확인 (Current Entitlements)
  /// 표준 3단계 프로세스: Receipt 검증 → 상태 분석 → 권한 부여
  Future<EntitlementResult> getCurrentEntitlements({bool forceRefresh = false}) async {
    // 🎯 캐시 우선 사용
    if (!forceRefresh && _isCacheValid()) {
      if (kDebugMode) {
        debugPrint('📦 [EntitlementEngine] 유효한 캐시 사용');
      }
      return _cachedResult!;
    }
    
    // 🎯 중복 요청 방지
    if (_ongoingRequest != null) {
      if (kDebugMode) {
        debugPrint('⏳ [EntitlementEngine] 진행 중인 요청 대기');
      }
      return await _ongoingRequest!;
    }

    // 새로운 요청 시작
    _ongoingRequest = _fetchEntitlements(forceRefresh);
    
    try {
      final result = await _ongoingRequest!;
      _updateCache(result);
      return result;
    } finally {
      _ongoingRequest = null;
    }
  }

  /// 실제 권한 조회 로직 (표준 Entitlement Engine)
  Future<EntitlementResult> _fetchEntitlements(bool forceRefresh) async {
    if (kDebugMode) {
      debugPrint('🎯 [EntitlementEngine] 권한 조회 시작 (forceRefresh: $forceRefresh)');
    }

    try {
      // Step 1: Receipt 검증 (Firebase Functions)
      final receiptData = await _validateReceipt();
      
      // Step 2: 상태 분석 (Entitlement Code 생성)
      final entitlementCode = _analyzeSubscriptionState(receiptData);
      
      // Step 3: 권한 부여 결정
      final entitlementResult = _generateEntitlementResult(entitlementCode, receiptData);
      
      if (kDebugMode) {
        debugPrint('✅ [EntitlementEngine] 권한 조회 완료: ${entitlementResult.statusMessage}');
      }
      
      return entitlementResult;
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [EntitlementEngine] 권한 조회 실패: $e');
      }
      
      // 폴백: Firestore 직접 조회
      return await _handleFirestoreFallback();
    }
  }

  /// Step 1: Receipt 검증 (Firebase Functions 호출)
  Future<Map<String, dynamic>> _validateReceipt() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception('사용자가 로그인되지 않음');
    }

    final callable = _functions.httpsCallable('sub_checkSubscriptionStatus');
    final result = await callable.call({
      'appStoreFirst': true,
    }).timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw Exception('Firebase Functions 타임아웃'),
    );

    final data = Map<String, dynamic>.from(result.data as Map);
    if (data['success'] != true) {
      throw Exception('구독 데이터 없음');
    }

    return Map<String, dynamic>.from(data['subscription'] as Map);
  }

  /// Step 2: 상태 분석 (Entitlement Code 생성)
  double _analyzeSubscriptionState(Map<String, dynamic> receiptData) {
    final isActive = receiptData['isActive'] as bool? ?? false;
    final currentPlan = receiptData['currentPlan'] as String? ?? 'free';
    final autoRenewStatus = receiptData['autoRenewStatus'] as bool? ?? false;
    
    // 🎯 표준 Entitlement Code 시스템
    // 양수: 서비스 접근 허용, 음수: 접근 거부
    if (isActive && currentPlan == 'trial') {
      return autoRenewStatus ? 1.1 : 1.2; // 체험 (자동갱신 여부)
    } else if (isActive && currentPlan == 'premium') {
      return autoRenewStatus ? 2.1 : 2.2; // 프리미엄 (자동갱신 여부)
    } else if (currentPlan == 'free') {
      return -1.0; // 무료 플랜
    } else {
      return -2.0; // 만료/취소
    }
  }

  /// Step 3: 권한 부여 결정
  EntitlementResult _generateEntitlementResult(double entitlementCode, Map<String, dynamic> receiptData) {
    final planStatusString = receiptData['planStatus'] as String? ?? 'free';
    final planStatus = PlanStatus.fromString(planStatusString);
    final hasAccess = entitlementCode > 0;
    final isTrial = entitlementCode >= 1.0 && entitlementCode < 2.0;
    final isPremium = entitlementCode >= 2.0;
    final autoRenewStatus = receiptData['autoRenewStatus'] as bool? ?? false;
    final subscriptionType = receiptData['subscriptionType'] as String? ?? '';
    
    // 만료일 파싱
    DateTime? expirationDate;
    final expirationDateString = receiptData['expirationDate'] as String?;
    if (expirationDateString != null) {
      try {
        if (expirationDateString.contains('T')) {
          expirationDate = DateTime.parse(expirationDateString);
        } else if (RegExp(r'^\d{13}$').hasMatch(expirationDateString)) {
          expirationDate = DateTime.fromMillisecondsSinceEpoch(int.parse(expirationDateString));
        } else if (RegExp(r'^\d{10}$').hasMatch(expirationDateString)) {
          expirationDate = DateTime.fromMillisecondsSinceEpoch(int.parse(expirationDateString) * 1000);
        } else {
          expirationDate = DateTime.parse(expirationDateString);
        }
      } catch (e) {
        expirationDate = null;
      }
    }
    
    // 남은 일수 계산
    int daysUntilExpiration = 0;
    if (expirationDate != null) {
      final difference = expirationDate.difference(DateTime.now());
      daysUntilExpiration = difference.inDays;
    }
    
    // PlanStatus에 따른 정확한 표시명 생성
    String statusMessage;
    switch (planStatus) {
      case PlanStatus.trialActive:
        // 체험 활성: '프리미엄 체험 (#일 남음)'
        if (daysUntilExpiration > 0) {
          statusMessage = '프리미엄 체험 ($daysUntilExpiration일 남음)';
        } else {
          statusMessage = '프리미엄 체험';
        }
        break;
      
      case PlanStatus.trialCancelled:
        // 체험 취소: '프리미엄 체험 (#일 남음)'
        if (daysUntilExpiration > 0) {
          statusMessage = '프리미엄 체험 ($daysUntilExpiration일 남음)';
        } else {
          statusMessage = '프리미엄 체험';
        }
        break;
      
      case PlanStatus.trialCompleted:
        // 체험 완료: '프리미엄 (monthly)'
        final subType = subscriptionType.isNotEmpty ? subscriptionType : 'monthly';
        statusMessage = '프리미엄 ($subType)';
        break;
      
      case PlanStatus.premiumActive:
        // 프리미엄 활성: '프리미엄 (monthly/yearly)'
        final subType = subscriptionType.isNotEmpty ? subscriptionType : 'monthly';
        statusMessage = '프리미엄 ($subType)';
        break;
      
      case PlanStatus.premiumGrace:
        // 프리미엄 유예: '프리미엄 (monthly) : 결제 확인 필요'
        final subType = subscriptionType.isNotEmpty ? subscriptionType : 'monthly';
        statusMessage = '프리미엄 ($subType) : 결제 확인 필요';
        break;
      
      case PlanStatus.premiumCancelled:
        // 프리미엄 취소: '프리미엄 (#일 남음)(monthly)'
        final subType = subscriptionType.isNotEmpty ? subscriptionType : 'monthly';
        if (daysUntilExpiration > 0) {
          statusMessage = '프리미엄 ($daysUntilExpiration일 남음)($subType)';
        } else {
          statusMessage = '프리미엄 ($subType)';
        }
        break;
      
      case PlanStatus.premiumExpired:
        // 프리미엄 만료: '무료'
        statusMessage = '무료';
        break;
      
      case PlanStatus.refunded:
        // 환불: '무료'
        statusMessage = '무료';
        break;
      
      case PlanStatus.free:
      default:
        // 무료: '무료'
        statusMessage = '무료';
        break;
    }

    return EntitlementResult(
      hasAccess: hasAccess,
      isTrial: isTrial,
      isPremium: isPremium,
      isExpired: !hasAccess,
      autoRenewStatus: autoRenewStatus,
      entitlementCode: entitlementCode,
      statusMessage: statusMessage,
      rawData: receiptData,
      planStatus: planStatus,
    );
  }

  /// Firestore 폴백 처리
  Future<EntitlementResult> _handleFirestoreFallback() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        return EntitlementResult.notLoggedIn();
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) {
        return EntitlementResult.free();
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final subscriptionData = userData['subscription'] as Map<String, dynamic>?;
      
      if (subscriptionData == null) {
        return EntitlementResult.free();
      }

      // Firestore 데이터로 EntitlementResult 생성
      final plan = subscriptionData['plan'] as String? ?? 'free';
      final isActive = subscriptionData['isActive'] as bool? ?? false;
      final isFreeTrial = subscriptionData['isFreeTrial'] as bool? ?? false;

      if (isActive && isFreeTrial) {
        return EntitlementResult.trial();
      } else if (isActive && plan == 'premium') {
        return EntitlementResult.premium();
      } else {
        return EntitlementResult.free();
      }

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [EntitlementEngine] Firestore 폴백 실패: $e');
      }
      return EntitlementResult.free();
    }
  }

  /// 캐시 관리
  bool _isCacheValid() {
    if (_cachedResult == null || _lastCacheTime == null) return false;
    final timeDiff = DateTime.now().difference(_lastCacheTime!);
    return timeDiff < _cacheValidDuration;
  }

  void _updateCache(EntitlementResult result) {
    _cachedResult = result;
    _lastCacheTime = DateTime.now();
  }

  void invalidateCache() {
    _cachedResult = null;
    _lastCacheTime = null;
    _ongoingRequest = null;
    
    if (kDebugMode) {
      debugPrint('🗑️ [EntitlementEngine] 캐시 무효화');
    }
  }

  void dispose() {
    invalidateCache();
  }
}

/// 권한 조회 결과 모델 (단순화)
class EntitlementResult {
  final bool hasAccess;
  final bool isTrial;
  final bool isPremium;
  final bool isExpired;
  final bool autoRenewStatus;
  final double entitlementCode;
  final String statusMessage;
  final Map<String, dynamic> rawData;
  final PlanStatus planStatus;

  const EntitlementResult({
    required this.hasAccess,
    required this.isTrial,
    required this.isPremium,
    required this.isExpired,
    required this.autoRenewStatus,
    required this.entitlementCode,
    required this.statusMessage,
    required this.rawData,
    required this.planStatus,
  });

  /// 팩토리 생성자들
  factory EntitlementResult.free() {
    return const EntitlementResult(
      hasAccess: false,
      isTrial: false,
      isPremium: false,
      isExpired: false,
      autoRenewStatus: false,
      entitlementCode: -1.0,
      statusMessage: '무료',
      rawData: {},
      planStatus: PlanStatus.free,
    );
  }

  factory EntitlementResult.trial() {
    return const EntitlementResult(
      hasAccess: true,
      isTrial: true,
      isPremium: false,
      isExpired: false,
      autoRenewStatus: true,
      entitlementCode: 1.1,
      statusMessage: '프리미엄 체험',
      rawData: {},
      planStatus: PlanStatus.trialActive,
    );
  }

  factory EntitlementResult.premium() {
    return const EntitlementResult(
      hasAccess: true,
      isTrial: false,
      isPremium: true,
      isExpired: false,
      autoRenewStatus: true,
      entitlementCode: 2.1,
      statusMessage: '프리미엄 (monthly)',
      rawData: {},
      planStatus: PlanStatus.premiumActive,
    );
  }

  factory EntitlementResult.notLoggedIn() {
    return const EntitlementResult(
      hasAccess: false,
      isTrial: false,
      isPremium: false,
      isExpired: false,
      autoRenewStatus: false,
      entitlementCode: -3.0,
      statusMessage: '로그인 필요',
      rawData: {},
      planStatus: PlanStatus.free,
    );
  }

  @override
  String toString() {
    return 'EntitlementResult(hasAccess: $hasAccess, statusMessage: $statusMessage, entitlementCode: $entitlementCode, planStatus: $planStatus)';
  }
} 