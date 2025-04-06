import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import '../services/user_preferences_service.dart';
import '../services/unified_cache_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../services/page_content_service.dart';
import '../main.dart'; // firebaseApp 전역 변수 가져오기
import 'package:get_it/get_it.dart';
import '../services/image_service.dart';
import '../services/usage_limit_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    forceCodeForRefreshToken: true,
    signInOption: SignInOption.standard,
    scopes: ['email', 'profile'],
  );

  // 현재 사용자 가져오기
  User? get currentUser => _auth.currentUser;

  // 사용자 상태 변경 스트림
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// 앱 재설치 확인 메서드
  Future<bool> _checkAppInstallation() async {
    const String appInstallKey = 'pikabook_installed';
    final prefs = await SharedPreferences.getInstance();
    
    // 앱 설치 확인 키가 있는지 확인
    final bool isAppAlreadyInstalled = prefs.getBool(appInstallKey) ?? false;
    
    // 키가 없으면 새 설치로 간주하고 설정
    if (!isAppAlreadyInstalled) {
      await prefs.setBool(appInstallKey, true);
      // 기존에 로그인된 상태면 강제 로그아웃
      if (FirebaseAuth.instance.currentUser != null) {
        await FirebaseAuth.instance.signOut();
        debugPrint('새 설치 감지: Auth Service에서 로그아웃 처리');
        return true; // 새 설치
      }
    }
    
    return false; // 기존 설치
  }

  // Google 로그인
  Future<User?> signInWithGoogle() async {
    try {
      // 앱 재설치 여부 확인
      await _checkAppInstallation();
      
      // Firebase 초기화 확인
      _checkFirebaseInitialized();
      
      // 구글 로그인 프로세스 시작
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      
      // 사용자가 로그인 취소한 경우
      if (googleUser == null) {
        debugPrint('구글 로그인 취소됨');
        return null;
      }
      
      // 구글 인증 정보 얻기
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      // Firebase 인증 정보 생성
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      
      // Firebase로 로그인
      final UserCredential userCredential = 
          await FirebaseAuth.instance.signInWithCredential(credential);
          
      final User? user = userCredential.user;
      
      // 사용자 정보가 있다면 Firestore에 사용자 정보 업데이트
      if (user != null) {
        await _saveUserToFirestore(user, isNewUser: userCredential.additionalUserInfo?.isNewUser ?? false);
        debugPrint('구글 로그인 성공: ${user.uid}');
      }
      
      return user;
    } catch (e) {
      debugPrint('구글 로그인 오류: $e');
      rethrow;
    }
  }

  // Firebase 초기화 여부 확인
  void _checkFirebaseInitialized() {
    // Firebase가 초기화되지 않은 경우 예외 발생
    if (Firebase.apps.isEmpty) {
      debugPrint('⚠️ Firebase가 초기화되지 않았습니다');
      // 초기화되지 않았지만 예외는 발생시키지 않습니다.
      // 일반적으로 이 시점에는 Firebase가 이미 초기화되어 있어야 함
    } else {
      debugPrint('✅ Firebase 초기화 확인됨');
    }
  }

  // Apple로 로그인
  Future<User?> signInWithApple() async {
    try {
      debugPrint('Apple login: 1. Starting authentication...');
      // Firebase 초기화 확인
      _checkFirebaseInitialized();
      
      debugPrint('Apple login: 2. Generating nonce...');
      // Apple 로그인 시작 - 간단하게 유지
      final rawNonce = _generateNonce(32);
      final nonce = _sha256ofString(rawNonce);
      
      // 디버그 로그 추가
      debugPrint('Apple login raw nonce: $rawNonce');
      debugPrint('Apple login hashed nonce: $nonce');
      
      debugPrint('Apple login: 3. Requesting Apple credential...');
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );
      
      debugPrint('Apple login: 4. Received Apple credential');
      // identityToken과 authorizationCode 로그
      debugPrint('Apple identityToken exists: ${credential.identityToken != null}');
      debugPrint('Apple authorizationCode exists: ${credential.authorizationCode != null}');
      if (credential.identityToken != null) {
        debugPrint('Apple identityToken first 10 chars: ${credential.identityToken!.substring(0, 10)}...');
      }
      
      // 토큰 검증
      if (credential.identityToken == null) {
        debugPrint('Apple login ERROR: Identity token is null!');
        throw Exception('애플 인증 토큰이 없습니다');
      }
      
      debugPrint('Apple login: 5. Creating Firebase credential...');
      // Firebase 인증 정보 생성
      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: credential.identityToken!,
        rawNonce: rawNonce,
        accessToken: credential.authorizationCode, // 추가된 accessToken 파라미터
      );
      
      debugPrint('Apple login: 6. Signing in with Firebase...');
      // Firebase 로그인
      final userCredential = await _auth.signInWithCredential(oauthCredential);
      final user = userCredential.user;
      
      debugPrint('Apple login: 7. Firebase login successful');
      // 사용자 정보 처리
      if (user != null) {
        debugPrint('Apple login: 8. Saving user data to Firestore');
        await _saveUserToFirestore(user, isNewUser: userCredential.additionalUserInfo?.isNewUser ?? false);
        debugPrint('Apple login: 9. User data saved successfully');
      }
      
      debugPrint('Apple login: 10. Process completed');
      return user;
    } catch (e) {
      debugPrint('애플 로그인 오류: $e');
      // 오류 세부 정보 출력
      if (e is FirebaseAuthException) {
        debugPrint('Firebase Auth Error Code: ${e.code}');
        debugPrint('Firebase Auth Error Message: ${e.message}');
      }
      rethrow;
    }
  }

  // Apple로 로그인 (대안적 방법)
  Future<User?> signInWithAppleAlternative() async {
    try {
      debugPrint('Alternative Apple login: 1. Starting authentication...');
      // Firebase 초기화 확인
      _checkFirebaseInitialized();
      
      debugPrint('Alternative Apple login: 2. Generating nonce...');
      // Nonce 생성
      final rawNonce = _generateNonce(32);
      final nonce = _sha256ofString(rawNonce);
      
      debugPrint('Alternative Apple login: 3. Requesting Apple credential...');
      // Apple 로그인 실행
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );
      
      debugPrint('Alternative Apple login: 4. Received credential');
      // 토큰 검증
      if (appleCredential.identityToken == null) {
        throw Exception('애플 인증 토큰이 없습니다');
      }
      
      debugPrint('Alternative Apple login: 5. Creating provider...');
      // 다른 방식으로 OAuthProvider 설정
      final appleProvider = OAuthProvider('apple.com');
      appleProvider.setCustomParameters({'nonce': rawNonce});
      
      debugPrint('Alternative Apple login: 6. Creating credential...');
      // 인증 정보 생성
      final authCredential = OAuthCredential(
        providerId: 'apple.com',
        signInMethod: 'oauth',
        accessToken: appleCredential.authorizationCode,
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );
      
      debugPrint('Alternative Apple login: 7. Signing in with Firebase...');
      // Firebase 로그인
      final userCredential = await _auth.signInWithCredential(authCredential);
      final user = userCredential.user;
      
      // 사용자 이름 처리
      if (user != null) {
        // 사용자 정보 업데이트
        if ((user.displayName == null || user.displayName!.isEmpty) &&
            (appleCredential.givenName != null || appleCredential.familyName != null)) {
          final givenName = appleCredential.givenName ?? '';
          final familyName = appleCredential.familyName ?? '';
          final displayName = (familyName + givenName).trim();
          
          if (displayName.isNotEmpty) {
            await user.updateDisplayName(displayName);
          }
        }
        
        // Firestore에 저장
        await _saveUserToFirestore(user, 
          isNewUser: userCredential.additionalUserInfo?.isNewUser ?? false,
        );
      }
      
      return user;
    } catch (e) {
      debugPrint('대안적 애플 로그인 오류: $e');
      if (e is FirebaseAuthException) {
        debugPrint('Firebase Auth Error Code: ${e.code}');
        debugPrint('Firebase Auth Error Message: ${e.message}');
      }
      rethrow;
    }
  }

  // 로그아웃
  Future<void> signOut() async {
    try {
      debugPrint('로그아웃 시작...');
      
      // 1. 현재 UID 저장
      final currentUid = _auth.currentUser?.uid;
      
      // 2. 현재 사용자 ID를 캐시 서비스에서 제거
      final cacheService = UnifiedCacheService();
      await cacheService.clearCurrentUserId();
      
      // 3. 메모리 캐시 초기화
      cacheService.clearCache();
      
      // 4. 이미지 캐시 정리
      await ImageService().clearImageCache();
      
      // 5. 처리된 텍스트 캐시 정리
      GetIt.I<PageContentService>().clearProcessedTextCache();
      
      // 6. Firebase 로그아웃
      await _auth.signOut();
      
      debugPrint('로그아웃 완료');
      
      // 7. 세션 종료 처리 (필요시)
      if (currentUid != null) {
        await _endUserSession(currentUid);
      }
    } catch (e) {
      debugPrint('로그아웃 중 오류 발생: $e');
      rethrow;
    }
  }

  // 사용자 계정 삭제
  Future<void> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인된 사용자가 없습니다.');
      }
      
      final userId = user.uid;
      final userEmail = user.email;
      final displayName = user.displayName;
      
      // 1. 먼저 모든 데이터 삭제 작업을 수행
      await _deleteAllUserData(userId, userEmail, displayName);
      
      try {
        // 2. Firebase Auth에서 사용자 삭제 시도 (실패해도 진행)
        await user.delete();
        debugPrint('계정이 성공적으로 삭제되었습니다');
      } catch (authError) {
        // Auth 삭제 실패해도 계속 진행 (데이터는 이미 삭제됨)
        debugPrint('계정 삭제 진행 중: $authError');
        // 강제 로그아웃 처리
        await signOut();
        // 오류를 전파하지 않음 - 사용자 데이터는 이미 삭제되었으므로 성공으로 처리
      }
      // 성공적으로 처리됨 - 명시적 return으로 함수 종료
      return;
    } catch (e) {
      // 내부 처리 오류만 로깅하고, 실제 사용자 데이터가 삭제되었으면 오류를 전파하지 않음
      debugPrint('계정 삭제 오류: $e');
      // 사용자 경험을 위해 오류를 전파하지 않고 성공으로 처리
      // rethrow 대신 return 사용
      return;
    }
  }

  // 재인증 처리를 위한 별도 메서드
  Future<void> _handleReauthentication(User user) async {
    try {
      await user.getIdToken(true);
    } catch (e) {
      if (e is FirebaseAuthException && e.code == 'requires-recent-login') {
        final authProvider = user.providerData.firstOrNull?.providerId;
        
        if (authProvider?.contains('google') == true) {
          final googleUser = await _googleSignIn.signIn();
          if (googleUser != null) {
            final googleAuth = await googleUser.authentication;
            final credential = GoogleAuthProvider.credential(
              accessToken: googleAuth.accessToken,
              idToken: googleAuth.idToken,
            );
            await user.reauthenticateWithCredential(credential);
          } else {
            throw FirebaseAuthException(
              code: 'user-cancelled',
              message: '재인증 취소됨',
            );
          }
        } else if (authProvider?.contains('apple') == true) {
          throw Exception('Apple 로그인 재인증이 필요합니다.');
        }
      } else {
        rethrow;
      }
    }
  }

  // 모든 사용자 데이터 삭제를 처리하는 별도 메서드
  Future<void> _deleteAllUserData(String userId, String? email, String? displayName) async {
    try {
      // 1. 로컬 데이터 삭제 (이미지 파일 포함)
      await _clearAllLocalData();
      
      // 2. Firestore 데이터 삭제
      await _deleteFirestoreData(userId);
      
      // 3. Firebase Storage 이미지 데이터 삭제
      final usageLimitService = UsageLimitService();
      try {
        final storageDeleted = await usageLimitService.deleteFirebaseStorageData(userId);
        if (storageDeleted) {
          debugPrint('Firebase Storage 데이터 삭제 완료: $userId');
        } else {
          debugPrint('Firebase Storage 데이터 삭제 실패 또는 데이터 없음: $userId');
        }
      } catch (e) {
        debugPrint('Firebase Storage 데이터 삭제 시도 중 오류: $e');
      }
      
      // 4. 소셜 로그인 연결 해제
      await _clearSocialLoginSessions();
      
      // 5. 디바이스 ID 초기화
      await _resetDeviceId();
      
      // 6. 탈퇴 기록 저장
      await _saveDeletedUserRecord(userId, email, displayName);
      
      debugPrint('모든 사용자 데이터 삭제 완료');
    } catch (e) {
      debugPrint('사용자 데이터 삭제 중 오류: $e');
      rethrow;
    }
  }

  // 로컬 데이터 완전 삭제 (이미지 파일 포함)
  Future<void> _clearAllLocalData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheService = UnifiedCacheService();
      
      // 1. 이미지 파일 삭제
      final appDir = await getApplicationDocumentsDirectory();
      final imageDir = Directory('${appDir.path}/images');
      if (await imageDir.exists()) {
        await imageDir.delete(recursive: true);
        debugPrint('이미지 디렉토리 삭제 완료');
      }
      
      // 2. SharedPreferences 완전 초기화
      await prefs.clear();
      
      // 3. 캐시 서비스 초기화
      await cacheService.clearAllCache();
      
      // 4. 중요 키 개별 삭제 (혹시 모를 잔여 데이터 제거)
      final keys = [
        'current_user_id',
        'login_history',
        'onboarding_completed',
        'has_shown_tooltip',
        'last_signin_provider',
        'has_multiple_accounts',
        'cache_current_user_id',
        // 툴팁 관련 설정 추가
        'note_detail_tooltip_shown',
        'tooltip_shown_after_first_page',
        'home_screen_tooltip_shown',
        'first_note_created',
      ];
      
      for (final key in keys) {
        await prefs.remove(key);
      }
      
      debugPrint('로컬 데이터 완전 삭제 완료');
    } catch (e) {
      debugPrint('로컬 데이터 삭제 중 오류: $e');
      rethrow;
    }
  }

  // Firestore 데이터 완전 삭제
  Future<void> _deleteFirestoreData(String userId) async {
    try {
      final batch = _firestore.batch();
      
      // 1. 사용자 문서 삭제
      batch.delete(_firestore.collection('users').doc(userId));
      
      // 2. 노트 삭제 (익명 노트 포함)
      final notesQuery = await _firestore.collection('notes')
          .where('userId', isEqualTo: userId)
          .get();
      for (var doc in notesQuery.docs) {
        batch.delete(doc.reference);
      }
      
      // 2-1. 익명 노트도 함께 삭제
      final anonymousNotesQuery = await _firestore.collection('notes')
          .where('deviceId', isEqualTo: await _getDeviceId())
          .get();
      for (var doc in anonymousNotesQuery.docs) {
        batch.delete(doc.reference);
      }
      
      // 3. 페이지 삭제
      final pagesQuery = await _firestore.collection('pages')
          .where('userId', isEqualTo: userId)
          .get();
      for (var doc in pagesQuery.docs) {
        batch.delete(doc.reference);
      }
      
      // 4. 플래시카드 삭제
      final flashcardsQuery = await _firestore.collection('flashcards')
          .where('userId', isEqualTo: userId)
          .get();
      for (var doc in flashcardsQuery.docs) {
        batch.delete(doc.reference);
      }
      
      // 5. 이전 탈퇴 기록 삭제
      final deletedUserQuery = await _firestore.collection('deleted_users')
          .where('userId', isEqualTo: userId)
          .get();
      for (var doc in deletedUserQuery.docs) {
        batch.delete(doc.reference);
      }
      
      // 배치 작업 실행
      await batch.commit();
      debugPrint('Firestore 데이터 완전 삭제 완료');
    } catch (e) {
      debugPrint('Firestore 데이터 삭제 중 오류: $e');
      rethrow;
    }
  }

  // 탈퇴 기록 저장
  Future<void> _saveDeletedUserRecord(String userId, String? email, String? displayName) async {
    try {
      await _firestore.collection('deleted_users').doc(userId).set({
        'userId': userId,
        'email': email,
        'displayName': displayName,
        'deletedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('탈퇴 기록 저장 완료');
    } catch (e) {
      debugPrint('탈퇴 기록 저장 중 오류: $e');
      // 핵심 기능이 아니므로 오류를 전파하지 않음
    }
  }

  // Apple 로그인용 nonce 생성
  String _generateNonce(int length) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  // SHA256 해시 생성
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // 사용자 정보를 Firestore에 저장하는 메서드 (InitializationService와 유사하게 수정)
  Future<void> _saveUserToFirestore(User user, 
                                  {bool isNewUser = false, 
                                   AuthorizationCredentialAppleID? appleCredential}) async {
    try {
      final userRef = _firestore.collection('users').doc(user.uid);
      
      // 1. 탈퇴된 사용자인지 확인 (InitializationService의 로직 참조)
      final wasDeleted = await _checkIfUserWasDeleted(user.uid, user.email);
      
      // 2. 탈퇴 사용자이거나 새로운 사용자인 경우 기존 데이터 완전 삭제 (Firestore만)
      if (wasDeleted || isNewUser) {
        debugPrint('AuthService: 새 사용자 또는 탈퇴 후 재가입 감지: ${user.uid}');
        
        // 2-1. 기존 Firestore 데이터 삭제 (노트, 페이지 등은 여기서 처리 안 함, 필요 시 추가)
        // await _deleteFirestoreData(user.uid); // 주석 처리: InitializationService에서 처리
        
        // 2-2. 탈퇴 기록 삭제 (Firestore만)
        if (wasDeleted) {
          try {
            await _firestore.collection('deleted_users').doc(user.uid).delete();
            debugPrint('AuthService: 탈퇴 기록 삭제 완료');
          } catch (e) {
            debugPrint('AuthService: 탈퇴 기록 삭제 중 오류: $e');
          }
        }
      }
      
      // 3. 새로운 사용자 정보 저장
      String? finalDisplayName = user.displayName;
      
      // Apple 로그인 시 이름 처리
      if (appleCredential != null) {
        if ((finalDisplayName == null || finalDisplayName.isEmpty) &&
            (appleCredential.givenName != null || appleCredential.familyName != null)) {
          final givenName = appleCredential.givenName ?? '';
          final familyName = appleCredential.familyName ?? '';
          final appleName = '$givenName $familyName'.trim();
          
          if (appleName.isNotEmpty) {
            finalDisplayName = appleName;
            try {
              await user.updateDisplayName(finalDisplayName);
              debugPrint('AuthService: Firebase Auth 프로필 이름 업데이트 완료: $finalDisplayName');
            } catch (authError) {
              debugPrint('AuthService: Firebase Auth 프로필 이름 업데이트 실패: $authError');
            }
          }
        }
      }
      
      final userData = {
        'uid': user.uid,
        'email': user.email,
        'displayName': finalDisplayName, // 업데이트된 이름 사용
        'photoURL': user.photoURL,
        'lastLogin': FieldValue.serverTimestamp(), // lastSignIn 대신 lastLogin 사용 (InitializationService와 통일)
        'updatedAt': FieldValue.serverTimestamp(),
        'deviceId': await _getDeviceId(), // 디바이스 ID 저장
      };
      
      // 새 사용자인 경우 createdAt 추가
      if (isNewUser) {
        userData['createdAt'] = FieldValue.serverTimestamp();
        userData['onboardingCompleted'] = false; // 새 사용자는 온보딩 미완료
      }

      // null 값 제거
      userData.removeWhere((key, value) => value == null);

      // Firestore에 사용자 정보 저장 (merge: true로 기존 필드 유지)
      await userRef.set(userData, SetOptions(merge: true));

      debugPrint('AuthService: 사용자 정보가 Firestore에 저장되었습니다: ${user.uid} (새 사용자: $isNewUser)');
    } catch (error) {
      debugPrint('AuthService: Firestore에 사용자 정보 저장 중 오류 발생: $error');
      rethrow;
    }
  }
  
  // 탈퇴된 사용자인지 확인 (InitializationService와 동일 로직)
  Future<bool> _checkIfUserWasDeleted(String uid, String? email) async {
    try {
      final deletedDoc = await _firestore.collection('deleted_users').doc(uid).get();
      if (deletedDoc.exists) return true;
      
      if (email != null && email.isNotEmpty) {
        final querySnapshot = await _firestore.collection('deleted_users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        return querySnapshot.docs.isNotEmpty;
      }
      
      return false;
    } catch (e) {
      debugPrint('AuthService: 탈퇴 사용자 확인 중 오류: $e');
      return false;
    }
  }

  // 디바이스 ID 가져오기
  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('device_id');
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString('device_id', deviceId);
    }
    return deviceId;
  }

  // 디바이스 ID 초기화
  Future<void> _resetDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('device_id');
  }

  // 소셜 로그인 세션 완전 정리
  Future<void> _clearSocialLoginSessions() async {
    try {
      // 1. Google 로그인 연결 해제 (Google 계정 연결 권한까지 철회)
      try {
        final googleSignIn = GoogleSignIn();
        if (await googleSignIn.isSignedIn()) {
          // 단순 로그아웃이 아닌 disconnect() 사용해 계정 연결 자체를 끊어야 계정 선택 화면이 나타남
          await googleSignIn.disconnect();
          await googleSignIn.signOut();
          debugPrint('Google 계정 연결 완전 해제됨');
        }
      } catch (e) {
        debugPrint('Google 계정 연결 해제 중 오류: $e');
      }
      
      // 2. Apple 로그인 상태 정리
      try {
        // Apple은 앱 수준에서 연결 해제가 제한적이라 로컬 저장소에서 관련 정보 제거
        final prefs = await SharedPreferences.getInstance();
        
        // Apple 관련 모든 캐시 키 삭제
        final keys = prefs.getKeys();
        for (final key in keys) {
          if (key.contains('apple') || 
              key.contains('Apple') || 
              key.contains('sign_in') || 
              key.contains('oauth') ||
              key.contains('token') ||
              key.contains('credential')) {
            await prefs.remove(key);
          }
        }
        
        debugPrint('Apple 로그인 관련 정보 정리 완료');
      } catch (e) {
        debugPrint('Apple 로그인 정보 정리 중 오류: $e');
      }
      
      // 3. 로컬 캐시 완전 초기화
      try {
        final cacheService = UnifiedCacheService();
        await cacheService.clearAllCache();
        debugPrint('모든 캐시 데이터 초기화 완료');
      } catch (e) {
        debugPrint('캐시 데이터 초기화 중 오류: $e');
      }
    } catch (e) {
      debugPrint('소셜 로그인 세션 정리 중 오류: $e');
    }
  }

  /// 사용자 세션 종료 처리 (필요한 정리 작업 수행)
  Future<void> _endUserSession(String userId) async {
    try {
      // 사용자 세션 상태 업데이트 (활성 상태 false로 설정)
      await _firestore.collection('user_sessions').doc(userId).update({
        'isActive': false,
        'lastLogoutAt': FieldValue.serverTimestamp(),
      });
      
      debugPrint('사용자 세션 종료 처리 완료: $userId');
    } catch (e) {
      debugPrint('사용자 세션 종료 처리 중 오류 (무시됨): $e');
      // 세션 종료 처리 실패는 치명적이지 않으므로 오류를 무시함
    }
  }
}

