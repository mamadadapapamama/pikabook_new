import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'usage_limit_service.dart';
import '../../models/subscription_state.dart';

/// 배너 타입 열거형
enum BannerType {
  free,               // 무료 플랜
  trialStarted,       // 🆕 트라이얼 시작
  trialCancelled,     // 프리미엄 체험 취소
  trialCompleted,     // 트라이얼 완료
  premiumStarted,     // 🆕 프리미엄 시작 (무료체험 없이 바로 구매)
  premiumExpired,     // 프리미엄 만료
  premiumGrace,       // 🆕 Grace Period
  premiumCancelled,   // 🆕 프리미엄 구독 취소
  usageLimitFree,     // 무료 플랜 사용량 한도 → 업그레이드 모달
  usageLimitPremium,  // 프리미엄 플랜 사용량 한도 → 문의 폼
}

extension BannerTypeExtension on BannerType {
  String get name {
    switch (this) {
      case BannerType.free:
        return 'free';
      case BannerType.trialStarted:
        return 'trialStarted';
      case BannerType.trialCancelled:
        return 'trialCancelled';
      case BannerType.trialCompleted:
        return 'trialCompleted';
      case BannerType.premiumStarted:
        return 'premiumStarted';
      case BannerType.premiumExpired:
        return 'premiumExpired';
      case BannerType.premiumGrace:
        return 'premiumGrace';
      case BannerType.premiumCancelled:
        return 'premiumCancelled';
      case BannerType.usageLimitFree:
        return 'usageLimitFree';
      case BannerType.usageLimitPremium:
        return 'usageLimitPremium';
    }
  }

  String get title {
    switch (this) {
      case BannerType.free:
        return '무료 플랜 시작';
      case BannerType.trialStarted:
        return '🎉 프리미엄 체험 시작';
      case BannerType.trialCancelled:
        return '⏰ 프리미엄 구독 전환 취소됨';
      case BannerType.trialCompleted:
        return '⏰ 프리미엄 월 구독으로 전환됨';
      case BannerType.premiumStarted:
        return '🎉 프리미엄 시작';
      case BannerType.premiumExpired:
        return '💎 프리미엄 만료';
      case BannerType.premiumGrace:
        return '⚠️ 결제 확인 필요';
      case BannerType.premiumCancelled:
        return '⏰ 프리미엄 구독 전환 취소됨';
      case BannerType.usageLimitFree:
        return '⚠️ 사용량 한도 도달';
      case BannerType.usageLimitPremium:
        return '⚠️ 사용량 한도 도달';
    }
  }

  String get subtitle {
    switch (this) {
      case BannerType.free:
        return '무료 플랜을 사용 중입니다. 제한 없이 사용하시려면 프리미엄을 구독해 보세요.';
      case BannerType.trialStarted:
        return '7일간 프리미엄 기능을 여유있게 사용해보세요';
      case BannerType.trialCancelled:
        return '체험 기간 종료 시 무료 플랜으로 전환됩니다. 계속 사용하려면 구독하세요';
      case BannerType.trialCompleted:
        return '프리미엄 월 구독으로 전환되었습니다! 피카북을 여유있게 사용해보세요';
      case BannerType.premiumStarted:
        return '프리미엄 구독이 시작되었습니다! 피카북을 여유있게 사용해보세요';
      case BannerType.premiumExpired:
        return '프리미엄 혜택이 만료되었습니다. 계속 사용하려면 다시 구독하세요';
      case BannerType.premiumGrace:
        return 'App Store에서 결제 정보를 확인해주세요. 확인되지 않으면 구독이 취소될 수 있습니다';
      case BannerType.premiumCancelled:
        return '프리미엄 구독이 취소되었습니다. 계속 사용하려면 다시 구독하세요';
      case BannerType.usageLimitFree:
        return '프리미엄으로 업그레이드하여 무제한으로 사용하세요';
      case BannerType.usageLimitPremium:
        return '추가 사용량이 필요하시면 문의해 주세요';
    }
  }
}

/// 통합 배너 관리 서비스 (서버 응답 기반)
/// 구독 상태에 따른 배너 표시/숨김 관리 (사용자별 분리)
class BannerManager {
  // 싱글톤 패턴
  static final BannerManager _instance = BannerManager._internal();
  factory BannerManager() => _instance;
  BannerManager._internal();

  // 배너별 상태 저장
  final Map<BannerType, bool> _bannerStates = {};
  
  // 플랜별 배너 ID 저장 (프리미엄 만료, 체험 완료용)
  final Map<BannerType, String?> _bannerPlanIds = {};
  
  // 🔄 사용자별 SharedPreferences 키 생성
  static const Map<BannerType, String> _bannerKeyPrefixes = {
    BannerType.free: 'free_banner_dismissed_',
    BannerType.trialStarted: 'trial_started_banner_dismissed_',
    BannerType.trialCancelled: 'trial_cancelled_banner_dismissed_',
    BannerType.trialCompleted: 'trial_completed_banner_dismissed_',
    BannerType.premiumStarted: 'premium_started_banner_dismissed_',
    BannerType.premiumExpired: 'premium_expired_banner_dismissed_',
    BannerType.premiumGrace: 'premium_grace_banner_dismissed_',
    BannerType.premiumCancelled: 'premium_cancelled_banner_dismissed_',
    BannerType.usageLimitFree: 'usage_limit_free_banner_shown_',
    BannerType.usageLimitPremium: 'usage_limit_premium_banner_shown_',
  };

  // 🆔 현재 사용자 ID 가져오기
  String? get _currentUserId => FirebaseAuth.instance.currentUser?.uid;

  // 🔑 사용자별 배너 키 생성
  String _getUserBannerKey(BannerType type, {String? planId}) {
    final userId = _currentUserId ?? 'anonymous';
    final keyPrefix = _bannerKeyPrefixes[type]!;
    
    if (planId != null) {
      return '${keyPrefix}${userId}_$planId';
    } else {
      return '${keyPrefix}$userId';
    }
  }

  /// 구독 상태에 따른 배너 상태 설정
  void setBannerState(BannerType type, bool shouldShow, {String? planId}) {
    _bannerStates[type] = shouldShow;
    
    // 플랜 ID가 필요한 배너들
    if (type == BannerType.free || type == BannerType.trialStarted || type == BannerType.trialCancelled || 
        type == BannerType.trialCompleted || type == BannerType.premiumStarted ||
        type == BannerType.premiumExpired || type == BannerType.premiumCancelled || 
        type == BannerType.premiumGrace) {
      _bannerPlanIds[type] = planId ?? '${type.name}_${DateTime.now().millisecondsSinceEpoch}';
    }
    
    if (kDebugMode) {
      debugPrint('🎯 [BannerManager] ${type.name} 상태 설정: $shouldShow${planId != null ? ' (플랜ID: $planId)' : ''}');
    }
  }



  /// 배너 닫기 (사용자가 X 버튼 클릭 시) - 사용자별
  Future<void> dismissBanner(BannerType type) async {
    try {
      if (kDebugMode) {
        debugPrint('🚫 [BannerManager] dismissBanner 시작: ${type.name} (사용자: ${_currentUserId ?? 'anonymous'})');
      }
      
      final prefs = await SharedPreferences.getInstance();
      
      // 사용량 한도 배너는 단순 처리 (사용자별)
      if (type == BannerType.usageLimitFree || type == BannerType.usageLimitPremium) {
        final key = _getUserBannerKey(type);
        await prefs.setBool(key, true);
        
        if (kDebugMode) {
          debugPrint('✅ [BannerManager] ${type.name} 사용량 한도 배너 닫기 완료');
          debugPrint('   저장된 키: $key');
          debugPrint('   저장된 값: true');
        }
        return;
      }
      
      // 상태별 배너는 플랜별 처리 (사용자별)
      final planId = _bannerPlanIds[type];
      if (planId == null) {
        if (kDebugMode) {
          debugPrint('⚠️ [BannerManager] ${type.name} 플랜 ID가 없어서 닫기 처리 불가');
          debugPrint('   현재 _bannerPlanIds: $_bannerPlanIds');
        }
        return;
      }
      
      final dismissKey = _getUserBannerKey(type, planId: planId);
      await prefs.setBool(dismissKey, true);
      
      if (kDebugMode) {
        debugPrint('✅ [BannerManager] ${type.name} 플랜별 배너 닫기 완료');
        debugPrint('   플랜 ID: $planId');
        debugPrint('   저장된 키: $dismissKey');
        debugPrint('   저장된 값: true');
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [BannerManager] ${type.name} 배너 닫기 실패: $e');
        debugPrint('   에러 스택: ${e.toString()}');
      }
      rethrow; // 에러를 다시 던져서 HomeScreen에서 확인 가능하도록
    }
  }

  /// 🆕 로그아웃 시 배너 상태 초기화 (메모리만)
  void clearUserBannerStates() {
    _bannerStates.clear();
    _bannerPlanIds.clear();
    
    if (kDebugMode) {
      debugPrint('🔄 [BannerManager] 로그아웃으로 인한 메모리 배너 상태 초기화');
    }
  }

  /// 🆕 특정 사용자의 모든 배너 기록 삭제 (탈퇴 시)
  Future<void> deleteUserBannerData(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();
      
      // 해당 사용자의 모든 배너 키 찾아서 삭제
      for (final key in allKeys) {
        for (final bannerType in BannerType.values) {
          final keyPrefix = _bannerKeyPrefixes[bannerType]! + userId;
          if (key.startsWith(keyPrefix)) {
            await prefs.remove(key);
            if (kDebugMode) {
              debugPrint('🗑️ [BannerManager] 사용자 배너 데이터 삭제: $key');
            }
          }
        }
      }
      
      if (kDebugMode) {
        debugPrint('✅ [BannerManager] 사용자 $userId의 모든 배너 데이터 삭제 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [BannerManager] 사용자 배너 데이터 삭제 실패: $e');
      }
    }
  }

  /// 🆕 서버 응답으로부터 직접 배너 결정
  Future<List<BannerType>> getActiveBannersFromServerResponse(
    Map<String, dynamic> serverResponse, {
    bool forceRefresh = false,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🎯 [BannerManager] ===== 서버 응답 기반 배너 결정 시작 =====');
      }
      
      final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;
      final activeBanners = <BannerType>[];
      
      // 서버 응답에서 subscription 필드 추출 (안전한 타입 변환)
      final subscription = _safeMapConversion(serverResponse['subscription']);
      
      if (subscription == null) {
        if (kDebugMode) {
          debugPrint('⚠️ [BannerManager] subscription 필드 없음 - 기본 상태');
        }
        return activeBanners;
      }
      
      // 필드 추출
      final entitlement = subscription['entitlement'] as String? ?? 'free';
      final subscriptionStatus = subscription['subscriptionStatus'] as String? ?? 'cancelled';
      final hasUsedTrial = subscription['hasUsedTrial'] as bool? ?? false;
      final expirationDate = subscription['expirationDate'] as String?;
      
      if (kDebugMode) {
        debugPrint('📥 [BannerManager] 서버 응답 필드:');
        debugPrint('   entitlement: $entitlement');
        debugPrint('   subscriptionStatus: $subscriptionStatus');
        debugPrint('   hasUsedTrial: $hasUsedTrial');
        debugPrint('   expirationDate: $expirationDate');
      }
      
      // 🧪 테스트 계정 배너 메타데이터 우선 처리 (안전한 타입 변환)
      final bannerMetadata = _safeMapConversion(subscription['bannerMetadata']);
      if (bannerMetadata != null) {
        final testBanners = await _handleTestAccountBanners(bannerMetadata);
        
        if (kDebugMode) {
          debugPrint('🧪 [BannerManager] 테스트 계정 배너: ${testBanners.map((e) => e.name).toList()}');
        }
        return testBanners;
      }
      
      // 🚀 병렬 처리: 사용량 체크와 SharedPreferences 로드
      final futures = await Future.wait([
        UsageLimitService().checkInitialLimitStatus(),
        SharedPreferences.getInstance(),
      ]);
      
      final usageLimitStatus = futures[0] as Map<String, bool>;
      final prefs = futures[1] as SharedPreferences;
      
      // 사용량 한도 배너 결정
      _decideUsageLimitBannersFromServerResponse(activeBanners, entitlement, usageLimitStatus, prefs);
      
      // 구독 상태 배너 결정 (Grace Period 감지 포함)
      _decidePlanBannersFromServerResponse(activeBanners, entitlement, subscriptionStatus, hasUsedTrial, prefs, 
        expirationDate: expirationDate);
      
      if (kDebugMode) {
        stopwatch?.stop();
        debugPrint('✅ [BannerManager] 배너 결정 완료 (${stopwatch?.elapsedMilliseconds}ms)');
        debugPrint('   활성 배너: ${activeBanners.map((e) => e.name).toList()}');
      }
      
      return activeBanners;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [BannerManager] 배너 결정 실패: $e');
      }
      return [];
    }
  }

  /// 사용량 한도 배너 결정 (v4-simplified)
  void _decideUsageLimitBannersFromServerResponse(
    List<BannerType> activeBanners, 
    String entitlement, 
    Map<String, bool> usageLimitStatus,
    SharedPreferences prefs,
  ) {
    final ocrLimitReached = usageLimitStatus['ocrLimitReached'] ?? false;
    final ttsLimitReached = usageLimitStatus['ttsLimitReached'] ?? false;
    
    if (ocrLimitReached || ttsLimitReached) {
      if (entitlement == 'premium') {
        setBannerState(BannerType.usageLimitPremium, true);
        setBannerState(BannerType.usageLimitFree, false);
        if (_shouldShowBannerSync(BannerType.usageLimitPremium, prefs)) {
          activeBanners.add(BannerType.usageLimitPremium);
        }
      } else {
        setBannerState(BannerType.usageLimitFree, true);
        setBannerState(BannerType.usageLimitPremium, false);
        if (_shouldShowBannerSync(BannerType.usageLimitFree, prefs)) {
          activeBanners.add(BannerType.usageLimitFree);
        }
      }
    } else {
      setBannerState(BannerType.usageLimitFree, false);
      setBannerState(BannerType.usageLimitPremium, false);
    }
  }

  /// 플랜 배너 결정 (v4-simplified) - Grace Period 감지 포함
  void _decidePlanBannersFromServerResponse(
    List<BannerType> activeBanners,
    String entitlement,
    String subscriptionStatus, 
    bool hasUsedTrial,
    SharedPreferences prefs, {
    String? expirationDate,
  }) {
    final planId = 'plan_${DateTime.now().millisecondsSinceEpoch}';
    
    if (kDebugMode) {
      debugPrint('🎯 [BannerManager] v4-simplified 플랜 배너 결정:');
      debugPrint('   entitlement: $entitlement');
      debugPrint('   subscriptionStatus: $subscriptionStatus');
      debugPrint('   hasUsedTrial: $hasUsedTrial');
    }

    // 🚨 상태 변경 시 모든 이전 배너를 강제로 숨김 (중요!)
    _resetAllBannerStates();
    _dismissAllPreviousBanners(prefs);

    // 🎯 Grace Period 감지 (entitlement=premium + active 상태 + 만료일 임박)
    bool isGracePeriod = false;
    if (entitlement == 'premium' && subscriptionStatus == 'active' && expirationDate != null) {
      try {
        final expiration = DateTime.parse(expirationDate);
        final now = DateTime.now();
        final daysUntilExpiration = expiration.difference(now).inDays;
        
        // 만료일이 7일 이내면서 결제 확인이 필요한 상태로 추정 (Grace Period)
        if (daysUntilExpiration <= 7 && daysUntilExpiration >= 0) {
          isGracePeriod = true;
          if (kDebugMode) {
            debugPrint('🚨 [BannerManager] Grace Period 감지: ${daysUntilExpiration}일 남음');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ [BannerManager] 만료일 파싱 실패: $expirationDate');
        }
      }
    }

    // 🎯 현재 상태에 맞는 배너 하나만 결정 (우선순위 기반)
    BannerType? currentBanner;
    
    if (kDebugMode) {
      debugPrint('🔍 [BannerManager] 배너 결정 로직 검사:');
      debugPrint('   isGracePeriod: $isGracePeriod');
      debugPrint('   subscriptionStatus: $subscriptionStatus');
      debugPrint('   entitlement: $entitlement');
      debugPrint('   hasUsedTrial: $hasUsedTrial');
    }
    
    if (isGracePeriod) {
      // 🚨 최우선: Grace Period
      currentBanner = BannerType.premiumGrace;
      if (kDebugMode) {
        debugPrint('🚨 [BannerManager] Grace Period 배너 선택');
      }
    } else if (subscriptionStatus == 'active') {
      // 🎉 활성 상태
      if (entitlement == 'trial') {
        currentBanner = BannerType.trialStarted;
        if (kDebugMode) {
          debugPrint('🎉 [BannerManager] 트라이얼 시작 배너 선택');
        }
      } else if (entitlement == 'premium') {
        // 🎯 트라이얼에서 프리미엄으로 전환된 경우 감지
        if (hasUsedTrial) {
          currentBanner = BannerType.trialCompleted;
          if (kDebugMode) {
            debugPrint('🎉 [BannerManager] 트라이얼 완료 배너 선택');
          }
        } else {
          currentBanner = BannerType.premiumStarted;
          if (kDebugMode) {
            debugPrint('🎉 [BannerManager] 프리미엄 시작 배너 선택');
          }
        }
      }
    } else if (subscriptionStatus == 'cancelling') {
      // ⚠️ 취소 예정
      currentBanner = entitlement == 'trial' ? BannerType.trialCancelled : BannerType.premiumCancelled;
      if (kDebugMode) {
        debugPrint('⚠️ [BannerManager] 취소 예정 배너 선택: ${currentBanner?.name}');
      }
    } else if (subscriptionStatus == 'expired') {
      // 💔 만료됨
      if (entitlement == 'trial' || hasUsedTrial) {
        currentBanner = BannerType.trialCompleted;
        if (kDebugMode) {
          debugPrint('💔 [BannerManager] 트라이얼 완료 배너 선택 (만료됨)');
        }
      } else {
        currentBanner = BannerType.premiumExpired;
        if (kDebugMode) {
          debugPrint('💔 [BannerManager] 프리미엄 만료 배너 선택');
        }
      }
    } else if (subscriptionStatus == 'refunded') {
      // 💸 환불됨
      currentBanner = BannerType.premiumCancelled;
      if (kDebugMode) {
        debugPrint('💸 [BannerManager] 프리미엄 취소 배너 선택 (환불됨)');
      }
    } else if (subscriptionStatus == 'cancelled' && entitlement == 'free') {
      // 🆓 무료 플랜으로 전환된 모든 경우:
      // 1. 환영모달에서 트라이얼 사용하지 않고 나가기 (hasUsedTrial: false)
      // 2. 트라이얼 중도취소 후 기간 종료 (hasUsedTrial: true)
      // 3. 프리미엄 중도취소 후 기간 종료 
      //    - 트라이얼 없이 바로 프리미엄 구독한 유저 (hasUsedTrial: false)
      //    - 트라이얼 후 자동 프리미엄 전환된 유저 (hasUsedTrial: true)
      // 4. Grace Period 종료 (hasUsedTrial: true)
      currentBanner = BannerType.free;
      if (kDebugMode) {
        debugPrint('🆓 [BannerManager] 무료 플랜 배너 선택');
      }
    } else {
      // 🎯 예상치 못한 상태 조합 - 상세 로그
      if (kDebugMode) {
        debugPrint('❓ [BannerManager] 배너 결정 조건에 맞지 않음:');
        debugPrint('   subscriptionStatus: $subscriptionStatus');
        debugPrint('   entitlement: $entitlement');
        debugPrint('   hasUsedTrial: $hasUsedTrial');
        debugPrint('   isGracePeriod: $isGracePeriod');
      }
    }
    
    // 🎯 결정된 배너 하나만 활성화
    if (currentBanner != null) {
      setBannerState(currentBanner, true, planId: planId);
      if (_shouldShowBannerSync(currentBanner, prefs)) {
        activeBanners.add(currentBanner);
        
        if (kDebugMode) {
          debugPrint('✅ [BannerManager] 현재 상태 배너: ${currentBanner.name}');
        }
      }
    } else {
      if (kDebugMode) {
        debugPrint('ℹ️ [BannerManager] 현재 상태에 해당하는 배너 없음');
      }
    }
  }

  /// 🚨 모든 이전 배너를 강제로 닫힌 상태로 만들기
  /// 
  /// 새로운 상태의 배너를 표시하기 전에 모든 이전 배너를 숨김
  void _dismissAllPreviousBanners(SharedPreferences prefs) {
    final userId = _currentUserId ?? 'anonymous';
    
    // 🎯 모든 플랜 관련 배너 타입들
    final planBannerTypes = [
      BannerType.free,
      BannerType.trialStarted,
      BannerType.trialCancelled,
      BannerType.trialCompleted,
      BannerType.premiumStarted,
      BannerType.premiumExpired,
      BannerType.premiumCancelled,
      BannerType.premiumGrace,
    ];
    
    // 🚨 각 배너 타입의 모든 planId 변형을 찾아서 닫힌 상태로 설정
    final allKeys = prefs.getKeys();
    for (final bannerType in planBannerTypes) {
      final keyPrefix = _bannerKeyPrefixes[bannerType]! + userId + '_';
      
      for (final key in allKeys) {
        if (key.startsWith(keyPrefix)) {
          // 이미 닫힌 상태가 아니면 닫힌 상태로 설정
          if (!(prefs.getBool(key) ?? false)) {
            prefs.setBool(key, true);
            if (kDebugMode) {
              debugPrint('🚫 [BannerManager] 이전 배너 강제 닫음: $key');
            }
          }
        }
      }
    }
  }

  /// 테스트 계정 배너 처리
  Future<List<BannerType>> _handleTestAccountBanners(Map<String, dynamic> bannerMetadata) async {
    final bannerType = bannerMetadata['bannerType'] as String?;
    if (bannerType == null) return [];
    
    if (kDebugMode) {
      debugPrint('🧪 [BannerManager] 테스트 배너 처리: $bannerType');
    }
    
    switch (bannerType) {
      case 'free':
        return [BannerType.free];
      case 'trialStarted':
        return [BannerType.trialStarted];
      case 'trialCompleted':
        return [BannerType.trialCompleted];
      case 'premiumStarted':
        return [BannerType.premiumStarted];
      case 'premiumCancelled':
        return [BannerType.premiumCancelled];
      case 'premiumExpired':
        return [BannerType.premiumExpired];
      case 'usageLimitFree':
        return [BannerType.usageLimitFree];
      case 'usageLimitPremium':
        return [BannerType.usageLimitPremium];
      case 'premiumGrace':
        return [BannerType.premiumGrace];
      default:
        if (kDebugMode) {
          debugPrint('⚠️ [BannerManager] 알 수 없는 테스트 배너 타입: $bannerType');
        }
        return [];
    }
  }



  /// 모든 플랜 상태 배너 초기화
  void _resetAllBannerStates() {
    setBannerState(BannerType.free, false);
    setBannerState(BannerType.trialStarted, false);
    setBannerState(BannerType.trialCancelled, false);
    setBannerState(BannerType.trialCompleted, false);
    setBannerState(BannerType.premiumStarted, false);
    setBannerState(BannerType.premiumExpired, false);
    setBannerState(BannerType.premiumCancelled, false);
    setBannerState(BannerType.premiumGrace, false);
  }



  /// 🚀 배너 표시 여부 확인 (동기 처리 - 성능 최적화) - 사용자별
  bool _shouldShowBannerSync(BannerType type, SharedPreferences prefs) {
    final shouldShow = _bannerStates[type] ?? false;
    
    if (kDebugMode) {
      debugPrint('🔍 [BannerManager] _shouldShowBannerSync: ${type.name}');
      debugPrint('   배너 상태: $shouldShow');
    }
    
    if (!shouldShow) {
      if (kDebugMode) {
        debugPrint('   결과: false (배너 상태가 false)');
      }
      return false;
    }

    // 사용량 한도 배너는 단순 처리 (사용자별)
    if (type == BannerType.usageLimitFree || type == BannerType.usageLimitPremium) {
      final key = _getUserBannerKey(type);
      final hasUserDismissed = prefs.getBool(key) ?? false;
      final result = !hasUserDismissed;
      
      if (kDebugMode) {
        debugPrint('   사용량 배너 - 키: $key, 닫힘: $hasUserDismissed, 결과: $result');
      }
      
      return result;
    }
    
    // 프리미엄 만료, 체험 완료 배너는 플랜별 처리 (사용자별)
    final planId = _bannerPlanIds[type];
    
    if (kDebugMode) {
      debugPrint('   플랜별 배너 - planId: $planId');
    }
    
    if (planId == null) {
      if (kDebugMode) {
        debugPrint('   결과: false (planId가 null)');
      }
      return false;
    }
    
    final dismissKey = _getUserBannerKey(type, planId: planId);
    final hasUserDismissed = prefs.getBool(dismissKey) ?? false;
    final result = !hasUserDismissed;
    
    if (kDebugMode) {
      debugPrint('   플랜별 배너 - 키: $dismissKey, 닫힘: $hasUserDismissed, 결과: $result');
    }
    
    return result;
  }

  /// 🎯 안전한 Map 변환 헬퍼
  Map<String, dynamic>? _safeMapConversion(dynamic data) {
    if (data == null) return null;
    
    try {
      if (data is Map<String, dynamic>) {
        return data;
      } else if (data is Map) {
        // _Map<Object?, Object?> 등을 Map<String, dynamic>으로 변환
        return Map<String, dynamic>.from(data.map((key, value) => MapEntry(key.toString(), value)));
      } else {
      if (kDebugMode) {
          debugPrint('⚠️ [BannerManager] 예상치 못한 데이터 타입: ${data.runtimeType}');
      }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [BannerManager] Map 변환 실패: $e');
      }
      return null;
    }
  }





} 