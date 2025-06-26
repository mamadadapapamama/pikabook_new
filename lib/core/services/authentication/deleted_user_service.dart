import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// 탈퇴된 사용자 정보 관리를 위한 중앙화된 서비스
class DeletedUserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // 싱글톤 패턴
  static final DeletedUserService _instance = DeletedUserService._internal();
  factory DeletedUserService() => _instance;
  DeletedUserService._internal();
  
  /// 현재 사용자의 탈퇴 이력 정보 조회 (항상 Firebase에서 최신 데이터 조회)
  Future<Map<String, dynamic>?> getDeletedUserInfo({bool forceRefresh = false}) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser?.email == null) {
        if (kDebugMode) {
          print('❌ [DeletedUserService] 사용자 이메일이 없어 탈퇴 이력 확인 불가');
        }
        return null;
      }
      
      final email = currentUser!.email!;
      
      if (kDebugMode) {
        print('🔍 [DeletedUserService] 탈퇴 이력 조회 시작: $email (항상 Firebase 호출)');
        
        // 디버그: 해당 이메일의 모든 탈퇴 기록 수 확인
        final allRecordsQuery = await _firestore
            .collection('deleted_users')
            .where('email', isEqualTo: email)
            .get();
        print('   해당 이메일의 총 탈퇴 기록 수: ${allRecordsQuery.docs.length}');
      }
      
      // 항상 Firestore에서 최신 데이터 조회 (가장 최근 탈퇴 기록)
      final emailQuery = await _firestore
          .collection('deleted_users')
          .where('email', isEqualTo: email)
          .orderBy('lastDeletedAt', descending: true) // 가장 최근 탈퇴 순으로 정렬
          .limit(1)
          .get();
      
      Map<String, dynamic>? deletedUserInfo;
      
      if (emailQuery.docs.isNotEmpty) {
        deletedUserInfo = emailQuery.docs.first.data();
        
        if (kDebugMode) {
          print('📧 [DeletedUserService] 탈퇴 이력 발견: $email');
          print('   총 ${emailQuery.docs.length}개 중 최신 기록 사용');
          print('   문서 ID: ${emailQuery.docs.first.id}');
          _logDeletedUserInfo(deletedUserInfo);
        }
      } else {
        if (kDebugMode) {
          print('📧 [DeletedUserService] 탈퇴 이력 없음: $email');
        }
      }
      
      return deletedUserInfo;
    } catch (e) {
      if (kDebugMode) {
        print('❌ [DeletedUserService] 탈퇴 이력 조회 중 오류: $e');
      }
      return null;
    }
  }
  
  /// 탈퇴된 사용자인지 확인
  Future<bool> isDeletedUser({bool forceRefresh = false}) async {
    final deletedUserInfo = await getDeletedUserInfo(forceRefresh: forceRefresh);
    return deletedUserInfo != null;
  }
  
  /// 이전 플랜 정보 조회
  Future<Map<String, dynamic>?> getLastPlanInfo({bool forceRefresh = false}) async {
    final deletedUserInfo = await getDeletedUserInfo(forceRefresh: forceRefresh);
    return deletedUserInfo?['lastPlan'] as Map<String, dynamic>?;
  }
  
  /// 무료체험 사용 이력 확인 (탈퇴 이력 기반)
  Future<bool> hasUsedFreeTrialFromHistory({bool forceRefresh = false}) async {
    final lastPlan = await getLastPlanInfo(forceRefresh: forceRefresh);
    
    if (lastPlan != null) {
      // 🎯 새로운 방식: hasEverUsedTrial 필드 우선 확인
      final hasEverUsedTrial = lastPlan['hasEverUsedTrial'] as bool? ?? false;
      if (hasEverUsedTrial) {
        if (kDebugMode) {
          print('✅ [DeletedUserService] 탈퇴 이력에서 무료체험 사용 이력 발견 (hasEverUsedTrial)');
        }
        return true;
      }
      
      // 🔄 하위 호환성: 기존 방식도 유지 (기존 데이터 대응)
      final wasFreeTrial = lastPlan['isFreeTrial'] as bool? ?? false;
      final planType = lastPlan['planType'] as String?;
      
      // 기존 데이터에서 무료체험 사용 이력 확인
      final hasUsedTrialLegacy = wasFreeTrial || planType == 'premium';
      
      if (kDebugMode && hasUsedTrialLegacy) {
        print('✅ [DeletedUserService] 탈퇴 이력에서 무료체험/프리미엄 사용 이력 발견 (레거시)');
        print('   이전 플랜: $planType, 무료체험: $wasFreeTrial');
      }
      
      return hasUsedTrialLegacy;
    }
    
    return false;
  }
  
  /// 탈퇴 기록 저장 (AuthService에서 호출)
  Future<void> saveDeletedUserRecord(
    String userId, 
    String? email, 
    String? displayName, 
    Map<String, dynamic>? subscriptionDetails
  ) async {
    try {
      if (kDebugMode) {
        print('💾 [DeletedUserService] 탈퇴 기록 저장 시작: $userId');
      }
      
      final docRef = _firestore.collection('deleted_users').doc(userId);
      
      // 90일 후 자동 삭제 날짜 계산
      final autoDeleteDate = DateTime.now().add(const Duration(days: 90));
      
      // 기존 기록 확인
      final existingDoc = await docRef.get();
      
      if (existingDoc.exists) {
        if (kDebugMode) {
          print('🔄 [DeletedUserService] 기존 탈퇴 기록 업데이트: $userId');
        }
        // 기존 기록에 재탈퇴 시간 추가 (자동 삭제 날짜 갱신)
        await docRef.update({
          'lastDeletedAt': FieldValue.serverTimestamp(),
          'deleteCount': FieldValue.increment(1),
          'autoDeleteAt': Timestamp.fromDate(autoDeleteDate),
        });
      } else {
        if (kDebugMode) {
          print('📝 [DeletedUserService] 새로운 탈퇴 기록 생성: $userId');
        }
        
        // 새로운 탈퇴 기록 생성
        final deleteRecord = {
          'userId': userId,
          'email': email,
          'displayName': displayName,
          'deletedAt': FieldValue.serverTimestamp(),
          'lastDeletedAt': FieldValue.serverTimestamp(),
          'deleteCount': 1,
          'autoDeleteAt': Timestamp.fromDate(autoDeleteDate),
          'reason': 'user_requested',
        };
        
        // 탈퇴 시점의 플랜 정보 저장
        if (subscriptionDetails != null) {
          final lastPlan = {
            'planType': subscriptionDetails['currentPlan'],
            'isFreeTrial': subscriptionDetails['isFreeTrial'],
            'subscriptionType': subscriptionDetails['subscriptionType'],
            'daysRemaining': subscriptionDetails['daysRemaining'],
            'expiryDate': subscriptionDetails['expiryDate'] != null 
                ? Timestamp.fromDate(subscriptionDetails['expiryDate'] as DateTime)
                : null,
            'hasEverUsedTrial': subscriptionDetails['hasEverUsedTrial'] ?? false,
          };
          
          deleteRecord['lastPlan'] = lastPlan;
          
          if (kDebugMode) {
            print('📝 [DeletedUserService] 플랜 정보 저장:');
            _logPlanInfo(lastPlan);
          }
        } else {
          if (kDebugMode) {
            print('⚠️ [DeletedUserService] 플랜 정보가 없어서 저장하지 않음');
          }
        }
        
        await docRef.set(deleteRecord);
      }
      

      
      if (kDebugMode) {
        print('✅ [DeletedUserService] 탈퇴 기록 저장 완료: $userId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ [DeletedUserService] 탈퇴 기록 저장 중 오류: $e');
      }
      throw e; // 탈퇴 기록 저장 실패는 중요하므로 예외 전파
    }
  }
  
  /// 기존 탈퇴 기록에 플랜 정보 업데이트 (임시용)
  Future<void> updateDeletedUserPlanInfo(String email, Map<String, dynamic> planInfo) async {
    try {
      if (kDebugMode) {
        print('🔧 [DeletedUserService] 탈퇴 기록 플랜 정보 업데이트 시작: $email');
      }
      
      final query = await _firestore
          .collection('deleted_users')
          .where('email', isEqualTo: email)
          .orderBy('lastDeletedAt', descending: true) // 가장 최근 탈퇴 기록
          .limit(1)
          .get();
      
      if (query.docs.isNotEmpty) {
        final docRef = query.docs.first.reference;
        await docRef.update({
          'lastPlan': planInfo,
        });
        

        
        if (kDebugMode) {
          print('✅ [DeletedUserService] 탈퇴 기록 플랜 정보 업데이트 완료');
        }
      } else {
        if (kDebugMode) {
          print('❌ [DeletedUserService] 해당 이메일의 탈퇴 기록을 찾을 수 없음: $email');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ [DeletedUserService] 탈퇴 기록 업데이트 중 오류: $e');
      }
      throw e;
    }
  }
  

  
  /// 탈퇴 이력 정보 로깅
  void _logDeletedUserInfo(Map<String, dynamic> deletedUserInfo) {
    print('📋 [DeletedUserService] 탈퇴 이력 상세 정보:');
    print('   이전 사용자 ID: ${deletedUserInfo['userId']}');
    print('   탈퇴 시간: ${deletedUserInfo['deletedAt']}');
    print('   탈퇴 횟수: ${deletedUserInfo['deleteCount']}');
    print('   이전 플랜 데이터: ${deletedUserInfo['lastPlan']}');
    
    final lastPlan = deletedUserInfo['lastPlan'] as Map<String, dynamic>?;
    if (lastPlan != null) {
      _logPlanInfo(lastPlan);
    }
  }
  
  /// 플랜 정보 로깅
  void _logPlanInfo(Map<String, dynamic> planInfo) {
    print('   플랜 타입: ${planInfo['planType']}');
    print('   무료체험: ${planInfo['isFreeTrial']}');
    print('   구독 타입: ${planInfo['subscriptionType']}');
    print('   남은 일수: ${planInfo['daysRemaining']}');
    print('   만료일: ${planInfo['expiryDate']}');
  }
} 