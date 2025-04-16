import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'app.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'services/image_service.dart';

/// 앱의 진입점
/// 
/// 앱 실행 준비 및 스플래시 화면 관리만 담당하고
/// 모든 로직은 App 클래스에 위임합니다.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 릴리즈 모드에서 디버그 출력 억제 (타이머 등 출력 방지)
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }
  
  // 시작 시 캐시 정리
  await _cleanupOnStart();
  
  // Firebase 초기화 (오류 처리 추가)
  bool firebaseInitialized = false;
  int maxRetries = 3;
  int retryCount = 0;
  
  while (!firebaseInitialized && retryCount < maxRetries) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      firebaseInitialized = true;
      debugPrint('Firebase 초기화 성공!');
    } catch (e) {
      retryCount++;
      debugPrint('Firebase 초기화 실패 ($retryCount/$maxRetries): $e');
      
      if (retryCount < maxRetries) {
        // 잠시 대기 후 재시도
        await Future.delayed(Duration(milliseconds: 500 * retryCount));
      }
    }
  }
  
  if (!firebaseInitialized) {
    debugPrint('Firebase 초기화 최종 실패: 오프라인 모드로 실행');
  }
  
  runApp(const App());
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
    
    debugPrint('앱 시작 시 캐시 정리 완료');
  } catch (e) {
    debugPrint('앱 시작 시 캐시 정리 중 오류: $e');
  }
}