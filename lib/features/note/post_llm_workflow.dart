import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/utils/timeout_manager.dart';
import '../../../core/utils/error_handler.dart';
import 'services/page_service.dart';
import 'services/note_service.dart';
import '../../../core/services/common/usage_limit_service.dart';
import '../../../core/services/cache/cache_manager.dart';
import '../../core/models/text_unit.dart';
import '../../core/models/processing_status.dart';
import '../../../core/services/text_processing/streaming_receive_service.dart';
import '../../../core/services/text_processing/streaming_page_update_service.dart';
import '../../core/models/page_processing_data.dart';
import 'pre_llm_workflow.dart';

/// 후처리 워크플로우: 백그라운드 LLM 처리
/// 오케스트레이션 중심으로 각 서비스들을 조정
/// 
/// 주요 역할:
/// 1. 큐 관리 (Queue Management)
/// 2. 서비스 오케스트레이션 (Service Orchestration)
/// 3. 오류 처리 (Error Handling)
/// 4. 완료 상태 추적 (Completion Tracking)
class PostLLMWorkflow {
  // 서비스 인스턴스들
  final PageService _pageService = PageService();
  final NoteService _noteService = NoteService();
  final UsageLimitService _usageLimitService = UsageLimitService();
  final CacheManager _cacheManager = CacheManager();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 새로운 전담 서비스들
  final StreamingReceiveService _streamingService = StreamingReceiveService();
  final StreamingPageUpdateService _pageUpdateService = StreamingPageUpdateService();

  // 처리 큐 (메모리 기반)
  static final Queue<PostProcessingJob> _processingQueue = Queue<PostProcessingJob>();
  static bool _isProcessing = false;
  
  // 타임아웃 관리
  final Map<String, TimeoutManager> _llmTimeoutManagers = {};
  final Map<String, bool> _retryStates = {};

  /// 후처리 작업을 큐에 추가
  Future<void> enqueueJob(PostProcessingJob job) async {
    if (kDebugMode) {
      debugPrint('📋 [워크플로우] 작업 큐에 추가: ${job.noteId} (${job.pages.length}개 페이지)');
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
      debugPrint('🚀 [워크플로우] 큐 처리 시작: ${_processingQueue.length}개 작업');
    }

    while (_processingQueue.isNotEmpty) {
      final job = _processingQueue.removeFirst();
      
      try {
        await _processJob(job);
        await _removeJobFromFirestore(job.noteId);
        
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ [워크플로우] 작업 실패: ${job.noteId}, 오류: $e');
        }
        
        // 재시도 로직
        await _handleJobError(job, e);
      }
      
      // 다음 작업 전 잠시 대기 (API 레이트 리밋 고려)
      await Future.delayed(const Duration(milliseconds: 500));
    }

    _isProcessing = false;
    
    if (kDebugMode) {
      debugPrint('✅ [워크플로우] 큐 처리 완료');
    }
  }

  /// 단일 작업 처리 (오케스트레이션)
  Future<void> _processJob(PostProcessingJob job) async {
    if (kDebugMode) {
      debugPrint('🤖 [워크플로우] 작업 시작: ${job.noteId}');
    }

    try {
      // 1. 노트 상태를 처리 중으로 업데이트
      await _updateNoteStatus(job.noteId, ProcessingStatus.translating);

      // 2. LLM 처리 타임아웃 시작
      _startLlmTimeout(job.noteId);

      // 3. 텍스트 세그먼트 수집
      final allSegments = <String>[];
      final Set<String> completedPages = {};
      
      for (final pageData in job.pages) {
        for (final segment in pageData.textSegments) {
          if (segment.trim().isNotEmpty) {
            allSegments.add(segment);
          }
        }
      }
      
      if (kDebugMode) {
        debugPrint('📊 [워크플로우] 수집된 세그먼트: ${allSegments.length}개');
      }

      // 4. 스트리밍 수신 처리 (StreamingReceiveService)
      await for (final result in _streamingService.processStreamingTranslation(
        textSegments: allSegments,
        pages: job.pages,
        sourceLanguage: job.pages.first.sourceLanguage,
        targetLanguage: job.pages.first.targetLanguage,
        noteId: job.noteId,
        needPinyin: true,
      )) {
        if (!result.isSuccess) {
          if (kDebugMode) {
            debugPrint('❌ [워크플로우] 스트리밍 오류: ${result.error}');
          }
          continue;
        }

        // 5. 페이지별 업데이트 (StreamingPageUpdateService)
        for (final pageData in job.pages) {
          final pageResults = result.pageResults[pageData.pageId] ?? [];
          if (pageResults.isNotEmpty) {
            await _pageUpdateService.updatePageWithStreamingResult(
              pageData: pageData,
              llmResults: pageResults,
              totalExpectedUnits: pageData.textSegments.length,
            );
          }
        }
        
        // 6. 완료 확인
        _checkAndNotifyCompletedPagesOCR(result.pageResults, completedPages, job.pages);
        
        if (result.isComplete) {
          if (kDebugMode) {
            debugPrint('✅ [워크플로우] 스트리밍 완료: ${result.processedChunks}개 청크');
          }
          break;
        }
      }

      // 7. LLM 처리 완료 - 타임아웃 매니저 정리
      _completeLlmTimeout(job.noteId);

      // 8. 노트 완료 상태 업데이트
      await _updateNoteStatus(job.noteId, ProcessingStatus.completed);
      
      // 9. 사용량 업데이트 (UsageLimitService)
      await _updateUsageAfterProcessing(job);
      
      // 10. 전체 노트 완료 알림
      await _sendNoteCompletionNotification(job.noteId);

      if (kDebugMode) {
        debugPrint('🎉 [워크플로우] 작업 완료: ${job.noteId}');
      }

    } catch (e) {
      _stopLlmTimeout(job.noteId);
      
      // 타임아웃 에러인지 확인
      final errorType = ErrorHandler.analyzeError(e);
      if (errorType == ErrorType.timeout) {
        await _updateNoteStatus(job.noteId, ProcessingStatus.retrying);
        await _notifyLlmTimeout(job.noteId);
      } else {
        await _updateNoteStatus(job.noteId, ProcessingStatus.failed);
      }
      
      rethrow;
    }
  }

  /// OCR 세그먼트 기준으로 완료된 페이지들 확인
  void _checkAndNotifyCompletedPagesOCR(
    Map<String, List<TextUnit>> pageResults,
    Set<String> completedPages,
    List<PageProcessingData> pages,
  ) {
    for (final page in pages) {
      final pageId = page.pageId;
      if (completedPages.contains(pageId)) continue;
      
      final llmUnits = pageResults[pageId] ?? [];
      final ocrSegmentCount = page.textSegments.length;

      // OCR 세그먼트 개수 기준으로 완료 판단
      if (llmUnits.length >= ocrSegmentCount && ocrSegmentCount > 0) {
        completedPages.add(pageId);
      if (kDebugMode) {
          debugPrint('🎉 [워크플로우] 페이지 완료 (OCR 기준): $pageId (LLM: ${llmUnits.length}개, OCR: ${ocrSegmentCount}개)');
      }
      }
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
        debugPrint('⚠️ [워크플로우] 노트 상태 업데이트 실패: $noteId, 오류: $e');
      }
    }
  }

  /// 노트 전체 완료 알림 전송
  Future<void> _sendNoteCompletionNotification(String noteId) async {
    try {
      // TODO: 노트 전체 완료 푸시 알림 서비스 연동
      if (kDebugMode) {
        debugPrint('🔔 [워크플로우] 노트 완료 알림: $noteId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 노트 완료 알림 실패: $noteId, 오류: $e');
      }
    }
  }

  /// 작업 오류 처리
  Future<void> _handleJobError(PostProcessingJob job, dynamic error) async {
    if (job.retryCount < 3) {
      // 지수 백오프로 재시도
      final delay = Duration(seconds: math.pow(2, job.retryCount).toInt());
      
      if (kDebugMode) {
        debugPrint('🔄 [워크플로우] 재시도 스케줄링: ${job.noteId}, ${delay.inSeconds}초 후');
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
        debugPrint('💀 [워크플로우] 최종 실패: ${job.noteId}, 오류: $error');
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
        debugPrint('💀 [워크플로우] 사용자 실패 알림: $noteId');
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
      if (kDebugMode) {
        debugPrint('💾 [워크플로우] 작업 백업 저장 시작: ${job.noteId}');
      }
      
      final jobData = job.toJson();
      
      await _firestore.collection('processing_jobs').doc(job.noteId).set({
        'data': jobData,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      if (kDebugMode) {
        debugPrint('✅ [워크플로우] 작업 백업 저장 완료: ${job.noteId}');
      }
      
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('⚠️ 작업 백업 저장 실패: $e');
        debugPrint('   스택 트레이스: $stackTrace');
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

  /// 사용량 업데이트 (UsageLimitService 활용)
  Future<void> _updateUsageAfterProcessing(PostProcessingJob job) async {
    try {
      if (kDebugMode) {
        debugPrint('📊 [워크플로우] 사용량 업데이트 시작: ${job.noteId}');
      }
      
      // 실제 처리된 데이터를 기반으로 사용량 계산
      int totalOcrPages = 0;
      int totalStorageBytes = 0;
      int totalTranslatedChars = 0;
      
      for (final pageData in job.pages) {
        // OCR 성공한 페이지 수
        if (pageData.ocrSuccess) {
          totalOcrPages++;
        }
        
        // 스토리지 사용량
        totalStorageBytes += pageData.imageFileSize.toInt();
        
        // 번역된 문자 수 (텍스트 세그먼트 길이 합계)
        for (final segment in pageData.textSegments) {
          totalTranslatedChars += segment.length;
        }
      }
      
      // UsageLimitService 활용
      final limitStatus = await _usageLimitService.updateUsageAfterNoteCreation(
        ocrPages: totalOcrPages,
        storageBytes: totalStorageBytes,
        translatedChars: totalTranslatedChars,
      );
      
      if (kDebugMode) {
        debugPrint('📊 [워크플로우] 사용량 업데이트 완료:');
        debugPrint('   OCR 페이지: $totalOcrPages개');
        debugPrint('   스토리지: ${(totalStorageBytes / 1024 / 1024).toStringAsFixed(2)}MB');
        debugPrint('   번역 문자: $totalTranslatedChars자');
        debugPrint('   제한 상태: $limitStatus');
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 사용량 업데이트 실패: ${job.noteId}, 오류: $e');
      }
      // 사용량 업데이트 실패는 전체 프로세스를 실패시키지 않음
    }
  }

  /// LLM 처리 타임아웃 시작
  void _startLlmTimeout(String noteId) {
    _stopLlmTimeout(noteId); // 기존 타이머 정리
    
    final timeoutManager = TimeoutManager();
    _llmTimeoutManagers[noteId] = timeoutManager;
    _retryStates[noteId] = false;
    
    timeoutManager.start(
      timeoutSeconds: 5, // 테스트용: 30 -> 5초로 변경
      onProgress: (elapsedSeconds) {
        if (kDebugMode) {
          debugPrint('⏱️ [워크플로우] LLM 처리 경과: ${noteId} - ${elapsedSeconds}초');
        }
      },
      onTimeout: () {
        if (kDebugMode) {
          debugPrint('⏰ [워크플로우] LLM 타임아웃 발생: $noteId');
        }
        _handleLlmTimeout(noteId);
      },
    );
  }

  /// LLM 처리 정상 완료
  void _completeLlmTimeout(String noteId) {
    final timeoutManager = _llmTimeoutManagers[noteId];
    timeoutManager?.complete();
    _llmTimeoutManagers.remove(noteId);
    _retryStates.remove(noteId);
  }

  /// LLM 처리 타임아웃 중지
  void _stopLlmTimeout(String noteId) {
    final timeoutManager = _llmTimeoutManagers[noteId];
    timeoutManager?.dispose();
    _llmTimeoutManagers.remove(noteId);
  }

  /// LLM 타임아웃 알림
  Future<void> _notifyLlmTimeout(String noteId) async {
    try {
      await _firestore.collection('notes').doc(noteId).update({
        'llmTimeout': true,
        'timeoutNotifiedAt': FieldValue.serverTimestamp(),
        'retryAvailable': true,
      });
      
      if (kDebugMode) {
        debugPrint('🔔 [워크플로우] LLM 타임아웃 알림: $noteId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ LLM 타임아웃 알림 실패: $noteId, 오류: $e');
      }
    }
  }

  /// LLM 타임아웃 처리
  void _handleLlmTimeout(String noteId) {
    // 현재 작업 중지 시그널 (실제 구현은 StreamingReceiveService에서 처리)
    _retryStates[noteId] = true;
  }

  /// LLM 처리 재시도
  Future<void> retryLlmProcessing(String noteId) async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 [워크플로우] LLM 재시도 시작: $noteId');
      }

      // 재시도 상태 업데이트
      await _updateNoteStatus(noteId, ProcessingStatus.translating);
      await _firestore.collection('notes').doc(noteId).update({
        'llmTimeout': false,
        'retryAvailable': false,
        'retryStartedAt': FieldValue.serverTimestamp(),
      });

      // 기존 작업 찾기 (실제로는 큐에서 재실행하거나 새로운 작업 생성)
      // TODO: 실제 재시도 로직 구현
      
      if (kDebugMode) {
        debugPrint('✅ [워크플로우] LLM 재시도 완료: $noteId');
      }

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [워크플로우] LLM 재시도 실패: $noteId, 오류: $e');
      }
      await _updateNoteStatus(noteId, ProcessingStatus.failed);
    }
  }
}
