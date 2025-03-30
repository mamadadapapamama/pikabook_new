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

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // 현재 사용자 가져오기
  User? get currentUser => _auth.currentUser;

  // 사용자 상태 변경 스트림
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // 이메일/비밀번호로 회원가입
  Future<UserCredential> signUpWithEmailAndPassword(
      String email, String password, String name) async {
    try {
      UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // 사용자 정보 Firestore에 저장
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'name': name,
        'email': email,
        'createdAt': FieldValue.serverTimestamp(),
        'profileImage': '',
      }, SetOptions(merge: true));

      return userCredential;
    } catch (e) {
      debugPrint('이메일 회원가입 오류: $e');
      rethrow;
    }
  }

  // 이메일/비밀번호로 로그인
  Future<UserCredential> signInWithEmailAndPassword(
      String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      debugPrint('이메일 로그인 오류: $e');
      rethrow;
    }
  }

  // Google 로그인
  Future<User?> signInWithGoogle() async {
    try {
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
        await _saveUserToFirestore(userCredential.user!);
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

      // Apple 로그인 시작
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

        await _saveUserToFirestore(userCredential.user!);
      }

      return userCredential.user;
    } catch (e) {
      debugPrint('Apple 로그인 중 오류 발생: $e');
      return null;
    }
  }

  // 로그아웃
  Future<void> signOut() async {
    try {
      final userPrefs = UserPreferencesService();
      
      // 로그인 기록 초기화
      await userPrefs.clearLoginHistory();
      
      // Firebase 로그아웃
      await _auth.signOut();
      
      // Google 로그인을 사용한 경우 로그아웃
      final googleSignIn = GoogleSignIn();
      if (await googleSignIn.isSignedIn()) {
        await googleSignIn.signOut();
      }
      
      debugPrint('로그아웃 완료');
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

      // Firestore에서 사용자 데이터 삭제
      await _firestore.collection('users').doc(user.uid).delete();

      // Firebase Auth에서 사용자 삭제
      await user.delete();
    } catch (e) {
      debugPrint('계정 삭제 오류: $e');
      rethrow;
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

  Future<void> _saveUserToFirestore(User user) async {
    await _firestore.collection('users').doc(user.uid).set({
      'name': user.displayName,
      'email': user.email,
      'profileImage': user.photoURL,
      'createdAt': FieldValue.serverTimestamp(),
      'lastLoginAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
