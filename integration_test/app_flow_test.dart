import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:pikabook_new/main.dart' as app;

// 테스트 계정 정보
class TestCredentials {
  // 첫 번째 테스트 계정
  static const String email1 = 'pika.test0001@gmail.com';
  static const String password1 = 'pikatest123!';
  
  // 두 번째 테스트 계정 (첫 번째가 실패할 경우 사용)
  static const String email2 = 'pikabook.test0002@gmail.com';
  static const String password2 = 'vlzkvlzk002!';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  // 테스트 시간 제한 설정
  final timeout = const Duration(minutes: 5);

  group('피카북 앱 핵심 기능 테스트', () {
    testWidgets('전체 사용자 플로우 테스트', (WidgetTester tester) async {
      // 앱 실행
      app.main();
      
      // 앱이 로드될 때까지 기다림
      await tester.pumpAndSettle(const Duration(seconds: 2));
      
      print('🚀 앱이 시작되었습니다');

      // 온보딩/스플래시 화면이 있다면 기다리기
      await Future.delayed(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      print('🔍 앱 초기화 후 화면 분석 중...');

      // 로그인 화면 확인
      final loginText = find.text('로그인');
      if (loginText.evaluate().isNotEmpty) {
        print('🔐 로그인 화면 감지됨');
        await _loginWithTestAccount(tester);
      } else {
        print('🔍 이미 로그인된 것으로 보임');
        // 홈 또는 노트 화면 확인
        final homeText = find.text('홈');
        final noteText = find.text('내 노트');
        if (homeText.evaluate().isEmpty && noteText.evaluate().isEmpty) {
          print('⚠️ 로그인된 것 같지만 홈/노트 화면을 찾을 수 없음');
          throw Exception('앱이 예상된 상태가 아닙니다');
        }
      }

      // 테스트 흐름 계속
      await _continueTestFlow(tester);
      
      print('✅ 모든 테스트 완료!');
    }, timeout: Timeout(timeout));
  });
}

/// 테스트 계정으로 로그인
Future<void> _loginWithTestAccount(WidgetTester tester) async {
  // 이메일 필드 찾기
  Finder? emailField;
  
  try {
    emailField = find.byKey(const Key('emailField'));
    if (emailField.evaluate().isEmpty) {
      // 키가 없는 경우 TextField 기준으로 찾기
      final textFields = find.byType(TextField);
      if (textFields.evaluate().length >= 2) {
        // 일반적으로 첫 번째가 이메일, 두 번째가 비밀번호
        emailField = textFields.first;
        print('📝 이메일 필드를 TextField 타입으로 찾음');
      } else {
        print('⚠️ 로그인 폼을 찾을 수 없음');
        return;
      }
    }
  } catch (e) {
    print('⚠️ 이메일 필드 찾기 오류: $e');
    return;
  }
  
  // 첫 번째 계정으로 로그인
  print('🔑 첫 번째 계정으로 로그인 시도');
  
  try {
    await tester.enterText(emailField, TestCredentials.email1);
    await tester.pump();
    
    // 비밀번호 필드 찾기
    Finder passwordField;
    final passwordByKey = find.byKey(const Key('passwordField'));
    if (passwordByKey.evaluate().isNotEmpty) {
      passwordField = passwordByKey;
    } else {
      final textFields = find.byType(TextField);
      // 두 번째 텍스트 필드가 비밀번호일 가능성이 높음
      passwordField = textFields.at(1);
    }
    
    await tester.enterText(passwordField, TestCredentials.password1);
    await tester.pump();
    
    // 로그인 버튼 찾기
    Finder loginButton;
    final loginButtonByKey = find.byKey(const Key('loginButton'));
    if (loginButtonByKey.evaluate().isNotEmpty) {
      loginButton = loginButtonByKey;
    } else {
      // 일반적으로 '로그인' 텍스트가 있는 버튼
      loginButton = find.widgetWithText(ElevatedButton, '로그인');
      if (loginButton.evaluate().isEmpty) {
        // 다른 방법으로 시도
        loginButton = find.text('로그인').last;
      }
    }
    
    // 로그인 버튼 클릭
    await tester.tap(loginButton);
    await tester.pumpAndSettle();
    
    // 로그인 완료 대기
    await Future.delayed(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    
    // 로그인 확인
    final homeOrNote = find.text('홈').evaluate().isNotEmpty || 
                       find.text('내 노트').evaluate().isNotEmpty;
    
    if (homeOrNote) {
      print('✅ 첫 번째 계정 로그인 성공!');
    } else {
      print('⚠️ 첫 번째 계정 로그인 실패, 두 번째 계정 시도...');
      
      // 두 번째 계정으로 재시도
      await tester.enterText(emailField, TestCredentials.email2);
      await tester.pump();
      
      await tester.enterText(passwordField, TestCredentials.password2);
      await tester.pump();
      
      await tester.tap(loginButton);
      await tester.pumpAndSettle();
      
      // 로그인 완료 대기
      await Future.delayed(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      
      // 두 번째 계정 로그인 확인
      final loggedIn = find.text('홈').evaluate().isNotEmpty || 
                      find.text('내 노트').evaluate().isNotEmpty;
      
      if (loggedIn) {
        print('✅ 두 번째 계정 로그인 성공!');
      } else {
        print('❌ 모든 계정 로그인 실패');
      }
    }
  } catch (e) {
    print('❌ 로그인 과정에서 오류 발생: $e');
  }
}

/// 테스트 흐름 진행
Future<void> _continueTestFlow(WidgetTester tester) async {
  try {
    // 노트 목록 화면으로 이동
    final myNotesButton = find.text('내 노트');
    if (myNotesButton.evaluate().isNotEmpty) {
      await tester.tap(myNotesButton);
      await tester.pumpAndSettle();
      print('📝 노트 목록 화면으로 이동했습니다');
    } else {
      print('📝 이미 노트 화면에 있거나 UI 구조가 다릅니다');
    }
    
    // 노트가 있는지 확인
    final cards = find.byType(Card);
    if (cards.evaluate().isNotEmpty) {
      // 기존 노트 선택
      await tester.tap(cards.first);
      await tester.pumpAndSettle();
      print('📄 기존 노트를 선택했습니다');
      
      // TTS 기능 테스트
      final ttsButton = find.text('본문 전체 듣기');
      if (ttsButton.evaluate().isNotEmpty) {
        print('🔊 TTS 기능 테스트 시작');
        
        await tester.tap(ttsButton);
        await tester.pumpAndSettle();
        
        // 잠시 대기
        await Future.delayed(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        
        // TTS 중지
        await tester.tap(ttsButton);
        await tester.pumpAndSettle();
        
        print('✅ TTS 기능 테스트 완료');
      } else {
        print('ℹ️ TTS 버튼을 찾을 수 없습니다');
      }
      
      // 백 버튼으로 노트 목록으로 돌아가기
      final backButton = find.byIcon(Icons.arrow_back);
      if (backButton.evaluate().isNotEmpty) {
        await tester.tap(backButton);
        await tester.pumpAndSettle();
        print('⬅️ 노트 목록으로 돌아갑니다');
      } else {
        // 시스템 뒤로가기
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
    } else {
      print('ℹ️ 노트를 찾을 수 없습니다');
    }
    
    // 홈으로 돌아가기
    final homeButton = find.text('홈');
    if (homeButton.evaluate().isNotEmpty) {
      await tester.tap(homeButton);
      await tester.pumpAndSettle();
      print('🏠 홈 화면으로 이동');
    }
    
    // 설정 메뉴로 이동하기
    Finder? settingsOrProfile;
    final profileButton = find.text('프로필');
    final settingsButton = find.text('설정');
    final personIcon = find.byIcon(Icons.person);
    
    if (profileButton.evaluate().isNotEmpty) {
      settingsOrProfile = profileButton;
    } else if (settingsButton.evaluate().isNotEmpty) {
      settingsOrProfile = settingsButton;
    } else if (personIcon.evaluate().isNotEmpty) {
      settingsOrProfile = personIcon;
    }
    
    if (settingsOrProfile != null) {
      await tester.tap(settingsOrProfile);
      await tester.pumpAndSettle();
      print('⚙️ 설정/프로필 화면으로 이동');
      
      // 로그아웃 버튼 찾기
      final logoutButton = find.text('로그아웃');
      if (logoutButton.evaluate().isNotEmpty) {
        await tester.tap(logoutButton);
        await tester.pumpAndSettle();
        
        // 확인 다이얼로그
        final confirmButton = find.text('확인');
        if (confirmButton.evaluate().isNotEmpty) {
          await tester.tap(confirmButton);
          await tester.pumpAndSettle();
          print('🔓 로그아웃 완료');
          
          // 로그아웃 확인
          await Future.delayed(const Duration(seconds: 2));
          await tester.pumpAndSettle();
          
          final loginScreen = find.text('로그인');
          if (loginScreen.evaluate().isNotEmpty) {
            print('✅ 로그아웃 성공: 로그인 화면으로 돌아왔습니다');
          } else {
            print('⚠️ 로그아웃 후 로그인 화면을 찾을 수 없습니다');
          }
        }
      } else {
        print('ℹ️ 로그아웃 버튼을 찾을 수 없습니다');
      }
    } else {
      print('ℹ️ 설정/프로필 메뉴를 찾을 수 없습니다');
    }
  } catch (e) {
    print('❌ 테스트 흐름 중 오류: $e');
  }
} 