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
    if (_firebaseInitialized.isCompleted) {
      // 이미 초기화가 시작된 경우 결과 반환
      return _firebaseInitialized.future;
    }

    try {
      // Firebase 초기화
      await Firebase.initializeApp(options: options);
      
      // Firestore 설정 - 최적화를 위한 캐시 설정
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true, // 오프라인 지원을 위한 캐시 활성화
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED, // 캐시 크기 최적화
      );
      
      // 초기화 완료 표시
      await markFirebaseInitialized(true);
      
      // 사용자 인증 상태 확인 (별도의 비동기 작업으로 분리)
      _checkAuthenticationState();
      
      return true;
    } catch (e) {
      // 초기화 실패 기록
      _firebaseError = '앱 초기화 중 오류가 발생했습니다: $e';
      await markFirebaseInitialized(false);
      return false;
    }
  }
  
  // Firebase가 이미 초기화되었음을 표시하는 메서드
  Future<void> markFirebaseInitialized(bool success) async {
    // 중복 호출 방지
    if (_firebaseInitialized.isCompleted) return;
    
    _firebaseInitialized.complete(success);
  }

  // 사용자 인증 상태 확인 메서드
  Future<void> _checkAuthenticationState() async {
    try {
      // 이미 완료된 경우 스킵
      if (_userAuthenticationChecked.isCompleted) {
        return;
      }

      // Firebase Auth 인스턴스 가져오기
      final auth = FirebaseAuth.instance;

      // 현재 사용자 확인 (null이면 로그인되지 않은 상태)
      final currentUser = auth.currentUser;

      if (currentUser != null) {
        // 사용자 정보 확인 
        _saveLastLoginActivity(currentUser);
      }

      // 인증 상태 확인 완료 (로그인 화면으로 이동할 수 있도록)
      _userAuthenticationChecked.complete(true);
    } catch (e) {
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
      // 이전과 동일하게 Future를 완료하되, 익명 로그인을 하지 않고 로그인 화면으로 전환하기 위해
      // 인증 실패로 설정
      _userAuthenticationChecked = Completer<bool>();
      _userAuthenticationChecked.complete(true); // 인증 체크는 완료되었지만 로그인은 되지 않은 상태
      
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
  /*
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
  */
  
  // 새 초기화 재시도 메서드 (로그아웃 후 사용)
  void retryInitialization({required FirebaseOptions options}) {
    if (isFirebaseInitializing) return;

    // 인증 상태만 초기화 (Firebase는 이미 초기화됨)
    if (_userAuthenticationChecked.isCompleted) {
      _userAuthenticationChecked = Completer<bool>();
    }
    _authError = null;
    
    // Firebase 초기화 상태는 유지
    debugPrint('인증 상태 초기화 완료, 로그인 화면으로 이동 준비됨');
    
    // 사용자 인증 상태 확인 (로그인 화면에서 적절히 처리할 수 있게 함)
    _userAuthenticationChecked.complete(true);
  }

  // 사용자 로그인 처리 및 온보딩 상태 관리
  Future<void> handleUserLogin(User user) async {
    debugPrint('사용자 로그인 처리 시작: ${user.uid} (익명: ${user.isAnonymous})');
    
    try {
      final firestore = FirebaseFirestore.instance;
      final userPrefs = UserPreferencesService();
      
      // Firestore에서 사용자 데이터 확인
      final userDoc = await firestore.collection('users').doc(user.uid).get();
      
      // 사용자의 노트 데이터 확인 - userId 필드로 필터링
      final notesQuery = await firestore
          .collection('notes')
          .where('userId', isEqualTo: user.uid)
          .limit(1)
          .get();
      
      final hasNotes = notesQuery.docs.isNotEmpty;
      debugPrint('사용자 노트 데이터 확인: ${hasNotes ? "있음" : "없음"}');
      
      // 계정 첫 로그인 여부 확인 - 완전히 새로운 사용자인 경우
      final isNewUser = !userDoc.exists;
      
      if (isNewUser) {
        debugPrint('새 사용자 계정: 온보딩 표시');
        
        // 온보딩 상태 설정 - 새 계정이면 온보딩 필요
        await userPrefs.setOnboardingCompleted(false);
        
        // Firestore에 사용자 정보 생성
        await firestore.collection('users').doc(user.uid).set({
          'isNew': true,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
          'onboardingCompleted': false,
          'isAnonymous': user.isAnonymous,
          'email': user.email,
          'displayName': user.displayName,
        }, SetOptions(merge: true));
        
      } else {
        // 기존 사용자인 경우 - 노트 데이터 기반으로 온보딩 결정
        if (!hasNotes) {
          debugPrint('기존 사용자지만 노트 데이터 없음: 온보딩 표시');
          
          // 노트가 없으면 온보딩 표시
          await userPrefs.setOnboardingCompleted(false);
          
          // Firestore 사용자 상태 업데이트
          await firestore.collection('users').doc(user.uid).update({
            'onboardingCompleted': false,
            'lastLogin': FieldValue.serverTimestamp(),
          });
        } else {
          debugPrint('기존 사용자 & 노트 데이터 있음: 온보딩 건너뛰기');
          
          // 노트가 있으면 온보딩 건너뛰기
          await userPrefs.setOnboardingCompleted(true);
          
          // Firestore 사용자 상태 업데이트
          await firestore.collection('users').doc(user.uid).update({
            'onboardingCompleted': true,
            'lastLogin': FieldValue.serverTimestamp(),
          });
        }
      }
      
      debugPrint('사용자 로그인 처리 완료: ${user.uid}');
    } catch (e) {
      debugPrint('사용자 로그인 처리 중 오류: $e');
      // 오류 발생 시 기본값으로 온보딩 표시
      try {
        final userPrefs = UserPreferencesService();
        await userPrefs.setOnboardingCompleted(false);
      } catch (e2) {
        debugPrint('기본 온보딩 상태 설정 중 오류: $e2');
      }
    }
  }
}
