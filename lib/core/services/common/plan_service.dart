import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../../models/plan.dart';
import '../authentication/deleted_user_service.dart';
import '../cache/event_cache_manager.dart';

/// 구독 플랜과 사용량 관리를 위한 서비스
class PlanService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // 플랜 유형
  static const String PLAN_FREE = 'free';
  static const String PLAN_PREMIUM = 'premium';
  
  // 플랜별 제한
  static const Map<String, Map<String, int>> PLAN_LIMITS = {
    PLAN_FREE: {
      'ocrPages': 10,          // 월 10장 (업로드 이미지 수)
      'ttsRequests': 30,       // 월 30회 (듣기 기능)
    },
    PLAN_PREMIUM: {
      'ocrPages': 300,         // 월 300장 (업로드 이미지 수)
      'ttsRequests': 1000,     // 월 1,000회 (듣기 기능)
    },
  };
  
  // SharedPreferences 키
  static const String _kPlanTypeKey = 'plan_type';
  static const String _kPlanExpiryKey = 'plan_expiry';
  static const String _kLastPlanTypeKey = 'last_plan_type';
  
  // 싱글톤 패턴 구현
  static final PlanService _instance = PlanService._internal();
  factory PlanService() => _instance;
  
  PlanService._internal() {
    _setupEventListeners();
  }
  
  // 이벤트 기반 캐시 매니저
  final EventCacheManager _eventCache = EventCacheManager();
  
  // 🎯 실시간 플랜 변경 스트림 추가
  final StreamController<Map<String, dynamic>> _planChangeController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  /// 플랜 변경 스트림
  Stream<Map<String, dynamic>> get planChangeStream => _planChangeController.stream;
  
  /// 이벤트 리스너 설정
  void _setupEventListeners() {
    // 플랜 변경 이벤트 수신
    _eventCache.eventStream.listen((event) {
      if (event.type == CacheEventType.planChanged || 
          event.type == CacheEventType.subscriptionChanged) {
        final userId = event.userId;
        if (userId != null) {
          _eventCache.invalidateCache('plan_type_$userId');
          _eventCache.invalidateCache('subscription_$userId');
          
          if (kDebugMode) {
            debugPrint('🔄 [PlanService] 이벤트로 인한 캐시 무효화: ${event.type}');
          }
        }
      }
    });
  }
  
  // 현재 사용자 ID 가져오기
  String? get _currentUserId => _auth.currentUser?.uid;
  
  /// 현재 사용자의 플랜 타입 가져오기 (이벤트 기반 캐시)
  Future<String> getCurrentPlanType({bool forceRefresh = false}) async {
    try {
      final userId = _currentUserId;
      if (userId == null) return PLAN_FREE;
      
      final cacheKey = 'plan_type_$userId';
      
      // 강제 새로고침이 아닌 경우 캐시 확인
      if (!forceRefresh) {
        final cachedPlanType = _eventCache.getCache<String>(cacheKey);
        if (cachedPlanType != null) {
          if (kDebugMode) {
            debugPrint('📦 [EventCache] 캐시된 플랜 타입 사용: $cachedPlanType');
          }
          return cachedPlanType;
        }
      } else {
        if (kDebugMode) {
          debugPrint('🔄 [PlanService] 강제 새로고침으로 캐시 무시');
        }
      }
      
      // 직접 Firestore에서 플랜 정보 조회 (캐시 없이)
      final userDoc = await _firestore.collection('users').doc(_currentUserId).get();
      if (!userDoc.exists) return PLAN_FREE;
      
      final data = userDoc.data() as Map<String, dynamic>;
      final subscriptionData = data['subscription'] as Map<String, dynamic>?;
      
      if (subscriptionData == null) return PLAN_FREE;
      
      final plan = subscriptionData['plan'] as String? ?? PLAN_FREE;
      final expiryDate = subscriptionData['expiryDate'] as Timestamp?;
      
      // 만료 확인
      if (expiryDate != null) {
        final expiry = expiryDate.toDate();
        final now = DateTime.now();
        
        if (expiry.isAfter(now)) {
          return plan; // 만료되지 않았으면 원래 플랜
        } else {
          return PLAN_FREE; // 만료되었으면 무료 플랜
        }
      }
      
      return plan;
      
              // 이벤트 캐시에 저장
        _eventCache.setCache(cacheKey, plan);
        
        return plan;
    } catch (e) {
      debugPrint('플랜 정보 조회 오류: $e');
      return PLAN_FREE;
    }
  }
  
  /// 외부에서 플랜 변경 이벤트를 발생시킬 수 있는 public 메서드 (중앙화된 EventCache 사용)
  void notifyPlanChanged(String planType, {String? userId}) {
    final targetUserId = userId ?? _currentUserId;
    _eventCache.notifyPlanChanged(planType, userId: targetUserId);
    
    // 🎯 실시간 플랜 변경 알림
    _notifyPlanChangeStream({
      'planType': planType,
      'userId': targetUserId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }
  
  /// 🎯 플랜 변경 스트림 알림
  void _notifyPlanChangeStream(Map<String, dynamic> planChangeData) {
    if (!_planChangeController.isClosed) {
      _planChangeController.add(planChangeData);
      if (kDebugMode) {
        debugPrint('🔔 [PlanService] 실시간 플랜 변경 알림: $planChangeData');
      }
    }
  }
  
  /// 서비스 정리 (스트림 컨트롤러 닫기)
  void dispose() {
    _planChangeController.close();
    if (kDebugMode) {
      debugPrint('🗑️ [PlanService] 서비스 정리 완료');
    }
  }
  
  /// 외부에서 구독 변경 이벤트를 발생시킬 수 있는 public 메서드 (중앙화된 EventCache 사용)
  void notifySubscriptionChanged(Map<String, dynamic> subscriptionData, {String? userId}) {
    final targetUserId = userId ?? _currentUserId;
    _eventCache.notifySubscriptionChanged(subscriptionData, userId: targetUserId);
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
  
  /// 사용자의 구독 업그레이드 여부 확인
  Future<bool> canUpgradePlan() async {
    final currentPlan = await getCurrentPlanType();
    return currentPlan != PLAN_PREMIUM;
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
      final subscriptionType = subscriptionDetails['subscriptionType'] as String?; // yearly/monthly 정보
      
      final limits = await getPlanLimits(currentPlan);
      
      if (currentPlan == PLAN_PREMIUM && isFreeTrial && daysRemaining > 0) {
        // 프리미엄 체험 중
        String planName = '프리미엄 체험 (${daysRemaining}일 남음)';
        if (subscriptionType != null) {
          planName = '프리미엄 체험 ($subscriptionType, ${daysRemaining}일 남음)';
        }
        return Plan.premiumTrial(
          daysRemaining: daysRemaining,
          expiryDate: expiryDate,
          limits: limits,
        ).copyWith(
          hasUsedFreeTrial: hasUsedFreeTrial,
          name: planName,
        );
      } else if (currentPlan == PLAN_PREMIUM) {
        // 정식 프리미엄
        String planName = '프리미엄';
        if (subscriptionType != null) {
          planName = '프리미엄 ($subscriptionType)';
        }
        return Plan.premium(limits: limits).copyWith(
          hasUsedFreeTrial: hasUsedFreeTrial,
          expiryDate: expiryDate,
          name: planName,
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
      debugPrint('문의하기 기능 호출됨: subject=$subject, body=$body');
      
      // Google Form 열기
      final formUrl = Uri.parse('https://docs.google.com/forms/d/e/1FAIpQLSfgVL4Bd5KcTh9nhfbVZ51yApPAmJAZJZgtM4V9hNhsBpKuaA/viewform?usp=dialog');
      
      if (await canLaunchUrl(formUrl)) {
        await launchUrl(formUrl, mode: LaunchMode.externalApplication);
      } else {
        debugPrint('Google Form을 열 수 없습니다: $formUrl');
        throw Exception('문의 폼을 열 수 없습니다.');
      }
    } catch (e) {
      debugPrint('문의하기 기능 오류: $e');
      rethrow;
    }
  }

  /// Premium 플랜으로 업그레이드
  Future<bool> upgradeToPremium(String userId, {
    required DateTime expiryDate,
    String? subscriptionType, // yearly 또는 monthly
    bool isFreeTrial = false, // 무료체험 여부
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
              'status': isFreeTrial ? 'trial' : 'active',
              'subscriptionType': subscriptionType, // yearly/monthly 정보 저장
              'isFreeTrial': isFreeTrial,
            },
            if (isFreeTrial) 'hasUsedFreeTrial': true, // 무료체험인 경우에만 사용 기록
            if (isFreeTrial) 'hasEverUsedTrial': true, // 🎯 새로운 필드: 무료체험 사용 이력
          }, SetOptions(merge: true));
      
      // 프리미엄 업그레이드 이벤트 발생 (중앙화된 메서드 사용)
      _eventCache.notifyPremiumUpgraded(
        userId: userId,
        subscriptionType: subscriptionType ?? 'monthly',
        expiryDate: expiryDate,
        isFreeTrial: isFreeTrial,
      );
      
      return true;
    } catch (e) {
      debugPrint('프리미엄 업그레이드 실패: $e');
      return false;
    }
  }

  /// 월간 사용량 초기화 (매월 1일 실행)
  /// 참고: 실제 사용량 초기화는 UsageLimitService에서 직접 처리하세요
  Future<void> resetMonthlyUsage() async {
    final planType = await getCurrentPlanType();
    
    // Premium이 아닌 경우만 초기화 필요
    if (planType == PLAN_FREE) {
      debugPrint('무료 플랜 사용자 - 월간 사용량 초기화 필요');
      // 실제 초기화는 UsageLimitService.resetAllUsage() 직접 호출
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
      
      // 🎯 실제: 7일 후 만료일 설정
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
              'subscriptionType': 'monthly', // 무료체험은 monthly 기반
            },
            'hasUsedFreeTrial': true, // 체험 사용 기록
            'hasEverUsedTrial': true, // 🎯 새로운 필드: 무료체험 사용 이력
          }, SetOptions(merge: true));
      
      // 무료체험 시작 이벤트 발생 (중앙화된 메서드 사용)
      _eventCache.notifyFreeTrialStarted(
        userId: userId,
        subscriptionType: 'monthly',
        expiryDate: expiryDate,
      );
      
      debugPrint('🎯 [PROD] 7일 무료 체험 시작: $userId, 만료일: $expiryDate');
      return true;
    } catch (e) {
      debugPrint('무료 체험 시작 실패: $e');
      return false;
    }
  }
  
  /// 무료 체험 사용 여부 확인 (탈퇴 이력 포함)
  Future<bool> hasUsedFreeTrial(String userId) async {
    try {
      // 1. 현재 사용자 문서에서 확인
      final userDoc = await _firestore
          .collection('users')
          .doc(userId)
          .get();
          
      if (userDoc.exists) {
        final userData = userDoc.data();
        
        // 🎯 새로운 방식: hasEverUsedTrial 필드 우선 확인
        final hasEverUsedTrial = userData?['hasEverUsedTrial'] as bool? ?? false;
        if (hasEverUsedTrial) {
          if (kDebugMode) {
            print('✅ [PlanService] 현재 계정에서 무료체험 사용 이력 발견 (hasEverUsedTrial)');
          }
          return true;
        }
        
        // 🔄 하위 호환성: 기존 hasUsedFreeTrial 필드도 확인
        final hasUsedTrial = userData?['hasUsedFreeTrial'] as bool? ?? false;
        if (hasUsedTrial) {
          if (kDebugMode) {
            print('✅ [PlanService] 현재 계정에서 무료체험 사용 이력 발견 (레거시)');
          }
          return true;
        }
      }
      
      // 2. 중앙화된 서비스를 통해 탈퇴 이력에서 확인
      final deletedUserService = DeletedUserService();
      final hasUsedTrialFromHistory = await deletedUserService.hasUsedFreeTrialFromHistory();
      
      if (hasUsedTrialFromHistory) {
        return true;
      }
      
      if (kDebugMode) {
        print('❌ [PlanService] 무료체험 사용 이력 없음');
      }
      return false;
    } catch (e) {
      debugPrint('무료 체험 사용 여부 확인 오류: $e');
      return false;
    }
  }
  
  /// 구독 상세 정보 조회 (이벤트 기반 캐시)
  Future<Map<String, dynamic>> getSubscriptionDetails({bool forceRefresh = false}) async {
    final userId = _currentUserId;
    
    // 강제 새로고침 시 관련 캐시 무효화
    if (forceRefresh && userId != null) {
      _eventCache.invalidateCache('plan_type_$userId');
      _eventCache.invalidateCache('subscription_$userId');
    }
    
    // 캐시 확인
    if (!forceRefresh && userId != null) {
      final cacheKey = 'subscription_$userId';
      final cachedSubscription = _eventCache.getCache<Map<String, dynamic>>(cacheKey);
      if (cachedSubscription != null) {
        if (kDebugMode) {
          debugPrint('📦 [EventCache] 캐시된 구독 정보 사용: $userId');
        }
        return cachedSubscription;
      }
    }
    
    try {
      if (userId == null) {
        return {
          'currentPlan': PLAN_FREE,
          'hasUsedFreeTrial': false,
          'hasEverUsedTrial': false,
          'hasEverUsedPremium': false,
          'isFreeTrial': false,
          'daysRemaining': 0,
          'expiryDate': null,
          'subscriptionType': null,
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
          'hasEverUsedTrial': false,
          'hasEverUsedPremium': false,
          'isFreeTrial': false,
          'daysRemaining': 0,
          'expiryDate': null,
          'subscriptionType': null,
        };
      }

      final data = userDoc.data() as Map<String, dynamic>;
      final subscriptionData = data['subscription'] as Map<String, dynamic>?;
      
      // hasUsedFreeTrial은 사용자 문서의 루트 레벨에서 가져오기
      final hasUsedFreeTrial = data['hasUsedFreeTrial'] as bool? ?? false;
      // 🎯 새로운 필드: hasEverUsedTrial도 가져오기
      final hasEverUsedTrial = data['hasEverUsedTrial'] as bool? ?? false;
      // 🎯 프리미엄 사용 이력도 가져오기
      final hasEverUsedPremium = data['hasEverUsedPremium'] as bool? ?? false;

      if (subscriptionData == null) {
        return {
          'currentPlan': PLAN_FREE,
          'hasUsedFreeTrial': hasUsedFreeTrial,
          'hasEverUsedTrial': hasEverUsedTrial,
          'hasEverUsedPremium': hasEverUsedPremium,
          'isFreeTrial': false,
          'daysRemaining': 0,
          'expiryDate': null,
          'subscriptionType': null,
        };
      }

      final plan = subscriptionData['plan'] as String? ?? PLAN_FREE;
      final status = subscriptionData['status'] as String?;
      final isFreeTrial = subscriptionData['isFreeTrial'] as bool? ?? false;
      final expiryDate = subscriptionData['expiryDate'] as Timestamp?;
      final subscriptionType = subscriptionData['subscriptionType'] as String?; // yearly/monthly

      int daysRemaining = 0;
      String currentPlan = PLAN_FREE;

      if (expiryDate != null) {
        final expiry = expiryDate.toDate();
        final now = DateTime.now();
        
        if (expiry.isAfter(now)) {
          // 🧪 테스트: 3분 체험의 경우 분 단위로 계산하되, 최소 1일로 표시
          final minutesRemaining = expiry.difference(now).inMinutes;
          if (minutesRemaining > 0 && minutesRemaining < 60) {
            daysRemaining = 1; // 1시간 미만이면 1일로 표시 (테스트용)
          } else {
            daysRemaining = expiry.difference(now).inDays;
            if (daysRemaining == 0 && expiry.isAfter(now)) {
              daysRemaining = 1; // 당일 내에 만료되는 경우도 1일로 표시
            }
          }
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
        if (expiryDate != null) {
          final minutesRemaining = expiryDate.toDate().difference(DateTime.now()).inMinutes;
          print('   남은 분수: $minutesRemaining분');
        }
        print('   만료일: ${expiryDate?.toDate()}');
        print('   상태: $status');
        print('   구독 유형: $subscriptionType');
        
        // 🔍 Firestore 원본 데이터 디버깅
        print('🔍 [DEBUG] Firestore 원본 데이터:');
        print('   전체 사용자 데이터: $data');
        print('   구독 데이터: $subscriptionData');
        print('   구독 데이터의 isFreeTrial: ${subscriptionData?['isFreeTrial']}');
        print('   구독 데이터의 status: ${subscriptionData?['status']}');
        print('   구독 데이터의 plan: ${subscriptionData?['plan']}');
        
        // 만료 날짜 상세 분석
        if (expiryDate != null) {
          final now = DateTime.now();
          final expiry = expiryDate.toDate();
          print('🔍 [DEBUG] 만료 날짜 분석:');
          print('   현재 시간: $now');
          print('   만료 시간: $expiry');
          print('   만료 여부: ${expiry.isBefore(now) ? "만료됨" : "유효함"}');
          print('   시간 차이: ${expiry.difference(now).inMinutes}분');
        }
      }

      final result = {
        'currentPlan': currentPlan,
        'hasUsedFreeTrial': hasUsedFreeTrial,
        'hasEverUsedTrial': hasEverUsedTrial,
        'hasEverUsedPremium': hasEverUsedPremium,
        'isFreeTrial': isFreeTrial,
        'daysRemaining': daysRemaining,
        'expiryDate': expiryDate?.toDate(),
        'status': status,
        'subscriptionType': subscriptionType,
      };
      
      // 캐시에 저장
      if (userId != null) {
        _eventCache.setCache('subscription_$userId', result);
      }
      
      return result;
    } catch (e) {
      debugPrint('구독 상세 정보 조회 중 오류: $e');
      return {
        'currentPlan': PLAN_FREE,
        'hasUsedFreeTrial': false,
        'hasEverUsedTrial': false,
        'hasEverUsedPremium': false,
        'isFreeTrial': false,
        'daysRemaining': 0,
        'expiryDate': null,
        'subscriptionType': null,
      };
    }
  }
  
  /// 프리미엄(체험/정식) → 무료 플랜 전환 (이력 유지)
  Future<bool> convertToFree(String userId) async {
    try {
      // 현재 구독 정보 확인
      final subscriptionDetails = await getSubscriptionDetails(forceRefresh: true);
      final currentPlan = subscriptionDetails['currentPlan'] as String;
      final isFreeTrial = subscriptionDetails['isFreeTrial'] as bool? ?? false;
      final subscriptionType = subscriptionDetails['subscriptionType'] as String?;
      
      if (currentPlan != PLAN_PREMIUM) {
        if (kDebugMode) {
          debugPrint('⚠️ [PlanService] 프리미엄 상태가 아닙니다 - 전환 불필요');
        }
        return true; // 이미 무료 플랜이면 성공으로 처리
      }
      
      // 이전 플랜 이력 저장 + 구독 정보 삭제
      Map<String, dynamic> updateData = {
        'subscription': FieldValue.delete(), // 구독 정보 삭제
        'hasUsedFreeTrial': true, // 체험 사용 이력 유지
        'hasEverUsedTrial': true, // 체험 사용 이력 유지 (영구)
      };
      
      // 정식 프리미엄이었다면 프리미엄 이력도 저장
      if (!isFreeTrial) {
        updateData.addAll({
          'hasEverUsedPremium': true, // 🎯 프리미엄 사용 이력 추가 (영구)
          'lastPremiumSubscriptionType': subscriptionType, // 🎯 마지막 프리미엄 구독 타입
          'lastPremiumExpiredAt': FieldValue.serverTimestamp(), // 🎯 프리미엄 만료 시간
        });
      }
      
      await _firestore
          .collection('users')
          .doc(userId)
          .update(updateData);
      
      // 캐시 무효화 (플랜 변경)
      _eventCache.invalidateCache('plan_type_$userId');
      _eventCache.invalidateCache('subscription_$userId');
      
      if (kDebugMode) {
        if (isFreeTrial) {
          debugPrint('✅ [PlanService] 체험→무료 플랜 전환 완료');
          debugPrint('   체험 이력 유지: hasEverUsedTrial = true');
        } else {
          debugPrint('✅ [PlanService] 프리미엄→무료 플랜 전환 완료');
          debugPrint('   프리미엄 이력 저장: hasEverUsedPremium = true');
          debugPrint('   마지막 구독 타입: $subscriptionType');
        }
      }
      
      return true;
    } catch (e) {
      debugPrint('프리미엄→무료 플랜 전환 실패: $e');
      return false;
    }
  }

  /// 체험 종료 시 프리미엄으로 전환 (구매 시에만 사용)
  Future<bool> convertTrialToPremium(String userId) async {
    try {
      // 현재 구독 정보 확인
      final subscriptionDetails = await getSubscriptionDetails(forceRefresh: true);
      final isFreeTrial = subscriptionDetails['isFreeTrial'] as bool? ?? false;
      final currentSubscriptionType = subscriptionDetails['subscriptionType'] as String?;
      
      if (!isFreeTrial) {
        if (kDebugMode) {
          debugPrint('⚠️ [PlanService] 체험 상태가 아닙니다 - 전환 불필요');
        }
        return true; // 이미 프리미엄이면 성공으로 처리
      }
      
      // 기존 구독 타입에 따라 만료일 설정 (무료체험은 보통 monthly 기반)
      final subscriptionType = currentSubscriptionType ?? 'monthly';
      final Duration duration;
      
      if (subscriptionType == 'yearly') {
        duration = const Duration(days: 365);
      } else {
        duration = const Duration(days: 30); // monthly
      }
      
      final newExpiryDate = DateTime.now().add(duration);
      
      await _firestore
          .collection('users')
          .doc(userId)
          .update({
            'subscription.status': 'active',
            'subscription.isFreeTrial': false,
            'subscription.expiryDate': Timestamp.fromDate(newExpiryDate),
            'subscription.subscriptionType': subscriptionType,
            'hasUsedFreeTrial': true, // 체험 사용 이력 유지
            'hasEverUsedTrial': true, // 체험 사용 이력 유지 (영구)
          });
      
      // 체험→프리미엄 전환 이벤트 발생 (중앙화된 메서드 사용)
      _eventCache.notifyPremiumUpgraded(
        userId: userId,
        subscriptionType: subscriptionType,
        expiryDate: newExpiryDate,
        isFreeTrial: false,
      );
      
      if (kDebugMode) {
        debugPrint('✅ [PlanService] 체험→프리미엄 전환 완료 (구매)');
        debugPrint('   구독 타입: $subscriptionType');
        debugPrint('   새 만료일: $newExpiryDate');
        debugPrint('   체험 이력 유지: hasEverUsedTrial = true');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [PlanService] 체험→프리미엄 전환 실패: $e');
      }
      return false;
    }
  }
} 
