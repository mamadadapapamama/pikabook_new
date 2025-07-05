import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../services/subscription/app_store_subscription_service.dart';
import '../services/common/plan_service.dart';
import '../services/common/banner_manager.dart';
import '../services/payment/in_app_purchase_service.dart';

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

  /// 🧪 실기기 App Store 구독 테스트 환경 진단 도구
  Future<Map<String, dynamic>> diagnosisTestEnvironment() async {
    if (kDebugMode) {
      debugPrint('🧪 [SubscriptionDebug] === 실기기 테스트 환경 진단 시작 ===');
    }

    final diagnosis = <String, dynamic>{};

    try {
      // 1. 기본 환경 확인
      diagnosis['environment'] = await _checkEnvironment();
      
      // 2. Firebase 연결 상태
      diagnosis['firebase'] = await _checkFirebaseConnection();
      
      // 3. App Store Connect 상태
      diagnosis['appStore'] = await _checkAppStoreConnection();
      
      // 4. 샌드박스 테스트 계정 상태
      diagnosis['sandbox'] = await _checkSandboxAccount();
      
      // 5. 현재 구독 상태
      diagnosis['subscription'] = await _checkCurrentSubscription();

      // 6. 진단 결과 출력
      _printDiagnosisResult(diagnosis);
      
      return diagnosis;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SubscriptionDebug] 진단 중 오류: $e');
      }
      diagnosis['error'] = e.toString();
      return diagnosis;
    }
  }

  /// 1. 기본 환경 확인
  Future<Map<String, dynamic>> _checkEnvironment() async {
    return {
      'isDebugMode': kDebugMode,
      'isReleaseMode': kReleaseMode,
      'isProfileMode': kProfileMode,
      'buildMode': kDebugMode ? 'Debug' : (kReleaseMode ? 'Release' : 'Profile'),
    };
  }

  /// 2. Firebase 연결 상태 확인
  Future<Map<String, dynamic>> _checkFirebaseConnection() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      
      if (currentUser == null) {
        return {
          'status': 'not_logged_in',
          'message': '❌ Firebase 로그인 필요',
        };
      }

      // Firestore 연결 테스트
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      return {
        'status': 'connected',
        'userId': currentUser.uid,
        'email': currentUser.email,
        'userDocExists': userDoc.exists,
        'message': '✅ Firebase 연결 정상',
      };
    } catch (e) {
      return {
        'status': 'error',
        'message': '❌ Firebase 연결 오류: $e',
      };
    }
  }

  /// 3. App Store Connect 상태 확인
  Future<Map<String, dynamic>> _checkAppStoreConnection() async {
    try {
      final appStoreService = AppStoreSubscriptionService();
      
      // Firebase Functions 호출 테스트
      final subscriptionStatus = await appStoreService.getCurrentSubscriptionStatus(forceRefresh: true);
      
      return {
        'status': 'connected',
        'planType': subscriptionStatus.planType,
        'isActive': subscriptionStatus.isActive,
        'isPremium': subscriptionStatus.isPremium,
        'isTrial': subscriptionStatus.isTrial,
        'autoRenewStatus': subscriptionStatus.autoRenewStatus,
        'message': '✅ App Store Connect 연결 정상',
      };
    } catch (e) {
      return {
        'status': 'error',
        'message': '❌ App Store Connect 오류: $e',
      };
    }
  }

  /// 4. 샌드박스 테스트 계정 상태 확인
  Future<Map<String, dynamic>> _checkSandboxAccount() async {
    try {
      final inAppPurchase = InAppPurchase.instance;
      final isAvailable = await inAppPurchase.isAvailable();
      
      if (!isAvailable) {
        return {
          'status': 'unavailable',
          'message': '❌ In-App Purchase 사용 불가 (설정 → App Store에서 샌드박스 계정 로그인 필요)',
        };
      }

      // 상품 정보 로드 테스트
      const productIds = {
        'premium_monthly',
        'premium_yearly', 
        'premium_monthly_with_trial'
      };
      
      final productDetailsResponse = await inAppPurchase.queryProductDetails(productIds);
      
      return {
        'status': 'available',
        'availableProducts': productDetailsResponse.productDetails.map((p) => p.id).toList(),
        'notFoundProducts': productDetailsResponse.notFoundIDs,
        'message': isAvailable 
            ? '✅ In-App Purchase 사용 가능 (샌드박스 환경 감지됨)'
            : '⚠️ In-App Purchase 상태 불명확',
      };
    } catch (e) {
      return {
        'status': 'error',
        'message': '❌ 샌드박스 확인 오류: $e',
      };
    }
  }

  /// 5. 현재 구독 상태 확인
  Future<Map<String, dynamic>> _checkCurrentSubscription() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        return {
          'status': 'not_logged_in',
          'message': '❌ 로그인 필요',
        };
      }

      // Firestore에서 직접 구독 정보 확인
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) {
        return {
          'status': 'no_user_doc',
          'message': '❌ 사용자 문서 없음',
        };
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final subscriptionData = userData['subscription'] as Map<String, dynamic>?;

      return {
        'status': 'found',
        'firestoreData': subscriptionData,
        'hasSubscriptionField': subscriptionData != null,
        'message': subscriptionData != null 
            ? '✅ Firestore 구독 정보 존재'
            : '⚠️ Firestore 구독 정보 없음 (Firebase Functions 의존)',
      };
    } catch (e) {
      return {
        'status': 'error',
        'message': '❌ 구독 상태 확인 오류: $e',
      };
    }
  }

  /// 진단 결과 출력
  void _printDiagnosisResult(Map<String, dynamic> diagnosis) {
    if (!kDebugMode) return;

    debugPrint('\n🧪 === 실기기 테스트 환경 진단 결과 ===');
    debugPrint('');
    
    // 환경 정보
    final env = diagnosis['environment'] as Map<String, dynamic>?;
    if (env != null) {
      debugPrint('📱 빌드 환경: ${env['buildMode']}');
      debugPrint('   - Debug: ${env['isDebugMode']}');
      debugPrint('   - Release: ${env['isReleaseMode']}');
    }
    
    // Firebase 상태
    final firebase = diagnosis['firebase'] as Map<String, dynamic>?;
    if (firebase != null) {
      debugPrint('🔥 Firebase: ${firebase['message']}');
      if (firebase['status'] == 'connected') {
        debugPrint('   - 사용자: ${firebase['email']}');
        debugPrint('   - 문서 존재: ${firebase['userDocExists']}');
      }
    }
    
    // App Store 상태
    final appStore = diagnosis['appStore'] as Map<String, dynamic>?;
    if (appStore != null) {
      debugPrint('🍎 App Store: ${appStore['message']}');
      if (appStore['status'] == 'connected') {
        debugPrint('   - 현재 플랜: ${appStore['planType']}');
        debugPrint('   - 프리미엄: ${appStore['isPremium']}');
        debugPrint('   - 체험: ${appStore['isTrial']}');
      }
    }
    
    // 샌드박스 상태
    final sandbox = diagnosis['sandbox'] as Map<String, dynamic>?;
    if (sandbox != null) {
      debugPrint('🧪 샌드박스: ${sandbox['message']}');
      if (sandbox['status'] == 'available') {
        debugPrint('   - 사용 가능한 상품: ${sandbox['availableProducts']}');
        debugPrint('   - 찾을 수 없는 상품: ${sandbox['notFoundProducts']}');
      }
    }
    
    // 구독 상태
    final subscription = diagnosis['subscription'] as Map<String, dynamic>?;
    if (subscription != null) {
      debugPrint('📊 구독 정보: ${subscription['message']}');
      if (subscription['firestoreData'] != null) {
        debugPrint('   - Firestore 데이터: ${subscription['firestoreData']}');
      }
    }
    
    debugPrint('');
    debugPrint('=== 진단 완료 ===\n');
  }

  /// 🎯 실기기 테스트용 샌드박스 계정 설정 가이드 출력
  void printSandboxSetupGuide() {
    if (!kDebugMode) return;

    debugPrint('\n🧪 === 실기기 샌드박스 테스트 설정 가이드 ===');
    debugPrint('');
    debugPrint('1️⃣ App Store Connect에서 샌드박스 테스트 계정 생성');
    debugPrint('   - App Store Connect → Users and Access → Sandbox Testers');
    debugPrint('   - + 버튼으로 새 테스트 계정 생성');
    debugPrint('   - 예: test+sandbox1@yourdomain.com');
    debugPrint('');
    debugPrint('2️⃣ 실기기에서 샌드박스 계정 로그인');
    debugPrint('   - iOS 설정 → App Store → 샌드박스 계정');
    debugPrint('   - 생성한 테스트 계정으로 로그인');
    debugPrint('');
    debugPrint('3️⃣ 앱에서 구독 테스트');
    debugPrint('   - 앱 재시작');
    debugPrint('   - 구독 버튼 클릭');
    debugPrint('   - 샌드박스 계정으로 결제 진행');
    debugPrint('');
    debugPrint('⚠️ 주의사항:');
    debugPrint('   - 프로덕션 Apple ID로 샌드박스 테스트 불가');
    debugPrint('   - 샌드박스에서는 실제 결제되지 않음');
    debugPrint('   - 테스트 후 구독이 자동으로 만료됨');
    debugPrint('');
    debugPrint('=== 설정 가이드 완료 ===\n');
  }

  /// 🔧 테스트용 Firestore 데이터 생성
  Future<bool> createTestSubscriptionData({
    required String testType,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        if (kDebugMode) {
          debugPrint('❌ [SubscriptionDebug] 로그인 필요');
        }
        return false;
      }

      final now = DateTime.now();
      Map<String, dynamic> subscriptionData;

      switch (testType) {
        case 'free':
          subscriptionData = {
            'plan': 'free',
            'status': 'active',
            'isActive': true,
            'isFreeTrial': false,
            'autoRenewStatus': false,
          };
          break;
        case 'trial':
          subscriptionData = {
            'plan': 'premium',
            'status': 'trial',
            'isActive': true,
            'isFreeTrial': true,
            'autoRenewStatus': true,
            'startDate': Timestamp.fromDate(now.subtract(const Duration(days: 2))),
            'expirationDate': Timestamp.fromDate(now.add(const Duration(days: 5))),
          };
          break;
        case 'premium':
          subscriptionData = {
            'plan': 'premium',
            'status': 'active',
            'isActive': true,
            'isFreeTrial': false,
            'autoRenewStatus': true,
            'startDate': Timestamp.fromDate(now.subtract(const Duration(days: 10))),
            'expirationDate': Timestamp.fromDate(now.add(const Duration(days: 20))),
          };
          break;
        default:
          if (kDebugMode) {
            debugPrint('❌ [SubscriptionDebug] 알 수 없는 테스트 타입: $testType');
          }
          return false;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .update({
        'subscription': subscriptionData,
      });

      if (kDebugMode) {
        debugPrint('✅ [SubscriptionDebug] 테스트 데이터 생성 완료: $testType');
        debugPrint('   데이터: $subscriptionData');
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SubscriptionDebug] 테스트 데이터 생성 실패: $e');
      }
      return false;
    }
  }

  /// 🔧 Firestore 직접 조회 테스트 (Firebase Functions 무시)
  Future<Map<String, dynamic>> testFirestoreDirectly() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        return {
          'status': 'error',
          'message': '❌ 로그인 필요',
        };
      }

      if (kDebugMode) {
        debugPrint('🔍 [SubscriptionDebug] Firestore 직접 조회 테스트 시작: ${currentUser.uid}');
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) {
        return {
          'status': 'no_document',
          'message': '❌ 사용자 문서 없음',
        };
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      final subscriptionData = userData['subscription'] as Map<String, dynamic>?;

      if (subscriptionData == null) {
        return {
          'status': 'no_subscription',
          'message': '❌ subscription 필드 없음',
          'userData': userData,
        };
      }

      // 구독 정보 파싱 테스트
      final plan = subscriptionData['plan'] as String? ?? 'free';
      final isActive = subscriptionData['isActive'] as bool? ?? false;
      final isFreeTrial = subscriptionData['isFreeTrial'] as bool? ?? false;
      final autoRenewStatus = subscriptionData['autoRenewStatus'] as bool? ?? false;

      String planType = plan;
      if (isFreeTrial && plan == 'premium') {
        planType = 'trial';
      }

             if (kDebugMode) {
         debugPrint('✅ [SubscriptionDebug] Firestore 직접 조회 성공:');
         debugPrint('   - 전체 subscription 데이터: $subscriptionData');
         debugPrint('   - 원본 plan: $plan');
         debugPrint('   - 최종 planType: $planType');
         debugPrint('   - isActive: $isActive');
         debugPrint('   - isFreeTrial: $isFreeTrial');
         debugPrint('   - autoRenewStatus: $autoRenewStatus');
       }

      return {
        'status': 'success',
        'message': '✅ Firestore 직접 조회 성공',
        'subscriptionData': subscriptionData,
        'parsedPlanType': planType,
        'parsedIsActive': isActive,
        'parsedIsTrial': isFreeTrial,
        'parsedAutoRenew': autoRenewStatus,
      };

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SubscriptionDebug] Firestore 직접 조회 실패: $e');
      }
      return {
        'status': 'error',
        'message': '❌ Firestore 조회 오류: $e',
      };
    }
  }

  /// 🔄 배너 닫기 상태 리셋
  Future<bool> resetBannerDismissStates() async {
    try {
      final bannerManager = BannerManager();
      await bannerManager.resetAllBannerStates();
      
      if (kDebugMode) {
        debugPrint('✅ [SubscriptionDebug] 모든 배너 닫기 상태 리셋 완료');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SubscriptionDebug] 배너 상태 리셋 실패: $e');
      }
      return false;
    }
  }

  /// 🔄 특정 배너 닫기 상태 리셋
  Future<bool> resetSpecificBanner(String bannerTypeName) async {
    try {
      final bannerManager = BannerManager();
      
      // 배너 타입 문자열을 BannerType enum으로 변환
      BannerType? bannerType;
      for (final type in BannerType.values) {
        if (type.name == bannerTypeName) {
          bannerType = type;
          break;
        }
      }
      
      if (bannerType == null) {
        if (kDebugMode) {
          debugPrint('❌ [SubscriptionDebug] 알 수 없는 배너 타입: $bannerTypeName');
          debugPrint('   사용 가능한 타입: ${BannerType.values.map((e) => e.name).toList()}');
        }
        return false;
      }
      
      await bannerManager.resetBannerState(bannerType);
      
      if (kDebugMode) {
        debugPrint('✅ [SubscriptionDebug] $bannerTypeName 배너 상태 리셋 완료');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SubscriptionDebug] 특정 배너 상태 리셋 실패: $e');
      }
      return false;
    }
  }
}