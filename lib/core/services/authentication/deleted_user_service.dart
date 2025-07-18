import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// 탈퇴한 '유료/체험' 사용자의 이력을 관리하여, 무료 체험 남용을 방지하는 서비스
class DeletedUserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collectionName = 'trial_abuse_records';

  // 싱글톤 패턴
  static final DeletedUserService _instance = DeletedUserService._internal();
  factory DeletedUserService() => _instance;
  DeletedUserService._internal();

  /// 유료/체험 사용자의 탈퇴 기록을 저장합니다. (UserAccountService에서 호출)
  /// @param deviceId - 남용 방지를 위한 기기 ID
  Future<void> saveTrialUserDeletionRecord(
    String userId,
    String? email,
    String deviceId,
  ) async {
    try {
      if (kDebugMode) {
        print('💾 [DeletedUserService] 유료/체험 사용자 탈퇴 기록 저장: User $userId, Device $deviceId');
      }
      
      final docRef = _firestore.collection(_collectionName).doc(userId);

      final record = {
        'userId': userId,
        'email': email,
        'deviceId': deviceId,
        'deletedAt': FieldValue.serverTimestamp(),
      };

      await docRef.set(record);

      if (kDebugMode) {
        print('✅ [DeletedUserService] 탈퇴 기록 저장 완료: $userId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ [DeletedUserService] 탈퇴 기록 저장 중 오류: $e');
      }
      // 이 로직이 실패해도 계정 삭제의 다른 부분은 계속 진행되어야 하므로 오류를 다시 던지지 않음
    }
  }

  /// 주어진 이메일 또는 기기 ID가 이전에 무료 체험을 사용했는지 확인합니다.
  /// (회원가입 과정에서 호출될 수 있음)
  Future<bool> hasUsedTrialBefore({
    required String? email,
    required String deviceId,
  }) async {
    try {
      // Firestore는 다른 필드에 대한 OR 쿼리를 지원하지 않으므로, 두 개의 개별 쿼리를 실행합니다.
      final hasDeviceRecord = await _checkByDeviceId(deviceId);
      if (hasDeviceRecord) {
        if (kDebugMode) print('⚠️ [DeletedUserService] 기기 ID($deviceId)에서 체험판 사용 이력 발견');
        return true;
      }
      
      // 기기 ID에 이력이 없을 때만 이메일 확인
      if (email != null && email.isNotEmpty) {
        final hasEmailRecord = await _checkByEmail(email);
        if (hasEmailRecord) {
          if (kDebugMode) print('⚠️ [DeletedUserService] 이메일($email)에서 체험판 사용 이력 발견');
          return true;
        }
      }

      if (kDebugMode) print('✅ [DeletedUserService] 체험판 사용 이력 없음: Email $email, Device $deviceId');
      return false;
    } catch (e) {
      if (kDebugMode) print('❌ [DeletedUserService] 체험판 이력 확인 중 오류: $e');
      return false; // 오류 발생 시 사용자를 차단하지 않도록 false 반환
    }
  }

  Future<bool> _checkByEmail(String email) async {
    try {
      final query = await _firestore
          .collection(_collectionName)
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      return query.docs.isNotEmpty;
    } catch (e) {
      if (kDebugMode) print('❌ [DeletedUserService] 이메일로 이력 확인 중 오류: $e');
      return false;
    }
  }

  Future<bool> _checkByDeviceId(String deviceId) async {
    try {
      final query = await _firestore
          .collection(_collectionName)
          .where('deviceId', isEqualTo: deviceId)
          .limit(1)
          .get();
      return query.docs.isNotEmpty;
    } catch (e) {
      if (kDebugMode) print('❌ [DeletedUserService] 기기 ID로 이력 확인 중 오류: $e');
      return false;
    }
  }
} 