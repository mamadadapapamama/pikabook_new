import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/services/media/image_service.dart';
import '../../../core/services/common/usage_limit_service.dart';
import 'user_preferences_service.dart';
import 'deleted_user_service.dart';
import '../cache/event_cache_manager.dart';

import '../subscription/unified_subscription_manager.dart';
import '../common/banner_manager.dart';


class AuthService {
  // 🎯 상수 정의
  static const String _appInstallKey = 'pikabook_installed';
  static const String _deviceIdKey = 'device_id';
  static const String _lastUserIdKey = 'last_user_id';
  static const int _batchSize = 500; // Firestore 배치 제한
  static const int _recentLoginMinutes = 5; // 재인증 필요 시간
  
  // 🔄 싱글톤 패턴 구현
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    forceCodeForRefreshToken: true,
    signInOption: SignInOption.standard,
    scopes: ['email', 'profile'],
    // 🚫 로컬 네트워크 검색 비활성화
    hostedDomain: null,
  );
  
  String? _lastUserId;
  bool _isInitialized = false; // 🎯 중복 초기화 방지
  Timer? _subscriptionRefreshTimer; // 🎯 구독 새로고침 디바운싱
  
  AuthService._internal() {
    _initializeUserChangeDetection();
  }
  
  /// 사용자 변경 감지 및 캐시 초기화 (중복 초기화 방지)
  void _initializeUserChangeDetection() {
    if (_isInitialized) {
      if (kDebugMode) {
        debugPrint('🔄 [AuthService] 이미 초기화됨 - 중복 초기화 방지');
      }
      return;
    }
    
    if (kDebugMode) {
      debugPrint('🔄 [AuthService] 사용자 변경 감지 리스너 초기화 시작');
    }
    
    _isInitialized = true;
    _auth.authStateChanges().listen((User? user) async {
      final currentUserId = user?.uid;
      
      // 🎯 중복 로그 방지: 실제로 사용자가 변경된 경우에만 로그 출력
      if (_lastUserId != currentUserId) {
        if (kDebugMode) {
          debugPrint('🔍 [AuthService] 인증 상태 변경: ${_lastUserId ?? "없음"} → ${currentUserId ?? "없음"}');
        }
        
        // 🎯 일시적인 인증 상태 변경 무시 (In-App Purchase 중 발생할 수 있음)
        if (_lastUserId != null && currentUserId == null) {
          // 로그인 상태에서 로그아웃으로 변경된 경우 - 잠시 대기 후 재확인
          if (kDebugMode) {
            debugPrint('⚠️ [AuthService] 일시적 로그아웃 감지 - 3초 후 재확인');
          }
          
          await Future.delayed(const Duration(seconds: 3));
          
          // 3초 후 다시 확인
          final reconfirmedUser = _auth.currentUser;
          if (reconfirmedUser != null) {
            if (kDebugMode) {
              debugPrint('✅ [AuthService] 일시적 로그아웃이었음 - 사용자 복원됨: ${reconfirmedUser.uid}');
            }
            return; // 일시적 변경이었으므로 처리하지 않음
          } else {
            if (kDebugMode) {
              debugPrint('🔍 [AuthService] 실제 로그아웃 확인됨');
            }
          }
        }
        
        // 사용자가 변경된 경우 (로그아웃 → 로그인, 다른 사용자로 로그인)
        if (_lastUserId != null && _lastUserId != currentUserId) {
          if (kDebugMode) {
            debugPrint('🔄 [AuthService] 사용자 변경 감지 - 캐시 초기화');
            debugPrint('   이전 사용자: $_lastUserId → 현재 사용자: $currentUserId');
          }
          
          // 🎯 구독 서비스 캐시 무효화 (중요!)
          _invalidateSubscriptionCaches();
          
          // 🎯 배너 상태 초기화 (로그아웃 시와 사용자 전환 시 모두)
          if (currentUserId == null) {
            // 로그아웃하는 경우
            if (kDebugMode) {
              debugPrint('🔄 [AuthService] 로그아웃 감지 - 배너 상태 초기화');
            }
            _clearBannerStates();
          } else {
            // 다른 사용자로 로그인하는 경우 - 이전 사용자 배너 캐시 즉시 무효화
            if (kDebugMode) {
              debugPrint('🔄 [AuthService] 사용자 전환 감지 - 이전 사용자 배너 캐시 무효화');
            }
            _clearBannerStates(); // 사용자 전환 시에도 배너 캐시 무효화
          }
          
          // 모든 캐시 초기화
          final eventCache = EventCacheManager();
          eventCache.clearAllCache();
          
          // SharedPreferences에서 사용자별 데이터 정리
          await _removePrefsKey(_lastUserIdKey);
        }
        
        _lastUserId = currentUserId;
        
        // 새 사용자 ID 저장
        if (currentUserId != null) {
          await _setPrefsString(_lastUserIdKey, currentUserId);
          
          // 🎯 로그인 시점에 App Store에서 강제로 구독 정보 불러오기
          await _forceRefreshSubscriptionOnLogin();
        }
      }
    });
  }

  /// 사용자 변경 감지 및 구독 캐시 무효화
  void _invalidateSubscriptionCaches() {
    if (kDebugMode) {
      debugPrint('🔄 [AuthService] 사용자 변경으로 인한 구독 캐시 무효화');
    }
    
    UnifiedSubscriptionManager().invalidateCache();
  }

  /// 🎯 배너 상태 초기화 (로그인/로그아웃 시)
  void _clearBannerStates() {
    if (kDebugMode) {
      debugPrint('🔄 [AuthService] 사용자 변경으로 인한 배너 상태 초기화');
    }
    
    try {
      final bannerManager = BannerManager();
      bannerManager.clearUserBannerStates();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AuthService] 배너 상태 초기화 실패: $e');
      }
    }
  }

  /// 로그인 후 구독 상태 강제 새로고침 (디바운싱 적용)
  Future<void> _forceRefreshSubscriptionOnLogin() async {
    // 🎯 기존 타이머 취소
    _subscriptionRefreshTimer?.cancel();
    
    // 🎯 500ms 디바운싱 적용
    _subscriptionRefreshTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        if (kDebugMode) {
          debugPrint('🔄 [AuthService] 로그인 후 구독 상태 강제 새로고침 시작 (디바운싱됨)');
        }
        
        // 🚨 온보딩 완료 여부 확인 - 신규 사용자는 온보딩 완료 후에만 구독 상태 체크
        final userPreferences = UserPreferencesService();
        final preferences = await userPreferences.getPreferences();
        final hasCompletedOnboarding = preferences.onboardingCompleted;
        
        if (!hasCompletedOnboarding) {
          if (kDebugMode) {
            debugPrint('⚠️ [AuthService] 온보딩 미완료 사용자 - 구독 상태 체크 건너뜀');
          }
          return;
        }
        
        if (kDebugMode) {
          debugPrint('✅ [AuthService] 온보딩 완료된 사용자 - 구독 상태 체크 진행');
        }
        
        // 로그인 직후에는 항상 최신 구독 상태를 서버에서 가져옴
        await UnifiedSubscriptionManager().getSubscriptionState(
          forceRefresh: true, // 강제 새로고침
        );
        
        if (kDebugMode) {
          debugPrint('✅ [AuthService] 로그인 후 구독 상태 새로고침 완료');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ [AuthService] 로그인 후 구독 상태 새로고침 실패: $e');
        }
      }
    });
  }

// === 인증상태 관리 및 재설치 여부 판단 ===

  // 현재 사용자 가져오기
  User? get currentUser => _auth.currentUser;

  // 사용자 상태 변경 스트림
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// 앱 재설치 확인 메서드
  Future<bool> _checkAppInstallation() async {
    // 앱 설치 확인 키가 있는지 확인
    final bool isAppAlreadyInstalled = await _getPrefsBool(_appInstallKey) ?? false;
    
    // 키가 없으면 새 설치로 간주하고 설정
    if (!isAppAlreadyInstalled) {
      await _setPrefsBool(_appInstallKey, true);
      // 기존에 로그인된 상태면 강제 로그아웃
      if (FirebaseAuth.instance.currentUser != null) {
        await FirebaseAuth.instance.signOut();
        debugPrint('새 설치 감지: Auth Service에서 로그아웃 처리');
        return true; // 새 설치
      }
    }
    
    return false; // 기존 설치
  }

// === 이메일 로그인 ===

  // 이메일로 회원가입
  Future<User?> signUpWithEmail(String email, String password) async {
    try {
      // 앱 재설치 여부 확인
      await _checkAppInstallation();
      
      final UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      final User? user = userCredential.user;
      
      // 사용자 정보가 있다면 Firestore에 사용자 정보 저장
      if (user != null) {
        // 🎯 회원가입 시 이메일 검증 메일 자동 발송
        await _sendEmailVerification(user);
        
        await _saveUserToFirestore(user, isNewUser: true);
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
      // 앱 재설치 여부 확인
      await _checkAppInstallation();
      
      final UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      final User? user = userCredential.user;
      
      // 사용자 정보가 있다면 Firestore에 사용자 정보 업데이트
      if (user != null) {
        await _saveUserToFirestore(user, isNewUser: false);
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
      // 이메일 발송 실패해도 회원가입은 진행
    }
  }

  /// 이메일 검증 메일 재발송 (공개 메소드)
  Future<bool> resendEmailVerification() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다.');
      }

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

      // 서버에서 최신 상태 가져오기
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
  bool get isEmailVerified {
    return _auth.currentUser?.emailVerified ?? false;
  }

  /// 현재 사용자의 이메일 주소
  String? get currentUserEmail {
    return _auth.currentUser?.email;
  }

// === 소셜 로그인 ===

  /// Apple Sign In 공통 오류 처리
  User? _handleAppleSignInError(dynamic e, String context) {
    debugPrint('$context 오류: $e');
    
    // 🎯 Apple Sign In 특정 오류 처리
    if (e.toString().contains('AuthorizationError Code=1001')) {
      // 사용자 취소 - null 반환하여 조용히 처리
      debugPrint('$context: 사용자가 취소함');
      return null;
    }
    
    if (e.toString().contains('AKAuthenticationError Code=-7003')) {
      // Apple ID 인증 실패 - 재시도 권장
      debugPrint('$context: Apple ID 인증 실패');
      throw Exception('Apple ID 인증에 실패했습니다. 다시 시도해 주세요.');
    }
    
    if (e.toString().contains('NSOSStatusErrorDomain Code=-54')) {
      // 시스템 권한 오류 - 디바이스 재부팅 권장
      debugPrint('$context: 시스템 권한 오류');
      throw Exception('시스템 오류가 발생했습니다. 디바이스를 재부팅하고 다시 시도해 주세요.');
    }
    
    // 오류 세부 정보 출력
    if (e is FirebaseAuthException) {
      debugPrint('Firebase Auth Error Code: ${e.code}');
      debugPrint('Firebase Auth Error Message: ${e.message}');
    }
    
    // 기타 오류는 다시 던지기
    throw e;
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
      return _handleAppleSignInError(e, 'Apple Sign In');
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
      return _handleAppleSignInError(e, 'Alternative Apple Sign In');
    }
  }

// === 로그아웃 ===

  Future<void> signOut() async {
    try {
      debugPrint('로그아웃 시작...');
      
      // 1. 현재 UID 저장
      final currentUid = _auth.currentUser?.uid;
      
      // 2. 타이머 정리
      _subscriptionRefreshTimer?.cancel();
      
      // 3. 병렬 처리 가능한 작업들
      await Future.wait([
        _clearSocialLoginSessions(),
        ImageService().clearImageCache(),
      ]);
      
      // 4. Firebase 로그아웃
      await _auth.signOut();
      
      debugPrint('로그아웃 완료');
      
      // 5. 세션 종료 처리 (필요시)
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
        final isRecentLogin = timeSinceLastSignIn.inMinutes <= _recentLoginMinutes;
        
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
  
  /// 재인증 오류 처리 공통 메서드
  void _handleReauthError(dynamic e, String provider) {
    debugPrint('$provider 재인증 실패: $e');
    if (e.toString().contains('취소') || e.toString().contains('cancel')) {
      throw Exception('계정 보안을 위해 $provider 재로그인이 필요합니다.\n탈퇴를 원하시면 재로그인 후 다시 시도해주세요.');
    } else {
      throw Exception('$provider 재인증에 실패했습니다.\n네트워크를 확인하고 다시 시도해주세요.');
    }
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
      _handleReauthError(e, 'Google');
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
      _handleReauthError(e, 'Apple');
    }
  }

  // 모든 사용자 데이터 삭제를 처리하는 별도 메서드
  Future<void> _deleteAllUserData(String userId, String? email, String? displayName) async {
    try {
      debugPrint('사용자 데이터 삭제 시작: $userId');
      
      // 🔥 중요: Firestore 데이터 삭제 전에 플랜 정보를 먼저 수집
      Map<String, dynamic>? subscriptionDetails;
      try {
        // PlanService 완전 삭제. 구독 정보는 UnifiedSubscriptionManager 또는 null-safe 기본값 사용
        final unifiedManager = UnifiedSubscriptionManager();
        final subscriptionState = await unifiedManager.getSubscriptionState(forceRefresh: true);
        subscriptionDetails = {
          'entitlement': subscriptionState.entitlement.value,
          'subscriptionStatus': subscriptionState.subscriptionStatus.value,
          'hasUsedTrial': subscriptionState.hasUsedTrial,
          'isPremium': subscriptionState.isPremium,
          'isTrial': subscriptionState.isTrial,
          'isExpired': subscriptionState.isExpired,
          'daysRemaining': subscriptionState.daysRemaining,
          'statusMessage': subscriptionState.statusMessage,
        };
        if (kDebugMode) {
          print('📊 [AuthService] 탈퇴 전 플랜 정보 수집 완료:');
          print('   권한: ${subscriptionDetails['entitlement']}');
          print('   구독 상태: ${subscriptionDetails['subscriptionStatus']}');
          print('   체험 사용 이력: ${subscriptionDetails['hasUsedTrial']}');
          print('   프리미엄: ${subscriptionDetails['isPremium']}');
          print('   체험: ${subscriptionDetails['isTrial']}');
          print('   만료: ${subscriptionDetails['isExpired']}');
          print('   남은 일수: ${subscriptionDetails['daysRemaining']}');
          print('   상태 메시지: ${subscriptionDetails['statusMessage']}');
        }
      } catch (e) {
        if (kDebugMode) {
          print('⚠️ [AuthService] 플랜 정보 수집 실패: $e');
        }
        subscriptionDetails = null;
      }
      
      // 병렬로 처리 가능한 작업들
      await Future.wait([
        _clearAllLocalData(),
        _deleteFirestoreData(userId),
        _deleteFirebaseStorageData(userId),
        _deleteUserBannerData(userId), // 🎯 사용자 배너 데이터 삭제 추가
      ]);
      
      // 소셜 로그인 세션 정리
      await _clearSocialLoginSessions();
      
      // 디바이스 ID는 유지 (익명 노트 관리용)
      
      // 탈퇴 기록 저장 (실패해도 계속 진행)
      try {
        final deletedUserService = DeletedUserService();
        await deletedUserService.saveDeletedUserRecord(userId, email, displayName, subscriptionDetails);
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

  // 🎯 사용자 배너 데이터 삭제 (탈퇴 시)
  Future<void> _deleteUserBannerData(String userId) async {
    try {
      if (kDebugMode) {
        debugPrint('🗑️ [AuthService] 사용자 배너 데이터 삭제 시작: $userId');
      }
      
      final bannerManager = BannerManager();
      await bannerManager.deleteUserBannerData(userId);
      
      if (kDebugMode) {
        debugPrint('✅ [AuthService] 사용자 배너 데이터 삭제 완료: $userId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [AuthService] 사용자 배너 데이터 삭제 중 오류: $e');
      }
      // 배너 데이터 삭제 실패는 치명적이지 않으므로 계속 진행
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
      bool hasMore = true;
      
      while (hasMore) {
        final query = await FirebaseFirestore.instance
            .collection(collection)
            .where(field, isEqualTo: value)
            .limit(_batchSize)
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
        hasMore = query.docs.length == _batchSize;
      }
    } catch (e) {
      debugPrint('$collection 배치 삭제 중 오류: $e');
      rethrow;
    }
  }



  /// SharedPreferences 헬퍼 메서드들
  Future<SharedPreferences> _getPrefs() async {
    return await SharedPreferences.getInstance();
  }

  Future<void> _setPrefsString(String key, String value) async {
    final prefs = await _getPrefs();
    await prefs.setString(key, value);
  }

  Future<void> _setPrefsInt(String key, int value) async {
    final prefs = await _getPrefs();
    await prefs.setInt(key, value);
  }

  Future<void> _setPrefsBool(String key, bool value) async {
    final prefs = await _getPrefs();
    await prefs.setBool(key, value);
  }

  Future<String?> _getPrefsString(String key) async {
    final prefs = await _getPrefs();
    return prefs.getString(key);
  }

  Future<bool?> _getPrefsBool(String key) async {
    final prefs = await _getPrefs();
    return prefs.getBool(key);
  }

  Future<void> _removePrefsKey(String key) async {
    final prefs = await _getPrefs();
    await prefs.remove(key);
  }

  // 디바이스 ID 가져오기
  Future<String> _getDeviceId() async {
    String? deviceId = await _getPrefsString(_deviceIdKey);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await _setPrefsString(_deviceIdKey, deviceId);
    }
    return deviceId;
  }



  // 탈퇴된 사용자 정보 확인 (중앙화된 서비스 사용)
  Future<Map<String, dynamic>?> getDeletedUserInfo(String userId) async {
    final deletedUserService = DeletedUserService();
    return await deletedUserService.getDeletedUserInfo();
  }

  // 탈퇴된 사용자인지 확인 (기존 호환성 유지)
  Future<bool> _checkIfUserDeleted(String userId) async {
    final deletedUserService = DeletedUserService();
    return await deletedUserService.isDeletedUser();
  }

  // 핵심 서비스 캐시 초기화
  Future<void> _clearAllServiceCaches() async {
    try {
      debugPrint('핵심 서비스 캐시 초기화 시작');
      
      // 로그아웃 이벤트 발생 (중앙화된 이벤트 시스템 사용)
      final eventCache = EventCacheManager();
      eventCache.notifyUserLoggedOut(); // 모든 사용자 캐시 무효화
      
      // UserPreferences 초기화 (온보딩 상태 등)
      final userPrefsService = UserPreferencesService();
      // UserPreferencesService 캐시 완전 초기화
      await userPrefsService.clearUserData();
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
        userData['deviceCount'] = 1;
        userData['deviceIds'] = [await _getDeviceId()];
        
        // 🎯 신규 사용자 기본 구독 정보 설정
        userData['subscription'] = {
          'plan': 'free',
          'status': 'active',
          'isActive': true,
          'isFreeTrial': false,
          'autoRenewStatus': false,
          'createdAt': FieldValue.serverTimestamp(),
        };
        
        // 신규 사용자는 항상 set 사용
        await userRef.set(userData);
        
        if (kDebugMode) {
          debugPrint('✅ [AuthService] 신규 사용자 Firestore 저장 완료: ${user.uid}');
        }
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
          userData['deviceCount'] = 1;
          userData['deviceIds'] = [deviceId];
          await userRef.set(userData);
        }
        
        if (kDebugMode) {
          debugPrint('✅ [AuthService] 기존 사용자 Firestore 업데이트 완료: ${user.uid}');
        }
      }
      
    } catch (e) {
      debugPrint('⚠️ [AuthService] Firestore 저장 중 오류 (로그인 진행): $e');
      // 오류가 있어도 로그인 프로세스는 계속 진행
    }
  }
}

