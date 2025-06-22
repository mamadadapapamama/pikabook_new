import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

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
    if (_isInitialized) {
      if (kDebugMode) {
        debugPrint('ℹ️ [Notification] 이미 초기화됨');
      }
      return;
    }

    try {
      if (kDebugMode) {
        debugPrint('🚀 [Notification] 서비스 초기화 시작');
      }

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

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
        
        // 권한 상태 확인
        final hasPermission = await requestPermissions();
        debugPrint('🔐 [Notification] 권한 상태: $hasPermission');
        
        // 예약된 알림 확인
        await getPendingNotifications();
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

  /// 권한 요청
  Future<bool> requestPermissions() async {
    try {
      if (kDebugMode) {
        debugPrint('🔐 [Notification] 권한 요청 시작');
      }

      if (Platform.isIOS) {
        final bool? result = await _flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            );
        
        if (kDebugMode) {
          debugPrint('📱 [Notification] iOS 권한 결과: $result');
        }
        return result ?? false;
      }

      if (await Permission.notification.isDenied) {
        final status = await Permission.notification.request();
        if (kDebugMode) {
          debugPrint('🤖 [Notification] Android 권한 요청 결과: $status');
        }
        return status == PermissionStatus.granted;
      }
      
      if (kDebugMode) {
        debugPrint('✅ [Notification] 권한이 이미 허용됨');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Notification] 권한 요청 실패: $e');
      }
      return false;
    }
  }

  /// 무료체험 종료 알림 스케줄링 (인앱구매용)
  Future<void> scheduleTrialEndNotifications(DateTime trialStartDate) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final trialEndDate = trialStartDate.add(const Duration(days: 7));
      
      // 기존 체험 관련 알림 취소
      await cancelTrialNotifications();

      // 🧪 DEBUG MODE: 테스트를 위해 알림을 몇 분 후로 설정
      if (kDebugMode) {
        final now = DateTime.now();
        
        // 테스트용: 2분 후에 "1일 전" 알림
        final testOneDayBefore = now.add(const Duration(minutes: 2));
        await _scheduleNotification(
          id: 1001,
          title: '🧪 [테스트] 프리미엄 무료체험 내일 종료',
          body: '무료 체험이 곧 종료되고, 유료 구독으로 전환될 예정입니다.',
          scheduledDate: testOneDayBefore,
          payload: 'trial_ending_tomorrow',
        );

        // 테스트용: 4분 후에 "당일" 알림
        final testEndDay = now.add(const Duration(minutes: 4));
        await _scheduleNotification(
          id: 1002,
          title: '🧪 [테스트] 프리미엄 무료체험 오늘 종료',
          body: '오늘 프리미엄 무료체험이 종료되고, 유료구독으로 전환됩니다.',
          scheduledDate: testEndDay,
          payload: 'trial_ending_today',
        );

        debugPrint('🧪 [TEST] 무료체험 알림 테스트 모드 활성화');
        debugPrint('   2분 후: 1일 전 알림 (${testOneDayBefore.toString()})');
        debugPrint('   4분 후: 당일 알림 (${testEndDay.toString()})');
        return;
      }

      // 🚀 PRODUCTION MODE: 실제 오전 10시 스케줄링
      // 1일 전 오전 10시 알림 (6일 후 오전 10시)
      final oneDayBeforeAt10AM = DateTime(
        trialEndDate.year,
        trialEndDate.month,
        trialEndDate.day - 1,
        10, // 오전 10시
        0,
      );

      await _scheduleNotification(
        id: 1001,
        title: '프리미엄 무료체험 내일 종료',
        body: '무료 체험이 곧 종료되고, 유료 구독으로 전환될 예정입니다.',
        scheduledDate: oneDayBeforeAt10AM,
        payload: 'trial_ending_tomorrow',
      );

      // 당일 오전 10시 알림 (7일 후 오전 10시)
      final endDayAt10AM = DateTime(
        trialEndDate.year,
        trialEndDate.month,
        trialEndDate.day,
        10, // 오전 10시
        0,
      );

      await _scheduleNotification(
        id: 1002,
        title: '프리미엄 무료체험 오늘 종료',
        body: '오늘 프리미엄 무료체험이 종료되고, 유료구독으로 전환됩니다.',
        scheduledDate: endDayAt10AM,
        payload: 'trial_ending_today',
      );

      if (kDebugMode) {
        debugPrint('✅ [Notification] 무료체험 알림 스케줄링 완료 (오전 10시)');
        debugPrint('   체험 시작: ${trialStartDate.toString()}');
        debugPrint('   체험 종료: ${trialEndDate.toString()}');
        debugPrint('   1일 전 알림: ${oneDayBeforeAt10AM.toString()}');
        debugPrint('   당일 알림: ${endDayAt10AM.toString()}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Notification] 무료체험 알림 스케줄링 실패: $e');
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
      if (kDebugMode) {
        debugPrint('📅 [Notification] 스케줄링 시작:');
        debugPrint('   ID: $id');
        debugPrint('   제목: $title');
        debugPrint('   내용: $body');
        debugPrint('   예약 시간: $scheduledDate');
        debugPrint('   현재 시간: ${DateTime.now()}');
        debugPrint('   페이로드: $payload');
      }

      // 과거 시간이면 스케줄링하지 않음
      if (scheduledDate.isBefore(DateTime.now())) {
        if (kDebugMode) {
          debugPrint('⚠️ [Notification] 과거 시간으로 스케줄링 시도: $scheduledDate');
        }
        return;
      }

      // 서비스가 초기화되지 않았다면 초기화
      if (!_isInitialized) {
        if (kDebugMode) {
          debugPrint('🔄 [Notification] 서비스 초기화 중...');
        }
        await initialize();
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

      // 시간대 변환
      final tzDateTime = tz.TZDateTime.from(scheduledDate, tz.local);
      
      if (kDebugMode) {
        debugPrint('🌍 [Notification] 시간대 변환:');
        debugPrint('   원본: $scheduledDate');
        debugPrint('   TZ: $tzDateTime');
        debugPrint('   현재 TZ: ${tz.TZDateTime.now(tz.local)}');
      }

      await _flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tzDateTime,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );

      if (kDebugMode) {
        debugPrint('✅ [Notification] 스케줄링 완료: $title');
        debugPrint('   예약 시간: $tzDateTime');
        
        // 스케줄링 후 예약된 알림 목록 확인
        final pending = await _flutterLocalNotificationsPlugin.pendingNotificationRequests();
        debugPrint('📋 [Notification] 현재 예약된 알림 수: ${pending.length}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [Notification] 스케줄링 실패: $e');
        debugPrint('   스택 트레이스: ${StackTrace.current}');
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
      final pendingNotifications = await _flutterLocalNotificationsPlugin.pendingNotificationRequests();
      
      if (kDebugMode) {
        debugPrint('📋 [Notification] 예약된 알림 목록 (${pendingNotifications.length}개):');
        for (final notification in pendingNotifications) {
          debugPrint('   ID: ${notification.id}');
          debugPrint('   제목: ${notification.title}');
          debugPrint('   내용: ${notification.body}');
          debugPrint('   페이로드: ${notification.payload}');
          debugPrint('   ---');
        }
      }
      
      return pendingNotifications;
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