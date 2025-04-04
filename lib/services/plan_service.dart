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
  static const String PLAN_BETA = 'beta';
  
  // SharedPreferences 키
  static const String _kPlanTypeKey = 'plan_type';
  static const String _kPlanExpiryKey = 'plan_expiry';
  
  // 싱글톤 패턴 구현
  static final PlanService _instance = PlanService._internal();
  factory PlanService() => _instance;
  
  PlanService._internal();
  
  // 현재 사용자 ID 가져오기
  String? get _currentUserId => _auth.currentUser?.uid;
  
  /// 현재 사용자의 플랜 타입 가져오기
  Future<String> getCurrentPlanType() async {
    // 베타 기간 확인
    final isBetaPeriod = await _usageLimitService.isBetaPeriod();
    if (isBetaPeriod) {
      return PLAN_BETA;
    }
    
    try {
      // Firestore에서 사용자 플랜 정보 확인
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
            
            // 만료 여부 확인
            if (expiryDate != null) {
              final expiry = (expiryDate as Timestamp).toDate();
              if (expiry.isAfter(DateTime.now()) && planType != null) {
                return planType;
              }
            }
          }
        }
      }
      
      // Firestore에 정보가 없거나 만료된 경우 무료 플랜으로 간주
      return PLAN_FREE;
    } catch (e) {
      debugPrint('플랜 정보 조회 오류: $e');
      return PLAN_FREE;
    }
  }
  
  /// 플랜 이름 가져오기 (표시용)
  String getPlanName(String planType) {
    switch (planType) {
      case PLAN_PREMIUM:
        return '프리미엄';
      case PLAN_BETA:
        return '베타 테스터';
      case PLAN_FREE:
      default:
        return '무료';
    }
  }
  
  /// 플랜별 기능 제한 정보 가져오기
  Future<Map<String, int>> getPlanLimits(String planType) async {
    switch (planType) {
      case PLAN_PREMIUM:
        return {
          'ocrPages': 100,          // 월 100페이지
          'translatedChars': 100000, // 월 10만 글자
          'ttsRequests': 1000,       // 월 1000회
          'storageBytes': 1024 * 1024 * 1024, // 1GB
        };
      case PLAN_BETA:
        return {
          'ocrPages': UsageLimitService.MAX_FREE_OCR_PAGES,
          'translatedChars': UsageLimitService.MAX_FREE_TRANSLATION_CHARS,
          'ttsRequests': UsageLimitService.MAX_FREE_TTS_REQUESTS,
          'storageBytes': UsageLimitService.MAX_FREE_STORAGE_BYTES,
        };
      case PLAN_FREE:
      default:
        return {
          'ocrPages': UsageLimitService.BASIC_FREE_OCR_PAGES, 
          'translatedChars': UsageLimitService.BASIC_FREE_TRANSLATION_CHARS,
          'ttsRequests': UsageLimitService.BASIC_FREE_TTS_REQUESTS,
          'storageBytes': UsageLimitService.BASIC_FREE_STORAGE_MB * 1024 * 1024,
        };
    }
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
    final isBetaPeriod = await _usageLimitService.isBetaPeriod();
    
    int remainingDays = 0;
    if (isBetaPeriod) {
      remainingDays = await _usageLimitService.getRemainingBetaDays();
    }
    
    return {
      'planType': planType,
      'planName': getPlanName(planType),
      'planLimits': planLimits,
      'currentUsage': currentUsage,
      'usagePercentages': usagePercentages,
      'isBetaPeriod': isBetaPeriod,
      'remainingDays': remainingDays,
    };
  }
  
  /// 사용자 제한 상태 확인
  Future<Map<String, dynamic>> checkUserLimits() async {
    return await _usageLimitService.checkFreeLimits();
  }
} 