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
import '../../core/models/processed_text.dart';
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

    bool streamingStarted = false;

    try {
      // 1. 노트 상태를 처리 중으로 업데이트
      await _updateNoteStatus(job.noteId, ProcessingStatus.translating);

      // 2. LLM 처리 타임아웃 시작
      _startLlmTimeout(job.noteId);

      // 3. 텍스트 세그먼트 수집
      final allSegments = <String>[];
      final Set<String> completedPages = {};
      
      for (final pageData in job.pages) {
        if (pageData.mode == TextProcessingMode.paragraph) {
          // 문단 모드: 전체 텍스트를 하나의 세그먼트로 전송
          if (pageData.reorderedText.trim().isNotEmpty) {
            allSegments.add(pageData.reorderedText.trim());
            if (kDebugMode) {
              debugPrint('📄 [워크플로우] 문단 모드 전체 텍스트 추가: ${pageData.reorderedText.length}자');
            }
          }
        } else {
          // 문장 모드: 기존 세그먼트 사용
          for (final segment in pageData.textSegments) {
            if (segment.trim().isNotEmpty) {
              allSegments.add(segment);
            }
          }
        }
      }
      
      if (kDebugMode) {
        debugPrint('📊 [워크플로우] 수집된 세그먼트: ${allSegments.length}개');
        if (job.pages.isNotEmpty && job.pages.first.mode == TextProcessingMode.paragraph) {
          debugPrint('📄 [워크플로우] 문단 모드: 전체 텍스트 LLM 처리');
        }
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
        if (kDebugMode) {
          debugPrint('🌊 [워크플로우] 스트리밍 결과 수신 - success: ${result.isSuccess}, chunk: ${result.chunkIndex}, complete: ${result.isComplete}, started: $streamingStarted');
          debugPrint('📊 [워크플로우] 페이지 결과 수: ${result.pageResults.length}개');
        }
        
        // 첫 번째 결과를 받으면 스트리밍 시작으로 표시 (타임아웃은 유지)
        if (!streamingStarted) {
          if (kDebugMode) {
            debugPrint('🌊 [워크플로우] 첫 번째 스트리밍 응답 수신 - 스트리밍 시작: ${job.noteId}');
          }
          streamingStarted = true;
          // 타임아웃은 스트리밍 완료까지 유지
        }
        
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
            debugPrint('✅ [워크플로우] 스트리밍 완료 신호 수신: ${result.processedChunks}개 청크');
            debugPrint('📊 [워크플로우] 완료된 페이지: ${completedPages.length}/${job.pages.length}개');
            debugPrint('📄 [워크플로우] 최종 페이지 결과:');
            for (final entry in result.pageResults.entries) {
              debugPrint('   - ${entry.key}: ${entry.value.length}개 유닛');
            }
          }
          // 스트리밍 완료 시 타임아웃 중지
          _stopLlmTimeout(job.noteId);
          break;
        }
      }

      // 7. LLM 처리 완료 - 타임아웃 매니저 정리
      if (!streamingStarted) {
        // 스트리밍이 시작되지 않았다면 정상 완료 처리
        _completeLlmTimeout(job.noteId);
      } else {
        // 스트리밍이 완료되었으므로 타임아웃 정리 (이미 _stopLlmTimeout 호출됨)
        _retryStates.remove(job.noteId);
      }

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
      // 스트리밍이 시작되지 않았다면 타임아웃 중지
      if (!streamingStarted) {
        _stopLlmTimeout(job.noteId);
      }
      
      // 타임아웃 에러인지 확인
      final errorType = ErrorHandler.analyzeError(e);
      if (errorType == ErrorType.timeout && !streamingStarted) {
        // 스트리밍이 시작되기 전의 타임아웃만 처리
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
        'showFailureMessage': true, // UI에서 실패 메시지 표시 플래그
        'userFriendlyError': '처리 중 문제가 발생했습니다. 잠시 후 다시 시도해주세요.',
      });
      
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
      
      for (final pageData in job.pages) {
        // OCR 성공한 페이지 수 (업로드 이미지 수)
        if (pageData.ocrSuccess) {
          totalOcrPages++;
        }
      }
      
      // UsageLimitService 활용 (단순화된 시스템)
      final limitStatus = await _usageLimitService.updateUsageAfterNoteCreation(
        ocrPages: totalOcrPages,
      );
      
      if (kDebugMode) {
        debugPrint('📊 [워크플로우] 사용량 업데이트 완료:');
        debugPrint('   업로드 이미지 수: $totalOcrPages개');
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
    
    if (kDebugMode) {
      debugPrint('⏱️ [워크플로우] LLM 타임아웃 시작: $noteId (활성 타이머: ${_llmTimeoutManagers.length}개)');
    }
    
    final timeoutManager = TimeoutManager();
    _llmTimeoutManagers[noteId] = timeoutManager;
    _retryStates[noteId] = false;
    
    timeoutManager.start(
      timeoutSeconds: 60, // 문단 모드 고려: 60초
      identifier: 'LLM-$noteId',
      onProgress: (elapsedSeconds) {
        if (kDebugMode) {
          debugPrint('⏱️ [워크플로우] LLM 처리 경과: ${noteId} - ${elapsedSeconds}초 (활성: ${_llmTimeoutManagers.length}개)');
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
    if (timeoutManager != null) {
      if (kDebugMode) {
        debugPrint('🛑 [워크플로우] LLM 타임아웃 중지: $noteId (중지 전 활성: ${_llmTimeoutManagers.length}개)');
      }
      timeoutManager.dispose();
      _llmTimeoutManagers.remove(noteId);
      if (kDebugMode) {
        debugPrint('🛑 [워크플로우] LLM 타임아웃 정리 완료: $noteId (남은 활성: ${_llmTimeoutManagers.length}개)');
      }
    } else {
      if (kDebugMode) {
        debugPrint('⚠️ [워크플로우] 중지할 타임아웃 없음: $noteId (현재 활성: ${_llmTimeoutManagers.length}개)');
      }
    }
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
