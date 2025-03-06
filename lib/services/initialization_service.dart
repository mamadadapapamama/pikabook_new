import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// 앱 초기화를 관리하는 서비스
///
/// Firebase 초기화 및 사용자 인증을 비동기적으로 처리하여
/// 앱 시작 시간을 단축합니다.
class InitializationService {
  // 초기화 상태를 추적하는 컨트롤러
  Completer<bool> _firebaseInitialized = Completer<bool>();
  Completer<bool> _userAuthenticated = Completer<bool>();

  // 오류 메시지 저장
  String? _firebaseError;
  String? _authError;

  // 상태 확인 getter
  Future<bool> get isFirebaseInitialized => _firebaseInitialized.future;
  Future<bool> get isUserAuthenticated => _userAuthenticated.future;
  bool get isFirebaseInitializing => !_firebaseInitialized.isCompleted;
  bool get isUserAuthenticating => !_userAuthenticated.isCompleted;

  // 오류 메시지 getter
  String? get firebaseError => _firebaseError;
  String? get authError => _authError;

  // Firebase 초기화 메서드
  Future<void> initializeFirebase({required FirebaseOptions options}) async {
    if (_firebaseInitialized.isCompleted) return;

    try {
      // Firebase 초기화 시작
      debugPrint('Firebase 초기화 시작...');
      await Firebase.initializeApp(options: options);
      debugPrint('Firebase 초기화 완료');

      // 초기화 완료 표시
      _firebaseInitialized.complete(true);

      // 사용자 인증 시작
      _authenticateUser();
    } catch (e) {
      debugPrint('Firebase 초기화 실패: $e');
      _firebaseError = '앱 초기화 중 오류가 발생했습니다: $e';
      _firebaseInitialized.complete(false);
      _userAuthenticated.complete(false);
    }
  }

  // 사용자 인증 메서드
  Future<void> _authenticateUser() async {
    if (_userAuthenticated.isCompleted) return;

    try {
      final auth = FirebaseAuth.instance;

      // 현재 사용자가 없으면 익명 로그인 수행
      if (auth.currentUser == null) {
        debugPrint('익명 인증 시작...');
        await auth.signInAnonymously();
        debugPrint('익명 인증 성공: ${auth.currentUser?.uid}');
      } else {
        debugPrint('기존 사용자 발견: ${auth.currentUser?.uid}');
      }

      // 인증 후 다시 확인
      if (auth.currentUser == null) {
        throw Exception('익명 인증 후에도 사용자가 null입니다.');
      }

      // 인증 완료 표시
      _userAuthenticated.complete(true);
    } catch (e) {
      debugPrint('사용자 인증 실패: $e');
      _authError = '사용자 인증 중 오류가 발생했습니다: $e';
      _userAuthenticated.complete(false);
    }
  }

  // 초기화 재시도 메서드
  void retryInitialization({required FirebaseOptions options}) {
    if (isFirebaseInitializing || isUserAuthenticating) return;

    // 컨트롤러 재설정
    _firebaseInitialized = Completer<bool>();
    _userAuthenticated = Completer<bool>();
    _firebaseError = null;
    _authError = null;

    // 초기화 다시 시작
    initializeFirebase(options: options);
  }
}
