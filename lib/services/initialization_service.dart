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
  Future<void> _checkAuthenticationState() async {
    try {
      // 이미 완료된 경우 스킵
      if (_firebaseInitialized.isCompleted) {
        return;
      }

      // Firebase Auth 인스턴스 가져오기
      final auth = FirebaseAuth.instance;

      // 현재 사용자 확인 (null이면 로그인되지 않은 상태)
      final currentUser = auth.currentUser;

      if (currentUser != null) {
        // 일반 사용자인 경우 마지막 로그인 정보 업데이트
        await _saveLastLoginActivity(currentUser);
      }

      // 인증 상태 확인 완료 설정
      _firebaseInitialized.complete(true);
      debugPrint('인증 상태 확인 완료: ${currentUser != null ? '로그인 상태' : '로그아웃 상태'}');
    } catch (e) {
      _authError = '인증 상태를 확인하는 중 오류가 발생했습니다: $e';
      _firebaseInitialized.complete(false);
      debugPrint('인증 상태 확인 오류: $e');
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

  // 사용자 로그인 처리 및 온보딩 상태 관리
  Future<void> handleUserLogin(User user) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final userPrefs = UserPreferencesService();
      
      // Firestore에서 사용자 데이터 확인
      final userDoc = await firestore.collection('users').doc(user.uid).get();
      
      // 사용자의 노트 데이터 확인 - userId 필드로 필터링
      bool hasNotes = false;
      try {
        final notesQuery = await firestore
            .collection('notes')
            .where('userId', isEqualTo: user.uid)
            .limit(1)
            .get();
        
        hasNotes = notesQuery.docs.isNotEmpty;
        debugPrint('사용자 ${user.uid}의 노트 데이터 확인: ${hasNotes ? "노트 있음" : "노트 없음"}');
      } catch (e) {
        debugPrint('노트 데이터 확인 중 오류: $e');
        // 노트 컬렉션이 없으면 노트가 없는 것으로 처리
        hasNotes = false;
      }
      
      // 계정 첫 로그인 여부 확인 - 완전히 새로운 사용자인 경우
      final isNewUser = !userDoc.exists;
      
      if (isNewUser) {
        // 온보딩 상태 설정 - 새 계정이면 온보딩 필요
        await userPrefs.setOnboardingCompleted(false);
        
        // Firestore에 사용자 정보 생성
        await firestore.collection('users').doc(user.uid).set({
          'isNew': true,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
          'onboardingCompleted': false,
          'email': user.email,
          'displayName': user.displayName,
          'hasOnboarded': false, // 온보딩 미완료 상태로 저장
        }, SetOptions(merge: true));
        
      } else {
        // 기존 사용자인 경우 - 노트 데이터 기반으로 온보딩 결정
        if (!hasNotes) {
          // 노트가 없으면 온보딩 표시
          await userPrefs.setOnboardingCompleted(false);
          
          // Firestore 사용자 상태 업데이트
          await firestore.collection('users').doc(user.uid).update({
            'onboardingCompleted': false,
            'lastLogin': FieldValue.serverTimestamp(),
            'hasOnboarded': false, // 온보딩 미완료 상태로 저장
          });
        } else {
          // 노트가 있으면 온보딩 건너뛰기
          await userPrefs.setOnboardingCompleted(true);
          
          // Firestore 사용자 상태 업데이트
          await firestore.collection('users').doc(user.uid).update({
            'onboardingCompleted': true,
            'lastLogin': FieldValue.serverTimestamp(),
            'hasOnboarded': true, // 온보딩 완료 상태로 저장
          });
        }
      }
      
      // 캐시 서비스 초기화 - 로그인마다 신선한 데이터 사용
      final cacheService = UnifiedCacheService();
      await cacheService.clearAllCache();
      
    } catch (e) {
      debugPrint('사용자 로그인 처리 오류: $e');
      // 오류 발생 시 기본값으로 온보딩 표시
      try {
        final userPrefs = UserPreferencesService();
        await userPrefs.setOnboardingCompleted(false);
      } catch (e2) {
        debugPrint('기본 온보딩 상태 설정 중 오류: $e2');
      }
    }
  }

  // Firebase 초기화 상태 설정 (백그라운드 초기화 완료 시 호출)
  Future<void> markFirebaseInitialized(bool initialized) async {
    if (!_firebaseInitialized.isCompleted) {
      _firebaseInitialized.complete(initialized);
      debugPrint('Firebase 초기화 상태 업데이트: $initialized');
    }
  }

  // Firebase 초기화 함수
  Future<bool> initializeFirebase() async {
    try {
      // 이미 초기화되었는지 확인
      if (Firebase.apps.isNotEmpty) {
        await markFirebaseInitialized(true);
        debugPrint('Firebase 이미 초기화됨');
        return true;
      }
      
      // 초기화되지 않은 경우 초기화 수행
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      
      await markFirebaseInitialized(true);
      debugPrint('Firebase 초기화 완료');
      return true;
    } catch (e) {
      _firebaseError = '앱 초기화 중 오류가 발생했습니다: $e';
      debugPrint('Firebase 초기화 오류: $e');
      return false;
    }
  }

  // Google 로그인
  Future<User?> signInWithGoogle() async {
    try {
      // Firebase가 초기화되었는지 확인
      if (!_firebaseInitialized.isCompleted && Firebase.apps.isEmpty) {
        bool initialized = await initializeFirebase();
        if (!initialized) {
          throw Exception('Firebase를 초기화할 수 없습니다.');
        }
      }

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await _firebaseAuth.signInWithCredential(credential);
      final User? user = userCredential.user;

      if (user != null) {
        // 사용자 데이터를 Firestore에 저장
        await _saveUserToFirestore(user);
      }

      return user;
    } catch (e) {
      debugPrint('Google 로그인 오류: $e');
      rethrow;
    }
  }

  // Apple 로그인
  Future<User?> signInWithApple() async {
    try {
      // Firebase가 초기화되었는지 확인
      if (!_firebaseInitialized.isCompleted && Firebase.apps.isEmpty) {
        bool initialized = await initializeFirebase();
        if (!initialized) {
          throw Exception('Firebase를 초기화할 수 없습니다.');
        }
      }

      // Apple 로그인 요청에 필요한 nonce 생성
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      // Apple로 인증 요청
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      // OAuthCredential 생성
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: credential.identityToken,
        rawNonce: rawNonce,
      );

      // Firebase에 로그인
      final userCredential =
          await _firebaseAuth.signInWithCredential(oauthCredential);
      final user = userCredential.user;

      // 이름 업데이트 (Apple은 첫 로그인에만 이름 정보 제공)
      if (credential.givenName != null && user != null) {
        String displayName = '${credential.givenName} ${credential.familyName ?? ''}';
        await user.updateDisplayName(displayName.trim());
      }

      if (user != null) {
        // 사용자 데이터를 Firestore에 저장
        await _saveUserToFirestore(user);
      }

      return user;
    } catch (e) {
      debugPrint('Apple 로그인 오류: $e');
      rethrow;
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

  // 사용자 정보를 Firestore에 저장하는 메서드
  Future<void> _saveUserToFirestore(User user) async {
    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      
      await userRef.set({
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        'photoURL': user.photoURL,
        'lastSignIn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      debugPrint('사용자 정보가 Firestore에 저장되었습니다: ${user.uid}');
    } catch (e) {
      debugPrint('사용자 정보 저장 오류: $e');
    }
  }

  // 초기화 재시도 메서드
  Future<void> retryInitialization({required FirebaseOptions options}) async {
    try {
      // Firebase 초기화 상태 재설정
      if (_firebaseInitialized.isCompleted) {
        // 이미 완료된 경우, 새로운 Completer 생성
        // (실제로는 더 복잡한 상태 관리가 필요할 수 있음)
        debugPrint('초기화 재시도: Firebase 상태 재설정');
      }
      
      // Firebase 재초기화 시도
      await Firebase.initializeApp(options: options);
      await markFirebaseInitialized(true);
      
      debugPrint('Firebase 초기화 재시도 완료');
    } catch (e) {
      debugPrint('Firebase 초기화 재시도 오류: $e');
      _firebaseError = '앱 초기화 재시도 중 오류가 발생했습니다: $e';
    }
  }
}
