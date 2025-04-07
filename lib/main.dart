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
  final profileMode = false;
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
    
    // 릴리즈 모드에서는 디버그 프린트 완전 비활성화
    debugPrint = (String? message, {int? wrapWidth}) { };
    
    // 에러 로깅 설정 - 심각한 오류만 기록
    FlutterError.onError = (FlutterErrorDetails details) {
      DebugUtils.error('앱 오류: ${details.exception}');
    };
  } else {
    // 디버그 모드 설정
    DebugUtils.enableLogInRelease = true;
    
    // 타이머 관련 키워드 체크 함수
    bool containsTimerKeyword(String message) {
      final keywords = [
        'pikabook', 'timer', '타이머', '로딩', '로더', 
        'ms', '초', '시간', '소요', '처리', 
        'loading', 'duration', 'elapsed', 'timeout',
        '성공', '실패', '완료', '진행', '대기', '취소',
        '다이얼로그', 'dialog', '메시지',
        '✅', '⚠️', '🔴', 'error', '오류',
      ];
      
      for (var keyword in keywords) {
        if (message.contains(keyword)) {
          return true;
        }
      }
      
      return false;
    }
    
    // 타이머 패턴 체크 함수
    bool containsTimerPattern(String message) {
      // 숫자 + ms, 숫자 + 초, 시간 :, 등의 패턴 체크
      final patterns = [
        RegExp(r'\d+\s*ms'),
        RegExp(r'\d+\s*(초|분|시간)'),
        RegExp(r'(시간|처리|소요)\s*[:\-=]'),
        RegExp(r'\d{4,}'),  // 4자리 이상 연속된 숫자
      ];
      
      for (var pattern in patterns) {
        if (pattern.hasMatch(message)) {
          return true;
        }
      }
      
      return false;
    }
    
    // 디버그 모드에서도 모든 로그 출력 비활성화 (타이머 문제 해결)
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message == null) return;
      
      // 모든 로그 메시지 로우 레벨 필터링
      final lowerMessage = message.toLowerCase();
      
      // 1. 타이머 관련 단어 있으면 필터링
      if (containsTimerKeyword(lowerMessage)) {
        return;
      }
      
      // 2. 숫자와 ms, 초 등의 패턴이 있으면 필터링
      if (containsTimerPattern(lowerMessage)) {
        return;
      }
      
      // 3. Pikabook, 피카북 등의 단어 필터링
      if (lowerMessage.contains('pikabook') || 
          lowerMessage.contains('피카북') ||
          lowerMessage.contains('loading') ||
          lowerMessage.contains('로딩')) {
        return;
      }
      
      // 필터링을 통과한 로그만 출력
      originalDebugPrint(message, wrapWidth: wrapWidth);
    };
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
  
  // 5.5 애니메이션 타이머 출력 억제를 위한 설정
  // Flutter의 내부 타이머 출력을 억제하기 위한 트릭
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exception.toString().toLowerCase().contains('timer') ||
        details.exception.toString().toLowerCase().contains('animation') ||
        details.exception.toString().toLowerCase().contains('ms') ||
        details.exception.toString().toLowerCase().contains('pikabook')) {
      // 애니메이션 및 타이머 관련 오류는 무시
      return;
    }
    
    // 그 외의 오류는 정상적으로 처리
    if (DebugUtils.isReleaseMode()) {
      DebugUtils.error('앱 오류: ${details.exception}');
    } else {
      FlutterError.dumpErrorToConsole(details);
    }
  };
  
  // 타이머 로그 특수 처리
  if (!DebugUtils.isReleaseMode()) {
    // 애니메이션 디버그 세부 정보 비활성화
    // 렌더링 관련 정보 갱신 및 정리
    WidgetsBinding.instance.reassembleApplication();
  }
  
  // 6. 앱 시작 - App 클래스에서 실제 초기화 진행
  runApp(const App());
  
  // 7. 스플래시 화면 제거
  FlutterNativeSplash.remove();
}