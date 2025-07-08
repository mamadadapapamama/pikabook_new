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

  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
  
  // 🎯 단일 캐시 시스템
  EntitlementResult? _cachedResult;
  DateTime? _lastCacheTime;
  static const Duration _cacheValidDuration = Duration(minutes: 5);
  
  // 🎯 중복 요청 방지 + 디바운싱
  Future<EntitlementResult>? _ongoingRequest;
  DateTime? _lastRequestTime;
  static const Duration _debounceDelay = Duration(milliseconds: 500);

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
    // 🚨 로그인 상태 우선 체크 (무한 반복 방지)
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (kDebugMode) {
        debugPrint('⚠️ [EntitlementEngine] 로그인되지 않음 - notLoggedIn 반환');
      }
      return EntitlementResult.notLoggedIn();
    }
    
    // 🎯 디바운싱: 500ms 이내 연속 요청 방지
    final now = DateTime.now();
    if (_lastRequestTime != null && now.difference(_lastRequestTime!) < _debounceDelay) {
      if (kDebugMode) {
        debugPrint('⏱️ [EntitlementEngine] 디바운싱: 너무 빠른 연속 요청 - 캐시 사용');
      }
      // 캐시가 있으면 캐시 반환, 없으면 기본값
      return _cachedResult ?? EntitlementResult.free();
    }
    _lastRequestTime = now;
    
    // 🎯 캐시 우선 사용 (forceRefresh가 false이거나 캐시가 매우 최신인 경우)
    if (_isCacheValid()) {
      if (!forceRefresh) {
        if (kDebugMode) {
          debugPrint('📦 [EntitlementEngine] 유효한 캐시 사용');
        }
        return _cachedResult!;
      } else {
        // forceRefresh=true여도 캐시가 1분 이내면 캐시 사용
        final cacheAge = DateTime.now().difference(_lastCacheTime!);
        if (cacheAge < Duration(minutes: 1)) {
          if (kDebugMode) {
            debugPrint('📦 [EntitlementEngine] forceRefresh이지만 캐시가 너무 최신 (${cacheAge.inSeconds}초) - 캐시 사용');
          }
          return _cachedResult!;
        }
      }
    }
    
    // 🎯 중복 요청 방지
    if (_ongoingRequest != null) {
        debugPrint('⏳ [EntitlementEngine] 진행 중인 요청 대기');
      return await _ongoingRequest!;
    }

    // 새로운 요청 시작
    debugPrint('🚀 [EntitlementEngine] 새로운 요청 시작');
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

  /// Step 1: Receipt 검증 (Firebase Functions 호출) - 재시도 로직 포함
  Future<Map<String, dynamic>> _validateReceipt() async {
    // 🔥 강제 로그
    print('🔥🔥🔥 [EntitlementEngine] _validateReceipt 시작! 🔥🔥🔥');
    
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      print('🔥 ERROR: 사용자 로그인 안됨');
      throw Exception('사용자가 로그인되지 않음');
    }

    print('🔥 사용자 UID: ${currentUser.uid}');
    final callable = _functions.httpsCallable('sub_checkSubscriptionStatus');
    
    // 🎯 재시도 로직 (최대 3회)
    Exception? lastException;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
          debugPrint('🔄 [EntitlementEngine] Firebase Functions 호출 시도 $attempt/3');
        
        print('🔥 Firebase Functions 호출 중...');
        final result = await callable.call({
          'appStoreFirst': true,
        }).timeout(
          Duration(seconds: 15 + (attempt * 5)), // 점진적으로 타임아웃 증가
          onTimeout: () => throw Exception('Firebase Functions 타임아웃 (시도 $attempt)'),
        );

        print('🔥 Firebase Functions 응답 받음!');
        final data = Map<String, dynamic>.from(result.data as Map);
        print('🔥 응답 데이터 변환 완료: ${data.toString()}');
        
        // 🔍 모든 서버 응답 로깅 (성공/실패 무관)
          debugPrint('�� [EntitlementEngine] 서버 전체 응답:');
          debugPrint('   data: ${data.toString()}');
          debugPrint('   success: ${data['success']}');
          debugPrint('   error: ${data['error']}');
          debugPrint('   message: ${data['message']}');
        
        if (data['success'] != true) {
          final errorMsg = data['error'] ?? data['message'] ?? '구독 데이터 없음';
            debugPrint('❌ [EntitlementEngine] 서버 오류 응답: $errorMsg');
          throw Exception('서버 오류: $errorMsg (시도 $attempt)');
        }

          debugPrint('✅ [EntitlementEngine] Firebase Functions 호출 성공 (시도 $attempt)');
          debugPrint('📊 [EntitlementEngine] 서버 응답 데이터:');
          debugPrint('   전체 응답: ${data.toString()}');
          
          final subscription = data['subscription'] as Map?;
          if (subscription != null) {
          debugPrint('   📦 구독 데이터: ${subscription.toString()}');
          debugPrint('   📝 주요 필드들:');
          debugPrint('      currentPlan: ${subscription['currentPlan']}');
          debugPrint('      isActive: ${subscription['isActive']}');
          debugPrint('      planStatus: ${subscription['planStatus']}');
          debugPrint('      autoRenewStatus: ${subscription['autoRenewStatus']}');
          debugPrint('      subscriptionType: ${subscription['subscriptionType']}');
          debugPrint('      expirationDate: ${subscription['expirationDate']}');
          debugPrint('   📋 모든 키-값 쌍:');
          subscription.forEach((key, value) {
            debugPrint('      $key: $value (${value.runtimeType})');
          });
          } else {
            debugPrint('   ⚠️ 구독 데이터가 null입니다!');
        }
        
        return Map<String, dynamic>.from(data['subscription'] as Map);
        
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
        
          debugPrint('❌ [EntitlementEngine] Firebase Functions 호출 실패 (시도 $attempt): $e');
        
        // 마지막 시도가 아니면 잠시 대기 후 재시도
        if (attempt < 3) {
          await Future.delayed(Duration(seconds: attempt * 2));
        }
      }
    }
    
    // 모든 시도 실패
    throw lastException ?? Exception('Firebase Functions 호출 실패');
  }

  /// Step 2: 상태 분석 (Entitlement Code 생성)
  double _analyzeSubscriptionState(Map<String, dynamic> receiptData) {
    // 🔥 강제 로그
    print('🔥🔥🔥 [EntitlementEngine] _analyzeSubscriptionState 시작! 🔥🔥🔥');
    print('🔥 받은 데이터: ${receiptData.toString()}');
    
    final isActive = receiptData['isActive'] as bool? ?? false;
    final currentPlan = receiptData['currentPlan'] as String? ?? 'free';
    final autoRenewStatus = receiptData['autoRenewStatus'] as bool? ?? false;
    
    print('🔥 분석 결과:');
    print('🔥   isActive: $isActive');
    print('🔥   currentPlan: $currentPlan');
    print('🔥   autoRenewStatus: $autoRenewStatus');
    
    debugPrint('🔍 [EntitlementEngine] 상태 분석 시작:');
    debugPrint('   isActive: $isActive');
    debugPrint('   currentPlan: $currentPlan');
    debugPrint('   autoRenewStatus: $autoRenewStatus');
    debugPrint('   전체 receiptData: ${receiptData.toString()}');
    
    // 🎯 표준 Entitlement Code 시스템
    // 양수: 서비스 접근 허용, 음수: 접근 거부
    double entitlementCode;
    if (isActive && currentPlan == 'trial') {
      entitlementCode = autoRenewStatus ? 1.1 : 1.2; // 체험 (자동갱신 여부)
    } else if (isActive && currentPlan == 'premium') {
      entitlementCode = autoRenewStatus ? 2.1 : 2.2; // 프리미엄 (자동갱신 여부)
    } else if (currentPlan == 'free') {
      entitlementCode = -1.0; // 무료 플랜
    } else {
      entitlementCode = -2.0; // 만료/취소
    }
    
    debugPrint('   📊 결과 entitlementCode: $entitlementCode');
    
    return entitlementCode;
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
    
    debugPrint('🔍 [EntitlementEngine] 권한 부여 결정 시작:');
    debugPrint('   entitlementCode: $entitlementCode');
    debugPrint('   planStatusString: $planStatusString');
    debugPrint('   planStatus: $planStatus');
    debugPrint('   hasAccess: $hasAccess');
    debugPrint('   isTrial: $isTrial');
    debugPrint('   isPremium: $isPremium');
    debugPrint('   autoRenewStatus: $autoRenewStatus');
    debugPrint('   subscriptionType: $subscriptionType');
    
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

    final result = EntitlementResult(
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
    
    debugPrint('📊 [EntitlementEngine] 최종 권한 결과:');
    debugPrint('   statusMessage: $statusMessage');
    debugPrint('   hasAccess: $hasAccess');
    debugPrint('   isTrial: $isTrial');
    debugPrint('   isPremium: $isPremium');
    debugPrint('   planStatus: $planStatus');
    debugPrint('   entitlementCode: $entitlementCode');
    
    return result;
  }

  /// Firestore 폴백 처리
  Future<EntitlementResult> _handleFirestoreFallback() async {
    debugPrint('🔄 [EntitlementEngine] Firestore 폴백 처리 시작');
    
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        debugPrint('❌ [EntitlementEngine] Firestore 폴백: 사용자 로그인 안됨');
        return EntitlementResult.notLoggedIn();
      }

      debugPrint('🔍 [EntitlementEngine] Firestore에서 사용자 문서 조회: ${currentUser.uid}');
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) {
        debugPrint('❌ [EntitlementEngine] Firestore 폴백: 사용자 문서 없음');
        return EntitlementResult.free();
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final subscriptionData = userData['subscription'] as Map<String, dynamic>?;
      
      debugPrint('📦 [EntitlementEngine] Firestore 사용자 데이터: ${userData.toString()}');
      debugPrint('📦 [EntitlementEngine] Firestore 구독 데이터: ${subscriptionData.toString()}');
      
      if (subscriptionData == null) {
        debugPrint('❌ [EntitlementEngine] Firestore 폴백: 구독 데이터 없음');
        return EntitlementResult.free();
      }

      // Firestore 데이터로 EntitlementResult 생성
      final plan = subscriptionData['plan'] as String? ?? 'free';
      final isActive = subscriptionData['isActive'] as bool? ?? false;
      final isFreeTrial = subscriptionData['isFreeTrial'] as bool? ?? false;

      debugPrint('🔍 [EntitlementEngine] Firestore 데이터 분석:');
      debugPrint('   plan: $plan');
      debugPrint('   isActive: $isActive');
      debugPrint('   isFreeTrial: $isFreeTrial');

      if (isActive && isFreeTrial) {
        debugPrint('✅ [EntitlementEngine] Firestore 폴백 결과: trial');
        return EntitlementResult.trial();
      } else if (isActive && plan == 'premium') {
        debugPrint('✅ [EntitlementEngine] Firestore 폴백 결과: premium');
        return EntitlementResult.premium();
      } else {
        debugPrint('✅ [EntitlementEngine] Firestore 폴백 결과: free');
        return EntitlementResult.free();
      }

    } catch (e) {
        debugPrint('❌ [EntitlementEngine] Firestore 폴백 실패: $e');
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
    
      debugPrint('🗑️ [EntitlementEngine] 캐시 무효화');
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