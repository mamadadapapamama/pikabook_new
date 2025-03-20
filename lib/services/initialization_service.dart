import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'unified_cache_service.dart';
import 'auth_service.dart';

/// 앱 초기화를 관리하는 서비스
///
/// Firebase 초기화 및 사용자 인증을 비동기적으로 처리하여
/// 앱 시작 시간을 단축합니다.
class InitializationService {
  // 초기화 상태를 추적하는 컨트롤러
  Completer<bool> _firebaseInitialized = Completer<bool>();
  Completer<bool> _userAuthenticationChecked = Completer<bool>();

  // 오류 메시지 저장
  String? _firebaseError;
  String? _authError;

  // 초기화 시작 시간 기록
  final DateTime _initStartTime = DateTime.now();

  // 인증 서비스 (지연 초기화)
  AuthService? _authService;
  
  // 인증 서비스 getter
  AuthService get authService {
    if (_authService == null) {
      _authService = AuthService();
    }
    return _authService!;
  }

  // 상태 확인 getter
  Future<bool> get isFirebaseInitialized => _firebaseInitialized.future;
  Future<bool> get isUserAuthenticationChecked => _userAuthenticationChecked.future;
  bool get isFirebaseInitializing => !_firebaseInitialized.isCompleted;
  bool get isUserAuthenticationChecking => !_userAuthenticationChecked.isCompleted;

  // 오류 메시지 getter
  String? get firebaseError => _firebaseError;
  String? get authError => _authError;

  // 사용자 인증 상태 getter
  bool get isUserAuthenticated => FirebaseAuth.instance.currentUser != null;
  bool get isAnonymousUser => FirebaseAuth.instance.currentUser?.isAnonymous ?? false;

  // Firebase 초기화 메서드
  Future<void> initializeFirebase({required FirebaseOptions options}) async {
    if (_firebaseInitialized.isCompleted) return;

    try {
      // Firebase 초기화 시작
      final initStartTime = DateTime.now();
      debugPrint('Firebase 초기화 시작... (${initStartTime.toString()})');
      
      // Firebase 코어만 초기화하고 나머지 서비스는 필요할 때 초기화
      await Firebase.initializeApp(options: options);
      
      final initDuration = DateTime.now().difference(initStartTime);
      debugPrint('Firebase 코어 초기화 완료 (소요시간: ${initDuration.inMilliseconds}ms)');

      // 초기화 완료 표시
      _firebaseInitialized.complete(true);

      // 사용자 인증 상태 확인 (필수 서비스)
      // 백그라운드로 처리하여 UI 블로킹 방지
      Future.microtask(() => _checkAuthenticationState());
      
      // 다른 Firebase 서비스는 필요할 때 초기화하도록 함
    } catch (e) {
      debugPrint('Firebase 초기화 실패: $e');
      _firebaseError = '앱 초기화 중 오류가 발생했습니다: $e';
      _firebaseInitialized.complete(false);
      _userAuthenticationChecked.complete(false);
    }
  }
  
  // Firebase가 이미 초기화되었음을 표시하는 메서드
  Future<void> markFirebaseInitialized() async {
    if (_firebaseInitialized.isCompleted) return;
    
    final elapsed = DateTime.now().difference(_initStartTime);
    debugPrint('Firebase 초기화 완료 표시 (외부 초기화, 소요시간: ${elapsed.inMilliseconds}ms)');
    _firebaseInitialized.complete(true);
    
    // 사용자 인증 상태 확인 (필수 서비스) - 백그라운드로 처리
    Future.microtask(() => _checkAuthenticationState());
  }

  // 사용자 인증 상태 확인 메서드
  Future<void> _checkAuthenticationState() async {
    if (_userAuthenticationChecked.isCompleted) return;

    try {
      final authCheckStartTime = DateTime.now();
      debugPrint('사용자 인증 상태 확인 시작 (${authCheckStartTime.toString()})');
      
      final auth = FirebaseAuth.instance;
      
      // 현재 사용자 확인
      if (auth.currentUser != null) {
        debugPrint('기존 사용자 발견: ${auth.currentUser?.uid} (익명: ${auth.currentUser?.isAnonymous})');
      } else {
        debugPrint('로그인된 사용자 없음');
      }

      // 인증 상태 확인 완료 표시
      _userAuthenticationChecked.complete(true);
      
      final authCheckDuration = DateTime.now().difference(authCheckStartTime);
      debugPrint('사용자 인증 상태 확인 완료 (소요시간: ${authCheckDuration.inMilliseconds}ms)');
      
    } catch (e) {
      debugPrint('사용자 인증 상태 확인 실패: $e');
      _authError = '사용자 인증 상태 확인 중 오류가 발생했습니다: $e';
      _userAuthenticationChecked.complete(false);
    }
  }

  // 익명 로그인 메서드
  Future<UserCredential?> signInAnonymously() async {
    try {
      final loginStartTime = DateTime.now();
      debugPrint('익명 인증 시작... (${loginStartTime.toString()})');
      
      final userCredential = await authService.signInAnonymously();
      
      final loginDuration = DateTime.now().difference(loginStartTime);
      debugPrint('익명 인증 성공: ${userCredential.user?.uid} (소요시간: ${loginDuration.inMilliseconds}ms)');
      
      return userCredential;
    } catch (e) {
      debugPrint('익명 인증 실패: $e');
      _authError = '익명 인증 중 오류가 발생했습니다: $e';
      return null;
    }
  }

  // Google 로그인 메서드
  Future<User?> signInWithGoogle() async {
    try {
      debugPrint('Google 인증 시작...');
      final user = await authService.signInWithGoogle();
      debugPrint('Google 인증 성공: ${user?.uid}');
      return user;
    } catch (e) {
      debugPrint('Google 인증 실패: $e');
      _authError = 'Google 인증 중 오류가 발생했습니다: $e';
      return null;
    }
  }

  // Apple 로그인 메서드
  Future<User?> signInWithApple() async {
    try {
      debugPrint('Apple 인증 시작...');
      final user = await authService.signInWithApple();
      debugPrint('Apple 인증 성공: ${user?.uid}');
      return user;
    } catch (e) {
      debugPrint('Apple 인증 실패: $e');
      _authError = 'Apple 인증 중 오류가 발생했습니다: $e';
      return null;
    }
  }

  // 익명 계정을 Google 계정과 연결하는 메서드
  Future<UserCredential?> linkAnonymousAccountWithGoogle() async {
    try {
      debugPrint('익명 계정을 Google 계정과 연결 시작...');
      final userCredential = await authService.linkAnonymousAccountWithGoogle();
      debugPrint('Google 계정 연결 성공: ${userCredential.user?.uid}');
      return userCredential;
    } catch (e) {
      debugPrint('Google 계정 연결 실패: $e');
      _authError = 'Google 계정 연결 중 오류가 발생했습니다: $e';
      return null;
    }
  }

  // 익명 계정을 Apple 계정과 연결하는 메서드
  Future<UserCredential?> linkAnonymousAccountWithApple() async {
    try {
      debugPrint('익명 계정을 Apple 계정과 연결 시작...');
      final userCredential = await authService.linkAnonymousAccountWithApple();
      debugPrint('Apple 계정 연결 성공: ${userCredential.user?.uid}');
      return userCredential;
    } catch (e) {
      debugPrint('Apple 계정 연결 실패: $e');
      _authError = 'Apple 계정 연결 중 오류가 발생했습니다: $e';
      return null;
    }
  }

  // 로그아웃 메서드
  Future<void> signOut() async {
    try {
      await authService.signOut();
      debugPrint('로그아웃 성공');
    } catch (e) {
      debugPrint('로그아웃 실패: $e');
      _authError = '로그아웃 중 오류가 발생했습니다: $e';
    }
  }

  // 초기화 재시도 메서드
  void retryInitialization({required FirebaseOptions options}) {
    if (isFirebaseInitializing || isUserAuthenticationChecking) return;

    // 컨트롤러 재설정
    _firebaseInitialized = Completer<bool>();
    _userAuthenticationChecked = Completer<bool>();
    _firebaseError = null;
    _authError = null;

    // 초기화 다시 시작
    initializeFirebase(options: options);
  }
}
