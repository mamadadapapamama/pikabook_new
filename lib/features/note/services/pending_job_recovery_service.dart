import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../post_llm_workflow.dart';
import '../pre_llm_workflow.dart';

/// 미완료 작업 복구 전용 서비스
/// PostLLMWorkflow에서 분리하여 단일 책임 원칙 준수
class PendingJobRecoveryService {
  // 싱글톤 패턴
  static final PendingJobRecoveryService _instance = PendingJobRecoveryService._internal();
  factory PendingJobRecoveryService() => _instance;
  PendingJobRecoveryService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PostLLMWorkflow _postLLMWorkflow = PostLLMWorkflow();

  /// 모든 미완료 작업 복구 (앱 시작시 - 현재는 비활성화)
  Future<void> recoverAllPendingJobs() async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 모든 미완료 작업 복구 시작');
      }

      final snapshot = await _firestore
          .collection('processing_jobs')
          .where('status', isEqualTo: 'pending')
          .get();

      if (snapshot.docs.isEmpty) {
        if (kDebugMode) {
          debugPrint('ℹ️ 복구할 미완료 작업 없음');
        }
        return;
      }

      int recoveredCount = 0;
      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final job = PostProcessingJob.fromJson(data['data']);
          
          await _postLLMWorkflow.enqueueJob(job);
          recoveredCount++;
          
          if (kDebugMode) {
            debugPrint('🔄 미완료 작업 복구: ${job.noteId}');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ 작업 파싱 실패 (건너뜀): $e');
          }
          continue;
        }
      }

      if (kDebugMode) {
        debugPrint('✅ 모든 미완료 작업 복구 완료: $recoveredCount개');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 모든 미완료 작업 복구 실패: $e');
      }
    }
  }

  /// 특정 노트의 미완료 작업만 복구 (노트 상세페이지 진입시 사용)
  Future<bool> recoverPendingJobsForNote(String noteId) async {
    try {
      if (kDebugMode) {
        debugPrint('🔍 노트별 미완료 작업 확인: $noteId');
      }

      final snapshot = await _firestore
          .collection('processing_jobs')
          .where('status', isEqualTo: 'pending')
          .get();

      bool hasRecoveredJob = false;

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final job = PostProcessingJob.fromJson(data['data']);
          
          // 해당 노트의 미완료 작업인지 확인
          if (job.noteId == noteId) {
            if (kDebugMode) {
              debugPrint('🔄 특정 노트 미완료 작업 복구: ${job.noteId}');
            }
            
            await _postLLMWorkflow.enqueueJob(job);
            hasRecoveredJob = true;
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ 작업 파싱 실패 (건너뜀): $e');
          }
          continue;
        }
      }

      if (hasRecoveredJob) {
        if (kDebugMode) {
          debugPrint('✅ 노트 $noteId의 미완료 작업 복구 완료');
        }
      } else {
        if (kDebugMode) {
          debugPrint('ℹ️ 노트 $noteId에 미완료 작업 없음');
        }
      }

      return hasRecoveredJob;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 특정 노트 미완료 작업 복구 실패: $noteId, 오류: $e');
      }
      return false;
    }
  }

  /// 미완료 작업 개수 확인
  Future<int> getPendingJobCount() async {
    try {
      final snapshot = await _firestore
          .collection('processing_jobs')
          .where('status', isEqualTo: 'pending')
          .get();
      
      return snapshot.docs.length;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 미완료 작업 개수 확인 실패: $e');
      }
      return 0;
    }
  }

  /// 특정 노트의 미완료 작업 존재 여부 확인
  Future<bool> hasPendingJobForNote(String noteId) async {
    try {
      final snapshot = await _firestore
          .collection('processing_jobs')
          .where('status', isEqualTo: 'pending')
          .get();

      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          final job = PostProcessingJob.fromJson(data['data']);
          
          if (job.noteId == noteId) {
            return true;
          }
        } catch (e) {
          continue;
        }
      }

      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 미완료 작업 존재 여부 확인 실패: $noteId, 오류: $e');
      }
      return false;
    }
  }

  /// 미완료 작업 정리 (완료되지 않은 오래된 작업 제거)
  Future<void> cleanupStaleJobs({Duration maxAge = const Duration(days: 7)}) async {
    try {
      if (kDebugMode) {
        debugPrint('🧹 오래된 미완료 작업 정리 시작');
      }

      final cutoffTime = DateTime.now().subtract(maxAge);
      final snapshot = await _firestore
          .collection('processing_jobs')
          .where('status', isEqualTo: 'pending')
          .where('createdAt', isLessThan: Timestamp.fromDate(cutoffTime))
          .get();

      int cleanedCount = 0;
      for (final doc in snapshot.docs) {
        await doc.reference.delete();
        cleanedCount++;
      }

      if (kDebugMode) {
        debugPrint('✅ 오래된 미완료 작업 정리 완료: $cleanedCount개');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 오래된 미완료 작업 정리 실패: $e');
      }
    }
  }
} 