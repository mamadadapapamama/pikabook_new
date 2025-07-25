import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'dart:async';
import 'firebase_options.dart';
import 'core/services/media/image_service.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/utils/logger.dart';

// import 'package:shared_preferences/shared_preferences.dart';
// import 'views/screens/home_screen_mvvm.dart';
// import 'views/screens/note_detail_screen.dart';

/// Logger 초기화 및 설정
void _initializeLogger() {
  if (kReleaseMode) {
    // 릴리즈 모드에서는 에러만 출력
    Logger.setMinLevel(LogLevel.error);
    Logger.setEnableLogInRelease(false);
  } else if (kDebugMode) {
    // 디버그 모드에서는 모든 로그 출력
    Logger.setMinLevel(LogLevel.debug);
    Logger.setEnableLogInRelease(false);
  }
  
  Logger.info('Logger 초기화 완료', tag: 'Logger');
}

/// 앱의 진입점
/// 
/// 앱 실행 준비 및 스플래시 화면 관리만 담당하고
/// 모든 로직은 App 클래스에 위임합니다.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Logger 초기화 및 설정
  _initializeLogger();
  
  // Firebase 초기화
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    // 🟡 Firebase 초기화 후 FCM 권한 요청
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    
    Logger.info('Firebase 및 FCM 초기화 완료', tag: 'Firebase');
  } catch (e) {
    Logger.error('Firebase 초기화 실패', tag: 'Firebase', error: e);
    // 초기화 실패해도 앱은 계속 실행 (일부 기능 제한)
  }
  
  // Timezone 초기화 (스케줄된 알림을 위해 필요)
  tz.initializeTimeZones();
  
  // 🌍 사용자의 실제 타임존 가져와서 설정
  await _setupUserTimezone();
  
  Logger.info('Timezone 초기화 완료: ${tz.local.name}', tag: 'Timezone');
  
  // 성능 최적화 설정
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    // iOS 텍스트 렌더링 성능 최적화
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
  }
  
  // Logger를 사용하므로 기존 debugPrint 오버라이드 제거
  // Logger가 중앙 집중식으로 로그를 관리함
  
  // 시작 시 캐시 정리
  await _cleanupOnStart();
  
  // Firestore 설정
  try {
    // 디버그 모드에서 타임스탬프 사용 설정
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    
    // Debug 모드에서 Firebase 로그 레벨 조정
    if (kDebugMode) {
      FirebaseAuth.instance.setSettings(
        appVerificationDisabledForTesting: false,
        forceRecaptchaFlow: false,
      );
      
          // 🚨 디버그 모드에서 Firebase Analytics 자동 이벤트 수집 비활성화
    // (중복 구매 이벤트 방지)
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(false);
    Logger.info('Firebase Analytics 자동 수집 비활성화 (중복 이벤트 방지)', tag: 'Firebase');
  }
  
  // Firebase Auth 자동 복원 방지 - Apple ID 다이얼로그 방지
  await _preventAutoSignIn();
  
} catch (e) {
  Logger.error('Firestore 설정 실패', tag: 'Firestore', error: e);
}

  // 이미지 캐시 초기화
  final imageService = ImageService();
  await imageService.cleanupTempFiles();
  
  // 일반적인 앱 실행
  runApp(const App());
}

/// Apple ID 자동 로그인 방지 (Apple ID 다이얼로그 방지)
Future<void> _preventAutoSignIn() async {
  try {
    if (kDebugMode) {
      debugPrint('🔒 Apple ID 자동 로그인 방지 처리 시작');
    }
    
    // Firebase Auth 현재 사용자 확인
    final currentUser = FirebaseAuth.instance.currentUser;
    
    if (currentUser == null) {
      Logger.info('로그인된 사용자 없음 - Apple ID 다이얼로그 방지 완료', tag: 'Auth');
      return;
    }
    
    
    // Apple 로그인 사용자인지 확인
    final isAppleUser = currentUser.providerData.any(
      (provider) => provider.providerId == 'apple.com'
    );
    
    if (isAppleUser) {
      Logger.info('Apple 로그인 사용자 감지 - 자동 갱신 방지 처리', tag: 'Auth');
      
      try {
        // 🎯 토큰 유효성을 갱신 없이 확인만 (forceRefresh: false)
        // 이때 시스템 오류 발생 시 조용히 처리
        await currentUser.getIdToken(false);
        Logger.info('Apple 토큰 유효함 - 정상 유지', tag: 'Auth');
      } catch (e) {
        // 🎯 시스템 오류(Code=-54) 등은 무시하고 계속 진행
        if (e.toString().contains('NSOSStatusErrorDomain Code=-54') ||
            e.toString().contains('process may not map database')) {
          Logger.warning('Apple 시스템 오류 감지 - 무시하고 계속 진행', tag: 'Auth', error: e);
          return; // 시스템 오류는 무시
        }
        
        // 실제 토큰 만료/무효인 경우에만 로그아웃
        Logger.warning('Apple 토큰 만료/무효 - 자동 로그아웃 처리', tag: 'Auth', error: e);
        await FirebaseAuth.instance.signOut();
        Logger.info('자동 로그아웃 완료 - Apple ID 다이얼로그 방지됨', tag: 'Auth');
      }
    } else {
      Logger.info('일반 사용자 - Apple ID 다이얼로그 우려 없음', tag: 'Auth');
    }
  } catch (e) {
    Logger.error('자동 로그인 방지 처리 중 오류', tag: 'Auth', error: e);
    // 오류 발생 시에도 안전하게 진행
  }
}

/// 앱 시작 시 캐시 및 임시 데이터 정리
Future<void> _cleanupOnStart() async {
  try {
    // 이미지 캐시 정리
    ImageCache imageCache = PaintingBinding.instance.imageCache;
    imageCache.clear();
    
    // 타이머 로그 출력 억제
    FlutterError.onError = (FlutterErrorDetails details) {
      if (!details.toString().contains('timer')) {
        FlutterError.presentError(details);
      }
    };
    
    // 이미지 서비스 임시 파일 정리
    await ImageService().cleanupTempFiles();
    
    Logger.info('앱 시작 시 캐시 정리 완료', tag: 'Cache');
  } catch (e) {
    Logger.error('앱 시작 시 캐시 정리 중 오류', tag: 'Cache', error: e);
  }
}

/// 사용자의 실제 타임존을 가져와서 설정합니다.
/// 실패 시 기본값으로 'Asia/Seoul'을 사용합니다.
Future<void> _setupUserTimezone() async {
  try {
    final userTimezone = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(userTimezone));
    Logger.info('사용자의 실제 타임존 설정: $userTimezone', tag: 'Timezone');
  } catch (e) {
    Logger.warning('사용자의 실제 타임존 설정 실패. 기본값으로 설정', tag: 'Timezone', error: e);
    tz.setLocalLocation(tz.getLocation('Asia/Seoul')); // 한국 시간대 기본값
  }
}
