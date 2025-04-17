import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show timeDilation;
import 'package:flutter/services.dart';
import 'app.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'firebase_options.dart';
import 'services/image_service.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'views/screens/home_screen.dart';
// import 'views/screens/note_detail_screen.dart';

/// 앱의 진입점
/// 
/// 앱 실행 준비 및 스플래시 화면 관리만 담당하고
/// 모든 로직은 App 클래스에 위임합니다.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 디버그 타이머 강제로 비활성화
  timeDilation = 1.0;
  
  // 릴리즈 모드에 관계없이 항상 디버그 UI와 성능 측정기 비활성화
  debugPaintSizeEnabled = false;
  debugPaintBaselinesEnabled = false;
  debugPaintPointersEnabled = false;
  debugPaintLayerBordersEnabled = false;
  debugRepaintRainbowEnabled = false;
  debugDisableClipLayers = false;
  debugDisableOpacityLayers = false;
  debugDisablePhysicalShapeLayers = false;
  
  // 디버그 관련 모든 출력 제한
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message == null) return;
    
    final String lowerMessage = message.toLowerCase();
    // 성능, 타이머, 애니메이션 관련 모든 디버그 출력 차단
    if (lowerMessage.contains('timer') || 
        lowerMessage.contains('animation') || 
        lowerMessage.contains('vsync') ||
        lowerMessage.contains('tick') ||
        lowerMessage.contains('scheduler') ||
        lowerMessage.contains('frame') ||
        lowerMessage.contains('benchmark') ||
        lowerMessage.contains('performance') ||
        lowerMessage.contains('ms')) {
      // 타이머/성능 관련 로그 무시
      return;
    }
    
    if (kReleaseMode) {
      // 릴리즈 모드에서는 모든 로그 억제
      return;
    }
    
    // 나머지 로그는 개발 모드에서만 출력
    final String? filteredMessage = message;
    debugPrintSynchronously(filteredMessage ?? '');
  };
  
  // 타이머 오류 무시 설정
  FlutterError.onError = (FlutterErrorDetails details) {
    final String errorString = details.toString().toLowerCase();
    // 타이머, 애니메이션, 틱 관련 오류는 모두 무시
    if (errorString.contains('timer') || 
        errorString.contains('animation') || 
        errorString.contains('tick') ||
        errorString.contains('vsync') ||
        errorString.contains('scheduler') ||
        errorString.contains('frame') ||
        errorString.contains('performance')) {
      // 무시 (출력하지 않음)
      return;
    }
    
    // 그 외 오류는 정상 처리
    FlutterError.presentError(details);
  };
  
  // 시작 시 캐시 정리
  await _cleanupOnStart();
  
  // Firebase 초기화
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    // 디버그 모드에서 타임스탬프 사용 설정
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    
    debugPrint('Firebase 초기화 완료');
  } catch (e) {
    debugPrint('Firebase 초기화 실패: $e');
    // 초기화 실패해도 앱은 계속 실행 (일부 기능 제한)
  }
  
  // 이미지 캐시 초기화
  final imageService = ImageService();
  await imageService.cleanupTempFiles();
  
  // 일반적인 앱 실행
  runApp(const App());
}

/// 앱 시작 시 캐시 및 임시 데이터 정리
Future<void> _cleanupOnStart() async {
  try {
    // 이미지 캐시 정리
    ImageCache imageCache = PaintingBinding.instance.imageCache;
    imageCache.clear();
    
    // 이미지 서비스 임시 파일 정리
    await ImageService().cleanupTempFiles();
    
    debugPrint('앱 시작 시 캐시 정리 완료');
  } catch (e) {
    debugPrint('앱 시작 시 캐시 정리 중 오류: $e');
  }
}

@override
Widget build(BuildContext context) {
  return MaterialApp(
    title: 'Pikabook',
    debugShowCheckedModeBanner: false, // 디버그 배너 비활성화
    theme: ThemeData(
      // ... existing code ...
    ),
    // ... existing code ...
  );
}