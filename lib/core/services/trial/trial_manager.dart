import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../notification/notification_service.dart';
import '../common/plan_service.dart';
import 'dart:async';

/// 무료체험 관리 서비스
class TrialManager {
  static final TrialManager _instance = TrialManager._internal();
  factory TrialManager() => _instance;
  TrialManager._internal();

  static const String _trialStartDateKey = 'trial_start_date';
  static const String _welcomeNotificationShownKey = 'welcome_notification_shown';
  static const int _trialDurationDays = 7; // 실제: 7일

  final NotificationService _notificationService = NotificationService();
  final PlanService _planService = PlanService();

  // 환영 메시지 콜백
  void Function(String title, String message)? onWelcomeMessage;
  
  // 체험 종료 콜백
  void Function(String title, String message)? onTrialExpired;

  // 체험 상태 확인 타이머
  Timer? _statusCheckTimer;
  bool _hasTrialExpiredCallbackFired = false;

  /// 무료체험 시작일
  DateTime? _trialStartDate;
  DateTime? get trialStartDate => _trialStartDate;

  /// 무료체험 종료일
  DateTime? get trialEndDate {
    if (_trialStartDate == null) return null;
    return _trialStartDate!.add(const Duration(days: _trialDurationDays));
  }

  /// 무료체험 남은 일수 (Firestore 기반)
  Future<int> get remainingDays async {
    try {
      final subscriptionDetails = await _planService.getSubscriptionDetails();
      return subscriptionDetails['daysRemaining'] as int? ?? 0;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Trial] 남은 일수 확인 실패: $e');
      }
      return 0;
    }
  }

  /// 무료체험 남은 시간 (시간 단위, Firestore 기반)
  Future<int> get remainingHours async {
    try {
      final subscriptionDetails = await _planService.getSubscriptionDetails();
      final expiryDate = subscriptionDetails['expiryDate'] as DateTime?;
      if (expiryDate == null) return 0;
      final now = DateTime.now();
      final difference = expiryDate.difference(now).inHours;
      return difference > 0 ? difference : 0;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Trial] 남은 시간 확인 실패: $e');
      }
      return 0;
    }
  }

  /// 무료체험 활성 상태 (Firestore 기반)
  Future<bool> get isTrialActive async {
    try {
      final subscriptionDetails = await _planService.getSubscriptionDetails();
      return subscriptionDetails['isFreeTrial'] as bool? ?? false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Trial] 체험 활성 상태 확인 실패: $e');
      }
      return false;
    }
  }

  /// 무료체험 만료 여부 (Firestore 기반)
  Future<bool> get isTrialExpired async {
    try {
      final subscriptionDetails = await _planService.getSubscriptionDetails();
      return subscriptionDetails['isExpired'] as bool? ?? false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Trial] 체험 만료 여부 확인 실패: $e');
      }
      return false;
    }
  }

  /// 사용자가 로그인한 상태인지 확인
  bool get isUserLoggedIn => FirebaseAuth.instance.currentUser != null;

  /// 프리미엄 사용자인지 확인 (실제 구독 상태 확인 로직 필요)
  bool get isPremiumUser {
    // TODO: 실제 구독 상태 확인 로직 구현
    // 현재는 로그인 상태로만 판단
    return isUserLoggedIn;
  }

  /// 샘플 모드 사용자인지 확인
  bool get isSampleMode => !isUserLoggedIn;

  /// 초기화 - 앱 시작 시 호출
  Future<void> initialize() async {
    try {
      await _loadTrialData();
      
      // 자동으로 체험을 시작하지 않음 - 사용자가 명시적으로 선택해야 함
      
      // 체험 종료 여부 확인 및 콜백 호출
      await _checkTrialExpirationAndNotify();
      
      if (kDebugMode) {
        debugPrint('✅ [Trial] 초기화 완료');
        debugPrint('   로그인 상태: $isUserLoggedIn');
        debugPrint('   체험 시작일: $_trialStartDate');
        debugPrint('   체험 종료일: $trialEndDate');
        debugPrint('   남은 일수: ${await remainingDays}일');
        debugPrint('   체험 활성: ${await isTrialActive}');
        debugPrint('   상태 텍스트: ${await trialStatusText}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Trial] 초기화 실패: $e');
      }
    }
  }

  /// 사용자가 선택한 프리미엄 무료체험 시작
  Future<bool> startPremiumTrial() async {
    try {
      if (!isUserLoggedIn) {
        if (kDebugMode) {
          debugPrint('⚠️ [Trial] 로그인하지 않은 사용자는 체험을 시작할 수 없습니다');
        }
        return false;
      }

      final userId = FirebaseAuth.instance.currentUser!.uid;
      final now = DateTime.now();
      _trialStartDate = now;
      
      if (kDebugMode) {
        debugPrint('🎯 [PROD] 무료체험 시작 - 7일 후 종료 예정');
        debugPrint('   시작일: $_trialStartDate');
        debugPrint('   종료 예정일: $trialEndDate');
        debugPrint('   남은 일수: ${trialEndDate!.difference(now).inDays}일');
      }
      
      // SharedPreferences에 저장
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_trialStartDateKey, _trialStartDate!.toIso8601String());
      
      // PlanService를 통해 Firestore에 체험 시작 기록
      final success = await _planService.startFreeTrial(userId);
      if (!success) {
        if (kDebugMode) {
          debugPrint('⚠️ [Trial] Firestore 체험 기록 실패 - 이미 사용했거나 오류 발생');
        }
        return false; // 실패 시 false 반환
      }
      
      // 체험 관련 알림 설정
      await setupTrialNotifications();
      
      // 🧪 테스트용 즉시 알림 확인 제거됨
      
      // 환영 메시지 표시 (한 번만)
      await _showWelcomeNotification();
      
      if (kDebugMode) {
        debugPrint('🎉 [Trial] 무료체험 시작');
        debugPrint('   시작일: $_trialStartDate');
        debugPrint('   종료일: $trialEndDate');
        debugPrint('   남은 일수: $remainingDays일');
        debugPrint('   Firestore 기록: ${success ? '성공' : '실패'}');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Trial] 무료체험 시작 실패: $e');
      }
      return false;
    }
  }

  /// 체험 데이터 로드
  Future<void> _loadTrialData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trialStartDateString = prefs.getString(_trialStartDateKey);
      
      if (trialStartDateString != null) {
        _trialStartDate = DateTime.parse(trialStartDateString);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Trial] 체험 데이터 로드 실패: $e');
      }
    }
  }

  /// 무료체험 알림 설정
  Future<void> setupTrialNotifications() async {
    if (_trialStartDate == null) return;
    
    try {
      // 노티피케이션 권한 요청
      final hasPermission = await _notificationService.requestPermissions();
      if (!hasPermission) {
        if (kDebugMode) {
          debugPrint('⚠️ [Trial] 노티피케이션 권한이 없습니다');
        }
        return;
      }
      
      // 무료체험 종료 알림 스케줄링
      await _notificationService.scheduleTrialEndNotifications(_trialStartDate!);
      
      if (kDebugMode) {
        debugPrint('✅ [Trial] 무료체험 알림 설정 완료');
        
        // 예약된 알림 확인
        final pendingNotifications = await _notificationService.getPendingNotifications();
        debugPrint('📋 [Trial] 현재 예약된 알림 수: ${pendingNotifications.length}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Trial] 무료체험 알림 설정 실패: $e');
      }
    }
  }

  /// 환영 메시지 표시 (가입 즉시, 한 번만)
  Future<void> _showWelcomeNotification() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isShown = prefs.getBool(_welcomeNotificationShownKey) ?? false;
      
      if (isShown) return;
      
      // 콜백을 통해 환영 메시지 표시
      if (onWelcomeMessage != null) {
        onWelcomeMessage!(
          '🎉 프리미엄 무료체험이 시작되었어요!',
          '피카북을 마음껏 사용해보세요.',
        );
      }
      
      // 표시됨 플래그 저장
      await prefs.setBool(_welcomeNotificationShownKey, true);
      
      if (kDebugMode) {
        debugPrint('👋 [Trial] 환영 메시지 콜백 호출 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Trial] 환영 메시지 표시 실패: $e');
      }
    }
  }

  /// 체험 상태 체크 (화면 전환 시 호출 가능)
  Future<void> checkTrialStatus() async {
    await _checkTrialExpirationAndNotify();
  }

  /// 체험 종료 여부 확인 및 콜백 호출 (앱 실행 시마다 체크)
  Future<void> _checkTrialExpirationAndNotify() async {
    if (!isUserLoggedIn) return;
    
    try {
      final subscriptionDetails = await _planService.getSubscriptionDetails();
      final isExpired = subscriptionDetails['isExpired'] as bool? ?? false;
      final wasFreeTrial = subscriptionDetails['isFreeTrial'] as bool? ?? false;
      
      // 체험이 있었고 현재 만료된 경우
      if (isExpired && wasFreeTrial) {
        // 이미 콜백을 호출했는지 확인 (중복 방지)
        if (!_hasTrialExpiredCallbackFired) {
          _hasTrialExpiredCallbackFired = true;
          
          if (onTrialExpired != null) {
            onTrialExpired!(
              '💎 프리미엄 플랜이 시작되었어요!\n자세한 내용은 설정→플랜에서 확인하세요.',
              '',
            );
          }
          
          if (kDebugMode) {
            debugPrint('⏰ [Trial] 체험 종료 감지 - 콜백 호출');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Trial] 체험 종료 확인 실패: $e');
      }
    }
  }

  /// 체험 종료 처리
  Future<void> handleTrialExpiration() async {
    try {
      // 체험 관련 알림 취소
      await _notificationService.cancelTrialNotifications();
      
      // 체험 종료 콜백 호출
      if (onTrialExpired != null) {
        onTrialExpired!(
          '💎 프리미엄 플랜이 시작되었어요!\n자세한 내용은 설정→플랜에서 확인하세요.',
          '',
        );
      }
      
      if (kDebugMode) {
        debugPrint('⏰ [Trial] 무료체험 종료 처리 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Trial] 체험 종료 처리 실패: $e');
      }
    }
  }

  /// 구독 완료 처리
  Future<void> handleSubscriptionComplete() async {
    try {
      // 모든 체험 관련 알림 취소
      await _notificationService.cancelTrialNotifications();
      
      if (kDebugMode) {
        debugPrint('🎊 [Trial] 구독 완료 - 체험 알림 취소');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Trial] 구독 완료 처리 실패: $e');
      }
    }
  }

  /// 로그아웃 시 체험 데이터 정리
  Future<void> clearTrialData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_trialStartDateKey);
      await prefs.remove(_welcomeNotificationShownKey);
      
      _trialStartDate = null;
      
      // 모든 알림 취소
      await _notificationService.cancelAllNotifications();
      
      if (kDebugMode) {
        debugPrint('🧹 [Trial] 체험 데이터 정리 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Trial] 체험 데이터 정리 실패: $e');
      }
    }
  }

  /// 체험 상태 문자열 (Firestore 기반)
  Future<String> get trialStatusText async {
    if (!isUserLoggedIn) return '샘플 모드';
    
    try {
      final subscriptionDetails = await _planService.getSubscriptionDetails();
      final currentPlan = subscriptionDetails['currentPlan'] as String;
      final isFreeTrial = subscriptionDetails['isFreeTrial'] as bool? ?? false;
      final daysRemaining = subscriptionDetails['daysRemaining'] as int? ?? 0;
      
      if (currentPlan == 'premium' && !isFreeTrial) {
        return '프리미엄 사용자';
      }
      
      if (isFreeTrial && daysRemaining > 0) {
        return '무료체험 ${daysRemaining}일 남음';
      }
      
      if (currentPlan == 'free') {
        return '무료 플랜';
      }
      
      return '체험 종료';
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Trial] 상태 텍스트 생성 실패: $e');
      }
      return '상태 확인 실패';
    }
  }

  /// 디버그 정보 출력 (Firestore 기반)
  Future<void> printDebugInfo() async {
    if (!kDebugMode) return;
    
    debugPrint('=== Trial Manager Debug Info ===');
    debugPrint('로그인 상태: $isUserLoggedIn');
    debugPrint('프리미엄 사용자: $isPremiumUser');
    debugPrint('샘플 모드: $isSampleMode');
    debugPrint('체험 시작일: $_trialStartDate');
    debugPrint('체험 종료일: $trialEndDate');
    debugPrint('체험 활성: ${await isTrialActive}');
    debugPrint('체험 만료: ${await isTrialExpired}');
    debugPrint('남은 일수: ${await remainingDays}일');
    debugPrint('남은 시간: ${await remainingHours}시간');
    debugPrint('상태 텍스트: ${await trialStatusText}');
    debugPrint('================================');
  }
} 