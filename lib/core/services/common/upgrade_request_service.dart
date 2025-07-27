import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/upgrade_request_form.dart';

/// 프리미엄 업그레이드 요청 Firestore 서비스
class UpgradeRequestService {
  static final UpgradeRequestService _instance = UpgradeRequestService._internal();
  factory UpgradeRequestService() => _instance;
  UpgradeRequestService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// 업그레이드 요청을 Firestore에 저장
  Future<bool> submitUpgradeRequest(UpgradeRequestForm form) async {
    try {
      if (kDebugMode) {
        debugPrint('📧 프리미엄 업그레이드 요청 Firestore 저장 시작');
      }

      // 현재 사용자 정보 가져오기
      final user = _auth.currentUser;
      final userId = user?.uid;
      final userEmail = user?.email;

      // Firestore 문서 데이터 생성
      final requestData = {
        'userId': userId,
        'userEmail': userEmail ?? form.userEmail,
        'userName': form.userName,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending', // pending, reviewed, approved, rejected
        
        // 기능 요청
        'needAdditionalNoteFeature': form.needAdditionalNoteFeature,
        'needListeningFeature': form.needListeningFeature,
        'needOtherFeatures': form.needOtherFeatures,
        'otherFeatureRequest': form.otherFeatureRequest,
        
        // 기능 제안
        'featureSuggestion': form.featureSuggestion,
        
        // 인터뷰 참여
        'interviewParticipation': form.interviewParticipation,
        'contactInfo': form.contactInfo,
        
        // 메타데이터
        'appVersion': '1.1.0',
        'platform': _getPlatform(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Firestore에 저장
      await _firestore
          .collection('upgrade_requests')
          .add(requestData);

      if (kDebugMode) {
        debugPrint('✅ 프리미엄 업그레이드 요청 Firestore 저장 완료');
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 프리미엄 업그레이드 요청 Firestore 저장 실패: $e');
      }
      return false;
    }
  }

  /// 플랫폼 정보 가져오기
  String _getPlatform() {
    if (kDebugMode) {
      return 'debug';
    }
    // 실제 플랫폼 감지 로직 (필요시 추가)
    return 'production';
  }




} 