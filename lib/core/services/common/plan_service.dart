import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'usage_limit_service.dart';

/// 구독 플랜과 사용량 관리를 위한 서비스
class PlanService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UsageLimitService _usageLimitService = UsageLimitService();
  
  // 플랜 유형
  static const String PLAN_FREE = 'free';
  static const String PLAN_PREMIUM = 'premium';
  static const String PLAN_TRIAL = 'trial';
  
  // 베타/Trial 종료일 (2024년 5월 31일)
  static final DateTime TRIAL_END_DATE = DateTime(2024, 5, 31, 23, 59, 59);
  
  // 플랜별 제한
  static const Map<String, Map<String, int>> PLAN_LIMITS = {
    PLAN_FREE: {
      'ocrPages': 30,          // 월 30페이지
      'translatedChars': 3000,  // 월 3,000자
      'ttsRequests': 100,      // 월 100회
      'storageBytes': 52428800, // 50MB (50 * 1024 * 1024)
    },
    PLAN_PREMIUM: {
      'ocrPages': 300,          // 월 300페이지
      'translatedChars': 100000, // 월 10만자
      'ttsRequests': 1000,      // 월 1,000회
      'storageBytes': 1073741824, // 1GB (1024 * 1024 * 1024)
    },
    PLAN_TRIAL: {
      'ocrPages': 100,          // 14일간 100페이지
      'translatedChars': 20000,  // 14일간 2만자
      'ttsRequests': 500,       // 14일간 500회
      'storageBytes': 104857600, // 100MB (100 * 1024 * 1024)
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
  
  // 현재 사용자 ID 가져오기
  String? get _currentUserId => _auth.currentUser?.uid;
  
  /// 현재 사용자의 플랜 타입 가져오기
  Future<String> getCurrentPlanType() async {
    try {
      // 1. Premium 확인
      if (_currentUserId != null) {
        final userDoc = await _firestore
            .collection('users')
            .doc(_currentUserId)
            .get();
            
        if (userDoc.exists) {
          final planData = userDoc.data()?['subscription'];
          if (planData != null) {
            final planType = planData['plan'] as String?;
            final expiryDate = planData['expiryDate'];
            
            // Premium 플랜이고 만료되지 않았으면 Premium 반환
            if (planType == PLAN_PREMIUM && expiryDate != null) {
              final expiry = (expiryDate as Timestamp).toDate();
              if (expiry.isAfter(DateTime.now())) {
                return PLAN_PREMIUM;
              }
            }
          }
        }
      }

      // 2. Trial 확인
      final now = DateTime.now();
      
      // 전체 Trial 기간이 끝나지 않았고
      if (now.isBefore(TRIAL_END_DATE)) {
        // 개별 사용자의 14일 Trial 기간이 유효하면
        final isTrialValid = await _usageLimitService.isTrialPeriod();
        if (isTrialValid) {
          return PLAN_TRIAL;
        }
      }

      // 3. 나머지는 Free
      return PLAN_FREE;
    } catch (e) {
      debugPrint('플랜 정보 조회 오류: $e');
      return PLAN_FREE;
    }
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
    String name = '';
    switch (planType) {
      case PLAN_PREMIUM:
        name = '프리미엄';
        break;
      case PLAN_TRIAL:
        name = '체험판';
        break;
      case PLAN_FREE:
      default:
        name = '무료';
    }
    return showBadge && planType == PLAN_FREE ? '$name plan' : name;
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
    
    Map<String, dynamic> additionalInfo = {};
    
    // Trial 플랜인 경우 남은 기간 정보 추가
    if (planType == PLAN_TRIAL) {
      final trialInfo = await _usageLimitService.getTrialPeriodInfo();
      additionalInfo = {
        'remainingDays': trialInfo['remainingDays'],
        'trialEndDate': TRIAL_END_DATE.toIso8601String(),
      };
    }
    
    return {
      'planType': planType,
      'planName': getPlanName(planType),
      'planLimits': planLimits,
      'currentUsage': currentUsage,
      'usagePercentages': usagePercentages,
      ...additionalInfo,
    };
  }
  
  /// 사용자 제한 상태 확인
  Future<Map<String, dynamic>> checkUserLimits() async {
    return await _usageLimitService.checkFreeLimits();
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
    
    // Trial이나 Premium 플랜이 아닌 경우만 초기화
    if (planType == PLAN_FREE) {
      await _usageLimitService.resetAllUsage();
    }
  }
} 
