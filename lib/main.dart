import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'app.dart';
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'utils/debug_utils.dart';

/// 앱의 진입점
/// 
/// 앱 실행 준비 및 스플래시 화면 관리만 담당하고
/// 모든 로직은 App 클래스에 위임합니다.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. 스플래시 화면 유지
  FlutterNativeSplash.preserve(widgetsBinding: WidgetsFlutterBinding.ensureInitialized());
  
  // 앱 스토어 심사를 위한 최적화: 메모리 사용량 최적화
  final profileMode = true;
  if (profileMode) {
    // 메모리 관련 제약 조정
    WidgetsBinding.instance.deferFirstFrame();
    
    // 이미지 캐시 크기 제한
    PaintingBinding.instance.imageCache.maximumSize = 50;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 50 * 1024 * 1024; // 50MB
    
    // 첫 프레임 렌더링 허용
    WidgetsBinding.instance.allowFirstFrame();
  }
  
  // 2. 시스템 UI 설정 (상태 표시줄 등)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  
  // 3. 가로 모드 비활성화
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // 4. 릴리즈 모드 확인 및 로그 설정
  if (DebugUtils.isReleaseMode()) {
    // 릴리즈 모드에서는 불필요한 로그 비활성화
    DebugUtils.enableLogInRelease = false;
    
    // 에러 로깅 설정 - 심각한 오류만 기록
    FlutterError.onError = (FlutterErrorDetails details) {
      DebugUtils.error('앱 오류: ${details.exception}');
    };
  } else {
    // 디버그 모드 설정
    DebugUtils.enableLogInRelease = true;
  }
  
  // 5. Firebase 초기화
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    // Firebase 초기화 실패 - 릴리즈 모드에서는 로그만 저장
    DebugUtils.error('Firebase 초기화 실패: $e');
  }
  
  // 6. 앱 시작 - App 클래스에서 실제 초기화 진행
  runApp(const App());
  
  // 7. 스플래시 화면 제거
  FlutterNativeSplash.remove();
}