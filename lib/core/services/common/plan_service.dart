import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
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
      
      // 직접 플랜 타입만 확인 (getSubscriptionDetails 호출하면 무한 루프)
      final currentPlan = await _getCurrentPlanTypeFromFirestore();
      
      // 이벤트 캐시에 저장
      _eventCache.setCache(cacheKey, currentPlan);
      
      return currentPlan;
    } catch (e) {
      debugPrint('플랜 정보 조회 오류: $e');
      return PLAN_FREE;
    }
  }
  
  /// 외부에서 플랜 변경 이벤트를 발생시킬 수 있는 public 메서드 (중앙화된 EventCache 사용)
  void notifyPlanChanged(String planType, {String? userId}) {
    final targetUserId = userId ?? _currentUserId;
    _eventCache.notifyPlanChanged(planType, userId: targetUserId);
  }
  
  /// 외부에서 구독 변경 이벤트를 발생시킬 수 있는 public 메서드 (중앙화된 EventCache 사용)
  void notifySubscriptionChanged(Map<String, dynamic> subscriptionData, {String? userId}) {
    final targetUserId = userId ?? _currentUserId;
    _eventCache.notifySubscriptionChanged(subscriptionData, userId: targetUserId);
  }
  
  /// Firestore에서 직접 플랜 타입만 확인 (내부용)
  Future<String> _getCurrentPlanTypeFromFirestore() async {
    if (_currentUserId == null) return PLAN_FREE;
    
    final userDoc = await _firestore
        .collection('users')
        .doc(_currentUserId)
        .get();
        
    if (!userDoc.exists) return PLAN_FREE;
    
    final userData = userDoc.data();
    
    // 1. 새로운 subscription 구조 확인
    final planData = userData?['subscription'];
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
    
    // 2. 기존 planType 필드 확인 (하위 호환성)
    final legacyPlanType = userData?['planType'] as String?;
    if (legacyPlanType == 'premium') {
      return PLAN_PREMIUM;
    }
    
    return PLAN_FREE;
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
        final hasUsedTrial = userData?['hasUsedFreeTrial'] as bool? ?? false;
        if (hasUsedTrial) {
          if (kDebugMode) {
            print('✅ [PlanService] 현재 계정에서 무료체험 사용 이력 발견');
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

      if (subscriptionData == null) {
        return {
          'currentPlan': PLAN_FREE,
          'hasUsedFreeTrial': hasUsedFreeTrial,
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
      }

      final result = {
        'currentPlan': currentPlan,
        'hasUsedFreeTrial': hasUsedFreeTrial,
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
        'isFreeTrial': false,
        'daysRemaining': 0,
        'expiryDate': null,
        'subscriptionType': null,
      };
    }
  }
  
  /// 체험 종료 시 프리미엄으로 전환
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
          });
      
      // 체험→프리미엄 전환 이벤트 발생 (중앙화된 메서드 사용)
      _eventCache.notifyPremiumUpgraded(
        userId: userId,
        subscriptionType: subscriptionType,
        expiryDate: newExpiryDate,
        isFreeTrial: false,
      );
      
      if (kDebugMode) {
        debugPrint('✅ [PlanService] 체험→프리미엄 전환 완료');
        debugPrint('   구독 타입: $subscriptionType');
        debugPrint('   새 만료일: $newExpiryDate');
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
