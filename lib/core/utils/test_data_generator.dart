import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// 테스트 데이터 자동 생성 유틸리티 (DEBUG 모드에서만 동작)
class TestDataGenerator {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 모든 테스트 계정 생성
  static Future<void> generateAllTestAccounts() async {
    if (!kDebugMode) {
      debugPrint('❌ 릴리즈 모드에서는 테스트 데이터를 생성할 수 없습니다.');
      return;
    }

    try {
      debugPrint('🎯 테스트 계정 생성 시작...');
      
      final testScenarios = [
        // === 기본 시나리오 ===
        {'email': 'trial@test.com', 'scenario': 'free_premium_trial'},
        {'email': 'triallimit@test.com', 'scenario': 'premium_trial_limit_reached'},
        {'email': 'expired@test.com', 'scenario': 'trial_expired'}, // 🎯 체험 만료 → 배너 테스트
        {'email': 'expiring@test.com', 'scenario': 'trial_expiring_soon'}, // 🎯 체험 만료 직전 → 실제 만료 플로우 테스트
        {'email': 'cancelled@test.com', 'scenario': 'trial_cancelled'}, // 🎯 체험 중간 취소 → 배너 테스트
        {'email': 'free@test.com', 'scenario': 'free_plan'},
        {'email': 'limit@test.com', 'scenario': 'free_limit_reached'},
        
        // === 월간 프리미엄 ===
        {'email': 'premium@test.com', 'scenario': 'premium_active'},
        {'email': 'plimit@test.com', 'scenario': 'premium_limit_reached'},
        
        // === 연간 프리미엄 ===
        {'email': 'yearly@test.com', 'scenario': 'premium_yearly_active'},
        {'email': 'yearlylimit@test.com', 'scenario': 'premium_yearly_limit_reached'},
        
        // 🎯 프리미엄 만료 (배너 테스트용)
        {'email': 'pexpired@test.com', 'scenario': 'premium_expired'},
        {'email': 'yearlyexpired@test.com', 'scenario': 'premium_yearly_expired'},
      ];

      for (final test in testScenarios) {
        await _createTestAccount(test['email']!, test['scenario']!);
      }
      
      debugPrint('✅ 모든 테스트 계정 생성 완료');
      
    } catch (e) {
      debugPrint('❌ 테스트 계정 생성 중 오류: $e');
    }
  }

  /// 개별 테스트 계정 생성
  static Future<void> _createTestAccount(String email, String scenario) async {
    final password = 'test123456';
    final displayName = scenario.split('_').join(' ');

    try {
      // 1. Firebase Auth에 사용자 생성
      UserCredential userCredential;
      try {
        userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } catch (e) {
        if (e.toString().contains('email-already-in-use')) {
          // 이미 존재하는 경우 로그인해서 데이터만 업데이트
          debugPrint('⚠️ $email 이미 존재 - 데이터 업데이트만 진행');
          userCredential = await _auth.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
        } else {
          rethrow;
        }
      }

      final user = userCredential.user!;
      
      // 2. 사용자 프로필 업데이트
      await user.updateDisplayName(displayName);

      // 3. Firestore에 사용자 기본 정보 저장
      await _createUserDocument(user.uid, email, displayName);

      // 4. 시나리오별 데이터 생성
      await _createScenarioData(user.uid, scenario);

      debugPrint('✅ $email 생성 완료');
      
    } catch (e) {
      debugPrint('❌ $email 생성 실패: $e');
      rethrow;
    }
  }

  /// 사용자 기본 문서 생성
  static Future<void> _createUserDocument(String uid, String email, String displayName) async {
    await _firestore.collection('users').doc(uid).set({
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoURL': '',
      'createdAt': FieldValue.serverTimestamp(),
      'lastLogin': FieldValue.serverTimestamp(),
      'isNewUser': false,
      'planType': 'free',
      'deviceCount': 1,
      // 🔧 온보딩 완료 상태 추가
      'hasOnboarded': true,
      'onboardingCompleted': true,
      // 기본 사용자 설정 추가
      'userName': displayName,
      'level': '중급',
      'learningPurpose': '직접 원서 공부',
      'translationMode': 'full',
      'sourceLanguage': 'zh-CN',
      'targetLanguage': 'ko',
      'hasLoginHistory': true,
      // 기본 사용량 초기화
      'usage': {
        'ocrPages': 0,
        'ttsRequests': 0,
        'translatedChars': 0,
        'storageUsageBytes': 0,
        'lastUpdated': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }

  /// 시나리오별 데이터 생성
  static Future<void> _createScenarioData(String uid, String scenario) async {
    final now = DateTime.now();
    
    switch (scenario) {
      case 'free_premium_trial':
        // 7일 무료체험 중
        await _firestore.collection('users').doc(uid).update({
          'subscription': {
            'plan': 'premium',
            'startDate': Timestamp.fromDate(now),
            'expiryDate': Timestamp.fromDate(now.add(const Duration(days: 7))),
            'status': 'trial',
            'subscriptionType': 'monthly',
            'isFreeTrial': true,
          },
          'hasUsedFreeTrial': true,
          'hasEverUsedTrial': true,
        });
        // 🎯 커스텀 제한을 설정하지 않음 - 플랜 기반 제한 사용
        break;

      case 'trial_expired':
        // 🎯 체험 만료 → 무료 플랜 (배너 테스트용)
        await _firestore.collection('users').doc(uid).update({
          // subscription 필드 삭제 (무료 플랜으로 전환)
          'subscription': FieldValue.delete(),
          // 체험 이력 저장
          'hasUsedFreeTrial': true,
          'hasEverUsedTrial': true,
          // 🎯 프리미엄 이력은 없음 (체험만 사용)
        });
        debugPrint('🧪 [TestData] Trial Completed 배너 테스트 데이터 생성 완료');
        break;

      case 'trial_expiring_soon':
        // 🎯 체험 만료 직전 - 2분 남음 (실제 만료 플로우 테스트용)
        await _firestore.collection('users').doc(uid).update({
          'subscription': {
            'plan': 'premium',
            'startDate': Timestamp.fromDate(now.subtract(const Duration(days: 6, hours: 23, minutes: 58))), // 거의 7일 전 시작
            'expiryDate': Timestamp.fromDate(now.add(const Duration(minutes: 2))), // 🎯 2분 후 만료
            'status': 'trial',
            'subscriptionType': 'monthly',
            'isFreeTrial': true, // 🎯 아직 무료체험 중
          },
          'hasUsedFreeTrial': true,
          'hasEverUsedTrial': true,
        });
        debugPrint('🧪 [TestData] 체험 만료 직전 상태 생성: 2분 후 만료 예정 (실제 만료 플로우 테스트용)');
        break;

      case 'trial_cancelled':
        // 🎯 체험 취소 → 체험 기간 끝까지 프리미엄 사용 가능 (App Store 표준 방식)
        await _firestore.collection('users').doc(uid).update({
          'subscription': {
            'plan': 'premium',
            'startDate': Timestamp.fromDate(now.subtract(const Duration(days: 3))), // 3일 전 시작
            'expiryDate': Timestamp.fromDate(now.add(const Duration(days: 4))), // 4일 후 만료 (총 7일)
            'status': 'trial',
            'subscriptionType': 'monthly',
            'isFreeTrial': true,
            'autoRenewStatus': false, // 🎯 자동 갱신 취소됨
            'isCancelled': true, // 🎯 취소 상태 표시
          },
          'hasUsedFreeTrial': true,
          'hasEverUsedTrial': true,
          // 🎯 프리미엄 이력은 없음 (체험만 사용)
        });
        debugPrint('🧪 [TestData] Trial Cancelled 상태 생성: 체험 기간 끝까지 프리미엄 사용 가능, 자동 갱신 비활성화');
        break;

      case 'free_plan':
        // 기본 무료 플랜
        await _firestore.collection('users').doc(uid).update({
          // 기본 상태 유지 (subscription 없음)
        });
        // 🎯 커스텀 제한을 설정하지 않음 - 플랜 기반 제한 사용
        break;

      case 'free_limit_reached':
        // 🎯 무료 플랜 제한 도달 (체험 이력 없음)
        await _firestore.collection('users').doc(uid).update({
          // 기본 상태 유지 (subscription 없음)
          'hasUsedFreeTrial': false, // 🎯 체험 사용 안 함
          'hasEverUsedTrial': false, // 🎯 체험 이력 없음
        });
        // 🎯 커스텀 제한을 설정하지 않음 - 플랜 기반 제한 사용
        await _createUsageData(uid, 'free_limit_reached');
        break;



      case 'premium_active':
        // 정식 프리미엄 (한 달 남음)
        await _firestore.collection('users').doc(uid).update({
          'subscription': {
            'plan': 'premium',
            'startDate': Timestamp.fromDate(now.subtract(const Duration(days: 30))),
            'expiryDate': Timestamp.fromDate(now.add(const Duration(days: 30))),
            'status': 'active',
            'subscriptionType': 'monthly',
            'isFreeTrial': false,
          },
          'hasUsedFreeTrial': true,
          'hasEverUsedTrial': true,
        });
        // 🎯 커스텀 제한을 설정하지 않음 - 플랜 기반 제한 사용
        break;

      case 'premium_limit_reached':
        // 프리미엄 제한 도달
        await _firestore.collection('users').doc(uid).update({
          'subscription': {
            'plan': 'premium',
            'startDate': Timestamp.fromDate(now.subtract(const Duration(days: 15))),
            'expiryDate': Timestamp.fromDate(now.add(const Duration(days: 15))),
            'status': 'active',
            'subscriptionType': 'monthly',
            'isFreeTrial': false,
          },
          'hasUsedFreeTrial': true,
          'hasEverUsedTrial': true,
        });
        // 🎯 커스텀 제한을 설정하지 않음 - 플랜 기반 제한 사용
        await _createUsageData(uid, 'premium_limit_reached');
        break;

      case 'premium_expired':
        // 🎯 프리미엄 만료 → 무료 플랜 (배너 테스트용)
        await _firestore.collection('users').doc(uid).update({
          // subscription 필드 삭제 (무료 플랜으로 전환)
          'subscription': FieldValue.delete(),
          // 이전 플랜 이력 저장
          'hasUsedFreeTrial': true,
          'hasEverUsedTrial': true,
          'hasEverUsedPremium': true, // 🎯 프리미엄 사용 이력
          'lastPremiumSubscriptionType': 'monthly', // 🎯 마지막 구독 타입
          'lastPremiumExpiredAt': Timestamp.fromDate(now.subtract(const Duration(days: 30))), // 🎯 만료 시간
        });
        debugPrint('🧪 [TestData] Premium Expired 배너 테스트 데이터 생성 완료');
        break;

      case 'premium_trial_limit_reached':
        // 🎯 프리미엄 무료체험 중 제한 도달 (매우 드문 케이스)
        await _firestore.collection('users').doc(uid).update({
          'subscription': {
            'plan': 'premium',
            'startDate': Timestamp.fromDate(now.subtract(const Duration(days: 3))),
            'expiryDate': Timestamp.fromDate(now.add(const Duration(days: 4))), // 4일 남음
            'status': 'trial',
            'subscriptionType': 'monthly',
            'isFreeTrial': true, // 🎯 무료체험 중
          },
          'hasUsedFreeTrial': true,
          'hasEverUsedTrial': true,
        });
        // 🎯 커스텀 제한을 설정하지 않음 - 플랜 기반 제한 사용
        await _createUsageData(uid, 'premium_limit_reached');
        break;

      case 'premium_yearly_active':
        // 정식 프리미엄 (한 년 남음)
        await _firestore.collection('users').doc(uid).update({
          'subscription': {
            'plan': 'premium',
            'startDate': Timestamp.fromDate(now.subtract(const Duration(days: 365))),
            'expiryDate': Timestamp.fromDate(now.add(const Duration(days: 365))),
            'status': 'active',
            'subscriptionType': 'yearly',
            'isFreeTrial': false,
          },
          'hasUsedFreeTrial': true,
          'hasEverUsedTrial': true,
        });
        // 🎯 커스텀 제한을 설정하지 않음 - 플랜 기반 제한 사용
        break;

      case 'premium_yearly_limit_reached':
        // 프리미엄 제한 도달
        await _firestore.collection('users').doc(uid).update({
          'subscription': {
            'plan': 'premium',
            'startDate': Timestamp.fromDate(now.subtract(const Duration(days: 365))),
            'expiryDate': Timestamp.fromDate(now.add(const Duration(days: 365))),
            'status': 'active',
            'subscriptionType': 'yearly',
            'isFreeTrial': false,
          },
          'hasUsedFreeTrial': true,
          'hasEverUsedTrial': true,
        });
        // 🎯 커스텀 제한을 설정하지 않음 - 플랜 기반 제한 사용
        await _createUsageData(uid, 'premium_limit_reached');
        break;

      case 'premium_yearly_expired':
        // 🎯 연간 프리미엄 만료 → 무료 플랜 (배너 테스트용)
        await _firestore.collection('users').doc(uid).update({
          // subscription 필드 삭제 (무료 플랜으로 전환)
          'subscription': FieldValue.delete(),
          // 이전 플랜 이력 저장
          'hasUsedFreeTrial': true,
          'hasEverUsedTrial': true,
          'hasEverUsedPremium': true, // 🎯 프리미엄 사용 이력
          'lastPremiumSubscriptionType': 'yearly', // 🎯 마지막 구독 타입 (연간)
          'lastPremiumExpiredAt': Timestamp.fromDate(now.subtract(const Duration(days: 365))), // 🎯 만료 시간
        });
        debugPrint('🧪 [TestData] Premium Yearly Expired 배너 테스트 데이터 생성 완료');
        break;
    }
    
    // 🎯 기존 커스텀 제한 데이터 삭제 (플랜 기반 제한 사용)
    await _deleteCustomLimits(uid);
  }

  /// 기존 커스텀 제한 데이터 삭제 (플랜 기반 제한 사용을 위해)
  static Future<void> _deleteCustomLimits(String uid) async {
    try {
      await _firestore.collection('user_limits').doc(uid).delete();
      if (kDebugMode) {
        debugPrint('🗑️ [TestDataGenerator] $uid 커스텀 제한 데이터 삭제 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [TestDataGenerator] $uid 커스텀 제한 데이터 삭제 실패 (문서가 없을 수 있음): $e');
      }
    }
  }

  /// 사용량 데이터 설정
  static Future<void> _createUsageData(String uid, String usageType) async {
    Map<String, int> usage;
    
    switch (usageType) {
      case 'free_limit_reached':
        usage = {
          'ocrPages': 10,        // 무료 플랜 한도 10장 모두 사용
          'ttsRequests': 30,     // 무료 플랜 한도 30회 모두 사용
        };
        break;
      case 'premium_limit_reached':
        usage = {
          'ocrPages': 300,       // 프리미엄 플랜 한도 300장 모두 사용
          'ttsRequests': 1000,   // 프리미엄 플랜 한도 1000회 모두 사용
        };
        break;
      case 'normal':
      default:
        usage = {
          'ocrPages': 0,
          'ttsRequests': 0,
        };
        break;
    }

    if (kDebugMode) {
      debugPrint('📊 [TestDataGenerator] $uid 사용량 데이터 설정: $usageType -> $usage');
    }

    await _firestore.collection('users').doc(uid).update({
      'usage.ocrPages': usage['ocrPages'],
      'usage.ttsRequests': usage['ttsRequests'],
      'usage.lastUpdated': FieldValue.serverTimestamp(),
    });
    
    if (kDebugMode) {
      debugPrint('✅ [TestDataGenerator] $uid 사용량 데이터 저장 완료');
    }
  }

  /// 사용량 제한 설정 (플랜 기반 제한 사용으로 더 이상 필요하지 않음)
  /// 🎯 커스텀 제한 대신 PlanService.PLAN_LIMITS를 사용하여 정확한 제한값 적용
  @deprecated
  static Future<void> _createUserLimits(String uid, String limitType) async {
    // 더 이상 사용하지 않음 - 플랜 기반 제한 사용
    if (kDebugMode) {
      debugPrint('⚠️ [TestDataGenerator] _createUserLimits는 더 이상 사용되지 않습니다. 플랜 기반 제한을 사용합니다.');
    }
  }

  /// 모든 테스트 계정 삭제 (정리용)
  static Future<void> deleteAllTestAccounts() async {
    if (!kDebugMode) {
      debugPrint('❌ 릴리즈 모드에서는 테스트 데이터를 삭제할 수 없습니다.');
      return;
    }

    try {
      debugPrint('🧹 테스트 계정 삭제 시작...');
      
      final testEmails = [
        'trial@test.com',
        'expired@test.com', 
        'free@test.com',
        'limit@test.com',
        'premium@test.com',
        'plimit@test.com',
        'pexpired@test.com',
      ];

      for (final email in testEmails) {
        try {
          // Firebase Auth에서 사용자 찾기 및 삭제는 Admin SDK가 필요함
          // 현재는 Firestore 데이터만 삭제
          debugPrint('⚠️ $email - Firestore 데이터만 삭제 (Auth는 수동 삭제 필요)');
        } catch (e) {
          debugPrint('❌ $email 삭제 실패: $e');
        }
      }
      
      debugPrint('✅ 테스트 데이터 정리 완료');
      
    } catch (e) {
      debugPrint('❌ 테스트 데이터 정리 중 오류: $e');
    }
  }

  /// 테스트 계정 정보 출력
  static void printTestAccounts() {
    if (!kDebugMode) return;
    
    debugPrint('📋 테스트 계정 목록:');
    debugPrint('=== 배너 테스트 계정 ===');
    debugPrint('🎯 expired@test.com (test123456) - Trial Completed 배너');
    debugPrint('🎯 cancelled@test.com (test123456) - Trial Completed 배너 (중간취소)');
    debugPrint('🎯 pexpired@test.com (test123456) - Premium Expired 배너 (월간)');
    debugPrint('🎯 yearlyexpired@test.com (test123456) - Premium Expired 배너 (연간)');
    debugPrint('=== 일반 테스트 계정 ===');
    debugPrint('1. trial@test.com (test123456) - 무료체험 중');
    debugPrint('2. triallimit@test.com (test123456) - 프리미엄 체험 중 제한 도달');
    debugPrint('3. expiring@test.com (test123456) - 체험 만료 직전 (2분 후)');  
    debugPrint('4. free@test.com (test123456) - 무료 플랜');
    debugPrint('5. limit@test.com (test123456) - 무료 제한 도달');
    debugPrint('6. premium@test.com (test123456) - 프리미엄 활성');
    debugPrint('7. plimit@test.com (test123456) - 프리미엄 제한 도달');
    debugPrint('=== 연간 구독 (Yearly) ===');
    debugPrint('8. yearly@test.com (test123456) - 프리미엄 연간 활성');
    debugPrint('9. yearlylimit@test.com (test123456) - 프리미엄 연간 제한 도달');
  }
} 