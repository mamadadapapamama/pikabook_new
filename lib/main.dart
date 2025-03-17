import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/note_service.dart';
import 'services/image_service.dart';
import 'services/unified_cache_service.dart';
import 'services/user_preferences_service.dart';
import 'views/screens/splash_screen.dart';
import 'views/screens/home_screen.dart';
import 'views/screens/onboarding_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/initialization_service.dart';
import 'app.dart';
import 'services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/chinese_segmenter_service.dart';

void main() async {
  // Flutter 엔진 초기화
  WidgetsFlutterBinding.ensureInitialized();

  // 초기화 서비스 생성
  final initializationService = InitializationService();

  // 병렬로 초기화 작업 실행
  await Future.wait([
    // Firebase 초기화
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
        .then((_) => initializationService.markFirebaseInitialized()),

    // 앱 설정 로드 (비동기로 실행하고 결과를 기다리지 않음)
    loadAppSettings(),

    // 통합 캐시 서비스 초기화 (비동기로 실행하고 결과를 기다리지 않음)
    UnifiedCacheService().initialize(),
  ]);

  // 앱 실행
  runApp(App(initializationService: initializationService));
}

// 앱 설정 로드 함수 개선
Future<void> loadAppSettings() async {
  try {
    final prefs = await SharedPreferences.getInstance();

    // 기본값은 false (비활성화)로 설정
    ChineseSegmenterService.isSegmentationEnabled =
        prefs.getBool('segmentation_enabled') ?? false;

    // 사전 로드는 필요할 때 지연 로딩으로 변경
    // 앱 시작 시 로드하지 않고, 실제로 필요할 때 로드하도록 함
    debugPrint('앱 설정 로드 완료');
  } catch (e) {
    debugPrint('설정 로드 중 오류 발생: $e');
    // 오류 발생 시 기본값으로 비활성화
    ChineseSegmenterService.isSegmentationEnabled = false;
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
