import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

/// 로컬 노티피케이션 서비스
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// 노티피케이션 서비스 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Android 초기화 설정
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS 초기화 설정
      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await _flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      _isInitialized = true;
      
      if (kDebugMode) {
        debugPrint('✅ [Notification] 서비스 초기화 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Notification] 초기화 실패: $e');
      }
    }
  }

  /// 노티피케이션 클릭 시 처리
  void _onNotificationTapped(NotificationResponse notificationResponse) {
    if (kDebugMode) {
      debugPrint('🔔 [Notification] 클릭됨: ${notificationResponse.payload}');
    }
    // TODO: 노티피케이션 타입별 처리 로직 추가
  }

  /// 노티피케이션 권한 요청
  Future<bool> requestPermissions() async {
    try {
      // iOS 권한 요청
      final bool? result = await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );

      // Android 권한 요청 (Android 13+)
      if (await Permission.notification.isDenied) {
        final status = await Permission.notification.request();
        return status.isGranted;
      }

      return result ?? true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Notification] 권한 요청 실패: $e');
      }
      return false;
    }
  }

  /// 무료체험 종료 알림 스케줄링
  Future<void> scheduleTrialEndNotifications(DateTime trialStartDate) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final trialEndDate = trialStartDate.add(const Duration(days: 7));
      
      // 기존 체험 관련 알림 취소
      await cancelTrialNotifications();

      // 1일 전 알림 (6일 후)
      await _scheduleNotification(
        id: 1001,
        title: '프리미엄 트라이얼 종료 안내',
        body: '내일 프리미엄 트라이얼이 종료됩니다. 계속 학습하려면 구독해주세요!',
        scheduledDate: trialEndDate.subtract(const Duration(days: 1)),
        payload: 'trial_ending_tomorrow',
      );

      // 당일 알림 (7일 후)
      await _scheduleNotification(
        id: 1002,
        title: '프리미엄 트라이얼 종료',
        body: '오늘 프리미엄 트라이얼이 종료됩니다. 지금 구독하고 계속 학습하세요!',
        scheduledDate: trialEndDate,
        payload: 'trial_ending_today',
      );

      // 종료 후 1일 알림 (8일 후)
      await _scheduleNotification(
        id: 1003,
        title: '프리미엄 구독 안내',
        body: '프리미엄 구독하고 계속 학습하세요. 더 많은 기능을 이용해보세요!',
        scheduledDate: trialEndDate.add(const Duration(days: 1)),
        payload: 'trial_expired',
      );

      if (kDebugMode) {
        debugPrint('✅ [Notification] 무료체험 알림 스케줄링 완료');
        debugPrint('   체험 시작: ${trialStartDate.toString()}');
        debugPrint('   체험 종료: ${trialEndDate.toString()}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Notification] 무료체험 알림 스케줄링 실패: $e');
      }
    }
  }

  /// 학습 리마인더 알림 설정
  Future<void> scheduleStudyReminders() async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      // 기존 학습 리마인더 취소
      await cancelStudyReminders();

      // 3일 후 미사용 알림
      await _scheduleNotification(
        id: 2001,
        title: '학습을 계속해보세요!',
        body: '3일째 학습하지 않으셨네요. 잠깐만 시간을 내어 중국어 실력을 늘려보세요!',
        scheduledDate: DateTime.now().add(const Duration(days: 3)),
        payload: 'study_reminder_3days',
      );

      // 주간 복습 알림 (매주 일요일 오후 7시)
      final now = DateTime.now();
      final nextSunday = now.add(Duration(days: 7 - now.weekday));
      final sundayEvening = DateTime(
        nextSunday.year,
        nextSunday.month,
        nextSunday.day,
        19, // 오후 7시
      );

      await _scheduleNotification(
        id: 2002,
        title: '주간 복습 시간',
        body: '이번 주 플래시카드를 복습해보세요. 꾸준한 복습이 실력 향상의 지름길입니다!',
        scheduledDate: sundayEvening,
        payload: 'weekly_review',
      );

      if (kDebugMode) {
        debugPrint('✅ [Notification] 학습 리마인더 알림 설정 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Notification] 학습 리마인더 설정 실패: $e');
      }
    }
  }

  /// 개별 노티피케이션 스케줄링
  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    try {
      // 과거 시간이면 스케줄링하지 않음
      if (scheduledDate.isBefore(DateTime.now())) {
        if (kDebugMode) {
          debugPrint('⚠️ [Notification] 과거 시간으로 스케줄링 시도: $scheduledDate');
        }
        return;
      }

      const AndroidNotificationDetails androidNotificationDetails =
          AndroidNotificationDetails(
        'pikabook_channel',
        'Pikabook 알림',
        channelDescription: 'Pikabook 앱의 학습 및 체험 관련 알림',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
      );

      const DarwinNotificationDetails iosNotificationDetails =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: iosNotificationDetails,
      );

      await _flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledDate, tz.local),
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );

      if (kDebugMode) {
        debugPrint('📅 [Notification] 스케줄링 완료: $title ($scheduledDate)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Notification] 스케줄링 실패: $e');
      }
    }
  }

  /// 무료체험 관련 알림 취소
  Future<void> cancelTrialNotifications() async {
    try {
      await _flutterLocalNotificationsPlugin.cancel(1001); // 1일 전
      await _flutterLocalNotificationsPlugin.cancel(1002); // 당일
      await _flutterLocalNotificationsPlugin.cancel(1003); // 1일 후
      
      if (kDebugMode) {
        debugPrint('🗑️ [Notification] 무료체험 알림 취소 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Notification] 무료체험 알림 취소 실패: $e');
      }
    }
  }

  /// 학습 리마인더 알림 취소
  Future<void> cancelStudyReminders() async {
    try {
      await _flutterLocalNotificationsPlugin.cancel(2001); // 3일 미사용
      await _flutterLocalNotificationsPlugin.cancel(2002); // 주간 복습
      
      if (kDebugMode) {
        debugPrint('🗑️ [Notification] 학습 리마인더 취소 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Notification] 학습 리마인더 취소 실패: $e');
      }
    }
  }

  /// 모든 알림 취소
  Future<void> cancelAllNotifications() async {
    try {
      await _flutterLocalNotificationsPlugin.cancelAll();
      
      if (kDebugMode) {
        debugPrint('🗑️ [Notification] 모든 알림 취소 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Notification] 모든 알림 취소 실패: $e');
      }
    }
  }

  /// 예약된 알림 목록 조회
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    try {
      return await _flutterLocalNotificationsPlugin.pendingNotificationRequests();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Notification] 예약된 알림 조회 실패: $e');
      }
      return [];
    }
  }

  /// 즉시 알림 표시 (환영 메시지 등)
  Future<void> showImmediateNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      const AndroidNotificationDetails androidNotificationDetails =
          AndroidNotificationDetails(
        'pikabook_channel',
        'Pikabook 알림',
        channelDescription: 'Pikabook 앱의 학습 및 체험 관련 알림',
        importance: Importance.high,
        priority: Priority.high,
      );

      const DarwinNotificationDetails iosNotificationDetails =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: iosNotificationDetails,
      );

      await _flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        notificationDetails,
        payload: payload,
      );

      if (kDebugMode) {
        debugPrint('📢 [Notification] 즉시 알림 표시: $title');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Notification] 즉시 알림 표시 실패: $e');
      }
    }
  }
} 