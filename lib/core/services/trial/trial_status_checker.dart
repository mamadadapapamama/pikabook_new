import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import '../common/plan_service.dart';
import '../notification/notification_service.dart';

/// 체험 상태 체크 서비스 - 서버 시간 기반
class TrialStatusChecker {
  static final TrialStatusChecker _instance = TrialStatusChecker._internal();
  factory TrialStatusChecker() => _instance;
  TrialStatusChecker._internal();

  final PlanService _planService = PlanService();
  final NotificationService _notificationService = NotificationService();
  
  Timer? _dailyCheckTimer;
  static const String _lastCheckDateKey = 'trial_last_check_date';
  static const String _trialExpiredNotificationShownKey = 'trial_expired_notification_shown';
  
  // 콜백들
  void Function(String title, String message)? onTrialExpired;
  void Function()? onTrialStatusChanged;

  /// 서비스 초기화 - 앱 시작 시 호출
  Future<void> initialize() async {
    try {
      // 1. 즉시 서버 상태 체크
      await checkTrialStatusFromServer();
      
      // 2. 하루 한번 체크 타이머 시작
      _startDailyCheckTimer();
      
      if (kDebugMode) {
        debugPrint('✅ [TrialStatusChecker] 초기화 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [TrialStatusChecker] 초기화 실패: $e');
      }
    }
  }

  /// 서버에서 체험 상태 체크 (앱 진입 시, 화면 전환 시 호출)
  Future<TrialStatus> checkTrialStatusFromServer() async {
    if (!_isUserLoggedIn) {
      return TrialStatus.notLoggedIn;
    }

    try {
      // 서버에서 최신 구독 정보 가져오기 (강제 새로고침)
      final subscriptionDetails = await _planService.getSubscriptionDetails(forceRefresh: true);
      
      final currentPlan = subscriptionDetails['currentPlan'] as String;
      final isFreeTrial = subscriptionDetails['isFreeTrial'] as bool? ?? false;
      final expiryDate = subscriptionDetails['expiryDate'] as DateTime?;
      final daysRemaining = subscriptionDetails['daysRemaining'] as int? ?? 0;
      final hasUsedFreeTrial = subscriptionDetails['hasUsedFreeTrial'] as bool? ?? false;

      // 체험 상태 결정
      TrialStatus status;
      if (currentPlan == 'premium' && !isFreeTrial) {
        status = TrialStatus.premiumUser;
        
        // 🎯 체험 종료 후 프리미엄 전환된 경우 - 한 번만 알림 표시
        if (hasUsedFreeTrial) {
          await _checkAndShowTrialExpiredNotification();
        }
      } else if (isFreeTrial && expiryDate != null) {
        final now = DateTime.now();
        if (now.isAfter(expiryDate)) {
          status = TrialStatus.trialExpired;
          // 체험 종료 콜백 호출
          await _handleTrialExpiration();
        } else {
          // 🎯 실제: 7일 체험의 경우 일 단위로 확인
          final daysRemaining = expiryDate.difference(now).inDays;
          if (kDebugMode) {
            debugPrint('   남은 일수: ${daysRemaining}일');
          }
          
          // 1일 이하 남았으면 곧 종료
          if (daysRemaining <= 1) {
            status = TrialStatus.trialEndingSoon;
          } else {
            status = TrialStatus.trialActive;
          }
        }
      } else {
        status = TrialStatus.freeUser;
      }

      // 마지막 체크 시간 업데이트
      await _updateLastCheckDate();

      if (kDebugMode) {
        debugPrint('🔍 [TrialStatusChecker] 서버 상태 체크 완료');
        debugPrint('   현재 플랜: $currentPlan');
        debugPrint('   무료 체험: $isFreeTrial');
        debugPrint('   남은 일수: $daysRemaining');
        debugPrint('   상태: ${status.name}');
      }

      // 상태 변경 콜백 호출
      onTrialStatusChanged?.call();

      return status;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [TrialStatusChecker] 서버 상태 체크 실패: $e');
      }
      return TrialStatus.checkFailed;
    }
  }

  /// 하루 한번 자동 체크 타이머 시작 (오전 0시)
  void _startDailyCheckTimer() {
    _dailyCheckTimer?.cancel();
    
    // 다음 오전 0시까지의 시간 계산
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final timeUntilMidnight = tomorrow.difference(now);

    if (kDebugMode) {
      debugPrint('⏰ [TrialStatusChecker] 다음 자동 체크: ${tomorrow.toString()}');
      debugPrint('   남은 시간: ${timeUntilMidnight.inHours}시간 ${timeUntilMidnight.inMinutes % 60}분');
    }

    // 첫 번째 타이머: 다음 오전 0시에 실행
    Timer(timeUntilMidnight, () {
      _performDailyCheck();
      
      // 이후 24시간마다 반복
      _dailyCheckTimer = Timer.periodic(const Duration(days: 1), (timer) {
        _performDailyCheck();
      });
    });
  }

  /// 하루 한번 자동 체크 실행
  Future<void> _performDailyCheck() async {
    if (kDebugMode) {
      debugPrint('🕛 [TrialStatusChecker] 하루 한번 자동 체크 실행');
    }

    try {
      // 이미 오늘 체크했는지 확인
      if (await _isAlreadyCheckedToday()) {
        if (kDebugMode) {
          debugPrint('⏭️ [TrialStatusChecker] 오늘 이미 체크함 - 스킵');
        }
        return;
      }

      // 서버 상태 체크
      final status = await checkTrialStatusFromServer();
      
      if (kDebugMode) {
        debugPrint('✅ [TrialStatusChecker] 자동 체크 완료: ${status.name}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [TrialStatusChecker] 자동 체크 실패: $e');
      }
    }
  }

  /// 체험 종료 처리
  Future<void> _handleTrialExpiration() async {
    try {
      // 체험 관련 알림 취소
      await _notificationService.cancelTrialNotifications();
      
      // 🎯 체험 종료 시 프리미엄으로 전환
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final success = await _planService.convertTrialToPremium(user.uid);
        if (kDebugMode) {
          debugPrint('🔄 [TrialStatusChecker] 체험→프리미엄 전환: ${success ? '성공' : '실패'}');
        }
      }
      
      // 체험 종료 콜백 호출
      if (onTrialExpired != null) {
        onTrialExpired!(
          '💎 프리미엄 플랜이 시작되었어요!',
          '자세한 내용은 설정→플랜에서 확인하세요.',
        );
      }
      
      if (kDebugMode) {
        debugPrint('⏰ [TrialStatusChecker] 체험 종료 처리 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [TrialStatusChecker] 체험 종료 처리 실패: $e');
      }
    }
  }

  /// 체험 종료 알림을 한 번만 표시하기 위한 체크
  Future<void> _checkAndShowTrialExpiredNotification() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isAlreadyShown = prefs.getBool(_trialExpiredNotificationShownKey) ?? false;
      
      if (!isAlreadyShown) {
        // 체험 종료 콜백 호출
        if (onTrialExpired != null) {
          onTrialExpired!(
            '💎 프리미엄 플랜이 시작되었어요!',
            '자세한 내용은 설정→플랜에서 확인하세요.',
          );
        }
        
        // 표시됨 플래그 저장
        await prefs.setBool(_trialExpiredNotificationShownKey, true);
        
        if (kDebugMode) {
          debugPrint('🎯 [TrialStatusChecker] 체험 종료 알림 표시 (최초 1회)');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [TrialStatusChecker] 체험 종료 알림 체크 실패: $e');
      }
    }
  }

  /// 오늘 이미 체크했는지 확인
  Future<bool> _isAlreadyCheckedToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckDate = prefs.getString(_lastCheckDateKey);
      final today = DateTime.now().toIso8601String().substring(0, 10); // YYYY-MM-DD
      
      return lastCheckDate == today;
    } catch (e) {
      return false;
    }
  }

  /// 마지막 체크 날짜 업데이트
  Future<void> _updateLastCheckDate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().substring(0, 10); // YYYY-MM-DD
      await prefs.setString(_lastCheckDateKey, today);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [TrialStatusChecker] 마지막 체크 날짜 업데이트 실패: $e');
      }
    }
  }

  /// 사용자 로그인 상태 확인
  bool get _isUserLoggedIn => FirebaseAuth.instance.currentUser != null;

  /// 리소스 정리
  void dispose() {
    _dailyCheckTimer?.cancel();
    _dailyCheckTimer = null;
    onTrialExpired = null;
    onTrialStatusChanged = null;
  }
}

/// 체험 상태 열거형
enum TrialStatus {
  notLoggedIn,      // 로그인하지 않음
  freeUser,         // 무료 사용자
  trialActive,      // 체험 진행 중
  trialEndingSoon,  // 체험 곧 종료 (1일 이하)
  trialExpired,     // 체험 만료됨
  premiumUser,      // 프리미엄 사용자
  checkFailed,      // 상태 체크 실패
}

extension TrialStatusExtension on TrialStatus {
  String get displayName {
    switch (this) {
      case TrialStatus.notLoggedIn:
        return '샘플 모드';
      case TrialStatus.freeUser:
        return '무료 플랜';
      case TrialStatus.trialActive:
        return '무료체험 진행 중';
      case TrialStatus.trialEndingSoon:
        return '무료체험 곧 종료';
      case TrialStatus.trialExpired:
        return '체험 종료';
      case TrialStatus.premiumUser:
        return '프리미엄';
      case TrialStatus.checkFailed:
        return '상태 확인 실패';
    }
  }

  // 🔔 인앱 배너 제거됨 - Push Notification만 사용
  bool get shouldShowBanner {
    return false; // 항상 false - 배너 사용하지 않음
  }

  bool get isPremiumFeatureAvailable {
    return this == TrialStatus.trialActive || 
           this == TrialStatus.trialEndingSoon || 
           this == TrialStatus.premiumUser;
  }
} 