import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'unified_cache_service.dart';
import 'auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_preferences_service.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import '../firebase_options.dart';

/// 앱 초기화를 관리하는 서비스
///
/// Firebase 초기화 및 사용자 인증을 비동기적으로 처리하여
/// 앱 시작 시간을 단축합니다.
class InitializationService {
  // 초기화 상태를 추적하는 컨트롤러
  final Completer<bool> _firebaseInitialized = Completer<bool>();

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
  bool get isFirebaseInitializing => !_firebaseInitialized.isCompleted;

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
    debugPrint('인증 오류 설정됨: $error');
  }

  // 사용자 인증 상태 getter
  bool get isUserAuthenticated => FirebaseAuth.instance.currentUser != null;

  // 인증 상태 변경 스트림
  Stream<User?> get authStateChanges {
    debugPrint('authStateChanges 스트림 요청됨');
    
    return _firebaseAuth.authStateChanges().map((user) {
      debugPrint('Firebase 인증 상태 변경 감지: ${user != null ? '로그인' : '로그아웃'}');
      return user;
    });
  }

  // GoogleSignIn 인스턴스 설정 (앱 이름 업데이트)
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    // clientId는 iOS에서만 필요하며, Android는 google-services.json에서 설정됨
    clientId: Platform.isIOS ? DefaultFirebaseOptions.currentPlatform.iosClientId : null,
    scopes: ['email', 'profile'],
  );

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  InitializationService();

  // 사용자 인증 상태 확인 메서드
  Future<Map<String, dynamic>> checkLoginState() async {
    try {
      debugPrint('로그인 상태 확인 시작');
      // 로컬 저장소에서 로그인 기록 확인
      final prefs = await SharedPreferences.getInstance();
      bool hasLoginHistory = prefs.getBool('login_history') ?? false;
      bool hasShownTooltip = prefs.getBool('hasShownTooltip') ?? false;
      
      // Firebase 인증 상태 확인
      final User? currentUser = _firebaseAuth.currentUser;
      
      // 추가: 사용자 계정 유효성 검증
      bool isValidUser = false;
      if (currentUser != null) {
        try {
          // 사용자 ID가 유효한지 확인 (Firestore에 실제 존재하는지)
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get();
          
          isValidUser = userDoc.exists;
          
          if (!isValidUser) {
            debugPrint('Firebase에 사용자가 존재하지 않음 (계정 탈퇴 가능성): ${currentUser.uid}');
            
            // 사용자가 존재하지 않으면 로컬 데이터 모두 초기화 (탈퇴했을 가능성)
            await _cleanupLocalDataAfterDeletion();
            
            // 강제 로그아웃 (Firebase에도 사용자가 없음)
            await _firebaseAuth.signOut();
          } else {
            debugPrint('유효한 사용자 확인됨: ${currentUser.uid}');
          }
        } catch (e) {
          debugPrint('사용자 유효성 검증 중 오류: $e');
          // 오류 발생 시 기본값으로 처리 (혹시 모를 오류를 피하기 위해)
          isValidUser = true;
        }
      }
      
      // 온보딩 완료 여부 확인
      // '로그인' 상태와 '온보딩 완료' 상태는 별개로 처리
      final userPrefs = UserPreferencesService();
      final isOnboardingCompleted = await userPrefs.getOnboardingCompleted();
      
      // 결과 생성
      final result = {
        'isLoggedIn': currentUser != null && isValidUser,
        'hasLoginHistory': hasLoginHistory,
        'isOnboardingCompleted': isOnboardingCompleted,
        'isFirstEntry': !hasShownTooltip,
      };

      debugPrint('로그인 상태 확인 결과: $result');
      return result;
    } catch (e) {
      debugPrint('로그인 상태 확인 중 오류 발생: $e');
      return {
        'isLoggedIn': false,
        'hasLoginHistory': false,
        'isOnboardingCompleted': false,
        'isFirstEntry': true,
      };
    }
  }
  
  /// 탈퇴 후 로컬 데이터 정리 (계정이 삭제된 경우 호출)
  Future<void> _cleanupLocalDataAfterDeletion() async {
    try {
      debugPrint('탈퇴 감지: 로컬 데이터 정리 시작');
      final userPrefs = UserPreferencesService();
      final cacheService = UnifiedCacheService();
      
      // 캐시 초기화
      await cacheService.clearAllCache();
      
      // 사용자 기본 설정 초기화
      await userPrefs.clearAllUserPreferences();
      
      // SharedPreferences에서 모든 사용자 관련 정보 삭제
      final prefs = await SharedPreferences.getInstance();
      
      // 인증 관련 키 삭제
      await prefs.remove('current_user_id');
      await prefs.remove('last_signin_provider');
      await prefs.remove('has_multiple_accounts');
      await prefs.remove('cache_current_user_id');
      
      // 로그인 기록 관련 키 삭제
      await prefs.remove('login_history');
      await prefs.remove('has_shown_onboarding');
      await prefs.remove('hasShownTooltip');
      await prefs.remove('onboarding_completed');
      
      debugPrint('탈퇴 후 로컬 데이터 정리 완료');
    } catch (e) {
      debugPrint('탈퇴 후 로컬 데이터 정리 중 오류: $e');
    }
  }

  // 사용자 로그인 처리 및 온보딩 상태 관리
  Future<Map<String, dynamic>> handleUserLogin(User user) async {
    try {
      debugPrint('사용자 로그인 처리 시작: ${user.uid} (${DateTime.now()})');
      final firestore = FirebaseFirestore.instance;
      final userPrefs = UserPreferencesService();
      final cacheService = UnifiedCacheService();
      
      // 캐시 서비스에 현재 사용자 ID 설정
      await cacheService.setCurrentUserId(user.uid);
      
      // Firestore에서 사용자 데이터 확인
      final userDoc = await firestore.collection('users').doc(user.uid).get();
      final isNewUser = !userDoc.exists;
      
      // 사용자 정보 저장 (새 사용자 여부에 따라 다른 처리)
      await _saveUserToFirestore(user, isNewUser: isNewUser);
      
      // 로그인 기록 저장
      await userPrefs.saveLoginHistory();
      
      // 결과 객체 초기화
      final result = {
        'isLoggedIn': true,
        'isNewUser': isNewUser,
        'hasLoginHistory': true,
        'isOnboardingCompleted': false,
        'isFirstEntry': true,
      };
      
      // 온보딩 상태 확인 및 저장
      if (!isNewUser) {
        // 기존 사용자
        final userData = userDoc.data() as Map<String, dynamic>?;
        final onboardingCompleted = userData?['onboardingCompleted'] ?? false;
        
        // 온보딩 상태 로컬에 저장
        await userPrefs.setOnboardingCompleted(onboardingCompleted);
        result['isOnboardingCompleted'] = onboardingCompleted;
        
        // 툴팁 상태 확인
        final prefs = await SharedPreferences.getInstance();
        final hasShownTooltip = prefs.getBool('hasShownTooltip') ?? false;
        result['isFirstEntry'] = !hasShownTooltip;
        
        debugPrint('기존 사용자 로그인: 온보딩 상태=$onboardingCompleted, 툴팁 표시 여부=${!hasShownTooltip}');
        
        // 온보딩이 완료된 경우에만 추가 설정 로드
        if (onboardingCompleted && userData != null) {
          await _loadUserSettings(userData, userPrefs);
        }
      } else {
        // 새 사용자는 온보딩 미완료 상태로 설정
        await userPrefs.setOnboardingCompleted(false);
        debugPrint('새 사용자 로그인: 온보딩 필요');
      }
      
      return result;
    } catch (e) {
      debugPrint('사용자 로그인 처리 중 오류 발생: $e');
      return {
        'isLoggedIn': true,
        'error': e.toString(),
        'isOnboardingCompleted': false,
        'isFirstEntry': true,
      };
    }
  }
  
  // 사용자 설정 로드 (재사용을 위한 별도 메서드)
  Future<void> _loadUserSettings(Map<String, dynamic> userData, UserPreferencesService userPrefs) async {
    try {
      if (userData['userName'] != null) {
        await userPrefs.setUserName(userData['userName']);
      }
      if (userData['learningPurpose'] != null) {
        await userPrefs.setLearningPurpose(userData['learningPurpose']);
      }
      if (userData['translationMode'] != null) {
        final useSegmentMode = userData['translationMode'] == 'segment';
        await userPrefs.setUseSegmentMode(useSegmentMode);
      }
      if (userData['defaultNoteSpace'] != null) {
        await userPrefs.setDefaultNoteSpace(userData['defaultNoteSpace']);
        await userPrefs.addNoteSpace(userData['defaultNoteSpace']);
      }
      
      // 로컬 Storage에 현재 사용자 ID 저장 (앱 재시작 시 빠른 검증용)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_user_id', userData['uid']);
      
      debugPrint('사용자 설정 로드 완료');
    } catch (e) {
      debugPrint('사용자 설정 로드 중 오류 발생: $e');
    }
  }

  // 로그아웃
  Future<void> signOut() async {
    try {
      debugPrint('철저한 로그아웃 처리 시작...');
      final userPrefs = UserPreferencesService();
      final cacheService = UnifiedCacheService();
      
      // 현재 사용자 ID 저장 (캐시 삭제용)
      final currentUser = FirebaseAuth.instance.currentUser;
      final userId = currentUser?.uid;
      
      // 1. 모든 캐시 데이터 초기화 (사용자별)
      if (userId != null && userId.isNotEmpty) {
        // 사용자 ID 기반으로 해당 사용자의 캐시만 삭제
        await cacheService.clearAllCache();
        debugPrint('현재 사용자($userId)의 캐시 데이터 삭제 완료');
      } else {
        // 사용자 ID를 알 수 없는 경우 전체 캐시 삭제
        await cacheService.clearAllCache();
        debugPrint('알 수 없는 사용자의 캐시 데이터 삭제 완료');
      }
      
      // 2. 사용자 기본 설정 초기화
      await userPrefs.clearAllUserPreferences();
      debugPrint('사용자 설정 데이터 초기화 완료');
      
      // 3. SharedPreferences에서 사용자 관련 정보 삭제
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('current_user_id');
      await prefs.remove('last_signin_provider');
      await prefs.remove('has_multiple_accounts');
      await prefs.remove('cache_current_user_id'); // 캐시 서비스에서 사용하는 사용자 ID
      debugPrint('SharedPreferences 사용자 정보 삭제 완료');
      
      // 4. Google 로그인 상태 확인 및 로그아웃
      try {
        if (await _googleSignIn.isSignedIn()) {
          await _googleSignIn.disconnect(); // 모든 계정 연결 해제 (단순 signOut보다 더 철저함)
          await _googleSignIn.signOut();
          debugPrint('Google 로그인 연결 해제 및 로그아웃 완료');
        }
      } catch (e) {
        debugPrint('Google 로그아웃 중 오류 (무시됨): $e');
      }
      
      // 5. Firebase 자체 로그아웃
      await _firebaseAuth.signOut();
      debugPrint('Firebase 로그아웃 완료');
      
      // 6. 추가: Apple 로그인 토큰 무효화 시도 (시스템 수준에서는 불가능)
      // Apple은 앱 수준에서 완전한 로그아웃이 어렵기 때문에 로컬 정보만 제거
      
      // 7. 로그인 기록 초기화 (다시 로그인할 때 새 계정으로 인식하도록)
      await userPrefs.clearLoginHistory();
      debugPrint('로그인 기록 초기화 완료');
      
      // 8. 메모리 내 상태 초기화
      _authError = null;
      debugPrint('로그아웃 처리 완전히 완료됨');
    } catch (e) {
      debugPrint('로그아웃 중 오류 발생: $e');
      // 오류가 발생해도 Firebase 로그아웃은 시도
      try {
        await _firebaseAuth.signOut();
      } catch (_) {}
      rethrow;
    }
  }

  // 마지막 로그인 활동 저장
  Future<void> _saveLastLoginActivity(User user) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final userRef = firestore.collection('users').doc(user.uid);
      
      // 문서가 존재하는지 확인
      final userDoc = await userRef.get();
      
      if (userDoc.exists) {
        // 문서가 있으면 업데이트
        await userRef.update({
          'lastActivity': FieldValue.serverTimestamp(),
          'lastAppVersion': '1.0.0', // 앱 버전 정보
        });
      } else {
        // 문서가 없으면 새로 생성
        await userRef.set({
          'uid': user.uid,
          'email': user.email,
          'displayName': user.displayName,
          'photoURL': user.photoURL,
          'lastActivity': FieldValue.serverTimestamp(),
          'lastAppVersion': '1.0.0',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      
      debugPrint('사용자 마지막 활동 정보 업데이트: ${user.uid}');
    } catch (e) {
      debugPrint('사용자 활동 정보 업데이트 실패: $e');
      // 오류가 발생해도 앱 실행에 영향 없음
    }
  }

  // 사용자 정보를 Firestore에 저장하는 메서드
  Future<void> _saveUserToFirestore(User user, {bool isNewUser = false}) async {
    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      
      final baseData = {
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        'photoURL': user.photoURL,
        'lastSignIn': FieldValue.serverTimestamp(),
      };

      if (isNewUser) {
        // 새 사용자인 경우 추가 데이터
        final newUserData = {
          ...baseData,
          'isNew': true,
          'createdAt': FieldValue.serverTimestamp(),
          'onboardingCompleted': false,
          'hasOnboarded': false,
        };
        
        await userRef.set(newUserData, SetOptions(merge: true));
      } else {
        // 기존 사용자인 경우 마지막 로그인만 업데이트
        await userRef.update(baseData);
      }
      
      debugPrint('사용자 정보가 Firestore에 저장되었습니다: ${user.uid} (새 사용자: $isNewUser)');
    } catch (e) {
      debugPrint('사용자 정보 저장 오류: $e');
      rethrow;
    }
  }

  // Firebase 초기화 상태 설정 (백그라운드 초기화 완료 시 호출)
  Future<void> markFirebaseInitialized(bool success) async {
    if (!_firebaseInitialized.isCompleted) {
      try {
        // 인증 상태 확인
        await checkLoginState();
        
        _firebaseInitialized.complete(success);
        debugPrint('Firebase 초기화 상태 설정: $success');
      } catch (e) {
        _firebaseError = '인증 상태 확인 중 오류가 발생했습니다: $e';
        _firebaseInitialized.complete(false);
        debugPrint('인증 상태 확인 오류: $e');
      }
    }
  }

  /// 앱 초기화 메서드
  /// Firebase를 초기화하고 사용자 인증 상태를 확인합니다.
  Future<bool> initializeApp() async {
    try {
      // 초기화 시작 로그
      debugPrint('앱 초기화 시작 (${_initStartTime.toIso8601String()})');

      // Firebase Core 초기화
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      
      // 인증 상태 확인
      await checkLoginState();
      
      // 초기화 완료 시간 및 소요 시간 계산
      final initEndTime = DateTime.now();
      final duration = initEndTime.difference(_initStartTime);
      
      debugPrint('앱 초기화 완료 (소요 시간: ${duration.inMilliseconds}ms)');
      
      // Firebase 초기화 상태가 아직 완료되지 않은 경우에만 완료 처리
      if (!_firebaseInitialized.isCompleted) {
        _firebaseInitialized.complete(true);
      }
      
      return true;
    } catch (e) {
      // 오류 발생 시 처리
      setFirebaseError('Firebase 초기화 중 오류가 발생했습니다: $e');
      debugPrint('Firebase 초기화 오류: $e');
      
      // 초기화 실패 반환
      return false;
    }
  }

  // Google 로그인
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Firebase가 초기화되었는지 확인
      if (!_firebaseInitialized.isCompleted && Firebase.apps.isEmpty) {
        bool initialized = await initializeApp();
        if (!initialized) {
          throw Exception('Firebase를 초기화할 수 없습니다.');
        }
      }

      // Google 로그인 UI 표시
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      // 로그인 취소된 경우
      if (googleUser == null) {
        debugPrint('Google 로그인 취소됨');
        return null;
      }

      // 인증 정보 가져오기
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // 인증 정보로 Firebase 인증 정보 생성
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Firebase로 로그인
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);

      // 인증 상태 확인
      await checkLoginState();
      
      debugPrint('Google 로그인 완료: ${userCredential.user?.uid}');
      return userCredential;
    } catch (e) {
      debugPrint('Google 로그인 오류: $e');
      setAuthError('Google 로그인 중 오류가 발생했습니다: $e');
      return null;
    }
  }

  // Apple 로그인
  Future<UserCredential?> signInWithApple() async {
    try {
      debugPrint('Apple 로그인 시작...');
      
      // Firebase가 초기화되었는지 확인
      if (!_firebaseInitialized.isCompleted && Firebase.apps.isEmpty) {
        bool initialized = await initializeApp();
        if (!initialized) {
          throw Exception('Firebase를 초기화할 수 없습니다.');
        }
      }

      // AuthService의 signInWithApple 메서드 사용
      final user = await authService.signInWithApple();
      
      if (user == null) {
        debugPrint('Apple 로그인 실패: 사용자 정보를 가져오지 못했습니다.');
        return null;
      }
      
      debugPrint('Apple 로그인 성공: ${user.uid}');
      
      // 인증 상태 확인
      await checkLoginState();

      // UserCredential로 직접 변환할 수 없으므로 null 반환
      // 이미 authStateChanges에서 로그인 이벤트가 발생하므로 실제로는 문제 없음
      return null;
    } catch (e) {
      debugPrint('Apple 로그인 오류 상세: $e');
      setAuthError('Apple 로그인 중 오류가 발생했습니다: $e');
      return null;
    }
  }

  // 현재 로그인된 사용자 가져오기
  User? getCurrentUser() {
    return FirebaseAuth.instance.currentUser;
  }

  // 초기화 재시도 메서드
  Future<void> retryInitialization({required FirebaseOptions options}) async {
    try {
      final startTime = DateTime.now();
      debugPrint('Firebase 초기화 재시도 시작 (${startTime.toString()})');
      
      // 이미 Firebase가 초기화되었는지 확인
      if (Firebase.apps.isNotEmpty) {
        debugPrint('Firebase가 이미 초기화되어 있음, 추가 초기화 생략');
        
        // 앱 상태만 확인
        await checkLoginState();
        
        // 초기화 완료 설정
        if (!_firebaseInitialized.isCompleted) {
          _firebaseInitialized.complete(true);
        }
        
        final duration = DateTime.now().difference(startTime);
        debugPrint('Firebase 상태 확인 완료 (소요시간: ${duration.inMilliseconds}ms)');
        
        return;
      }
      
      // Firebase 초기화 (아직 초기화되지 않은 경우에만)
      await Firebase.initializeApp(options: options);
      
      // 앱 상태 확인
      await checkLoginState();
      
      // 초기화 완료 설정
      if (!_firebaseInitialized.isCompleted) {
        _firebaseInitialized.complete(true);
      }
      
      final duration = DateTime.now().difference(startTime);
      debugPrint('Firebase 초기화 재시도 완료 (소요시간: ${duration.inMilliseconds}ms)');
      
      return;
    } catch (e) {
      debugPrint('Firebase 초기화 재시도 오류: $e');
      _firebaseError = '앱 초기화 재시도 중 오류가 발생했습니다: $e';
      // 초기화 실패 설정
      if (!_firebaseInitialized.isCompleted) {
        _firebaseInitialized.complete(false);
      }
      rethrow;
    }
  }

  /// 계정 탈퇴 처리 (사용자 데이터 완전 초기화)
  Future<Map<String, dynamic>> handleAccountDeletion({
    String? password,
    String? idToken,
    AuthCredential? credential
  }) async {
    try {
      debugPrint('사용자 계정 탈퇴 처리 시작...');
      final userPrefs = UserPreferencesService();
      final cacheService = UnifiedCacheService();
      
      // 현재 사용자 확인
      final currentUser = _firebaseAuth.currentUser;
      if (currentUser == null) {
        debugPrint('탈퇴 처리 실패: 로그인된 사용자가 없습니다.');
        return {
          'success': false,
          'requiresReauth': false,
          'message': '로그인된 사용자가 없습니다.'
        };
      }
      
      final userId = currentUser.uid;
      
      // 1. 재인증 수행 (필요한 경우)
      try {
        // 재인증이 필요한지 테스트 (간단한 작업 시도)
        await currentUser.getIdToken(true);
        
        // 재인증 시도 (자격 증명이 제공된 경우)
        if (credential != null) {
          await currentUser.reauthenticateWithCredential(credential);
          debugPrint('사용자 재인증 성공');
        } else if (password != null && currentUser.email != null) {
          // 이메일/비밀번호 사용자인 경우 비밀번호로 재인증
          final emailCredential = EmailAuthProvider.credential(
            email: currentUser.email!,
            password: password
          );
          await currentUser.reauthenticateWithCredential(emailCredential);
          debugPrint('이메일/비밀번호로 사용자 재인증 성공');
        } else if (idToken != null) {
          // 소셜 로그인의 경우 idToken으로 재인증
          final providerData = currentUser.providerData.firstOrNull;
          if (providerData != null) {
            final provider = providerData.providerId;
            AuthCredential socialCredential;
            
            if (provider.contains('google')) {
              socialCredential = GoogleAuthProvider.credential(idToken: idToken);
            } else if (provider.contains('apple')) {
              socialCredential = OAuthProvider('apple.com').credential(
                idToken: idToken
              );
            } else {
              throw Exception('지원되지 않는 인증 제공자입니다: $provider');
            }
            
            await currentUser.reauthenticateWithCredential(socialCredential);
            debugPrint('소셜 로그인으로 사용자 재인증 성공');
          }
        }
      } catch (e) {
        // 재인증 필요 여부 확인
        if (e is FirebaseAuthException && e.code == 'requires-recent-login') {
          debugPrint('계정 삭제를 위해 재인증이 필요합니다');
          
          // 사용자가 사용한 로그인 방식 확인
          final providerData = currentUser.providerData.firstOrNull;
          final provider = providerData?.providerId ?? 'unknown';
          
          return {
            'success': false,
            'requiresReauth': true,
            'message': '보안을 위해 재로그인이 필요합니다.',
            'provider': provider
          };
        } else {
          debugPrint('계정 삭제 전 재인증 검사 중 오류: $e');
        }
      }
      
      // 2. Firebase Auth에서 사용자 계정 삭제
      try {
        // 사용자 정보 보존 (Firestore 데이터 삭제용)
        final deletedUserEmail = currentUser.email;
        final deletedUserDisplayName = currentUser.displayName;
        
        // Firebase Auth에서 계정 삭제
        await currentUser.delete();
        debugPrint('Firebase Auth에서 사용자 계정 삭제 완료');
        
        // Firestore에서 사용자 데이터 삭제 (백그라운드 작업)
        _deleteUserDataFromFirestore(userId, deletedUserEmail, deletedUserDisplayName);
      } catch (e) {
        // 인증 재인증이 필요한 경우 등 처리 필요
        debugPrint('사용자 계정 삭제 중 오류: $e');
        
        if (e is FirebaseAuthException && e.code == 'requires-recent-login') {
          return {
            'success': false,
            'requiresReauth': true,
            'message': '보안을 위해 재로그인이 필요합니다.'
          };
        }
        
        throw Exception('계정 삭제에 실패했습니다: $e');
      }
      
      // 3. 모든 로컬 데이터 완전 초기화 (로그아웃보다 더 철저하게)
      // 캐시 데이터 삭제
      await cacheService.clearAllCache();
      
      // 사용자 설정 초기화
      await userPrefs.clearAllUserPreferences();
      
      // SharedPreferences에서 모든 사용자 관련 정보 삭제
      final prefs = await SharedPreferences.getInstance();
      
      // 인증 관련 키 삭제
      await prefs.remove('current_user_id');
      await prefs.remove('last_signin_provider');
      await prefs.remove('has_multiple_accounts');
      await prefs.remove('cache_current_user_id');
      
      // 로그인 기록 관련 키 삭제
      await prefs.remove('login_history');
      await prefs.remove('has_shown_onboarding');
      await prefs.remove('hasShownTooltip');
      await prefs.remove('onboarding_completed');
      
      // 사용자 ID로 시작하는 모든 키 삭제 (철저하게)
      final allKeys = prefs.getKeys();
      for (final key in allKeys) {
        if (key.startsWith('${userId}_') || 
            key.contains('_$userId') ||
            key.contains('auth_') ||
            key.contains('login_') ||
            key.contains('user_')) {
          await prefs.remove(key);
        }
      }
      
      // 3. Google 로그인 연결 해제 (있는 경우)
      try {
        if (await _googleSignIn.isSignedIn()) {
          await _googleSignIn.disconnect();
          await _googleSignIn.signOut();
        }
      } catch (e) {
        debugPrint('Google 계정 연결 해제 중 오류 (무시됨): $e');
      }
      
      debugPrint('계정 탈퇴 및 모든 로컬 데이터 초기화 완료');
      return {
        'success': true,
        'message': '계정이 성공적으로 삭제되었습니다.',
      };
    } catch (e) {
      debugPrint('계정 탈퇴 처리 중 오류 발생: $e');
      return {
        'success': false,
        'requiresReauth': false,
        'message': '계정 삭제 중 오류가 발생했습니다: $e'
      };
    }
  }
  
  /// Firestore에서 사용자 데이터 삭제 (백그라운드 작업)
  Future<void> _deleteUserDataFromFirestore(
    String userId, 
    String? userEmail,
    String? displayName
  ) async {
    try {
      debugPrint('Firestore에서 사용자 데이터 삭제 시작: $userId');
      final firestore = FirebaseFirestore.instance;
      
      // 1. 노트 문서 삭제
      final notesQuery = await firestore.collection('notes')
          .where('userId', isEqualTo: userId)
          .get();
          
      for (final doc in notesQuery.docs) {
        await firestore.collection('notes').doc(doc.id).delete();
      }
      debugPrint('사용자 노트 ${notesQuery.docs.length}개 삭제 완료');
      
      // 2. 페이지 문서 삭제
      final pagesQuery = await firestore.collection('pages')
          .where('userId', isEqualTo: userId)
          .get();
          
      for (final doc in pagesQuery.docs) {
        await firestore.collection('pages').doc(doc.id).delete();
      }
      debugPrint('사용자 페이지 ${pagesQuery.docs.length}개 삭제 완료');
      
      // 3. 탈퇴 사용자 목록에 추가 (재가입 감지용)
      await firestore.collection('deleted_users').doc(userId).set({
        'userId': userId,
        'email': userEmail,
        'displayName': displayName,
        'deletedAt': FieldValue.serverTimestamp(),
      });
      
      // 4. 마지막으로 사용자 문서 삭제
      await firestore.collection('users').doc(userId).delete();
      
      debugPrint('Firestore에서 사용자 데이터 삭제 완료');
    } catch (e) {
      debugPrint('Firestore 사용자 데이터 삭제 중 오류 (백그라운드): $e');
      // 백그라운드 작업이므로 오류가 발생해도 계속 진행
    }
  }
}
