import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:uuid/uuid.dart';

import 'deleted_user_service.dart';
import '../subscription/unified_subscription_manager.dart';
import '../../models/subscription_state.dart';


/// 🎯 사용자 계정 및 Firestore 데이터 관리를 전담하는 서비스
class UserAccountService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final UnifiedSubscriptionManager _subscriptionManager = UnifiedSubscriptionManager();


  // 싱글톤 패턴
  static final UserAccountService _instance = UserAccountService._internal();
  factory UserAccountService() => _instance;
  UserAccountService._internal();

  static const String _deviceIdKey = 'device_id';
  static const int _batchSize = 500;
  static const int _recentLoginMinutes = 5;

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
      
      // 4. 완전한 로그아웃 처리 (AuthService에서 호출됨)
      
    } catch (e) {
      debugPrint('계정 삭제 오류: $e');
      
      if (e is FirebaseAuthException) {
        if (e.code == 'requires-recent-login') {
          throw Exception(_getReauthRequiredMessage());
        }
      }
      rethrow;
    }
  }

    // 재인증 필요 여부 확인 (최근 로그인 시간 기반)
  Future<bool> isReauthenticationRequired() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;
      
      final idTokenResult = await user.getIdTokenResult();
      final lastSignInTime = idTokenResult.authTime;
      
      if (lastSignInTime != null) {
        final timeSinceLastSignIn = DateTime.now().difference(lastSignInTime);
        return timeSinceLastSignIn.inMinutes > _recentLoginMinutes;
      }
      return true;
    } catch (e) {
      return true;
    }
  }

  // 재인증 필요 메시지 생성
  String _getReauthRequiredMessage() {
    return '계정 보안을 위해 재로그인이 필요합니다.\n탈퇴를 원하시면 로그아웃 후 재시도해주세요.';
  }

  // 재인증 처리
  Future<void> _handleReauthentication(User user) async {
    final authProvider = user.providerData.firstOrNull?.providerId;
    
    if (authProvider?.contains('google') == true) {
      await _reauthenticateWithGoogle(user);
    } else if (authProvider?.contains('apple') == true) {
      await _reauthenticateWithApple(user);
    } else {
      throw Exception('지원되지 않는 인증 방식입니다.');
    }
  }
  
  void _handleReauthError(dynamic e, String provider) {
    throw Exception('$provider 재인증에 실패했습니다. 다시 시도해주세요.');
  }

  Future<void> _reauthenticateWithGoogle(User user) async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) throw Exception('Google 재인증 취소');
      
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      
      await user.reauthenticateWithCredential(credential);
    } catch (e) {
      _handleReauthError(e, 'Google');
    }
  }
  
  Future<void> _reauthenticateWithApple(User user) async {
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      );
      
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      
      await user.reauthenticateWithCredential(oauthCredential);
    } catch (e) {
      _handleReauthError(e, 'Apple');
    }
  }

  // 모든 사용자 데이터 삭제
  Future<void> _deleteAllUserData(String userId, String? email, String? displayName) async {
    try {
      // 🎯 1. 사용자의 구독 상태를 먼저 확인
      final subscriptionState = await _subscriptionManager.getSubscriptionState();
      final deviceId = await _getDeviceId();

      // 🎯 2. 유료/체험 사용자일 경우에만 탈퇴 기록 저장
      if (subscriptionState.entitlement.isPremiumOrTrial) {
        await DeletedUserService().saveTrialUserDeletionRecord(userId, email, deviceId);
      }

      // 3. Firestore 데이터 및 기타 로컬 데이터 삭제
      await Future.wait([
        _deleteFirestoreData(userId, deviceId),
        // _deleteFirebaseStorageData(userId), // 이 부분은 나중에 다른 서비스로 분리 필요
      ]);
      
    } catch (e) {
      debugPrint('사용자 데이터 삭제 중 오류: $e');
      rethrow;
    }
  }

  // Firestore 데이터 완전 삭제
  Future<void> _deleteFirestoreData(String userId, String deviceId) async {
    try {
      await _firestore.collection('users').doc(userId).delete();
      
      await _deleteBatchCollection('notes', 'userId', userId);
      await _deleteBatchCollection('notes', 'deviceId', deviceId);
      await _deleteBatchCollection('pages', 'userId', userId);
      await _deleteBatchCollection('flashcards', 'userId', userId);
      
    } catch (e) {
      debugPrint('Firestore 데이터 삭제 중 오류: $e');
      rethrow;
    }
  }
  
  // 배치 삭제 헬퍼
  Future<void> _deleteBatchCollection(String collection, String field, String value) async {
    try {
      QuerySnapshot query;
      do {
        query = await _firestore
            .collection(collection)
            .where(field, isEqualTo: value)
            .limit(_batchSize)
            .get();
            
        if (query.docs.isEmpty) break;
        
        final batch = _firestore.batch();
        for (var doc in query.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        
      } while (query.docs.length == _batchSize);
    } catch (e) {
      rethrow;
    }
  }

  /// 사용자 정보를 Firestore에 저장/업데이트
  Future<void> synchronizeUserData(User user, {bool isNewUser = false}) async {
    try {
      final userRef = _firestore.collection('users').doc(user.uid);
      final deviceId = await _getDeviceId();

      if (isNewUser) {
        // 신규 사용자: set으로 문서 생성
        final Map<String, dynamic> userData = {
          'uid': user.uid,
          'email': user.email,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
          'onboardingCompleted': false,
          'hasSeenWelcomeModal': false,
          'isNewUser': true,
          'deviceCount': 1,
          'deviceIds': [deviceId],
        };
        await userRef.set(userData);

        if (kDebugMode) {
          debugPrint('✅ [UserAccountService] 신규 사용자 Firestore 저장 완료: ${user.uid}');
        }
      } else {
        // 기존 사용자: update로 정보 업데이트
        final Map<String, dynamic> userData = {
          'lastLogin': FieldValue.serverTimestamp(),
        };

        final userDoc = await userRef.get();
        if (userDoc.exists) {
          final List<dynamic> deviceIds = userDoc.data()?['deviceIds'] ?? [];
          if (!deviceIds.contains(deviceId)) {
            userData['deviceIds'] = FieldValue.arrayUnion([deviceId]);
            userData['deviceCount'] = deviceIds.length + 1;
          }
          await userRef.update(userData);
        } else {
          // 에지 케이스: 기존 사용자지만 문서가 없는 경우 (온보딩 전 앱 삭제 등)
          userData['createdAt'] = FieldValue.serverTimestamp();
          userData['isNewUser'] = true;
          userData['onboardingCompleted'] = false;
          userData['hasSeenWelcomeModal'] = false;
          userData['deviceCount'] = 1;
          userData['deviceIds'] = [deviceId];
          await userRef.set(userData);
        }

        if (kDebugMode) {
          debugPrint('✅ [UserAccountService] 기존 사용자 Firestore 업데이트 완료: ${user.uid}');
        }
      }
    } catch (e) {
      debugPrint('⚠️ [UserAccountService] Firestore 저장 중 오류 (로그인 진행): $e');
      // 오류가 있어도 로그인 프로세스는 계속 진행
    }
  }

  // 디바이스 ID 가져오기
  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString(_deviceIdKey);
    if (deviceId == null) {
      deviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, deviceId);
    }
    return deviceId;
  }
} 