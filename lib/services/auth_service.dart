import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import '../services/user_preferences_service.dart';
import '../services/unified_cache_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

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

  // Google 로그인
  Future<User?> signInWithGoogle() async {
    try {
      // 기존 로그인 상태를 확인하고 있으면 로그아웃
      try {
        if (await _googleSignIn.isSignedIn()) {
          await _googleSignIn.signOut();
          debugPrint('기존 Google 로그인 세션 정리');
        }
      } catch (e) {
        debugPrint('Google 기존 세션 확인 중 오류: $e');
      }
      
      // Google 로그인 인스턴스 생성
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // 사용자가 로그인을 취소한 경우
        return null;
      }

      // 인증 정보 가져오기
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Firebase 인증 정보 생성
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Firebase에 로그인
      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);

      // 사용자 정보 Firestore에 저장
      if (userCredential.user != null) {
        await _saveUserToFirestore(userCredential.user!, isNewUser: userCredential.additionalUserInfo?.isNewUser ?? false);
        
        // 캐시 서비스에 사용자 전환 알림
        final cacheService = UnifiedCacheService();
        await cacheService.setCurrentUserId(userCredential.user!.uid);
      }

      return userCredential.user;
    } catch (e) {
      debugPrint('Google 로그인 중 오류 발생: $e');
      return null;
    }
  }

  // Apple 로그인
  Future<User?> signInWithApple() async {
    try {
      // Firebase 초기화 확인
      if (!Firebase.apps.isNotEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      // nonce 생성
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);
          debugPrint("🔐 rawNonce: $rawNonce");
    debugPrint("🔐 nonce (SHA256): $nonce");


      // Apple 로그인 시작
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      // 디버그 로그 추가
      debugPrint("Apple 인증 토큰: ${appleCredential.identityToken}");
      debugPrint("Apple 인증 ID 상세: ${appleCredential.toString()}");
      debugPrint("Apple 인증 코드: ${appleCredential.authorizationCode}");
      debugPrint("Apple 인증 사용자 이름: ${appleCredential.givenName}, ${appleCredential.familyName}");
      debugPrint("Apple 인증 이메일: ${appleCredential.email}");


 // JWT 디코딩
    final Map<String, dynamic> decodedToken = _parseJwt(appleCredential.identityToken!);
    debugPrint("📦 Decoded Apple identityToken payload:");
    decodedToken.forEach((key, value) => debugPrint("    $key: $value"));
    debugPrint("🎯 aud from token: ${decodedToken['aud']}");


      // OAuthCredential 생성
      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
        accessToken: appleCredential.authorizationCode,
      );

      // Firebase에 로그인
      final userCredential = await _auth.signInWithCredential(oauthCredential);

      // 사용자 정보 Firestore에 저장
      if (userCredential.user != null) {
        // Apple은 처음 로그인할 때만 이름 정보를 제공
        String? displayName = userCredential.user!.displayName;

        // 이름 정보가 없고 Apple에서 제공한 이름이 있으면 사용
        if ((displayName == null || displayName.isEmpty) &&
            (appleCredential.givenName != null ||
                appleCredential.familyName != null)) {
          displayName = [
            appleCredential.givenName ?? '',
            appleCredential.familyName ?? ''
          ].join(' ').trim();

          // 이름 정보가 있으면 Firebase 사용자 프로필 업데이트
          if (displayName.isNotEmpty) {
            await userCredential.user!.updateDisplayName(displayName);
          }
        }

        await _saveUserToFirestore(userCredential.user!, isNewUser: userCredential.additionalUserInfo?.isNewUser ?? false);
        
        // 캐시 서비스에 사용자 전환 알림
        final cacheService = UnifiedCacheService();
        await cacheService.setCurrentUserId(userCredential.user!.uid);
      }

      return userCredential.user;
    } catch (e) {
      debugPrint('Apple 로그인 중 오류 발생: $e');
      return null;
    }
  }
// JWT 디코딩 함수 추가
Map<String, dynamic> _parseJwt(String token) {
  final parts = token.split('.');
  if (parts.length != 3) {
    throw Exception('Invalid JWT token');
  }

  final payload = parts[1];
  var normalized = base64Url.normalize(payload);
  var decoded = utf8.decode(base64Url.decode(normalized));
  return json.decode(decoded);
}

// 로그아웃
Future<void> signOut() async {
  try {
    final userPrefs = UserPreferencesService();
    
    // 소셜 로그인 상태 확인 및 연결 해제
    await _clearSocialLoginSessions();

    // 로그인 기록 초기화
    await userPrefs.clearLoginHistory();
    
    // 캐시 서비스에서 사용자 ID 제거
    final cacheService = UnifiedCacheService();
    await cacheService.clearCurrentUserId();
    
    // Firebase 로그아웃
    await _auth.signOut();
    
    debugPrint('로그아웃 완료');
  } catch (e) {
    debugPrint('로그아웃 중 오류 발생: $e');
    rethrow;
  }
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

  // 사용자 계정 삭제
  Future<void> deleteAccount() async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        throw Exception('로그인된 사용자가 없습니다.');
      }
      
      // 먼저 사용자 정보를 가져옴
      final userData = await _firestore.collection('users').doc(user.uid).get();
      
      // 탈퇴 정보 저장
      if (userData.exists) {
        // 탈퇴된 사용자 정보 저장
        await _firestore.collection('deleted_users').doc(user.uid).set({
          'userId': user.uid,
          'email': user.email,
          'displayName': user.displayName,
          'photoURL': user.photoURL,
          'deletedAt': FieldValue.serverTimestamp(),
          'userInfo': userData.data(),
        });
        
        debugPrint('탈퇴 사용자 정보가 저장되었습니다: ${user.uid}');
      }

      // Firestore에서 사용자 데이터 삭제
      await _firestore.collection('users').doc(user.uid).delete();
      
      // Firebase Auth에서 사용자 삭제
      await user.delete();
      
      // 캐시 서비스에서 사용자 ID 정리
      final cacheService = UnifiedCacheService();
      await cacheService.clearCurrentUserId();
      
      debugPrint('계정이 성공적으로 삭제되었습니다');
    } catch (e) {
      if (e is FirebaseAuthException && e.code == 'requires-recent-login') {
        debugPrint('계정 삭제를 위해 재인증이 필요합니다: ${e.message}');
        // 재인증이 필요한 경우
        throw Exception('계정 삭제를 위해 재로그인이 필요합니다. 로그아웃 후 다시 로그인해주세요.');
      } else {
        debugPrint('계정 삭제 오류: $e');
        rethrow;
      }
    }
  }

  // Apple 로그인용 nonce 생성
  String _generateNonce([int length = 32]) {
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

  Future<void> _saveUserToFirestore(User user, {bool isNewUser = false}) async {
    try {
      // 탈퇴된 사용자인지 먼저 확인
      final isDeleted = await _checkIfUserWasDeleted(user.uid, user.email);
      if (isDeleted) {
        debugPrint('탈퇴된 사용자가 재가입을 시도했습니다: ${user.uid}, ${user.email}');
        // 기존 탈퇴 기록 제거
        try {
          await FirebaseFirestore.instance
              .collection('deleted_users')
              .doc(user.uid)
              .delete();
          debugPrint('탈퇴 기록 제거 완료');
        } catch (e) {
          debugPrint('탈퇴 기록 제거 중 오류: $e');
        }
      }
      
      // 사용자 정보 업데이트
      final userData = {
        'userId': user.uid,
        'email': user.email,
        'displayName': user.displayName ?? '',
        'photoURL': user.photoURL,
        'lastLogin': FieldValue.serverTimestamp(),
        'createdAt': isNewUser ? FieldValue.serverTimestamp() : null,
        'updatedAt': FieldValue.serverTimestamp(),
        'onboardingCompleted': false,
      };

      // null 값 제거 (Firestore는 명시적 null 필드를 허용하지만 필터링하는 것이 좋음)
      userData.removeWhere((key, value) => value == null);

      // Firestore에 사용자 정보 저장
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(userData, SetOptions(merge: true));

      debugPrint('사용자 정보가 Firestore에 저장되었습니다: ${user.uid} (새 사용자: $isNewUser)');
    } catch (error) {
      debugPrint('Firestore에 사용자 정보 저장 중 오류 발생: $error');
    }
  }
  
  // 탈퇴된 사용자인지 확인
  Future<bool> _checkIfUserWasDeleted(String uid, String? email) async {
    try {
      // UID로 확인
      final deletedDoc = await FirebaseFirestore.instance
          .collection('deleted_users')
          .doc(uid)
          .get();
      
      if (deletedDoc.exists) {
        return true;
      }
      
      // 이메일로 확인 (이메일이 있는 경우)
      if (email != null && email.isNotEmpty) {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('deleted_users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
            
        return querySnapshot.docs.isNotEmpty;
      }
      
      return false;
    } catch (e) {
      debugPrint('탈퇴 사용자 확인 중 오류: $e');
      // 오류 발생 시 기본값 반환
      return false;
    }
  }
}
