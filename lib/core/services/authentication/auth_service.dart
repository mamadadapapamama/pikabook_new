import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';

import 'user_account_service.dart';

/// 🎯 Firebase 인증 제공자(Provider)를 관리하고 인증 흐름을 처리하는 서비스
///
/// **주요 책임:**
/// - 이메일, Google, Apple 등 다양한 인증 수단을 통한 로그인/회원가입 처리.
/// - Firebase Auth 상태 변경 스트림(`authStateChanges`) 및 현재 사용자(`currentUser`) 제공.
/// - 로그아웃 처리.
///
/// **참고:**
/// - 사용자 데이터(Firestore) 관리는 `UserAccountService`가 담당합니다.
/// - 인증 상태 변경에 따른 후속 작업(캐시 정리 등)은 `UserLifecycleManager`가 담당합니다.
class AuthService {
  // 🎯 상수 정의
  static const String _appInstallKey = 'pikabook_installed';
  
  // 🔄 싱글톤 패턴 구현
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    forceCodeForRefreshToken: true,
    signInOption: SignInOption.standard,
    scopes: ['email', 'profile'],
    hostedDomain: null,
  );

  AuthService._internal(); // 생성자는 비워 둠
  
// === 인증상태 관리 및 재설치 여부 판단 ===

  // 현재 사용자 가져오기
  User? get currentUser => _auth.currentUser;

  // 사용자 상태 변경 스트림
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// 앱 재설치 확인 메서드
  Future<bool> _checkAppInstallation() async {
    final prefs = await SharedPreferences.getInstance();
    final bool isAppAlreadyInstalled = prefs.getBool(_appInstallKey) ?? false;
    
    if (!isAppAlreadyInstalled) {
      await prefs.setBool(_appInstallKey, true);
      if (FirebaseAuth.instance.currentUser != null) {
        await FirebaseAuth.instance.signOut();
        debugPrint('새 설치 감지: Auth Service에서 로그아웃 처리');
        return true;
      }
    }
    return false;
  }

// === 이메일 로그인 ===

  // 이메일로 회원가입
  Future<User?> signUpWithEmail(String email, String password) async {
    try {
      await _checkAppInstallation();
      
      final UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final User? user = userCredential.user;
      
      if (user != null) {
        await _sendEmailVerification(user);
        await UserAccountService().synchronizeUserData(user, isNewUser: true);
        debugPrint('이메일 회원가입 성공: ${user.uid}');
      }
      return user;
    } catch (e) {
      debugPrint('이메일 회원가입 오류: $e');
      rethrow;
    }
  }

  // 이메일로 로그인
  Future<User?> signInWithEmail(String email, String password) async {
    try {
      await _checkAppInstallation();
      
      final UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final User? user = userCredential.user;
      
      if (user != null) {
        await UserAccountService().synchronizeUserData(user, isNewUser: false);
        debugPrint('이메일 로그인 성공: ${user.uid}');
      }
      return user;
    } catch (e) {
      debugPrint('이메일 로그인 오류: $e');
      rethrow;
    }
  }

// === 이메일 검증 및 비밀번호 관련 기능 ===

  /// 이메일 검증 메일 발송 (내부 사용)
  Future<void> _sendEmailVerification(User user) async {
    try {
      if (!user.emailVerified) {
        await user.sendEmailVerification();
        debugPrint('✅ [AuthService] 이메일 검증 메일 발송: ${user.email}');
      }
    } catch (e) {
      debugPrint('❌ [AuthService] 이메일 검증 메일 발송 실패: $e');
    }
  }

  /// 이메일 검증 메일 재발송 (공개 메소드)
  Future<bool> resendEmailVerification() async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('로그인이 필요합니다.');

      if (user.emailVerified) {
        debugPrint('✅ [AuthService] 이미 이메일이 검증됨');
        return true;
      }

      await user.sendEmailVerification();
      debugPrint('✅ [AuthService] 이메일 검증 메일 재발송: ${user.email}');
      return true;
    } catch (e) {
      debugPrint('❌ [AuthService] 이메일 검증 메일 재발송 실패: $e');
      rethrow;
    }
  }

  /// 이메일 검증 상태 확인 및 새로고침
  Future<bool> checkEmailVerification() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      await user.reload();
      final refreshedUser = _auth.currentUser;
      
      debugPrint('🔍 [AuthService] 이메일 검증 상태: ${refreshedUser?.emailVerified}');
      return refreshedUser?.emailVerified ?? false;
    } catch (e) {
      debugPrint('❌ [AuthService] 이메일 검증 상태 확인 실패: $e');
      return false;
    }
  }

  /// 비밀번호 재설정 메일 발송
  Future<bool> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      debugPrint('✅ [AuthService] 비밀번호 재설정 메일 발송: $email');
      return true;
    } catch (e) {
      debugPrint('❌ [AuthService] 비밀번호 재설정 메일 발송 실패: $e');
      rethrow;
    }
  }

  /// 현재 사용자의 이메일 검증 상태 확인
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  /// 현재 사용자의 이메일 주소
  String? get currentUserEmail => _auth.currentUser?.email;

// === 소셜 로그인 ===

  // Google 로그인
  Future<User?> signInWithGoogle() async {
    try {
      await _checkAppInstallation();
      
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        debugPrint('구글 로그인 취소됨');
        return null;
      }
      
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      
      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final User? user = userCredential.user;
      
      if (user != null) {
        await UserAccountService().synchronizeUserData(user, isNewUser: userCredential.additionalUserInfo?.isNewUser ?? false);
        debugPrint('구글 로그인 성공: ${user.uid}');
      }
      return user;
    } catch (e) {
      debugPrint('구글 로그인 오류: $e');
      rethrow;
    }
  }

  // Apple로 로그인
  Future<User?> signInWithApple() async {
    try {
      await _checkAppInstallation();
      
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      
      final userCredential = await _auth.signInWithCredential(oauthCredential);
      final user = userCredential.user;
      
      if (user != null) {
        if (appleCredential.givenName != null && userCredential.additionalUserInfo?.isNewUser == true) {
          await user.updateDisplayName('${appleCredential.givenName} ${appleCredential.familyName}'.trim());
        }
        await UserAccountService().synchronizeUserData(user, isNewUser: userCredential.additionalUserInfo?.isNewUser ?? false);
        debugPrint('Apple 로그인 성공: ${user.uid}');
      }
      return user;
    } catch (e) {
      debugPrint('Apple 로그인 오류: $e');
      rethrow;
    }
  }

// === 로그아웃 및 계정 삭제 ===

  /// 로그아웃
  Future<void> signOut() async {
    try {
      if (kDebugMode) {
        print('🚪 [AuthService] 로그아웃 시작 (UID: ${_auth.currentUser?.uid})');
      }

      await Future.wait([
        _auth.signOut(),
        _googleSignIn.signOut(),
      ]);
      
      if (kDebugMode) {
        print('✅ [AuthService] 로그아웃 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ [AuthService] 로그아웃 중 오류: $e');
      }
    }
  }

  /// 계정 삭제 (UserAccountService에 위임)
  Future<void> deleteAccount() async {
    try {
      await UserAccountService().deleteAccount();
      // 계정 삭제 성공 후, authStateChanges가 변경을 감지하고
      // UserLifecycleManager가 후속 처리를 담당.
      // 여기서는 추가적인 signOut() 호출이 필요 없음.
    } catch(e) {
      debugPrint('계정 삭제 프로세스 실패: $e');
      rethrow;
    }
  }
}

