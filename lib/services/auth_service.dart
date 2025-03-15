import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // 현재 사용자 가져오기
  User? get currentUser => _auth.currentUser;

  // 사용자 상태 변경 스트림
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // 익명 로그인
  Future<UserCredential> signInAnonymously() async {
    try {
      final userCredential = await _auth.signInAnonymously();

      // 사용자 정보 Firestore에 저장
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'isAnonymous': true,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return userCredential;
    } catch (e) {
      debugPrint('익명 로그인 오류: $e');
      rethrow;
    }
  }

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
        'isAnonymous': false,
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
  Future<UserCredential> signInWithGoogle() async {
    try {
      // Google 로그인 프로세스 시작
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        throw Exception('Google 로그인이 취소되었습니다.');
      }

      // Google 인증 정보 가져오기
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Firebase 인증 정보 생성
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Firebase로 로그인
      final userCredential = await _auth.signInWithCredential(credential);

      // 사용자 정보 Firestore에 저장
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'name': userCredential.user!.displayName,
        'email': userCredential.user!.email,
        'isAnonymous': false,
        'profileImage': userCredential.user!.photoURL,
        'lastLoginAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return userCredential;
    } catch (e) {
      debugPrint('Google 로그인 오류: $e');
      rethrow;
    }
  }

  // Apple 로그인
  Future<UserCredential> signInWithApple() async {
    try {
      // nonce 생성
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
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );

      // Firebase로 로그인
      final userCredential = await _auth.signInWithCredential(oauthCredential);

      // 사용자 이름 설정 (Apple은 첫 로그인에만 이름 제공)
      String? displayName = userCredential.user!.displayName;
      if (displayName == null || displayName.isEmpty) {
        displayName =
            '${appleCredential.givenName ?? ''} ${appleCredential.familyName ?? ''}'
                .trim();
        if (displayName.isNotEmpty) {
          await userCredential.user!.updateDisplayName(displayName);
        }
      }

      // 사용자 정보 Firestore에 저장
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'name': displayName.isNotEmpty ? displayName : 'Apple 사용자',
        'email': userCredential.user!.email,
        'isAnonymous': false,
        'lastLoginAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return userCredential;
    } catch (e) {
      debugPrint('Apple 로그인 오류: $e');
      rethrow;
    }
  }

  // 익명 계정을 Google 계정으로 연결
  Future<UserCredential> linkAnonymousAccountWithGoogle() async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        throw Exception('로그인된 사용자가 없습니다.');
      }

      if (!user.isAnonymous) {
        throw Exception('이미 로그인된 계정입니다.');
      }

      // Google 로그인 프로세스 시작
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        throw Exception('Google 로그인이 취소되었습니다.');
      }

      // Google 인증 정보 가져오기
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Firebase 인증 정보 생성
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // 익명 계정과 Google 계정 연결
      final userCredential = await user.linkWithCredential(credential);

      // 사용자 정보 업데이트
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'name': userCredential.user!.displayName,
        'email': userCredential.user!.email,
        'isAnonymous': false,
        'profileImage': userCredential.user!.photoURL,
        'accountLinkedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return userCredential;
    } catch (e) {
      debugPrint('Google 계정 연결 오류: $e');
      rethrow;
    }
  }

  // 익명 계정을 Apple 계정으로 연결
  Future<UserCredential> linkAnonymousAccountWithApple() async {
    try {
      final user = _auth.currentUser;

      if (user == null) {
        throw Exception('로그인된 사용자가 없습니다.');
      }

      if (!user.isAnonymous) {
        throw Exception('이미 로그인된 계정입니다.');
      }

      // nonce 생성
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
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );

      // 익명 계정과 Apple 계정 연결
      final userCredential = await user.linkWithCredential(oauthCredential);

      // 사용자 이름 설정 (Apple은 첫 로그인에만 이름 제공)
      String? displayName = userCredential.user!.displayName;
      if (displayName == null || displayName.isEmpty) {
        displayName =
            '${appleCredential.givenName ?? ''} ${appleCredential.familyName ?? ''}'
                .trim();
        if (displayName.isNotEmpty) {
          await userCredential.user!.updateDisplayName(displayName);
        }
      }

      // 사용자 정보 업데이트
      await _firestore.collection('users').doc(userCredential.user!.uid).set({
        'name': displayName.isNotEmpty ? displayName : 'Apple 사용자',
        'email': userCredential.user!.email,
        'isAnonymous': false,
        'accountLinkedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return userCredential;
    } catch (e) {
      debugPrint('Apple 계정 연결 오류: $e');
      rethrow;
    }
  }

  // 로그아웃
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
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
}
