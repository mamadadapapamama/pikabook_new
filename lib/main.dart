import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'app.dart';
import 'services/initialization_service.dart';

void main() async {
  // Flutter 엔진 초기화 보장
  WidgetsFlutterBinding.ensureInitialized();

  // 시스템 UI 설정 (상태 표시줄 색상 등)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  // 앱 방향 설정 (세로 모드만 허용)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 초기화 서비스 생성
  final initService = InitializationService();

  // Firebase 초기화 시작 (완료를 기다리지 않음)
  initService.initializeFirebase(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 앱 실행 (Firebase 초기화가 완료되기 전에도 UI는 표시됨)
  runApp(App(initializationService: initService));
}
