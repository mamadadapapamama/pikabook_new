import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/subscription/app_store_subscription_service.dart';
import '../services/common/plan_service.dart';
import '../services/common/banner_manager.dart';

/// 구독 상태 디버깅 헬퍼
/// 
/// 실제 Firebase Functions 응답과 로컬 데이터를 비교하여
/// 구독 상태 불일치 문제를 진단합니다.
class SubscriptionDebugHelper {
  static final SubscriptionDebugHelper _instance = SubscriptionDebugHelper._internal();
  factory SubscriptionDebugHelper() => _instance;
  SubscriptionDebugHelper._internal();

  /// 🔍 전체 구독 상태 진단
  Future<void> diagnoseSubscriptionState() async {
    if (!kDebugMode) return;

    debugPrint('🔍 === 구독 상태 진단 시작 ===');
    
    // 1. 사용자 정보 확인
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('❌ 사용자가 로그인되어 있지 않습니다');
      return;
    }
    
    debugPrint('👤 사용자 ID: ${user.uid}');
    debugPrint('📧 이메일: ${user.email}');
    
    try {
      // 2. Firebase Functions 직접 응답 확인
      await _checkFirebaseFunctionsResponse();
      
      // 3. Firestore 사용자 문서 확인
      await _checkFirestoreUserDocument(user.uid);
      
      // 4. PlanService 처리 결과 확인
      await _checkPlanServiceResult();
      
      // 5. BannerManager 결정 로직 확인
      await _checkBannerManagerLogic();
      
    } catch (e) {
      debugPrint('❌ 진단 중 오류 발생: $e');
    }
    
    debugPrint('🔍 === 구독 상태 진단 완료 ===');
  }

  /// Firebase Functions 직접 응답 확인
  Future<void> _checkFirebaseFunctionsResponse() async {
    debugPrint('\n📡 Firebase Functions 직접 응답:');
    
    try {
      final appStoreService = AppStoreSubscriptionService();
      final status = await appStoreService.checkSubscriptionStatus(forceRefresh: true);
      
      debugPrint('   플랜 타입: ${status.planType}');
      debugPrint('   활성 상태: ${status.isActive}');
      debugPrint('   만료일: ${status.expirationDate}');
      debugPrint('   자동 갱신: ${status.autoRenewStatus}');
      debugPrint('   프리미엄: ${status.isPremium}');
      debugPrint('   체험: ${status.isTrial}');
      debugPrint('   무료: ${status.isFree}');
      
    } catch (e) {
      debugPrint('   ❌ Firebase Functions 호출 실패: $e');
    }
  }

  /// Firestore 사용자 문서 확인
  Future<void> _checkFirestoreUserDocument(String userId) async {
    debugPrint('\n📄 Firestore 사용자 문서:');
    
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        
        debugPrint('   hasUsedFreeTrial: ${data['hasUsedFreeTrial']}');
        debugPrint('   hasEverUsedTrial: ${data['hasEverUsedTrial']}');
        debugPrint('   hasEverUsedPremium: ${data['hasEverUsedPremium']}');
        
        final subscription = data['subscription'] as Map<String, dynamic>?;
        if (subscription != null) {
          debugPrint('   구독 정보:');
          debugPrint('     플랜: ${subscription['plan']}');
          debugPrint('     상태: ${subscription['status']}');
          debugPrint('     체험: ${subscription['isFreeTrial']}');
          debugPrint('     시작일: ${subscription['startDate']}');
          debugPrint('     만료일: ${subscription['expiryDate']}');
        } else {
          debugPrint('   구독 정보: 없음 (무료 플랜)');
        }
      } else {
        debugPrint('   사용자 문서가 존재하지 않습니다');
      }
      
    } catch (e) {
      debugPrint('   ❌ Firestore 확인 실패: $e');
    }
  }

  /// PlanService 처리 결과 확인
  Future<void> _checkPlanServiceResult() async {
    debugPrint('\n🔧 PlanService 처리 결과:');
    
    try {
      final planService = PlanService();
      final details = await planService.getSubscriptionDetails(forceRefresh: true);
      
      debugPrint('   현재 플랜: ${details['currentPlan']}');
      debugPrint('   현재 체험 중: ${details['isFreeTrial']}');
      debugPrint('   체험 사용 이력: ${details['hasUsedFreeTrial']}');
      debugPrint('   체험 사용 이력(영구): ${details['hasEverUsedTrial']}');
      debugPrint('   프리미엄 사용 이력: ${details['hasEverUsedPremium']}');
      debugPrint('   만료 여부: ${details['isExpired']}');
      debugPrint('   남은 일수: ${details['daysRemaining']}');
      debugPrint('   취소 상태: ${details['isCancelled']}');
      debugPrint('   자동 갱신: ${details['autoRenewStatus']}');
      
    } catch (e) {
      debugPrint('   ❌ PlanService 확인 실패: $e');
    }
  }

  /// BannerManager 결정 로직 확인
  Future<void> _checkBannerManagerLogic() async {
    debugPrint('\n🎯 BannerManager 결정 로직:');
    
    try {
      final bannerManager = BannerManager();
      final activeBanners = await bannerManager.getActiveBanners();
      
      debugPrint('   활성 배너 수: ${activeBanners.length}');
      for (final banner in activeBanners) {
        debugPrint('   - ${banner.name}: ${banner.title}');
        final shouldShow = await bannerManager.shouldShowBanner(banner);
        debugPrint('     표시 여부: $shouldShow');
      }
      
      if (activeBanners.isEmpty) {
        debugPrint('   활성 배너 없음');
      }
      
    } catch (e) {
      debugPrint('   ❌ BannerManager 확인 실패: $e');
    }
  }

  /// 🧪 특정 시나리오 재현을 위한 테스트 데이터 생성
  Future<void> recreateTestScenario(String scenario) async {
    if (!kDebugMode) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('❌ 로그인이 필요합니다');
      return;
    }

    debugPrint('🧪 테스트 시나리오 재현: $scenario');

    try {
      final firestore = FirebaseFirestore.instance;
      final now = DateTime.now();

      switch (scenario) {
        case 'fresh_trial':
          // 방금 체험 시작한 상태 재현
          await firestore.collection('users').doc(user.uid).update({
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
            'hasEverUsedPremium': false, // 아직 정식 프리미엄은 아님
          });
          debugPrint('✅ 신규 7일 체험 시작 상태로 설정 완료');
          break;

        case 'trial_expired':
          // 체험 만료 상태 재현
          await firestore.collection('users').doc(user.uid).update({
            'subscription': FieldValue.delete(),
            'hasUsedFreeTrial': true,
            'hasEverUsedTrial': true,
            'hasEverUsedPremium': false,
          });
          debugPrint('✅ 체험 만료 → 무료 플랜 상태로 설정 완료');
          break;

        default:
          debugPrint('❌ 알 수 없는 시나리오: $scenario');
      }

      // 캐시 무효화
      final planService = PlanService();
      planService.notifyPlanChanged('test', userId: user.uid);

    } catch (e) {
      debugPrint('❌ 테스트 시나리오 생성 실패: $e');
    }
  }

  /// 📊 구독 상태 요약 출력
  Future<void> printSubscriptionSummary() async {
    if (!kDebugMode) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await diagnoseSubscriptionState();
    } catch (e) {
      debugPrint('📊 구독 상태 요약 실패: $e');
    }
  }
}