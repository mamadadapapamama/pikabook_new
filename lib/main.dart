import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'services/unified_cache_service.dart';
import 'views/screens/home_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/initialization_manager.dart';
import 'app.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/chinese_segmenter_service.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

// 앱의 시작점
// 언어 설정을 초기화합니다.
// 현재는 중국어만 지원하지만, 향후 다양한 언어를 지원할 예정입니다.

// Firebase 앱 인스턴스 전역 변수
FirebaseApp? firebaseApp;

// 메인 함수 - 진입점 최소화
Future<void> main() async {
  // 1. Flutter 초기화 - 가능한 빠르게
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  
  // 시스템 UI 설정
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  
  // 스플래시 화면 최대 지속 시간 설정 (5초 후 강제 제거)
  Timer(const Duration(seconds: 5), () {
    FlutterNativeSplash.remove();
    debugPrint('🎉 main: 스플래시 화면 제거됨 (타임아웃)');
  });
  
  // 에러 로깅 설정
  FlutterError.onError = (details) {
    debugPrint('Flutter 에러: ${details.exception}');
  };

  try {
    // 2. Firebase 초기화 (중복 초기화 방지)
    // Firebase 초기화 이미 시도되었을 경우를 대비한 처리
    if (Firebase.apps.isNotEmpty) {
      // 이미 초기화됨
      firebaseApp = Firebase.app();
      debugPrint('Firebase는 이미 초기화되어 있습니다. 기존 앱 사용.');
    } else {
      // 초기화 시도
      debugPrint('🔥 Firebase 초기화를 시도합니다.');
      firebaseApp = await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('🔥 Firebase 초기화 성공 - 앱 이름: ${firebaseApp!.name}');
    }
    
    // 3. 앱 실행 (바로 시작) - 스플래시 화면 제거
    runApp(const App());
    FlutterNativeSplash.remove();
    debugPrint('🎉 main: 스플래시 화면 제거됨 (정상 초기화)');
    
  } catch (e) {
    debugPrint('🚨 Firebase 초기화 오류: $e');
    
    // 오류가 중복 앱 오류인 경우 기존 앱 사용
    if (e.toString().contains('duplicate-app')) {
      firebaseApp = Firebase.app();
      debugPrint('🔥 중복 앱 오류 감지됨. 기존 Firebase 앱을 사용합니다.');
    }
    
    // 오류가 있더라도 앱을 시작하고 스플래시 제거 (오류 처리는 App 내부에서)
    runApp(const App());
    FlutterNativeSplash.remove();
    debugPrint('🎉 main: 스플래시 화면 제거됨 (오류 발생)');
  }
}

// 앱 설정 로드 함수 개선
Future<void> loadAppSettings() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final cacheService = UnifiedCacheService();

    // 기본값은 false (비활성화)로 설정
    ChineseSegmenterService.isSegmentationEnabled =
        prefs.getBool('segmentation_enabled') ?? false;

    // 언어 설정 초기화 - 아직 설정되지 않았다면 기본값 저장
    final sourceLanguage = await cacheService.getSourceLanguage();
    final targetLanguage = await cacheService.getTargetLanguage();
    
    debugPrint('언어 설정 로드 완료 - 소스 언어: $sourceLanguage, 타겟 언어: $targetLanguage');

    debugPrint('앱 설정 로드 완료');
  } catch (e) {
    debugPrint('설정 로드 중 오류 발생: $e');
    // 오류 발생 시 기본값으로 비활성화
    ChineseSegmenterService.isSegmentationEnabled = false;
  }
}

// 언어 설정 저장 함수 추가 (앱 종료 또는 백그라운드로 전환 시 호출)
Future<void> saveLanguageSettings() async {
  try {
    final cacheService = UnifiedCacheService();
    
    // 현재 언어 설정 저장
    final sourceLanguage = await cacheService.getSourceLanguage();
    final targetLanguage = await cacheService.getTargetLanguage();
    
    debugPrint('언어 설정 저장 - 소스 언어: $sourceLanguage, 타겟 언어: $targetLanguage');
  } catch (e) {
    debugPrint('언어 설정 저장 중 오류 발생: $e');
  }
}

// 오류 앱 컴포넌트 - 앱 시작 중 오류 발생 시 표시
class ErrorApp extends StatelessWidget {
  final String errorMessage;

  const ErrorApp({Key? key, required this.errorMessage}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pikabook 오류',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF8F56),
          primary: const Color(0xFFFF8F56),
        ),
        useMaterial3: true,
      ),
      // 다크 모드 비활성화
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF8F56),
          primary: const Color(0xFFFF8F56),
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.light,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 로고
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: Image.asset('assets/images/pikabook_bird.png'),
                  ),
                  const SizedBox(height: 24),
                  // 오류 메시지
                  const Text(
                    '오류가 발생했습니다',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    errorMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 재시도 버튼
                  ElevatedButton(
                    onPressed: () {
                      // 앱 재시작
                      main();
                    },
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PikaBook',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      // 다크 모드 비활성화
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      themeMode: ThemeMode.light,
      home: const HomeScreen(),
    );
  }
}
