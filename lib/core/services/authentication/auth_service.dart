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
import '../../../core/services/media/image_service.dart';
import '../../../core/services/common/usage_limit_service.dart';
import '../common/plan_service.dart';
import 'user_preferences_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    forceCodeForRefreshToken: true,
    signInOption: SignInOption.standard,
    scopes: ['email', 'profile'],
  );

// === 인증상태 관리 및 재설치 여부 판단 ===

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

// === 소셜 로그인 ===

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

// === 로그아웃 ===

  Future<void> signOut() async {
    try {
      debugPrint('로그아웃 시작...');
      
      // 1. 현재 UID 저장
      final currentUid = _auth.currentUser?.uid;
      
      // 2. 병렬 처리 가능한 작업들
      await Future.wait([
        _clearSocialLoginSessions(),
        ImageService().clearImageCache(),
      ]);
      
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

// === 탈퇴 ===

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
      
      debugPrint('계정 삭제 시작: $userId');
      
      // 1. 재인증 필요 여부 확인 후 처리
      final needsReauth = await isReauthenticationRequired();
      if (needsReauth) {
        await _handleReauthentication(user);
        debugPrint('재인증 완료');
      } else {
        debugPrint('재인증 불필요 - 최근 로그인 상태로 바로 진행');
      }
      
      // 2. 모든 데이터 삭제 작업 수행
      await _deleteAllUserData(userId, userEmail, displayName);
      debugPrint('사용자 데이터 삭제 완료');
      
      // 3. Firebase Auth에서 사용자 삭제
      await user.delete();
      debugPrint('계정이 성공적으로 삭제되었습니다: $userId');
      
      // 4. 완전한 로그아웃 처리 (혹시 남아있을 수 있는 세션 정리)
      await _auth.signOut();
      await _googleSignIn.signOut();
      debugPrint('탈퇴 후 완전한 로그아웃 처리 완료');
      
    } catch (e) {
      debugPrint('계정 삭제 오류: $e');
      
      // 재인증 관련 오류는 구체적인 메시지 제공
      if (e is FirebaseAuthException) {
        if (e.code == 'requires-recent-login') {
          throw Exception(_getReauthRequiredMessage());
        } else if (e.code == 'user-not-found') {
          throw Exception('사용자를 찾을 수 없습니다.');
        } else if (e.code == 'network-request-failed') {
          throw Exception('네트워크 연결을 확인해주세요.');
        } else if (e.code == 'user-disabled') {
          throw Exception('비활성화된 계정입니다.');
        } else {
          throw Exception('계정 삭제 중 오류가 발생했습니다: ${e.message}');
        }
      }
      
      // 재인증 취소나 실패
      if (e.toString().contains('재인증이 취소') || e.toString().contains('재인증에 실패')) {
        throw Exception(_getReauthRequiredMessage());
      }
      
      // 기타 오류
      rethrow;
    }
  }

  // 재인증 필요 여부 확인 (최근 로그인 시간 기반)
  Future<bool> isReauthenticationRequired() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('사용자가 로그인되어 있지 않음');
        return false;
      }
      
      // ID 토큰에서 인증 시간 확인
      final idTokenResult = await user.getIdTokenResult();
      final lastSignInTime = idTokenResult.authTime;
      
      if (lastSignInTime != null) {
        final timeSinceLastSignIn = DateTime.now().difference(lastSignInTime);
        // Firebase는 보통 5분 이내 로그인을 "최근"으로 간주
        final isRecentLogin = timeSinceLastSignIn.inMinutes <= 5;
        
        debugPrint('마지막 로그인: ${lastSignInTime.toLocal()}');
        debugPrint('경과 시간: ${timeSinceLastSignIn.inMinutes}분');
        debugPrint('재인증 필요: ${!isRecentLogin}');
        
        return !isRecentLogin;
      } else {
        debugPrint('인증 시간 정보 없음 - 재인증 필요');
        return true;
      }
    } catch (e) {
      debugPrint('재인증 필요 여부 확인 중 오류: $e');
      // 에러 발생 시 안전하게 재인증 필요로 처리
      return true;
    }
  }

  // 재인증 필요 메시지 생성
  String _getReauthRequiredMessage() {
    return '계정 보안을 위해 재로그인이 필요합니다.\n탈퇴를 원하시면 로그아웃 후 재시도해주세요.';
  }

  // 재인증 처리 (항상 재인증 요구하므로 단순화)
  Future<void> _handleReauthentication(User user) async {
    final authProvider = user.providerData.firstOrNull?.providerId;
    debugPrint('계정 삭제를 위한 재인증 시작 - 인증 제공자: $authProvider');
    
    if (authProvider?.contains('google') == true) {
      await _reauthenticateWithGoogle(user);
    } else if (authProvider?.contains('apple') == true) {
      await _reauthenticateWithApple(user);
    } else {
      throw Exception('지원되지 않는 인증 방식입니다.\n로그아웃 후 다시 로그인해주세요.');
    }
    
    debugPrint('재인증 완료');
  }
  
  // Google 재인증 (오류 메시지 개선)
  Future<void> _reauthenticateWithGoogle(User user) async {
    try {
      debugPrint('Google 재인증 시작');
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw Exception('Google 재인증이 취소되었습니다.');
      }
      
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      
      await user.reauthenticateWithCredential(credential);
      debugPrint('Google 재인증 완료');
    } catch (e) {
      debugPrint('Google 재인증 실패: $e');
      if (e.toString().contains('취소')) {
        throw Exception('계정 보안을 위해 Google 재로그인이 필요합니다.\n탈퇴를 원하시면 재로그인 후 다시 시도해주세요.');
      } else {
        throw Exception('Google 재인증에 실패했습니다.\n네트워크를 확인하고 다시 시도해주세요.');
      }
    }
  }
  
  // Apple 재인증 (오류 메시지 개선)
  Future<void> _reauthenticateWithApple(User user) async {
    try {
      debugPrint('Apple 재인증 시작');
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
      
      await user.reauthenticateWithCredential(oauthCredential);
      debugPrint('Apple 재인증 완료');
    } catch (e) {
      debugPrint('Apple 재인증 실패: $e');
      if (e.toString().contains('취소') || e.toString().contains('cancel')) {
        throw Exception('계정 보안을 위해 Apple 재로그인이 필요합니다.\n탈퇴를 원하시면 재로그인 후 다시 시도해주세요.');
      } else {
        throw Exception('Apple 재인증에 실패했습니다.\n네트워크를 확인하고 다시 시도해주세요.');
      }
    }
  }

  // 모든 사용자 데이터 삭제를 처리하는 별도 메서드
  Future<void> _deleteAllUserData(String userId, String? email, String? displayName) async {
    try {
      debugPrint('사용자 데이터 삭제 시작: $userId');
      
      // 병렬로 처리 가능한 작업들
      await Future.wait([
        _clearAllLocalData(),
        _deleteFirestoreData(userId),
        _deleteFirebaseStorageData(userId),
      ]);
      
      // 소셜 로그인 세션 정리
      await _clearSocialLoginSessions();
      
      // 디바이스 ID 초기화
      await _resetDeviceId();
      
      // 탈퇴 기록 저장 (실패해도 계속 진행)
      try {
        await _saveDeletedUserRecord(userId, email, displayName);
        debugPrint('탈퇴 기록 저장 완료');
      } catch (e) {
        debugPrint('탈퇴 기록 저장 실패 (무시): $e');
      }
      
      debugPrint('모든 사용자 데이터 삭제 완료');
    } catch (e) {
      debugPrint('사용자 데이터 삭제 중 오류: $e');
      rethrow;
    }
  }

  // Firebase Storage 데이터 삭제 (분리됨)
  Future<void> _deleteFirebaseStorageData(String userId) async {
    try {
      final usageLimitService = UsageLimitService();
      final storageDeleted = await usageLimitService.deleteFirebaseStorageData(userId);
      
      if (storageDeleted) {
        debugPrint('Firebase Storage 데이터 삭제 완료: $userId');
      } else {
        debugPrint('Firebase Storage 데이터 없음 또는 삭제 실패: $userId');
      }
    } catch (e) {
      debugPrint('Firebase Storage 데이터 삭제 중 오류: $e');
      // Storage 삭제 실패는 치명적이지 않으므로 계속 진행
    }
  }

  // 로컬 데이터 완전 삭제 (병렬 처리 추가)
  Future<void> _clearAllLocalData() async {
    try {
      debugPrint('로컬 데이터 삭제 시작');
      
      // 병렬로 처리 가능한 작업들
      await Future.wait([
        _clearImageFiles(),
        _clearSharedPreferences(),
        _clearAllServiceCaches(), // 모든 서비스 캐시 초기화 추가
      ]);
      
      debugPrint('로컬 데이터 완전 삭제 완료');
    } catch (e) {
      debugPrint('로컬 데이터 삭제 중 오류: $e');
      rethrow;
    }
  }
  
  // 이미지 파일 삭제
  Future<void> _clearImageFiles() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final imageDir = Directory('${appDir.path}/images');
      
      if (await imageDir.exists()) {
        await imageDir.delete(recursive: true);
        debugPrint('이미지 디렉토리 삭제 완료');
      }
    } catch (e) {
      debugPrint('이미지 파일 삭제 중 오류: $e');
      // 이미지 삭제 실패는 치명적이지 않음
    }
  }
  
  // SharedPreferences 삭제 (최적화: clear()만 사용)
  Future<void> _clearSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 전체 초기화 (clear()가 모든 키를 삭제하므로 개별 삭제 불필요)
      await prefs.clear();
      
      debugPrint('SharedPreferences 완전 삭제 완료');
    } catch (e) {
      debugPrint('SharedPreferences 삭제 중 오류: $e');
      rethrow;
    }
  }

  // Firestore 데이터 완전 삭제 (배치 크기 제한 처리 추가)
  Future<void> _deleteFirestoreData(String userId) async {
    try {
      debugPrint('Firestore 데이터 삭제 시작: $userId');
      
      // 디바이스 ID 가져오기
      final deviceId = await _getDeviceId();
      
      // 1. 사용자 문서 삭제
      await FirebaseFirestore.instance.collection('users').doc(userId).delete();
      debugPrint('사용자 문서 삭제 완료');
      
      // 2. 컬렉션별로 배치 삭제 (크기 제한 고려)
      await _deleteBatchCollection('notes', 'userId', userId);
      await _deleteBatchCollection('notes', 'deviceId', deviceId); // 익명 노트
      await _deleteBatchCollection('pages', 'userId', userId);
      await _deleteBatchCollection('flashcards', 'userId', userId);
      // deleted_users는 삭제하지 않음 - 탈퇴 기록 보존을 위해
      
      debugPrint('Firestore 데이터 완전 삭제 완료');
    } catch (e) {
      debugPrint('Firestore 데이터 삭제 중 오류: $e');
      rethrow;
    }
  }
  
  // 배치 삭제 헬퍼 메서드 (500개 제한 처리)
  Future<void> _deleteBatchCollection(String collection, String field, String value) async {
    try {
      const int batchSize = 500; // Firestore 배치 제한
      bool hasMore = true;
      
      while (hasMore) {
        final query = await FirebaseFirestore.instance
            .collection(collection)
            .where(field, isEqualTo: value)
            .limit(batchSize)
            .get();
            
        if (query.docs.isEmpty) {
          hasMore = false;
          break;
        }
        
        final batch = FirebaseFirestore.instance.batch();
        for (var doc in query.docs) {
          batch.delete(doc.reference);
        }
        
        await batch.commit();
        debugPrint('$collection 배치 삭제 완료: ${query.docs.length}개');
        
        // 마지막 배치인지 확인
        hasMore = query.docs.length == batchSize;
      }
    } catch (e) {
      debugPrint('$collection 배치 삭제 중 오류: $e');
      rethrow;
    }
  }

  // 탈퇴 기록 저장 (중복 방지)
  Future<void> _saveDeletedUserRecord(String userId, String? email, String? displayName) async {
    try {
      final docRef = FirebaseFirestore.instance.collection('deleted_users').doc(userId);
      
      // 기존 기록 확인
      final existingDoc = await docRef.get();
      
      if (existingDoc.exists) {
        debugPrint('탈퇴 기록이 이미 존재함: $userId');
        // 기존 기록에 재탈퇴 시간 추가
        await docRef.update({
          'lastDeletedAt': FieldValue.serverTimestamp(),
          'deleteCount': FieldValue.increment(1),
        });
        debugPrint('탈퇴 기록 업데이트 완료');
      } else {
        // 새로운 탈퇴 기록 생성
        await docRef.set({
          'userId': userId,
          'email': email,
          'displayName': displayName,
          'deletedAt': FieldValue.serverTimestamp(),
          'lastDeletedAt': FieldValue.serverTimestamp(),
          'deleteCount': 1,
        });
        debugPrint('새 탈퇴 기록 저장 완료');
      }
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

  // 핵심 서비스 캐시 초기화
  Future<void> _clearAllServiceCaches() async {
    try {
      debugPrint('핵심 서비스 캐시 초기화 시작');
      
      // PlanService 캐시 초기화 (가장 중요)
      final planService = PlanService();
      planService.clearCache();
      
      // UserPreferences 초기화 (온보딩 상태 등)
      final userPrefsService = UserPreferencesService();
      // 모든 사용자 설정 삭제
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear(); // 이미 위에서 호출되지만 확실히 하기 위해
      
      debugPrint('핵심 서비스 캐시 초기화 완료');
    } catch (e) {
      debugPrint('서비스 캐시 초기화 중 오류: $e');
      // 캐시 초기화 실패는 치명적이지 않으므로 계속 진행
    }
  }

  // 소셜 로그인 세션 완전 정리
  Future<void> _clearSocialLoginSessions() async {
    try {
      debugPrint('소셜 로그인 세션 정리 시작');
      
      // 병렬로 처리
      await Future.wait([
        _clearGoogleSession(),
        _clearAppleSession(),
      ]);
      
      debugPrint('모든 소셜 로그인 세션 정리 완료');
    } catch (e) {
      debugPrint('소셜 로그인 세션 정리 중 오류: $e');
      // 세션 정리 실패는 치명적이지 않음
    }
  }
  
  // Google 세션 정리
  Future<void> _clearGoogleSession() async {
    try {
      final googleSignIn = GoogleSignIn();
      if (await googleSignIn.isSignedIn()) {
        await googleSignIn.disconnect();
        await googleSignIn.signOut();
        debugPrint('Google 계정 연결 완전 해제됨');
      }
    } catch (e) {
      debugPrint('Google 세션 정리 중 오류: $e');
    }
  }
  
  // Apple 세션 정리
  Future<void> _clearAppleSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Apple 관련 모든 캐시 키 삭제
      final keys = prefs.getKeys();
      final appleKeys = keys.where((key) => 
        key.contains('apple') || 
        key.contains('Apple') || 
        key.contains('sign_in') || 
        key.contains('oauth') ||
        key.contains('token') ||
        key.contains('credential')
      ).toList();
      
      for (final key in appleKeys) {
        await prefs.remove(key);
      }
      
      debugPrint('Apple 로그인 관련 정보 정리 완료');
    } catch (e) {
      debugPrint('Apple 세션 정리 중 오류: $e');
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
        
        // 7일 무료 체험 시작
        try {
          final planService = PlanService();
          final trialStarted = await planService.startFreeTrial(user.uid);
          
          if (trialStarted) {
            debugPrint('신규 사용자 7일 무료 체험 시작: ${user.uid}');
          } else {
            debugPrint('무료 체험 시작 실패 (이미 사용했거나 오류): ${user.uid}');
          }
        } catch (e) {
          debugPrint('무료 체험 시작 중 오류: $e');
          // 무료 체험 시작 실패해도 회원가입은 계속 진행
        }
        
        // 신규 사용자는 항상 set 사용
        await userRef.set(userData);
      } else {
        // 기존 사용자 정보 업데이트
        final deviceId = await _getDeviceId();
        userData['lastUpdated'] = FieldValue.serverTimestamp();
        
        // 기존 문서 확인
        final userDoc = await userRef.get();
        if (userDoc.exists) {
          // 문서가 존재하면 update 사용
          final List<dynamic> deviceIds = userDoc.data()?['deviceIds'] ?? [];
          if (!deviceIds.contains(deviceId)) {
            userData['deviceIds'] = FieldValue.arrayUnion([deviceId]);
            userData['deviceCount'] = deviceIds.length + 1;
          }
          await userRef.update(userData);
        } else {
          // 문서가 없으면 set 사용 (온보딩 미완료 사용자)
          userData['createdAt'] = FieldValue.serverTimestamp();
          userData['isNewUser'] = false;
          userData['planType'] = 'free';
          userData['deviceCount'] = 1;
          userData['deviceIds'] = [deviceId];
          await userRef.set(userData);
        }
      }
      
      debugPrint('사용자 정보 Firestore 저장 완료: ${user.uid}');
    } catch (e) {
      debugPrint('사용자 정보 Firestore 저장 중 오류: $e');
      // 오류가 있어도 로그인 프로세스는 계속 진행
    }
  }
}

