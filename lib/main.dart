import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/note_service.dart';
import 'services/image_service.dart';
import 'services/unified_cache_service.dart';
import 'services/user_preferences_service.dart';
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
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'dart:async';

// MARK: 다국어 지원을 위한 확장 포인트
// 앱의 시작점에서 언어 설정을 초기화합니다.
// 현재는 중국어만 지원하지만, 향후 다양한 언어를 지원할 예정입니다.

// 앱 초기화 상태를 추적하기 위한 전역 타이머
Stopwatch? _globalInitTimer;

void main() {
  // 앱 시작 시간 추적 시작
  _globalInitTimer = Stopwatch()..start();
  debugPrint('========================================');
  debugPrint('| 앱 시작: ${DateTime.now().toString()} |');
  debugPrint('========================================');

  // 모든 예외를 캡처하여 앱이 충돌하지 않도록 함
  runZonedGuarded(() async {
    try {
      // 1. 가능한 빨리 Flutter 엔진 초기화
      debugPrint('Flutter 엔진 초기화 시작...');
      WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
      debugPrint('Flutter 엔진 초기화 완료 (${_globalInitTimer?.elapsedMilliseconds}ms)');
      
      // 2. 네이티브 스플래시 화면 유지
      FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
      
      // 3. 초기화 서비스 인스턴스 생성 (가벼운 동기 작업)
      debugPrint('초기화 서비스 생성 중...');
      final initializationService = InitializationService();
      debugPrint('초기화 서비스 생성 완료 (${_globalInitTimer?.elapsedMilliseconds}ms)');
      
      // 4. 앱 실행 (UI 렌더링 시작)
      debugPrint('앱 UI 렌더링 시작...');
      runApp(App(initializationService: initializationService));
      debugPrint('앱 UI 렌더링 시작됨 (${_globalInitTimer?.elapsedMilliseconds}ms)');
      
      // 5. 백그라운드에서 무거운 초기화 작업 비동기 실행 (UI 블로킹 방지)
      _initializeInBackground(initializationService);
      
    } catch (e, stackTrace) {
      // 초기화 중 오류 발생 시 로깅 및 간단한 오류 화면 표시
      debugPrint('앱 초기화 중 치명적 오류: $e');
      debugPrint(stackTrace.toString());
      
      // 네이티브 스플래시 제거 (오류 발생해도 제거해야 함)
      FlutterNativeSplash.remove();
      
      // 간단한 오류 화면 표시
      runApp(MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 20),
                Text('앱 초기화 오류: $e', 
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    // 앱 재시작 (실제로는 프로세스 재시작이 필요할 수 있음)
                    main();
                  },
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
      ));
    }
  }, (error, stack) {
    // 글로벌 예외 핸들러
    debugPrint('예상치 못한 오류 발생: $error');
    debugPrint(stack.toString());
  });
}

// 백그라운드에서 무거운 초기화 작업 실행 (UI 블로킹 방지)
Future<void> _initializeInBackground(InitializationService initializationService) async {
  debugPrint('백그라운드 초기화 시작...');
  
  try {
    // 1. Firebase 초기화 (무거운 작업)
    final firebaseTimer = Stopwatch()..start();
    debugPrint('Firebase 초기화 시작...');
    
    // InitializationService를 통해 Firebase 초기화
    await initializationService.initializeFirebase(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    debugPrint('Firebase 초기화 완료 (${firebaseTimer.elapsedMilliseconds}ms)');
    
    // 2. 앱 설정 로드 (상대적으로 가벼운 작업)
    final settingsTimer = Stopwatch()..start();
    debugPrint('앱 설정 로드 시작...');
    await loadAppSettings();
    debugPrint('앱 설정 로드 완료 (${settingsTimer.elapsedMilliseconds}ms)');
    
    // 3. 캐시 서비스 초기화 (무거운 작업일 수 있음)
    final cacheTimer = Stopwatch()..start();
    debugPrint('캐시 서비스 초기화 시작...');
    await UnifiedCacheService().initialize();
    debugPrint('캐시 서비스 초기화 완료 (${cacheTimer.elapsedMilliseconds}ms)');
    
    // 4. 기타 필요한 서비스 초기화 (필요시 추가)
    
    // 모든 초기화 완료 후 네이티브 스플래시 제거
    debugPrint('모든 백그라운드 초기화 작업 완료 (${_globalInitTimer?.elapsedMilliseconds}ms)');
    FlutterNativeSplash.remove();
    debugPrint('네이티브 스플래시 제거됨');
    
  } catch (e) {
    debugPrint('백그라운드 초기화 중 오류 발생: $e');
    // 오류가 발생해도 스플래시는 제거해야 함
    FlutterNativeSplash.remove();
    debugPrint('오류 발생으로 네이티브 스플래시 제거됨');
  }
}

// 앱 설정 로드 함수 개선
Future<void> loadAppSettings() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final userPreferences = UserPreferencesService();

    // 기본값은 false (비활성화)로 설정
    ChineseSegmenterService.isSegmentationEnabled =
        prefs.getBool('segmentation_enabled') ?? false;

    // 언어 설정 초기화 - 아직 설정되지 않았다면 기본값 저장
    final sourceLanguage = await userPreferences.getSourceLanguage();
    final targetLanguage = await userPreferences.getTargetLanguage();
    
    debugPrint('언어 설정 로드 완료 - 소스 언어: $sourceLanguage, 타겟 언어: $targetLanguage');

    // 사전 로드는 필요할 때 지연 로딩으로 변경
    // 앱 시작 시 로드하지 않고, 실제로 필요할 때 로드하도록 함
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
    final userPreferences = UserPreferencesService();
    
    // 현재 언어 설정 저장
    final sourceLanguage = await userPreferences.getSourceLanguage();
    final targetLanguage = await userPreferences.getTargetLanguage();
    
    debugPrint('언어 설정 저장 - 소스 언어: $sourceLanguage, 타겟 언어: $targetLanguage');
  } catch (e) {
    debugPrint('언어 설정 저장 중 오류 발생: $e');
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
      home: const HomeScreen(),
    );
  }
}
