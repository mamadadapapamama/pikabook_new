import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../notification/notification_service.dart';

/// 무료체험 관리 서비스
class TrialManager {
  static final TrialManager _instance = TrialManager._internal();
  factory TrialManager() => _instance;
  TrialManager._internal();

  static const String _trialStartDateKey = 'trial_start_date';
  static const String _welcomeNotificationShownKey = 'welcome_notification_shown';
  static const int _trialDurationDays = 7;

  final NotificationService _notificationService = NotificationService();

  /// 무료체험 시작일
  DateTime? _trialStartDate;
  DateTime? get trialStartDate => _trialStartDate;

  /// 무료체험 종료일
  DateTime? get trialEndDate {
    if (_trialStartDate == null) return null;
    return _trialStartDate!.add(const Duration(days: _trialDurationDays));
  }

  /// 무료체험 남은 일수
  int get remainingDays {
    if (trialEndDate == null) return 0;
    final now = DateTime.now();
    final difference = trialEndDate!.difference(now).inDays;
    return difference > 0 ? difference : 0;
  }

  /// 무료체험 남은 시간 (시간 단위)
  int get remainingHours {
    if (trialEndDate == null) return 0;
    final now = DateTime.now();
    final difference = trialEndDate!.difference(now).inHours;
    return difference > 0 ? difference : 0;
  }

  /// 무료체험 활성 상태
  bool get isTrialActive {
    if (trialEndDate == null) return false;
    return DateTime.now().isBefore(trialEndDate!);
  }

  /// 무료체험 만료 여부
  bool get isTrialExpired {
    if (trialEndDate == null) return false;
    return DateTime.now().isAfter(trialEndDate!);
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
      
      // 로그인한 사용자이고, 체험 기간이 시작되지 않았다면 체험 시작
      if (isUserLoggedIn && _trialStartDate == null) {
        await startTrial();
      }
      
      if (kDebugMode) {
        debugPrint('✅ [Trial] 초기화 완료');
        debugPrint('   로그인 상태: $isUserLoggedIn');
        debugPrint('   체험 시작일: $_trialStartDate');
        debugPrint('   체험 종료일: $trialEndDate');
        debugPrint('   남은 일수: $remainingDays일');
        debugPrint('   체험 활성: $isTrialActive');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Trial] 초기화 실패: $e');
      }
    }
  }

  /// 무료체험 시작
  Future<void> startTrial() async {
    try {
      if (!isUserLoggedIn) {
        if (kDebugMode) {
          debugPrint('⚠️ [Trial] 로그인하지 않은 사용자는 체험을 시작할 수 없습니다');
        }
        return;
      }

      final now = DateTime.now();
      _trialStartDate = now;
      
      // 🧪 DEBUG MODE: 테스트를 위해 체험 기간을 5분으로 설정
      if (kDebugMode) {
        // 테스트용: 5분 후 체험 종료 (배너 테스트용)
        _trialStartDate = now.subtract(const Duration(days: 6, hours: 23, minutes: 55));
        debugPrint('🧪 [TEST] 무료체험 테스트 모드 - 5분 후 종료 예정');
        debugPrint('   조정된 시작일: $_trialStartDate');
        debugPrint('   종료 예정일: $trialEndDate');
        debugPrint('   남은 시간: ${remainingHours}시간 ${(remainingHours * 60) % 60}분');
      }
      
      // SharedPreferences에 저장
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_trialStartDateKey, _trialStartDate!.toIso8601String());
      
      // 체험 관련 알림 설정
      await setupTrialNotifications();
      
      // 환영 메시지 표시 (한 번만)
      await _showWelcomeNotification();
      
      if (kDebugMode) {
        debugPrint('🎉 [Trial] 무료체험 시작');
        debugPrint('   시작일: $_trialStartDate');
        debugPrint('   종료일: $trialEndDate');
        debugPrint('   남은 일수: $remainingDays일');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Trial] 무료체험 시작 실패: $e');
      }
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
      
      // 환영 메시지 표시
      await _notificationService.showImmediateNotification(
        id: 999,
        title: 'Pikabook에 오신 것을 환영합니다! 🎉',
        body: '7일 무료체험이 시작되었습니다. 중국어 학습을 시작해보세요!',
        payload: 'welcome_message',
      );
      
      // 표시됨 플래그 저장
      await prefs.setBool(_welcomeNotificationShownKey, true);
      
      if (kDebugMode) {
        debugPrint('👋 [Trial] 환영 메시지 표시 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Trial] 환영 메시지 표시 실패: $e');
      }
    }
  }

  /// 체험 종료 처리
  Future<void> handleTrialExpiration() async {
    try {
      // 체험 관련 알림 취소
      await _notificationService.cancelTrialNotifications();
      
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

  /// 체험 상태 문자열
  String get trialStatusText {
    if (!isUserLoggedIn) return '샘플 모드';
    if (isPremiumUser) return '프리미엄 사용자';
    if (!isTrialActive) return '체험 종료';
    
    if (remainingDays > 0) {
      return '무료체험 ${remainingDays}일 남음';
    } else if (remainingHours > 0) {
      return '무료체험 ${remainingHours}시간 남음';
    } else {
      return '체험 종료';
    }
  }

  /// 체험 진행률 (0.0 ~ 1.0)
  double get trialProgress {
    if (_trialStartDate == null || trialEndDate == null) return 0.0;
    
    final now = DateTime.now();
    final totalDuration = trialEndDate!.difference(_trialStartDate!).inMilliseconds;
    final elapsedDuration = now.difference(_trialStartDate!).inMilliseconds;
    
    if (elapsedDuration <= 0) return 0.0;
    if (elapsedDuration >= totalDuration) return 1.0;
    
    return elapsedDuration / totalDuration;
  }

  /// 디버그 정보 출력
  void printDebugInfo() {
    if (!kDebugMode) return;
    
    debugPrint('=== Trial Manager Debug Info ===');
    debugPrint('로그인 상태: $isUserLoggedIn');
    debugPrint('프리미엄 사용자: $isPremiumUser');
    debugPrint('샘플 모드: $isSampleMode');
    debugPrint('체험 시작일: $_trialStartDate');
    debugPrint('체험 종료일: $trialEndDate');
    debugPrint('체험 활성: $isTrialActive');
    debugPrint('체험 만료: $isTrialExpired');
    debugPrint('남은 일수: $remainingDays일');
    debugPrint('남은 시간: $remainingHours시간');
    debugPrint('체험 진행률: ${(trialProgress * 100).toStringAsFixed(1)}%');
    debugPrint('상태 텍스트: $trialStatusText');
    debugPrint('================================');
  }
} 