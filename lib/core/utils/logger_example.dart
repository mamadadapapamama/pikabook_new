import 'package:flutter/foundation.dart';
import 'logger.dart';

/// Logger 사용법 예시
/// 
/// 이 파일은 centralized logging 시스템의 사용법을 보여줍니다.
/// 실제 프로젝트에서는 이 파일을 삭제하고 각 서비스에서 Logger를 직접 사용하세요.
class LoggerExample {
  
  /// 기본 로그 사용법
  static void basicUsage() {
    // 디버그 로그 (개발 환경에서만 출력)
    Logger.debug('디버그 정보', tag: 'Example');
    
    // 정보 로그
    Logger.info('일반 정보', tag: 'Example');
    
    // 경고 로그
    Logger.warning('경고 메시지', tag: 'Example');
    
    // 오류 로그 (오류 객체 포함)
    try {
      throw Exception('테스트 오류');
    } catch (e) {
      Logger.error('오류 발생', tag: 'Example', error: e);
    }
  }
  
  /// 특화된 로그 사용법
  static void specializedUsage() {
    // API 호출 로그
    Logger.api('사용자 정보 조회 시작', tag: 'UserAPI');
    Logger.api('사용자 정보 조회 완료', tag: 'UserAPI');
    
    // 데이터베이스 로그
    Logger.database('Firestore 문서 읽기', tag: 'UserDB');
    Logger.database('Firestore 문서 쓰기', tag: 'UserDB');
    
    // 인증 로그
    Logger.auth('로그인 시도', tag: 'AuthService');
    Logger.auth('로그인 성공', tag: 'AuthService');
    
    // 구독/결제 로그
    Logger.subscription('구독 상태 확인', tag: 'Subscription');
    Logger.subscription('결제 처리 완료', tag: 'Subscription');
    
    // UI 로그
    Logger.ui('화면 전환: Home → Note', tag: 'Navigation');
    Logger.ui('위젯 렌더링 완료', tag: 'NoteWidget');
    
    // 성능 측정 로그
    Logger.performance('API 응답 시간: 150ms', tag: 'Performance');
    Logger.performance('이미지 로딩 시간: 200ms', tag: 'Performance');
  }
  
  /// 로그 레벨 설정 예시
  static void logLevelExample() {
    // 개발 환경: 모든 로그 출력
    Logger.setMinLevel(LogLevel.debug);
    
    // 테스트 환경: 정보 레벨 이상만 출력
    Logger.setMinLevel(LogLevel.info);
    
    // 프로덕션 환경: 오류만 출력
    Logger.setMinLevel(LogLevel.error);
    
    // 릴리즈 모드에서도 로그 출력 허용 (필요한 경우)
    Logger.setEnableLogInRelease(true);
  }
  
  /// 실제 사용 시나리오 예시
  static void realWorldExample() {
    // 1. 사용자 로그인 과정
    Logger.auth('로그인 시도 시작', tag: 'AuthService');
    
    try {
      // 로그인 로직...
      Logger.auth('로그인 성공', tag: 'AuthService');
      
      // 2. 데이터 로딩
      Logger.database('사용자 데이터 조회 시작', tag: 'UserService');
      // 데이터베이스 조회...
      Logger.database('사용자 데이터 조회 완료', tag: 'UserService');
      
      // 3. API 호출
      Logger.api('노트 목록 조회 시작', tag: 'NoteAPI');
      // API 호출...
      Logger.api('노트 목록 조회 완료', tag: 'NoteAPI');
      
      // 4. UI 업데이트
      Logger.ui('홈 화면 새로고침', tag: 'HomeScreen');
      
    } catch (e) {
      // 5. 오류 처리
      Logger.error('로그인 과정에서 오류 발생', tag: 'AuthService', error: e);
      
      // 6. UI 오류 표시
      Logger.ui('오류 다이얼로그 표시', tag: 'ErrorDialog');
    }
  }
}

/// 로그 출력 예시:
/// 
/// 🔍 [DEBUG] [14:30:15] [Example] 디버그 정보
/// ℹ️ [INFO] [14:30:15] [Example] 일반 정보
/// ⚠️ [WARN] [14:30:15] [Example] 경고 메시지
/// ❌ [ERROR] [14:30:15] [Example] 오류 발생
/// Exception: 테스트 오류
/// 
/// 🌐 [INFO] [14:30:15] [UserAPI] 사용자 정보 조회 시작
/// 🗄️ [INFO] [14:30:15] [UserDB] Firestore 문서 읽기
/// 🔐 [INFO] [14:30:15] [AuthService] 로그인 시도
/// 💳 [INFO] [14:30:15] [Subscription] 구독 상태 확인
/// 🎨 [INFO] [14:30:15] [Navigation] 화면 전환: Home → Note
/// ⏱️ [INFO] [14:30:15] [Performance] API 응답 시간: 150ms 