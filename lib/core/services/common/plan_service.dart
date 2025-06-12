import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'usage_limit_service.dart';
import '../../models/plan.dart';

/// 구독 플랜과 사용량 관리를 위한 서비스
class PlanService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UsageLimitService _usageLimitService = UsageLimitService();
  
  // 플랜 유형
  static const String PLAN_FREE = 'free';
  static const String PLAN_PREMIUM = 'premium';
  
  // 플랜별 제한
  static const Map<String, Map<String, int>> PLAN_LIMITS = {
    PLAN_FREE: {
      'ocrPages': 30,          // 월 30페이지
      'translatedChars': 10000,  // 월 10,000자
      'ttsRequests': 0,      // 월 0회
      'storageBytes': 52428800, // 50MB (50 * 1024 * 1024)
    },
    PLAN_PREMIUM: {
      'ocrPages': 300,          // 월 300페이지
      'translatedChars': 100000, // 월 10만자
      'ttsRequests': 1000,      // 월 1,000회
      'storageBytes': 1073741824, // 1GB (1024 * 1024 * 1024)
    },
  };
  
  // SharedPreferences 키
  static const String _kPlanTypeKey = 'plan_type';
  static const String _kPlanExpiryKey = 'plan_expiry';
  static const String _kLastPlanTypeKey = 'last_plan_type';
  
  // 싱글톤 패턴 구현
  static final PlanService _instance = PlanService._internal();
  factory PlanService() => _instance;
  
  PlanService._internal();
  
  // 캐시 관련 변수
  String? _cachedPlanType;
  String? _cachedUserId;
  DateTime? _cacheTimestamp;
  static const Duration _cacheValidDuration = Duration(minutes: 5); // 5분간 캐시 유효
  
  // 현재 사용자 ID 가져오기
  String? get _currentUserId => _auth.currentUser?.uid;
  
  /// 현재 사용자의 플랜 타입 가져오기
  Future<String> getCurrentPlanType() async {
    try {
      // 캐시 확인
      if (_cachedPlanType != null && 
          _cachedUserId == _currentUserId && 
          _cacheTimestamp != null &&
          DateTime.now().difference(_cacheTimestamp!).compareTo(_cacheValidDuration) < 0) {
        if (kDebugMode) {
          debugPrint('🚀 PlanService - 캐시된 플랜 타입 사용: $_cachedPlanType');
        }
        return _cachedPlanType!;
      }
      
      if (_currentUserId != null) {
        final userDoc = await _firestore
            .collection('users')
            .doc(_currentUserId)
            .get();
            
        if (userDoc.exists) {
          final userData = userDoc.data();
          
          if (kDebugMode) {
            debugPrint('🔍 PlanService - 사용자 데이터 확인:');
            debugPrint('   사용자 ID: $_currentUserId');
            debugPrint('   subscription: ${userData?['subscription']}');
            debugPrint('   planType: ${userData?['planType']}');
          }
          
          // 1. 새로운 subscription 구조 확인
          final planData = userData?['subscription'];
          if (planData != null) {
            final planType = planData['plan'] as String?;
            final expiryDate = planData['expiryDate'];
            
            if (kDebugMode) {
              debugPrint('🔍 subscription 구조 발견:');
              debugPrint('   plan: $planType');
              debugPrint('   expiryDate: $expiryDate');
              debugPrint('   현재 시간: ${DateTime.now()}');
            }
            
            // Premium 플랜이고 만료되지 않았으면 Premium 반환
            if (planType == PLAN_PREMIUM && expiryDate != null) {
              final expiry = (expiryDate as Timestamp).toDate();
              if (expiry.isAfter(DateTime.now())) {
                debugPrint('✅ 프리미엄 플랜 확인됨! (만료일: $expiry)');
                _updateCache(PLAN_PREMIUM);
                return PLAN_PREMIUM;
              } else {
                debugPrint('⚠️ 프리미엄 플랜이지만 만료됨 (만료일: $expiry)');
              }
            }
          }
          
          // 2. 기존 planType 필드 확인 (하위 호환성)
          final legacyPlanType = userData?['planType'] as String?;
          if (legacyPlanType != null) {
            // 기존 데이터가 있으면 새 구조로 마이그레이션
            if (legacyPlanType == 'premium') {
              _updateCache(PLAN_PREMIUM);
              return PLAN_PREMIUM;
            } else if (legacyPlanType == 'free') {
              _updateCache(PLAN_FREE);
              return PLAN_FREE;
            }
          }
        }
      }

      // 기본값은 Free
      _updateCache(PLAN_FREE);
      return PLAN_FREE;
    } catch (e) {
      debugPrint('플랜 정보 조회 오류: $e');
      _updateCache(PLAN_FREE);
      return PLAN_FREE;
    }
  }
  
  /// 캐시 업데이트
  void _updateCache(String planType) {
    _cachedPlanType = planType;
    _cachedUserId = _currentUserId;
    _cacheTimestamp = DateTime.now();
  }
  
  /// 캐시 초기화 (사용자 변경 시 등)
  void clearCache() {
    _cachedPlanType = null;
    _cachedUserId = null;
    _cacheTimestamp = null;
  }
  
  /// 플랜 변경 감지
  Future<bool> hasPlanChangedToFree() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastPlanType = prefs.getString(_kLastPlanTypeKey);
      final currentPlanType = await getCurrentPlanType();
      
      // 현재 플랜 저장
      await prefs.setString(_kLastPlanTypeKey, currentPlanType);
      
      // 이전 플랜이 없거나 현재 플랜과 같으면 false
      if (lastPlanType == null || lastPlanType == currentPlanType) {
        return false;
      }
      
      // 이전 플랜이 Free가 아니고, 현재 플랜이 Free인 경우에만 true
      return lastPlanType != PLAN_FREE && currentPlanType == PLAN_FREE;
    } catch (e) {
      debugPrint('플랜 변경 감지 중 오류: $e');
      return false;
    }
  }
  
  /// 플랜 이름 가져오기 (표시용)
  String getPlanName(String planType, {bool showBadge = false}) {
    switch (planType) {
      case PLAN_PREMIUM:
        return '프리미엄';
      case PLAN_FREE:
      default:
        return showBadge ? '무료 플랜' : '무료';
    }
  }
  
  /// 플랜별 기능 제한 정보 가져오기
  Future<Map<String, int>> getPlanLimits(String planType) async {
    return Map<String, int>.from(PLAN_LIMITS[planType] ?? PLAN_LIMITS[PLAN_FREE]!);
  }
  
  /// 현재 사용량 퍼센트 가져오기
  Future<Map<String, double>> getUsagePercentages() async {
    return await _usageLimitService.getUsagePercentages();
  }
  
  /// 현재 사용량 데이터 가져오기
  Future<Map<String, dynamic>> getCurrentUsage() async {
    return await _usageLimitService.getUserUsage(forceRefresh: true);
  }
  
  /// 사용자의 구독 업그레이드 여부 확인
  Future<bool> canUpgradePlan() async {
    final currentPlan = await getCurrentPlanType();
    return currentPlan != PLAN_PREMIUM;
  }
  
  /// 플랜 상세 정보 (UI 표시용)
  Future<Map<String, dynamic>> getPlanDetails() async {
    final planType = await getCurrentPlanType();
    final planLimits = await getPlanLimits(planType);
    final currentUsage = await getCurrentUsage();
    final usagePercentages = await getUsagePercentages();
    
    return {
      'planType': planType,
      'planName': getPlanName(planType),
      'planLimits': planLimits,
      'currentUsage': currentUsage,
      'usagePercentages': usagePercentages,
    };
  }
  
  /// 사용자 제한 상태 확인
  Future<Map<String, dynamic>> checkUserLimits() async {
    return await _usageLimitService.checkFreeLimits();
  }
  
  /// Plan 모델을 사용하여 현재 플랜 정보 가져오기
  Future<Plan> getCurrentPlan() async {
    try {
      final subscriptionDetails = await getSubscriptionDetails();
      final currentPlan = subscriptionDetails['currentPlan'] as String;
      final isFreeTrial = subscriptionDetails['isFreeTrial'] as bool;
      final daysRemaining = subscriptionDetails['daysRemaining'] as int;
      final expiryDate = subscriptionDetails['expiryDate'] as DateTime?;
      final hasUsedFreeTrial = subscriptionDetails['hasUsedFreeTrial'] as bool;
      
      final limits = await getPlanLimits(currentPlan);
      
      if (currentPlan == PLAN_PREMIUM && isFreeTrial && daysRemaining > 0) {
        // 프리미엄 체험 중
        return Plan.premiumTrial(
          daysRemaining: daysRemaining,
          expiryDate: expiryDate,
          limits: limits,
        ).copyWith(hasUsedFreeTrial: hasUsedFreeTrial);
      } else if (currentPlan == PLAN_PREMIUM) {
        // 정식 프리미엄
        return Plan.premium(limits: limits).copyWith(
          hasUsedFreeTrial: hasUsedFreeTrial,
          expiryDate: expiryDate,
        );
      } else {
        // 무료 플랜
        return Plan.free(limits: limits).copyWith(
          hasUsedFreeTrial: hasUsedFreeTrial,
        );
      }
    } catch (e) {
      debugPrint('현재 플랜 정보 가져오기 중 오류: $e');
      return Plan.free();
    }
  }
  
  /// Plan 모델을 사용하여 플랜 이름 가져오기
  Future<String> getPlanDisplayName() async {
    final plan = await getCurrentPlan();
    return plan.name;
  }
  
  /// 문의하기 기능
  Future<void> contactSupport({String? subject, String? body}) async {
    try {
      // 여기에 문의하기 기능 구현 (이메일 발송 등)
      // 나중에 확장하기 위한 공간
      debugPrint('문의하기 기능 호출됨: subject=$subject, body=$body');
    } catch (e) {
      debugPrint('문의하기 기능 오류: $e');
      rethrow;
    }
  }

  /// Premium 플랜으로 업그레이드
  Future<bool> upgradeToPremium(String userId, {
    required DateTime expiryDate,
  }) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .set({
            'subscription': {
              'plan': PLAN_PREMIUM,
              'startDate': FieldValue.serverTimestamp(),
              'expiryDate': Timestamp.fromDate(expiryDate),
              'status': 'active',
            }
          }, SetOptions(merge: true));
      
      return true;
    } catch (e) {
      debugPrint('프리미엄 업그레이드 실패: $e');
      return false;
    }
  }

  /// 월간 사용량 초기화 (매월 1일 실행)
  Future<void> resetMonthlyUsage() async {
    final planType = await getCurrentPlanType();
    
    // Premium이 아닌 경우만 초기화
    if (planType == PLAN_FREE) {
      await _usageLimitService.resetAllUsage();
    }
  }

  /// 신규 사용자 7일 무료 체험 시작
  Future<bool> startFreeTrial(String userId) async {
    try {
      // 이미 체험을 사용했는지 확인
      final userDoc = await _firestore
          .collection('users')
          .doc(userId)
          .get();
          
      if (userDoc.exists) {
        final userData = userDoc.data();
        final hasUsedTrial = userData?['hasUsedFreeTrial'] as bool? ?? false;
        
        if (hasUsedTrial) {
          debugPrint('이미 무료 체험을 사용한 사용자: $userId');
          return false;
        }
      }
      
      // 7일 후 만료일 설정
      final expiryDate = DateTime.now().add(const Duration(days: 7));
      
      // 무료 체험 시작
      await _firestore
          .collection('users')
          .doc(userId)
          .set({
            'subscription': {
              'plan': PLAN_PREMIUM,
              'startDate': FieldValue.serverTimestamp(),
              'expiryDate': Timestamp.fromDate(expiryDate),
              'status': 'trial', // 체험 상태
              'isFreeTrial': true,
            },
            'hasUsedFreeTrial': true, // 체험 사용 기록
          }, SetOptions(merge: true));
      
      debugPrint('7일 무료 체험 시작: $userId, 만료일: $expiryDate');
      return true;
    } catch (e) {
      debugPrint('무료 체험 시작 실패: $e');
      return false;
    }
  }
  
  /// 무료 체험 사용 여부 확인
  Future<bool> hasUsedFreeTrial(String userId) async {
    try {
      final userDoc = await _firestore
          .collection('users')
          .doc(userId)
          .get();
          
      if (userDoc.exists) {
        final userData = userDoc.data();
        return userData?['hasUsedFreeTrial'] as bool? ?? false;
      }
      
      return false;
    } catch (e) {
      debugPrint('무료 체험 사용 여부 확인 오류: $e');
      return false;
    }
  }
  
  /// 구독 상세 정보 조회
  Future<Map<String, dynamic>> getSubscriptionDetails() async {
    try {
      final userId = _currentUserId;
      if (userId == null) {
        return {
          'currentPlan': PLAN_FREE,
          'hasUsedFreeTrial': false,
          'isFreeTrial': false,
          'daysRemaining': 0,
          'expiryDate': null,
        };
      }

      final userDoc = await _firestore
          .collection('users')
          .doc(userId)
          .get();

      if (!userDoc.exists) {
        return {
          'currentPlan': PLAN_FREE,
          'hasUsedFreeTrial': false,
          'isFreeTrial': false,
          'daysRemaining': 0,
          'expiryDate': null,
        };
      }

      final data = userDoc.data() as Map<String, dynamic>;
      final subscriptionData = data['subscription'] as Map<String, dynamic>?;
      
      // hasUsedFreeTrial은 사용자 문서의 루트 레벨에서 가져오기
      final hasUsedFreeTrial = data['hasUsedFreeTrial'] as bool? ?? false;

      if (subscriptionData == null) {
        return {
          'currentPlan': PLAN_FREE,
          'hasUsedFreeTrial': hasUsedFreeTrial,
          'isFreeTrial': false,
          'daysRemaining': 0,
          'expiryDate': null,
        };
      }

      final plan = subscriptionData['plan'] as String? ?? PLAN_FREE;
      final status = subscriptionData['status'] as String?;
      final isFreeTrial = subscriptionData['isFreeTrial'] as bool? ?? false;
      final expiryDate = subscriptionData['expiryDate'] as Timestamp?;

      int daysRemaining = 0;
      String currentPlan = PLAN_FREE;

      if (expiryDate != null) {
        final expiry = expiryDate.toDate();
        final now = DateTime.now();
        
        if (expiry.isAfter(now)) {
          daysRemaining = expiry.difference(now).inDays;
          currentPlan = plan; // 만료되지 않았으면 원래 플랜
        } else {
          currentPlan = PLAN_FREE; // 만료되었으면 무료 플랜
        }
      }

      if (kDebugMode) {
        print('🔍 구독 상세 정보 조회 결과:');
        print('   사용자 ID: $userId');
        print('   현재 플랜: $currentPlan');
        print('   무료 체험 사용 여부: $hasUsedFreeTrial');
        print('   현재 무료 체험 중: $isFreeTrial');
        print('   남은 일수: $daysRemaining');
        print('   만료일: ${expiryDate?.toDate()}');
        print('   상태: $status');
      }

      return {
        'currentPlan': currentPlan,
        'hasUsedFreeTrial': hasUsedFreeTrial,
        'isFreeTrial': isFreeTrial,
        'daysRemaining': daysRemaining,
        'expiryDate': expiryDate?.toDate(),
        'status': status,
      };
    } catch (e) {
      debugPrint('구독 상세 정보 조회 중 오류: $e');
      return {
        'currentPlan': PLAN_FREE,
        'hasUsedFreeTrial': false,
        'isFreeTrial': false,
        'daysRemaining': 0,
        'expiryDate': null,
      };
    }
  }
} 
