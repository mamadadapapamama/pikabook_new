import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'app.dart';
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

/// 앱의 진입점
/// 
/// 앱 실행 준비 및 스플래시 화면 관리만 담당하고
/// 모든 로직은 App 클래스에 위임합니다.
Future<void> main() async {
  // 1. Flutter 초기화 - 가능한 빠르게
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  
  // 2. 시스템 UI 설정
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.dark,
    ),
  );
  
  // 3. 에러 로깅 설정
  FlutterError.onError = (details) {
    debugPrint('Flutter 에러: ${details.exception}');
  };

  // 4. Firebase 미리 초기화 (중복 초기화 오류 방지)
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('🔥 main: Firebase 초기화 완료');
    } else {
      debugPrint('🔥 main: Firebase 이미 초기화됨');
    }
  } catch (e) {
    debugPrint('🔥 main: Firebase 초기화 오류: $e');
  }
  
  // 5. 앱 시작 - App 클래스에서 실제 초기화 진행
  runApp(const App());
  
  // 6. 스플래시 화면 즉시 제거
  FlutterNativeSplash.remove();
  debugPrint('🎉 main: 스플래시 화면 즉시 제거됨');
}