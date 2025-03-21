import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'unified_cache_service.dart';
import 'auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_preferences_service.dart';

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

  // 오류 메시지 setter
  void setFirebaseError(String error) {
    _firebaseError = error;
    if (!_firebaseInitialized.isCompleted) {
      _firebaseInitialized.complete(false);
    }
    debugPrint('Firebase 오류 설정됨: $error');
  }

  void setAuthError(String error) {
    _authError = error;
    if (!_userAuthenticationChecked.isCompleted) {
      _userAuthenticationChecked.complete(false);
    }
    debugPrint('인증 오류 설정됨: $error');
  }

  // 사용자 인증 상태 getter
  bool get isUserAuthenticated => FirebaseAuth.instance.currentUser != null;
  bool get isAnonymousUser => FirebaseAuth.instance.currentUser?.isAnonymous ?? false;

  // Firebase 초기화 메서드
  Future<bool> initializeFirebase({required FirebaseOptions options}) async {
    final startTime = DateTime.now();
    final initElapsed = startTime.difference(_initStartTime);
    debugPrint('Firebase 초기화 시작 (앱 시작 후 ${initElapsed.inMilliseconds}ms)');
    
    try {
      // Firebase 앱이 이미 초기화되었는지 확인
      if (Firebase.apps.isNotEmpty) {
        debugPrint('Firebase가 이미 초기화되어 있음');
        if (!_firebaseInitialized.isCompleted) {
          _firebaseInitialized.complete(true);
        }
        return true;
      }

      // Firebase 초기화
      debugPrint('Firebase 초기화 중...');
      await Firebase.initializeApp(options: options);

      // 초기화 완료
      if (!_firebaseInitialized.isCompleted) {
        _firebaseInitialized.complete(true);
      }
      
      final duration = DateTime.now().difference(startTime);
      debugPrint('Firebase 초기화 성공 (소요시간: ${duration.inMilliseconds}ms)');
      
      // Firebase 초기화 후 백그라운드에서 인증 상태 확인
      Future.microtask(() => _checkAuthenticationState());
      
      return true;
    } catch (e) {
      debugPrint('Firebase 초기화 실패: $e');
      _firebaseError = '앱 초기화 중 오류가 발생했습니다: $e';
      if (!_firebaseInitialized.isCompleted) {
        _firebaseInitialized.complete(false);
      }
      return false;
    }
  }
  
  // Firebase가 이미 초기화되었음을 표시하는 메서드
  Future<void> markFirebaseInitialized() async {
    if (_firebaseInitialized.isCompleted) {
      debugPrint('Firebase 초기화가 이미 완료되어 있어 markFirebaseInitialized()를 건너뜁니다.');
      return;
    }
    
    final elapsed = DateTime.now().difference(_initStartTime);
    debugPrint('Firebase 초기화 완료 표시 (외부 초기화, 소요시간: ${elapsed.inMilliseconds}ms)');
    _firebaseInitialized.complete(true);
    
    // 사용자 인증 상태 확인 (필수 서비스) - 백그라운드로 처리
    Future.microtask(() => _checkAuthenticationState());
  }

  // 사용자 인증 상태 확인 메서드
  Future<void> _checkAuthenticationState() async {
    final startTime = DateTime.now();
    debugPrint('사용자 인증 상태 확인 시작 (${startTime.toString()})');
    
    try {
      // 이미 완료된 경우 스킵
      if (_userAuthenticationChecked.isCompleted) {
        debugPrint('사용자 인증 상태가 이미 확인됨');
        return;
      }

      // Firebase Auth 인스턴스 가져오기
      final auth = FirebaseAuth.instance;
      debugPrint('Firebase Auth 인스턴스 가져옴, 현재 사용자 확인 중...');

      // 현재 사용자 확인 (null이면 로그인되지 않은 상태)
      final currentUser = auth.currentUser;

      if (currentUser != null) {
        debugPrint('사용자가 이미 로그인되어 있음: ${currentUser.uid} (익명: ${currentUser.isAnonymous})');
        
        // 추가: 사용자 정보 확인 
        _saveLastLoginActivity(currentUser);
      } else {
        debugPrint('로그인된 사용자 없음 - 로그인 화면으로 이동');
        // 중요: 이전에 여기서 자동 익명 로그인이 발생했을 수 있음
        // 이제는 로그인 화면으로 이동하도록 명시적으로 처리
      }

      // 인증 상태 확인 완료
      _userAuthenticationChecked.complete(true);
      
      final duration = DateTime.now().difference(startTime);
      debugPrint('인증 상태 확인 완료 (소요시간: ${duration.inMilliseconds}ms)');
    } catch (e) {
      debugPrint('인증 상태 확인 실패: $e');
      _authError = '인증 상태를 확인하는 중 오류가 발생했습니다: $e';
      _userAuthenticationChecked.complete(false);
    }
  }
  
  // 마지막 로그인 활동 저장
  Future<void> _saveLastLoginActivity(User user) async {
    try {
      final firestore = FirebaseFirestore.instance;
      await firestore.collection('users').doc(user.uid).update({
        'lastActivity': FieldValue.serverTimestamp(),
        'lastAppVersion': '1.0.0', // 앱 버전 정보 추가
      });
      debugPrint('사용자 마지막 활동 정보 업데이트: ${user.uid}');
    } catch (e) {
      debugPrint('사용자 활동 정보 업데이트 실패: $e');
    }
  }

  // 익명 로그인 메서드
  Future<User?> anonymousSignIn() async {
    final startTime = DateTime.now();
    debugPrint('익명 로그인 시작 (${startTime.toString()})');
    
    try {
      // Firebase 초기화 대기
      final firebaseReady = await isFirebaseInitialized;
      if (!firebaseReady) {
        debugPrint('Firebase 초기화 실패로 익명 로그인 불가');
        return null;
      }

      // 인증 서비스를 통해 익명 로그인
      debugPrint('익명 로그인 요청 중...');
      final userCredential = await authService.signInAnonymously();
      
      if (userCredential.user != null) {
        debugPrint('익명 로그인 성공: ${userCredential.user!.uid}');
      } else {
        debugPrint('익명 로그인 실패: 사용자 객체가 null임');
      }
      
      final duration = DateTime.now().difference(startTime);
      debugPrint('익명 로그인 처리 완료 (소요시간: ${duration.inMilliseconds}ms)');
      
      return userCredential.user;
    } catch (e) {
      debugPrint('익명 로그인 중 오류 발생: $e');
      return null;
    }
  }

  // 구글 로그인
  Future<User?> signInWithGoogle() async {
    final startTime = DateTime.now();
    debugPrint('구글 로그인 시작 (${startTime.toString()})');
    
    try {
      // Firebase 초기화 대기
      final firebaseReady = await isFirebaseInitialized;
      if (!firebaseReady) {
        debugPrint('Firebase 초기화 실패로 구글 로그인 불가');
        return null;
      }

      // 인증 서비스를 통해 Google 로그인
      debugPrint('구글 로그인 요청 중...');
      final user = await authService.signInWithGoogle();
      
      if (user != null) {
        debugPrint('구글 로그인 성공: ${user.uid}');
        
        // 새 사용자 계정 확인 및 온보딩 설정
        await handleUserLogin(user);
      } else {
        debugPrint('구글 로그인 실패: 사용자 객체가 null임');
      }
      
      final duration = DateTime.now().difference(startTime);
      debugPrint('구글 로그인 처리 완료 (소요시간: ${duration.inMilliseconds}ms)');
      
      return user;
    } catch (e) {
      debugPrint('구글 로그인 중 오류 발생: $e');
      return null;
    }
  }

  // Apple 로그인
  Future<User?> signInWithApple() async {
    final startTime = DateTime.now();
    debugPrint('Apple 로그인 시작 (${startTime.toString()})');
    
    try {
      // Firebase 초기화 대기
      final firebaseReady = await isFirebaseInitialized;
      if (!firebaseReady) {
        debugPrint('Firebase 초기화 실패로 Apple 로그인 불가');
        return null;
      }

      // 인증 서비스를 통해 Apple 로그인
      debugPrint('Apple 로그인 요청 중...');
      final user = await authService.signInWithApple();
      
      if (user != null) {
        debugPrint('Apple 로그인 성공: ${user.uid}');
        
        // 새 사용자 계정 확인 및 온보딩 설정
        await handleUserLogin(user);
      } else {
        debugPrint('Apple 로그인 실패: 사용자 객체가 null임');
      }
      
      final duration = DateTime.now().difference(startTime);
      debugPrint('Apple 로그인 처리 완료 (소요시간: ${duration.inMilliseconds}ms)');
      
      return user;
    } catch (e) {
      debugPrint('Apple 로그인 중 오류 발생: $e');
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
      // 로그아웃 전 마지막 사용자 정보 기록
      final currentUser = FirebaseAuth.instance.currentUser;
      final wasAnonymous = currentUser?.isAnonymous ?? false;
      final userId = currentUser?.uid;
      
      debugPrint('로그아웃 시작 (UserId: $userId, 익명 여부: $wasAnonymous)');
      
      // 로그아웃 처리
      await authService.signOut();
      
      // 로그아웃 이후 인증 상태 재설정
      _userAuthenticationChecked = Completer<bool>();
      _userAuthenticationChecked.complete(false); // 인증되지 않은 상태로 설정
      
      debugPrint('로그아웃 성공 - 인증 상태 초기화됨');
      
      // 사용자 기본 설정 초기화 (선택적)
      await _resetUserPreferences();
    } catch (e) {
      debugPrint('로그아웃 실패: $e');
      _authError = '로그아웃 중 오류가 발생했습니다: $e';
    }
  }
  
  // 사용자 기본 설정 초기화
  Future<void> _resetUserPreferences() async {
    try {
      final userPreferences = UserPreferencesService();
      await userPreferences.setOnboardingCompleted(false);
      debugPrint('사용자 기본 설정 초기화 완료');
    } catch (e) {
      debugPrint('사용자 기본 설정 초기화 실패: $e');
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

  // 사용자 로그인 처리 및 온보딩 상태 관리
  Future<void> handleUserLogin(User user) async {
    debugPrint('새 로그인 사용자 처리 중: ${user.uid}');
    
    try {
      // Firestore에서 사용자 데이터 확인
      final firestore = FirebaseFirestore.instance;
      final userDoc = await firestore.collection('users').doc(user.uid).get();
      
      // 계정 첫 로그인 여부 확인
      final isNewUser = !userDoc.exists || userDoc.data()?['onboardingCompleted'] != true;
      
      if (isNewUser) {
        debugPrint('새 사용자 계정 확인: 온보딩 상태 초기화');
        
        // 온보딩 상태 초기화 (새 계정이면 온보딩 표시)
        final UserPreferencesService prefs = UserPreferencesService();
        await prefs.setOnboardingCompleted(false);
        
        // Firestore에 사용자 정보 업데이트
        await firestore.collection('users').doc(user.uid).set({
          'isNew': true,
          'onboardingCompleted': false,
          'lastLogin': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        debugPrint('기존 사용자 계정 확인: 마지막 로그인 시간 업데이트');
        
        // 기존 사용자 마지막 로그인 시간 업데이트
        await firestore.collection('users').doc(user.uid).update({
          'lastLogin': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('사용자 로그인 처리 중 오류: $e');
    }
  }
}
