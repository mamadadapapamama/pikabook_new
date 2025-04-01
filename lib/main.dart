import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/note_service.dart';
import 'services/image_service.dart';
import 'services/unified_cache_service.dart';
import 'views/screens/home_screen.dart';
import 'views/screens/onboarding_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/initialization_service.dart';
import 'app.dart';
import 'services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/chinese_segmenter_service.dart';
import 'utils/language_constants.dart';
import 'dart:async';

// MARK: 다국어 지원을 위한 확장 포인트
// 앱의 시작점에서 언어 설정을 초기화합니다.
// 현재는 중국어만 지원하지만, 향후 다양한 언어를 지원할 예정입니다.

// 메인 함수 - 진입점 최소화
Future<void> main() async {
  // 플러터 엔진 초기화만 수행하고 바로 앱 실행
  WidgetsFlutterBinding.ensureInitialized();
  
  // 시스템 UI 설정 - 상태바 아이콘을 검은색으로 설정
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  
  // 에러 로깅 설정
  FlutterError.onError = (details) {
    debugPrint('Flutter 에러: ${details.exception}');
  };

  try {
    // Firebase를 먼저 초기화 - 이 부분이 중요
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase 초기화 성공');
  
    // 초기화 서비스 인스턴스 생성 (가벼운 작업)
    final initializationService = InitializationService();
    
    // 앱 실행 (UI 먼저 표시)
    runApp(App(initializationService: initializationService));
    
    // 백그라운드에서 비동기적으로 나머지 초기화 진행
    _initializeInBackground(initializationService);
  } catch (e) {
    debugPrint('Firebase 초기화 오류: $e');
    // 오류 발생 시 오류 화면 표시
    runApp(ErrorApp(errorMessage: 'Firebase 초기화 중 오류가 발생했습니다: $e'));
  }
}

// 백그라운드에서 Firebase 및 필수 서비스 초기화
Future<void> _initializeInBackground(InitializationService initializationService) async {
  try {
    // Firebase는 이미 초기화되었으므로 인증 상태만 확인
    await initializationService.markFirebaseInitialized(true);
    
    // 필요한 다른 초기화 작업들은 여기서 수행
    // 앱 이미 실행된 후 비동기로 처리되므로 UI 블로킹 없음
  } catch (e) {
    debugPrint('백그라운드 초기화 오류: $e');
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
