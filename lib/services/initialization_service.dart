import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // PlatformException 추가
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
import 'dart:math'; // Random 추가
import '../firebase_options.dart';
import '../main.dart'; // main.dart의 전역 Firebase 앱 변수를 사용

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
    // 계정 선택 화면을 항상 보여주는 설정
    signInOption: SignInOption.standard,
    // 로그아웃 후에도 계정 선택 화면이 나타나도록 함
    forceCodeForRefreshToken: true,
  );

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  bool _isFirebaseInitialized = false;

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
      debugPrint('사용자 로그인 처리 시작: ${user.uid}');
      final firestore = FirebaseFirestore.instance;
      final userPrefs = UserPreferencesService();
      final cacheService = UnifiedCacheService();
      
      // 1. 먼저 로컬 데이터 초기화 (이전 사용자 데이터 제거)
      await _cleanupPreviousUserData();
      
      // 2. 캐시 서비스에 현재 사용자 ID 설정
      await cacheService.setCurrentUserId(user.uid);
      
      // 3. Firestore에서 사용자 데이터 확인
      final userDoc = await firestore.collection('users').doc(user.uid).get();
      
      // 4. 탈퇴 기록 확인 및 처리
      final wasDeleted = await _checkIfUserWasDeleted(user.uid, user.email);
      final isNewUser = !userDoc.exists || wasDeleted;
      
      // 5. 사용자 정보 저장 (새 사용자 또는 탈퇴 후 재가입)
      if (isNewUser) {
        debugPrint('새 사용자 또는 탈퇴 후 재가입 감지: ${user.uid}');
        // 탈퇴 기록이 있으면 삭제
        if (wasDeleted) {
          await _clearDeletedUserRecord(user.uid, user.email);
        }
        // 새 사용자로 처리
        await _saveUserToFirestore(user, isNewUser: true);
        // 온보딩 상태 초기화
        await userPrefs.setOnboardingCompleted(false);
      } else {
        // 기존 사용자 데이터 업데이트
        await _saveUserToFirestore(user, isNewUser: false);
      }
      
      // 6. 로그인 기록 저장
      await userPrefs.saveLoginHistory();
      
      // 7. 결과 객체 구성
      final result = {
        'isLoggedIn': true,
        'isNewUser': isNewUser,
        'hasLoginHistory': true,
        'isOnboardingCompleted': false,
        'isFirstEntry': true,
      };
      
      // 8. 기존 사용자의 경우 온보딩 상태 확인
      if (!isNewUser) {
        final userData = userDoc.data() as Map<String, dynamic>?;
        if (userData != null) {
          final onboardingCompleted = userData['onboardingCompleted'] ?? false;
          await userPrefs.setOnboardingCompleted(onboardingCompleted);
          result['isOnboardingCompleted'] = onboardingCompleted;
          
          // 툴큰 상태 확인
          final prefs = await SharedPreferences.getInstance();
          final hasShownTooltip = prefs.getBool('hasShownTooltip') ?? false;
          result['isFirstEntry'] = !hasShownTooltip;
          
          // 온보딩이 완료된 경우에만 추가 설정 로드
          if (onboardingCompleted) {
            await _loadUserSettings(userData, userPrefs);
          }
        }
      }
      
      debugPrint('로그인 처리 완료: $result');
      return result;
    } catch (e) {
      debugPrint('사용자 로그인 처리 중 오류 발생: $e');
      // 오류 발생 시 모든 데이터 초기화
      await _cleanupPreviousUserData();
      return {
        'isLoggedIn': true,
        'error': e.toString(),
        'isOnboardingCompleted': false,
        'isFirstEntry': true,
      };
    }
  }

  // 이전 사용자 데이터 정리
  Future<void> _cleanupPreviousUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheService = UnifiedCacheService();
      
      // 1. 캐시 서비스 초기화
      await cacheService.clearAllCache();
      
      // 2. 중요 상태 키 초기화
      final keysToRemove = [
        'current_user_id',
        'login_history',
        'onboarding_completed',
        'has_shown_tooltip',
        'last_signin_provider',
        'has_multiple_accounts',
        'cache_current_user_id',
      ];
      
      for (final key in keysToRemove) {
        await prefs.remove(key);
      }
      
      debugPrint('이전 사용자 데이터 정리 완료');
    } catch (e) {
      debugPrint('이전 데이터 정리 중 오류: $e');
    }
  }

  // 탈퇴 기록 삭제
  Future<void> _clearDeletedUserRecord(String uid, String? email) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();
      
      // UID로 삭제
      final uidDoc = firestore.collection('deleted_users').doc(uid);
      batch.delete(uidDoc);
      
      // 이메일로 검색하여 삭제
      if (email != null && email.isNotEmpty) {
        final emailQuery = await firestore.collection('deleted_users')
            .where('email', isEqualTo: email)
            .get();
        for (var doc in emailQuery.docs) {
          batch.delete(doc.reference);
        }
      }
      
      await batch.commit();
      debugPrint('탈퇴 기록 삭제 완료');
    } catch (e) {
      debugPrint('탈퇴 기록 삭제 중 오류: $e');
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
      final authService = AuthService();
      await authService.signOut();
    } catch (e) {
      debugPrint('로그아웃 중 오류 발생: $e');
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
  Future<void> _saveUserToFirestore(User user, 
                                  {bool isNewUser = false, 
                                   AuthorizationCredentialAppleID? appleCredential}) async {
    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      
      String? finalDisplayName = user.displayName;
      
      // Apple 로그인 시 이름 처리
      if (appleCredential != null) {
        // Firebase에 이름이 없거나 Apple에서 제공한 이름이 있는 경우
        if ((finalDisplayName == null || finalDisplayName.isEmpty) &&
            (appleCredential.givenName != null || appleCredential.familyName != null)) {
          final givenName = appleCredential.givenName ?? '';
          final familyName = appleCredential.familyName ?? '';
          final appleName = '$givenName $familyName'.trim();
          
          if (appleName.isNotEmpty) {
            finalDisplayName = appleName;
            // Firebase Auth 프로필 업데이트 (선택 사항, 필요 시)
            try {
              await user.updateDisplayName(finalDisplayName);
              debugPrint('Firebase Auth 프로필 이름 업데이트 완료: $finalDisplayName');
            } catch (authError) {
              debugPrint('Firebase Auth 프로필 이름 업데이트 실패: $authError');
            }
          }
        }
      }
      
      final baseData = {
        'uid': user.uid,
        'email': user.email,
        'displayName': finalDisplayName, // 업데이트된 이름 사용
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
        // 기존 사용자인 경우 업데이트 (merge: true로 필드 추가/수정)
        await userRef.set(baseData, SetOptions(merge: true));
      }
      
      debugPrint('사용자 정보가 Firestore에 저장되었습니다: ${user.uid} (새 사용자: $isNewUser)');
    } catch (e) {
      debugPrint('사용자 정보 저장 오류: $e');
      rethrow;
    }
  }

  // 탈퇴한 사용자인지 확인
  Future<bool> _checkIfUserWasDeleted(String uid, String? email) async {
    try {
      final firestore = FirebaseFirestore.instance;
      
      // 1. UID로 확인
      final uidDoc = await firestore.collection('deleted_users').doc(uid).get();
      if (uidDoc.exists) {
        return true;
      }
      
      // 2. 이메일로 확인 (있는 경우)
      if (email != null && email.isNotEmpty) {
        final emailQuery = await firestore.collection('deleted_users')
            .where('email', isEqualTo: email)
            .get();
        return emailQuery.docs.isNotEmpty;
      }
      
      return false;
    } catch (e) {
      debugPrint('탈퇴 사용자 확인 중 오류: $e');
      return false;
    }
  }

  /// 앱 초기화 메서드
  /// Firebase를 초기화하고 사용자 인증 상태를 확인합니다.
  Future<bool> initializeApp() async {
    try {
      // 초기화 시작 로그
      debugPrint('앱 초기화 상태 확인 시작 (${_initStartTime.toIso8601String()})');

      // Firebase 초기화 여부 확인 (main.dart에서 초기화되었는지)
      if (firebaseApp != null) {
        // 이미 초기화된 경우 상태만 업데이트
        debugPrint('✅ InitService: 전역 Firebase 앱 변수가 설정되어 있습니다');
        _isFirebaseInitialized = true;
        
        // Completer가 아직 완료되지 않았다면 완료 처리
        if (!_firebaseInitialized.isCompleted) {
          _firebaseInitialized.complete(true);
        }
      } else {
        // 아직 초기화되지 않은 경우
        debugPrint('⚠️ InitService: 전역 Firebase 앱 변수가 설정되지 않았습니다');
        _isFirebaseInitialized = false;
        
        // 중요: 여기서 Firebase를 직접 초기화하지 않음
        setFirebaseError('Firebase가 main.dart에서 초기화되지 않았습니다');
        
        // Completer가 아직 완료되지 않았다면 완료 처리
    if (!_firebaseInitialized.isCompleted) {
          _firebaseInitialized.complete(false);
        }
        
        return false;
      }
      
      // Firebase 초기화 확인 후 로그인 상태 확인
      final loginStateResult = await checkLoginState();
      
      // 초기화 완료 시간 및 소요 시간 계산
      final initEndTime = DateTime.now();
      final duration = initEndTime.difference(_initStartTime);
      
      debugPrint('앱 초기화 상태 확인 완료 (소요 시간: ${duration.inMilliseconds}ms)');
      debugPrint('로그인 상태: ${loginStateResult['isLoggedIn'] ?? false}');
            
      return true;
    } catch (e) {
      // 오류 발생 시 처리
      setFirebaseError('앱 초기화 상태 확인 중 오류가 발생했습니다: $e');
      debugPrint('앱 초기화 상태 확인 오류: $e');
      
      // 초기화 실패를 명시적으로 반환
      if (!_firebaseInitialized.isCompleted) {
        _firebaseInitialized.complete(false);
      }
      return false;
    }
  }

  // Google 로그인
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // Firebase가 초기화되었는지 확인 (전역 변수 사용)
      if (firebaseApp == null) {
         debugPrint('⚠️ InitService: Firebase가 초기화되지 않았습니다. Google 로그인 불가능');
         throw Exception('Firebase가 초기화되지 않아 Google 로그인을 진행할 수 없습니다.');
      }

      // 기존 로그인 상태를 확인하고 있으면 로그아웃 (계정 선택 화면 표시 위함)
      try {
        if (await _googleSignIn.isSignedIn()) {
          await _googleSignIn.signOut();
          debugPrint('기존 Google 로그인 세션 정리');
        }
      } catch (e) {
        debugPrint('Google 기존 세션 확인 중 오류: $e');
      }

      // Google 로그인 UI 표시
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      // 로그인 취소된 경우
      if (googleUser == null) {
        debugPrint('Google 로그인 취소됨');
        return null;
      }
      
      debugPrint('Google 사용자 정보 가져옴: ${googleUser.email}');

      // 인증 정보 가져오기
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      debugPrint('Google 인증 토큰 가져옴 (AccessToken: ${googleAuth.accessToken != null}, IDToken: ${googleAuth.idToken != null})');

      // Firebase 인증 정보 생성
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Firebase에 로그인
      debugPrint('Firebase에 Google 자격 증명으로 로그인 시도');
      final UserCredential userCredential = await _firebaseAuth.signInWithCredential(credential);
      debugPrint('Firebase 로그인 성공: ${userCredential.user?.uid}');
      
      // 사용자 정보 Firestore에 저장 (로그인 성공 후 처리)
      if (userCredential.user != null) {
        await _saveUserToFirestore(userCredential.user!, isNewUser: userCredential.additionalUserInfo?.isNewUser ?? false);
        // 캐시 서비스에 사용자 전환 알림
        await _cacheService.setCurrentUserId(userCredential.user!.uid);
        // 마지막 활동 시간 저장
        await _saveLastLoginActivity(userCredential.user!);
      }

      return userCredential;
    } catch (e) {
      debugPrint('Google 로그인 중 심각한 오류 발생: $e');
      if (e is PlatformException) {
        debugPrint('PlatformException details: ${e.code} - ${e.message}');
      }
      // 오류 발생 시 null 반환 또는 예외 다시 던지기
      return null; 
    }
  }

  // Apple 로그인
  Future<UserCredential?> signInWithApple() async {
    try {
       // Firebase가 초기화되었는지 확인 (전역 변수 사용)
      if (firebaseApp == null) {
         debugPrint('⚠️ InitService: Firebase가 초기화되지 않았습니다. Apple 로그인 불가능');
         throw Exception('Firebase가 초기화되지 않아 Apple 로그인을 진행할 수 없습니다.');
      }

      // nonce 생성 (Apple 로그인 보안 요구사항)
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);
      debugPrint("🔐 Apple 로그인 시도 - nonce: $nonce");

      // Apple 로그인 UI 표시
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      debugPrint('Apple 자격 증명 받음 - ID 토큰 길이: ${appleCredential.identityToken?.length ?? 0}');

      // Firebase OAuth 자격 증명 생성
      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
        accessToken: appleCredential.authorizationCode,
      );

      // Firebase에 로그인
      debugPrint('Firebase에 Apple 자격 증명으로 로그인 시도');
      final UserCredential userCredential = await _firebaseAuth.signInWithCredential(oauthCredential);
      debugPrint('Firebase 로그인 성공: ${userCredential.user?.uid}');

      // 사용자 정보 Firestore에 저장 (로그인 성공 후 처리)
      if (userCredential.user != null) {
        await _saveUserToFirestore(userCredential.user!, 
                                 isNewUser: userCredential.additionalUserInfo?.isNewUser ?? false,
                                 appleCredential: appleCredential); // Apple 자격 증명 전달
        // 캐시 서비스에 사용자 전환 알림
        await _cacheService.setCurrentUserId(userCredential.user!.uid);
         // 마지막 활동 시간 저장
        await _saveLastLoginActivity(userCredential.user!);
      }

      return userCredential;
    } on SignInWithAppleException catch (e) { // 구체적인 예외 타입 명시
      debugPrint('Apple 로그인 중 오류 발생 (SignInWithAppleException): ${e.toString()}'); 
      // 오류 코드를 확인하여 사용자에게 더 친절한 메시지 제공 가능
      return null;
    } catch (e) {
      debugPrint('Apple 로그인 중 일반 오류 발생: $e');
      return null;
    }
  }

  // 현재 로그인된 사용자 가져오기
  User? getCurrentUser() {
    return FirebaseAuth.instance.currentUser;
  }

  // 초기화 재시도 메서드 (옵션 매개변수는 무시됨)
  Future<void> retryInitialization({FirebaseOptions? options}) async {
    debugPrint('앱 초기화 상태 재확인 시도...');
    _firebaseError = null; // 이전 오류 초기화
    
    // Firebase 초기화 상태 확인
    if (firebaseApp != null) {
      debugPrint('✅ retryInit: Firebase가 성공적으로 초기화되어 있습니다');
      _isFirebaseInitialized = true;
      
      // Completer가 아직 완료되지 않았다면 완료 처리
      if (!_firebaseInitialized.isCompleted) {
        _firebaseInitialized.complete(true);
      }
      
      // 로그인 상태 확인 
      await checkLoginState();
    } else {
      debugPrint('⚠️ retryInit: Firebase가 초기화되지 않았습니다');
      
      // 오류 설정
      setFirebaseError('Firebase가 main.dart에서 초기화되지 않았습니다');
      _isFirebaseInitialized = false;
      
      // Completer가 아직 완료되지 않았다면 완료 처리
      if (!_firebaseInitialized.isCompleted) {
        _firebaseInitialized.complete(false);
      }
    }
  }

  // Nonce 생성 및 해시 함수 (AuthService와 동일하게 유지)
  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // Firebase 초기화 상태 설정 (초기화 자체는 하지 않음)
  Future<void> markFirebaseInitialized(bool success) async {
    if (!_firebaseInitialized.isCompleted) {
      try {
        // 상태 업데이트 - 실제 초기화는 수행하지 않음
        _isFirebaseInitialized = success;
        
        // 전역 변수가 설정되어 있는지 확인하고, 설정되어 있지 않다면 로그만 남김
        if (firebaseApp == null) {
          debugPrint('⚠️ markFirebaseInitialized: 전역 Firebase 앱 변수가 null 상태입니다');
        } else {
          debugPrint('✅ markFirebaseInitialized: Firebase 초기화 확인됨');
        }
        
        // Completer 완료 처리
        _firebaseInitialized.complete(success);
        
        // 성공 시에만 로그인 상태 확인
        if (success) {
          await checkLoginState();
        }
        
        debugPrint('Firebase 초기화 상태 설정: $success');
    } catch (e) {
        // 오류 발생 시 처리
        _firebaseError = '초기화 상태 설정 중 오류: $e';
        if (!_firebaseInitialized.isCompleted) {
          _firebaseInitialized.complete(false);
        }
        debugPrint('초기화 상태 설정 오류: $e');
      }
    }
  }
}
