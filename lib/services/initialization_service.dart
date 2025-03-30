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
      debugPrint('로그인 상태 확인 시작 (${DateTime.now()})');
      final userPrefs = UserPreferencesService();
      
      // Firebase Auth 인스턴스 가져오기
      final auth = FirebaseAuth.instance;
      
      // 현재 사용자 확인 (null이면 로그인되지 않은 상태)
      final currentUser = auth.currentUser;
      
      // 결과 객체 초기화
      final result = {
        'isLoggedIn': currentUser != null,
        'hasLoginHistory': false,
        'isOnboardingCompleted': false,
        'isFirstEntry': true,
        'user': currentUser,
      };
      
      // 1. 로그인 상태 확인
      if (currentUser == null) {
        debugPrint('로그인 상태 확인 결과: 로그인되지 않음');
        return result; // 로그인되지 않음 - 로그인 화면으로 이동
      }
      
      // 2. 로그인 기록 여부 확인
      final hasLoginHistory = await userPrefs.hasLoginHistory();
      result['hasLoginHistory'] = hasLoginHistory;
      
      if (!hasLoginHistory) {
        // 로그인 기록 저장
        await userPrefs.saveLoginHistory();
        debugPrint('로그인 상태 확인 결과: 로그인됨, 이전 로그인 기록 없음');
        return result; // 이전 로그인 기록 없음 - 온보딩 화면으로 이동
      }
      
      // 3. 온보딩 완료 여부 확인
      final isOnboardingCompleted = await userPrefs.getOnboardingCompleted();
      result['isOnboardingCompleted'] = isOnboardingCompleted;
      
      if (!isOnboardingCompleted) {
        debugPrint('로그인 상태 확인 결과: 로그인됨, 로그인 기록 있음, 온보딩 미완료');
        return result; // 온보딩 미완료 - 온보딩 화면으로 이동
      }
      
      // 4. 첫 진입 여부 확인 (툴팁 표시 여부)
      final prefs = await SharedPreferences.getInstance();
      final hasShownTooltip = prefs.getBool('hasShownTooltip') ?? false;
      result['isFirstEntry'] = !hasShownTooltip;
      
      // 로그인 활동 정보 업데이트
      await _saveLastLoginActivity(currentUser);
      
      debugPrint('로그인 상태 확인 결과: 로그인됨, 로그인 기록 있음, 온보딩 완료, 첫 진입: ${!hasShownTooltip}');
      return result; // 온보딩 완료 - 홈 화면으로 이동 (첫 진입 여부에 따라 툴팁 표시)
    } catch (e) {
      debugPrint('로그인 상태 확인 중 오류 발생: $e');
      _authError = '로그인 상태를 확인하는 중 오류가 발생했습니다: $e';
      
      // 에러 발생 시 기본값 반환
      return {
        'isLoggedIn': false,
        'hasLoginHistory': false,
        'isOnboardingCompleted': false,
        'isFirstEntry': true,
        'user': null,
        'error': e.toString(),
      };
    }
  }

  // 사용자 로그인 처리 및 온보딩 상태 관리
  Future<Map<String, dynamic>> handleUserLogin(User user) async {
    try {
      debugPrint('사용자 로그인 처리 시작: ${user.uid} (${DateTime.now()})');
      final firestore = FirebaseFirestore.instance;
      final userPrefs = UserPreferencesService();
      
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

  // 로그아웃 처리
  Future<void> handleLogout() async {
    try {
      debugPrint('로그아웃 처리 시작 (${DateTime.now()})');
      final userPrefs = UserPreferencesService();
      
      // 로그인 기록 초기화 (기록은 유지하되 다시 로그인 여부 확인 필요)
      await userPrefs.clearLoginHistory();
      
      // Firebase 로그아웃
      await FirebaseAuth.instance.signOut();
      
      // Google 로그아웃 (Google 로그인을 사용한 경우)
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
      
      debugPrint('로그아웃 처리 완료');
    } catch (e) {
      debugPrint('로그아웃 처리 중 오류 발생: $e');
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
      // Firebase가 초기화되었는지 확인
      if (!_firebaseInitialized.isCompleted && Firebase.apps.isEmpty) {
        bool initialized = await initializeApp();
        if (!initialized) {
          throw Exception('Firebase를 초기화할 수 없습니다.');
        }
      }

      // Apple 로그인을 위한 nonce 생성
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      // Apple 로그인 요청
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      // OAuthCredential 생성
      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );

      // Firebase로 로그인
      final userCredential = await FirebaseAuth.instance.signInWithCredential(oauthCredential);
      
      // 인증 상태 확인
      await checkLoginState();
      
      // 사용자 이름이 없는 경우 처리 (Apple 로그인은 두 번째부터 이름을 제공하지 않음)
      if (userCredential.user != null && 
          (userCredential.user?.displayName == null || userCredential.user!.displayName!.isEmpty)) {
        String? fullName;
        
        if (appleCredential.givenName != null && appleCredential.familyName != null) {
          fullName = '${appleCredential.givenName} ${appleCredential.familyName}';
          
          // 사용자 프로필 업데이트
          await userCredential.user!.updateDisplayName(fullName);
        }
      }
      
      debugPrint('Apple 로그인 완료: ${userCredential.user?.uid}');
      return userCredential;
    } catch (e) {
      debugPrint('Apple 로그인 오류: $e');
      setAuthError('Apple 로그인 중 오류가 발생했습니다: $e');
      return null;
    }
  }

  // 로그아웃
  Future<void> signOut() async {
    try {
      // 캐시 서비스 가져오기
      final cacheService = UnifiedCacheService();
      
      // 모든 캐시 지우기
      await cacheService.clearAllCache();
      debugPrint('로그아웃 시 캐시 정리 완료');
      
      // Google 로그인 연결 해제
      await _googleSignIn.signOut();
      
      // Firebase 로그아웃
      await _firebaseAuth.signOut();
      debugPrint('Firebase 로그아웃 완료');
    } catch (e) {
      debugPrint('로그아웃 오류: $e');
      rethrow;
    }
  }

  // nonce 생성 메서드 (Apple 로그인에 필요)
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = DateTime.now().millisecondsSinceEpoch.toString();
    return List.generate(length, (index) => charset[index % charset.length])
        .join();
  }

  // nonce SHA256 해싱 (Apple 로그인 보안을 위해 필요)
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
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
        await _checkAuthenticationState();
        
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
      await _checkAuthenticationState();
      
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
}
