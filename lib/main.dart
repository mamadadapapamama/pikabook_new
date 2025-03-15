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
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase 직접 초기화
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 앱 설정 로드
  await loadAppSettings();

  // 초기화 서비스 생성
  final initializationService = InitializationService();

  // 초기화 서비스에 Firebase가 이미 초기화되었음을 알림
  await initializationService.markFirebaseInitialized();

  runApp(App(initializationService: initializationService));
}

// 앱 설정 로드 함수 추가
Future<void> loadAppSettings() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    // 기본값은 false (비활성화)로 설정
    ChineseSegmenterService.isSegmentationEnabled =
        prefs.getBool('segmentation_enabled') ?? false;

    // 사전 미리 로드
    final segmenterService = ChineseSegmenterService();
    await segmenterService.initialize();
    print('사전 미리 로드 완료');
  } catch (e) {
    print('설정 로드 중 오류 발생: $e');
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
