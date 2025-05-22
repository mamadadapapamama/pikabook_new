import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../media/image_service.dart';
import '../common/usage_limit_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
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

  // Apple로 로그인
  Future<User?> signInWithApple() async {
    try {
      debugPrint('Apple login: 1. Starting authentication...');
      
      // 앱 재설치 여부 확인
      await _checkAppInstallation();
      
      // Apple 로그인 시작
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      
      debugPrint('Apple login: 2. Got Apple credentials');
      
      // OAuthCredential 생성
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      
      debugPrint('Apple login: 3. Created OAuth credential');
      
      // Firebase 인증
      final userCredential = await _auth.signInWithCredential(oauthCredential);
      final user = userCredential.user;
      
      debugPrint('Apple login: 4. Signed in with Firebase');
      
      // 사용자 정보가 있으면 Firestore에 저장
      if (user != null) {
        // 이름 정보가 있다면 업데이트 (애플은 첫 로그인에만 이름 제공)
        if (appleCredential.givenName != null && userCredential.additionalUserInfo?.isNewUser == true) {
          // 사용자 프로필 업데이트
          await user.updateDisplayName('${appleCredential.givenName} ${appleCredential.familyName}'.trim());
          debugPrint('Apple login: 5. Updated user display name');
        }
        
        await _saveUserToFirestore(user, isNewUser: userCredential.additionalUserInfo?.isNewUser ?? false);
        debugPrint('Apple login: 6. Saved user to Firestore');
      }
      
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
      
      // 앱 재설치 여부 확인
      await _checkAppInstallation();
      
      // Apple 로그인을 사용한 Firebase 인증
      final provider = OAuthProvider('apple.com')
        ..addScope('email')
        ..addScope('name');
        
      // 인증 시도
      final result = await _auth.signInWithProvider(provider);
      final user = result.user;
      
      // 사용자 정보가 있으면 Firestore에 저장
      if (user != null) {
        await _saveUserToFirestore(user, isNewUser: result.additionalUserInfo?.isNewUser ?? false);
        debugPrint('Alternative Apple login: 2. Signed in successfully');
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
      
      // 2. 이미지 캐시 정리
      await ImageService().clearImageCache();
      
      // 3. Firebase 로그아웃
      await _auth.signOut();
      
      debugPrint('로그아웃 완료');
      
      // 4. 세션 종료 처리 (필요시)
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
      
      // 1. 이미지 파일 삭제
      final appDir = await getApplicationDocumentsDirectory();
      final imageDir = Directory('${appDir.path}/images');
      if (await imageDir.exists()) {
        await imageDir.delete(recursive: true);
        debugPrint('이미지 디렉토리 삭제 완료');
      }
      
      // 2. SharedPreferences 완전 초기화
      await prefs.clear();
      
      // 3. 중요 키 개별 삭제 (혹시 모를 잔여 데이터 제거)
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
      final batch = FirebaseFirestore.instance.batch();
      
      // 1. 사용자 문서 삭제
      batch.delete(FirebaseFirestore.instance.collection('users').doc(userId));
      
      // 2. 노트 삭제 (익명 노트 포함)
      final notesQuery = await FirebaseFirestore.instance.collection('notes')
          .where('userId', isEqualTo: userId)
          .get();
      for (var doc in notesQuery.docs) {
        batch.delete(doc.reference);
      }
      
      // 2-1. 익명 노트도 함께 삭제
      final anonymousNotesQuery = await FirebaseFirestore.instance.collection('notes')
          .where('deviceId', isEqualTo: await _getDeviceId())
          .get();
      for (var doc in anonymousNotesQuery.docs) {
        batch.delete(doc.reference);
      }
      
      // 3. 페이지 삭제
      final pagesQuery = await FirebaseFirestore.instance.collection('pages')
          .where('userId', isEqualTo: userId)
          .get();
      for (var doc in pagesQuery.docs) {
        batch.delete(doc.reference);
      }
      
      // 4. 플래시카드 삭제
      final flashcardsQuery = await FirebaseFirestore.instance.collection('flashcards')
          .where('userId', isEqualTo: userId)
          .get();
      for (var doc in flashcardsQuery.docs) {
        batch.delete(doc.reference);
      }
      
      // 5. 이전 탈퇴 기록 삭제
      final deletedUserQuery = await FirebaseFirestore.instance.collection('deleted_users')
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
      await FirebaseFirestore.instance.collection('deleted_users').doc(userId).set({
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
      
      debugPrint('모든 캐시 데이터 초기화 완료');
    } catch (e) {
      debugPrint('소셜 로그인 세션 정리 중 오류: $e');
    }
  }

  /// 사용자 세션 종료 처리 (필요한 정리 작업 수행)
  Future<void> _endUserSession(String userId) async {
    try {
      // 사용자 세션 상태 업데이트 (활성 상태 false로 설정)
      await FirebaseFirestore.instance.collection('user_sessions').doc(userId).update({
        'isActive': false,
        'lastLogoutAt': FieldValue.serverTimestamp(),
      });
      
      debugPrint('사용자 세션 종료 처리 완료: $userId');
    } catch (e) {
      debugPrint('사용자 세션 종료 처리 중 오류 (무시됨): $e');
      // 세션 종료 처리 실패는 치명적이지 않으므로 오류를 무시함
    }
  }

  // 사용자 정보를 Firestore에 저장하는 메서드
  Future<void> _saveUserToFirestore(User user, {bool isNewUser = false}) async {
    try {
      final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      
      // 사용자 기본 정보
      final userData = {
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName ?? '',
        'photoURL': user.photoURL ?? '',
        'lastLogin': FieldValue.serverTimestamp(),
      };
      
      // 신규 사용자인 경우 추가 정보 설정
      if (isNewUser) {
        userData['createdAt'] = FieldValue.serverTimestamp();
        userData['isNewUser'] = true;
        userData['planType'] = 'free'; // 기본 플랜 타입
        userData['deviceCount'] = 1;
        userData['deviceIds'] = [await _getDeviceId()];
      } else {
        // 기존 사용자 정보 업데이트
        final deviceId = await _getDeviceId();
        userData['lastUpdated'] = FieldValue.serverTimestamp();
        
        // 디바이스 ID 추가 (중복 없이)
        final userDoc = await userRef.get();
        if (userDoc.exists) {
          final List<dynamic> deviceIds = userDoc.data()?['deviceIds'] ?? [];
          if (!deviceIds.contains(deviceId)) {
            userData['deviceIds'] = FieldValue.arrayUnion([deviceId]);
            userData['deviceCount'] = deviceIds.length + 1;
          }
        }
      }
      
      // 데이터 저장 - 새 사용자는 set, 기존 사용자는 update
      if (isNewUser) {
        await userRef.set(userData);
      } else {
        await userRef.update(userData);
      }
      
      debugPrint('사용자 정보 Firestore 저장 완료: ${user.uid}');
    } catch (e) {
      debugPrint('사용자 정보 Firestore 저장 중 오류: $e');
      // 오류가 있어도 로그인 프로세스는 계속 진행
    }
  }
}

