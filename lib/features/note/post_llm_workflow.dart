import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/content/page_service.dart';
import '../../../core/services/content/note_service.dart';
import '../../../core/services/text_processing/llm_text_processing.dart';
import '../../core/models/processed_text.dart';
import '../../core/models/text_unit.dart';
import '../../core/models/processing_status.dart';
import 'pre_llm_workflow.dart';

/// 후처리 워크플로우: 백그라운드 LLM 처리
/// 배치 번역 → 병음 생성 → 페이지 업데이트 → 실시간 알림
class PostLLMWorkflow {
  // 서비스 인스턴스
  final PageService _pageService = PageService();
  final NoteService _noteService = NoteService();
  final LLMTextProcessing _llmService = LLMTextProcessing();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 처리 큐 (메모리 기반)
  static final Queue<PostProcessingJob> _processingQueue = Queue<PostProcessingJob>();
  static bool _isProcessing = false;

  /// 후처리 작업을 큐에 추가
  Future<void> enqueueJob(PostProcessingJob job) async {
    if (kDebugMode) {
      debugPrint('📋 후처리 작업 큐에 추가: ${job.noteId} (${job.pages.length}개 페이지)');
    }

    _processingQueue.add(job);

    // Firestore에도 백업 저장 (앱 종료시 복구용)
    await _saveJobToFirestore(job);

    // 처리 중이 아니면 즉시 시작
    if (!_isProcessing) {
      unawaited(_startProcessing());
    }
  }

  /// 큐 처리 시작
  Future<void> _startProcessing() async {
    if (_isProcessing) return;

    _isProcessing = true;
    
    if (kDebugMode) {
      debugPrint('🚀 후처리 큐 처리 시작: ${_processingQueue.length}개 작업');
    }

    while (_processingQueue.isNotEmpty) {
      final job = _processingQueue.removeFirst();
      
      try {
        await _processJob(job);
        await _removeJobFromFirestore(job.noteId);
        
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ 후처리 작업 실패: ${job.noteId}, 오류: $e');
        }
        
        // 재시도 로직
        await _handleJobError(job, e);
      }
      
      // 다음 작업 전 잠시 대기 (API 레이트 리밋 고려)
      await Future.delayed(const Duration(milliseconds: 500));
    }

    _isProcessing = false;
    
    if (kDebugMode) {
      debugPrint('✅ 후처리 큐 처리 완료');
    }
  }

  /// 단일 작업 처리
  Future<void> _processJob(PostProcessingJob job) async {
    if (kDebugMode) {
      debugPrint('🤖 후처리 작업 시작: ${job.noteId}');
    }

    try {
      // 1. 노트 상태를 처리 중으로 업데이트
      await _updateNoteStatus(job.noteId, ProcessingStatus.translating);

      // 2. 모든 페이지의 텍스트 세그먼트 수집
      final List<String> allSegments = [];
      final List<String> pageIds = [];
      
      if (kDebugMode) {
        debugPrint('📊 페이지 데이터 분석: ${job.pages.length}개 페이지');
      }
      
      for (int i = 0; i < job.pages.length; i++) {
        final pageData = job.pages[i];
        
        if (kDebugMode) {
          debugPrint('   페이지 ${i+1}: ${pageData.pageId}');
          debugPrint('   텍스트 세그먼트: ${pageData.textSegments.length}개');
          if (pageData.textSegments.isNotEmpty) {
            for (int j = 0; j < pageData.textSegments.length; j++) {
              final segment = pageData.textSegments[j];
              final preview = segment.length > 30 ? '${segment.substring(0, 30)}...' : segment;
              debugPrint('     세그먼트 ${j+1}: "$preview"');
            }
          }
        }
        
        for (final segment in pageData.textSegments) {
          if (segment.trim().isNotEmpty) {
            allSegments.add(segment);
            pageIds.add(pageData.pageId);
          }
        }
      }
      
      if (kDebugMode) {
        debugPrint('📊 최종 수집 결과: ${allSegments.length}개 텍스트 세그먼트');
      }

      if (allSegments.isEmpty) {
        if (kDebugMode) {
          debugPrint('⚠️ 처리할 텍스트 세그먼트가 없음: ${job.noteId}');
        }
        await _updateNoteStatus(job.noteId, ProcessingStatus.completed);
        return;
      }

      if (kDebugMode) {
        debugPrint('📝 배치 LLM 처리 시작: ${allSegments.length}개 세그먼트');
      }

      // 3. 배치 LLM 처리
      final processedResults = await _llmService.processTextSegments(
        allSegments,
        sourceLanguage: job.pages.first.sourceLanguage,
        targetLanguage: job.pages.first.targetLanguage,
        mode: job.pages.first.mode,
        needPinyin: true,
      );

      if (kDebugMode) {
        debugPrint('✅ LLM 처리 완료: ${processedResults.units.length}개 결과');
      }

      // 4. 페이지별 결과 분배 및 업데이트
      int segmentIndex = 0;
      for (int i = 0; i < job.pages.length; i++) {
        final pageData = job.pages[i];
        final segmentCount = pageData.textSegments.length;
        
        if (segmentCount == 0) continue;

        // 해당 페이지의 결과 추출
        final pageResults = processedResults.units
            .skip(segmentIndex)
            .take(segmentCount)
            .toList();

        // 페이지 업데이트
        await _updatePageWithResults(pageData, pageResults);
        
        // 진행 상황 알림
        await _notifyPageProgress(pageData.pageId, 1.0);
        
        segmentIndex += segmentCount;

        if (kDebugMode) {
          debugPrint('📄 페이지 업데이트 완료: ${pageData.pageId} (${pageResults.length}개 결과)');
        }
      }

      // 5. 노트 완료 상태 업데이트
      await _updateNoteStatus(job.noteId, ProcessingStatus.completed);
      
      // 6. 완료 알림
      await _sendCompletionNotification(job.noteId);

      if (kDebugMode) {
        debugPrint('🎉 후처리 작업 완료: ${job.noteId}');
      }

    } catch (e) {
      await _updateNoteStatus(job.noteId, ProcessingStatus.failed);
      rethrow;
    }
  }

  /// 페이지에 LLM 결과 업데이트
  Future<void> _updatePageWithResults(
    PageProcessingData pageData,
    List<TextUnit> results,
  ) async {
    try {
      // 번역과 병음 텍스트 조합
      final translatedText = results.map((unit) => unit.translatedText ?? '').join(' ');
      final pinyinText = results.map((unit) => unit.pinyin ?? '').join(' ');

      // 페이지 업데이트
      await _pageService.updatePage(pageData.pageId, {
        'translatedText': translatedText,
        'pinyin': pinyinText,
        'processedAt': FieldValue.serverTimestamp(),
        'status': ProcessingStatus.completed.toString(),
        'processedUnits': results.map((unit) => {
          'originalText': unit.originalText,
          'translatedText': unit.translatedText,
          'pinyin': unit.pinyin,
          'sourceLanguage': unit.sourceLanguage,
          'targetLanguage': unit.targetLanguage,
        }).toList(),
      });

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 페이지 업데이트 실패: ${pageData.pageId}, 오류: $e');
      }
      rethrow;
    }
  }

  /// 노트 처리 상태 업데이트
  Future<void> _updateNoteStatus(String noteId, ProcessingStatus status) async {
    try {
      await _firestore.collection('notes').doc(noteId).update({
        'processingStatus': status.toString(),
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 노트 상태 업데이트 실패: $noteId, 오류: $e');
      }
    }
  }

  /// 페이지 진행 상황 알림
  Future<void> _notifyPageProgress(String pageId, double progress) async {
    try {
      await _firestore.collection('pages').doc(pageId).update({
        'processingProgress': progress,
        'progressUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 진행 상황 알림 실패: $pageId, 오류: $e');
      }
    }
  }

  /// 완료 알림 전송
  Future<void> _sendCompletionNotification(String noteId) async {
    try {
      // TODO: 푸시 알림 서비스 연동
      if (kDebugMode) {
        debugPrint('🔔 처리 완료 알림: $noteId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 완료 알림 실패: $noteId, 오류: $e');
      }
    }
  }

  /// 작업 오류 처리
  Future<void> _handleJobError(PostProcessingJob job, dynamic error) async {
    if (job.retryCount < 3) {
      // 지수 백오프로 재시도
      final delay = Duration(seconds: math.pow(2, job.retryCount).toInt());
      
      if (kDebugMode) {
        debugPrint('🔄 재시도 스케줄링: ${job.noteId}, ${delay.inSeconds}초 후');
      }

      Timer(delay, () {
        final retryJob = job.copyWith(retryCount: job.retryCount + 1);
        _processingQueue.add(retryJob);
        
        if (!_isProcessing) {
          unawaited(_startProcessing());
        }
      });
    } else {
      // 최종 실패 처리
      if (kDebugMode) {
        debugPrint('💀 최종 실패: ${job.noteId}, 오류: $error');
      }
      
      await _updateNoteStatus(job.noteId, ProcessingStatus.failed);
      await _notifyUserOfFailure(job.noteId, error.toString());
    }
  }

  /// 사용자에게 실패 알림
  Future<void> _notifyUserOfFailure(String noteId, String errorMessage) async {
    try {
      await _firestore.collection('notes').doc(noteId).update({
        'processingError': errorMessage,
        'errorNotifiedAt': FieldValue.serverTimestamp(),
      });
      
      // TODO: 사용자에게 실패 알림 전송
      if (kDebugMode) {
        debugPrint('💀 사용자 실패 알림: $noteId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 실패 알림 전송 실패: $e');
      }
    }
  }

  /// Firestore에 작업 백업 저장
  Future<void> _saveJobToFirestore(PostProcessingJob job) async {
    try {
      await _firestore.collection('processing_jobs').doc(job.noteId).set({
        'data': job.toJson(),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 작업 백업 저장 실패: $e');
      }
    }
  }

  /// Firestore에서 작업 제거
  Future<void> _removeJobFromFirestore(String noteId) async {
    try {
      await _firestore.collection('processing_jobs').doc(noteId).delete();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 작업 백업 제거 실패: $e');
      }
    }
  }

  /// 앱 시작시 미완료 작업 복구
  Future<void> recoverPendingJobs() async {
    try {
      final snapshot = await _firestore
          .collection('processing_jobs')
          .where('status', isEqualTo: 'pending')
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final job = PostProcessingJob.fromJson(data['data']);
        
        if (kDebugMode) {
          debugPrint('🔄 미완료 작업 복구: ${job.noteId}');
        }
        
        await enqueueJob(job);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 미완료 작업 복구 실패: $e');
      }
    }
  }
}
