import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/page_service.dart';
import 'services/note_service.dart';
import '../../../core/services/common/usage_limit_service.dart';
import '../../../core/services/cache/cache_manager.dart';
import '../../core/models/processed_text.dart';
import '../../core/models/text_unit.dart';
import '../../core/models/note.dart';
import '../../core/models/processing_status.dart';
import '../../../core/services/text_processing/api_service.dart';
import 'pre_llm_workflow.dart';

/// 후처리 워크플로우: 백그라운드 LLM 처리
/// 배치 번역 → 병음 생성 → 페이지 업데이트 → 사용량 업데이트 → 실시간 알림
class PostLLMWorkflow {
  // 서비스 인스턴스
  final PageService _pageService = PageService();
  final NoteService _noteService = NoteService();
  final UsageLimitService _usageLimitService = UsageLimitService();
  final CacheManager _cacheManager = CacheManager();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ApiService _apiService = ApiService(); // 새로 추가


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

      // 3. 클라이언트 측에서도 큰 배치를 작은 청크로 나누어 처리
      const int CLIENT_CHUNK_SIZE = 20; // 클라이언트 청크 크기를 20으로 제한
      final List<TextUnit> allProcessedUnits = [];
      
      for (int i = 0; i < allSegments.length; i += CLIENT_CHUNK_SIZE) {
        final chunkSegments = allSegments.skip(i).take(CLIENT_CHUNK_SIZE).toList();
        
        if (kDebugMode) {
          debugPrint('📦 청크 ${(i ~/ CLIENT_CHUNK_SIZE) + 1}/${((allSegments.length - 1) ~/ CLIENT_CHUNK_SIZE) + 1} 처리 중: ${chunkSegments.length}개 세그먼트');
        }
        
        try {
          // 개별 청크 처리
          final serverResult = await _apiService.translateSegments(
            textSegments: chunkSegments,
            sourceLanguage: job.pages.first.sourceLanguage,
            targetLanguage: job.pages.first.targetLanguage,
            needPinyin: true,
            noteId: job.noteId,
          );

          if (kDebugMode) {
            debugPrint('✅ 청크 처리 완료: ${chunkSegments.length}개 세그먼트');
          }

          // 서버 응답에서 TextUnit 리스트 추출
          final chunkUnits = _extractUnitsFromServerResponse(serverResult);
          allProcessedUnits.addAll(chunkUnits);

          // 청크 간 짧은 지연
          if (i + CLIENT_CHUNK_SIZE < allSegments.length) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
          
        } catch (e) {
          if (kDebugMode) {
            debugPrint('❌ 청크 처리 실패: $e');
          }
          
          // 실패한 청크는 원본만 유지
          for (final segment in chunkSegments) {
            allProcessedUnits.add(TextUnit(
              originalText: segment,
              translatedText: '[번역 실패]',
              pinyin: '',
              sourceLanguage: job.pages.first.sourceLanguage,
              targetLanguage: job.pages.first.targetLanguage,
            ));
          }
        }
      }

      if (kDebugMode) {
        debugPrint('📊 전체 처리 완료: ${allProcessedUnits.length}개 TextUnit');
      }

      // 4. 페이지별 결과 분배 및 업데이트
      int segmentIndex = 0;
      for (int i = 0; i < job.pages.length; i++) {
        final pageData = job.pages[i];
        final segmentCount = pageData.textSegments.length;
        
        if (segmentCount == 0) continue;

        // 해당 페이지의 결과 추출
        final pageResults = allProcessedUnits
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
      
      // 6. 사용량 업데이트 (백그라운드에서 처리)
      await _updateUsageAfterProcessing(job);
      
      // 7. 노트 목록 캐싱 제거 - 노트 생성/삭제가 아니므로 불필요
      // await _cacheNotesAfterCompletion();
      
      // 8. 완료 알림
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
      final originalText = results.map((unit) => unit.originalText).join(' ');

      // 2차 ProcessedText 생성 (완전한 번역+병음 포함)
      final completeProcessedText = ProcessedText(
        mode: pageData.mode,
        displayMode: TextDisplayMode.full,
        fullOriginalText: originalText,
        fullTranslatedText: translatedText,
        units: results,
        sourceLanguage: pageData.sourceLanguage,
        targetLanguage: pageData.targetLanguage,
        streamingStatus: StreamingStatus.completed,
        completedUnits: results.length,
        progress: 1.0,
      );

      // 페이지 업데이트 - 2차 ProcessedText로 완전히 교체
      await _pageService.updatePage(pageData.pageId, {
        'translatedText': translatedText,
        'pinyin': pinyinText,
        'processedAt': FieldValue.serverTimestamp(),
        'status': ProcessingStatus.completed.toString(),
        'processedText': {
          'units': results.map((unit) => unit.toJson()).toList(),
          'mode': completeProcessedText.mode.toString(),
          'displayMode': completeProcessedText.displayMode.toString(),
          'fullOriginalText': completeProcessedText.fullOriginalText,
          'fullTranslatedText': completeProcessedText.fullTranslatedText,
          'sourceLanguage': pageData.sourceLanguage,
          'targetLanguage': pageData.targetLanguage,
          'streamingStatus': StreamingStatus.completed.index,
          'completedUnits': results.length,
          'progress': 1.0,
        },
      });

      if (kDebugMode) {
        debugPrint('✅ 2차 ProcessedText 업데이트 완료: ${pageData.pageId}');
        debugPrint('   번역 완료: ${results.length}개 유닛');
        debugPrint('   최종 ProcessedText 저장 완료');
      }

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
      if (kDebugMode) {
        debugPrint('💾 작업 백업 저장 시작: ${job.noteId}');
      }
      
      final jobData = job.toJson();
      
      if (kDebugMode) {
        debugPrint('✅ 작업 JSON 직렬화 성공');
      }
      
      await _firestore.collection('processing_jobs').doc(job.noteId).set({
        'data': jobData,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      if (kDebugMode) {
        debugPrint('✅ 작업 백업 저장 완료: ${job.noteId}');
      }
      
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('⚠️ 작업 백업 저장 실패: $e');
        debugPrint('   스택 트레이스: $stackTrace');
        debugPrint('   작업 ID: ${job.noteId}');
        debugPrint('   페이지 수: ${job.pages.length}');
        debugPrint('   userPrefs 타입: ${job.userPrefs.runtimeType}');
        debugPrint('   userPrefs 내용: ${job.userPrefs}');
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

  /// 사용량 업데이트 (백그라운드에서 처리)
  Future<void> _updateUsageAfterProcessing(PostProcessingJob job) async {
    try {
      if (kDebugMode) {
        debugPrint('📊 백그라운드 사용량 업데이트 시작: ${job.noteId}');
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
        totalStorageBytes += pageData.imageFileSize;
        
        // 번역된 문자 수 (텍스트 세그먼트 길이 합계)
        for (final segment in pageData.textSegments) {
          totalTranslatedChars += segment.length;
        }
      }
      
      // 사용량 업데이트
      final limitStatus = await _usageLimitService.updateUsageAfterNoteCreation(
        ocrPages: totalOcrPages,
        storageBytes: totalStorageBytes,
        translatedChars: totalTranslatedChars,
      );
      
      if (kDebugMode) {
        debugPrint('📊 백그라운드 사용량 업데이트 완료:');
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

  /// Firebase Functions 서버 응답에서 TextUnit 리스트 추출
  /// 
  /// 서버 응답 형식:
  /// ```json
  /// {
  ///   "success": true,
  ///   "translation": {
  ///     "units": [
  ///       {
  ///         "originalText": "你好",
  ///         "translatedText": "안녕하세요",
  ///         "pinyin": "Nǐ hǎo",
  ///         "sourceLanguage": "zh-CN",
  ///         "targetLanguage": "ko"
  ///       }
  ///     ],
  ///     "fullOriginalText": "你好",
  ///     "fullTranslatedText": "안녕하세요",
  ///     "mode": "segment",
  ///     "sourceLanguage": "zh-CN",
  ///     "targetLanguage": "ko"
  ///   },
  ///   "statistics": {
  ///     "segmentCount": 1,
  ///     "totalCharacters": 2,
  ///     "processingTime": 1234
  ///   }
  /// }
  /// ```
  List<TextUnit> _extractUnitsFromServerResponse(dynamic serverResult) {
    try {
      if (kDebugMode) {
        debugPrint('🔍 서버 응답 파싱 시작');
      }

      // 서버 응답이 Map인지 확인
      if (serverResult is! Map<String, dynamic>) {
        if (kDebugMode) {
          debugPrint('❌ 서버 응답이 Map이 아님: ${serverResult.runtimeType}');
        }
        return [];
      }

      final response = serverResult as Map<String, dynamic>;

      // success 필드 확인
      if (response['success'] != true) {
        if (kDebugMode) {
          debugPrint('❌ 서버 처리 실패: ${response['error'] ?? '알 수 없는 오류'}');
        }
        return [];
      }

      // translation 객체 확인
      final translation = response['translation'];
      if (kDebugMode) {
        debugPrint('🔍 translation 필드 타입: ${translation.runtimeType}');
        debugPrint('🔍 translation 내용: $translation');
      }
      
      if (translation is! Map) {
        if (kDebugMode) {
          debugPrint('❌ translation 필드가 없거나 Map이 아님');
        }
        return [];
      }

      // Map<String, dynamic>으로 변환
      final translationMap = Map<String, dynamic>.from(translation as Map);

      // units 배열 확인
      final units = translationMap['units'];
      if (units is! List) {
        if (kDebugMode) {
          debugPrint('❌ units 필드가 없거나 배열이 아님');
          debugPrint('🔍 translationMap 키들: ${translationMap.keys.toList()}');
        }
        return [];
      }

      // TextUnit 객체로 변환
      final List<TextUnit> textUnits = [];
      for (int i = 0; i < units.length; i++) {
        try {
          final unitData = units[i];
          if (kDebugMode && i < 3) {
            debugPrint('🔍 Unit $i 원본 데이터: $unitData');
            debugPrint('🔍 Unit $i 타입: ${unitData.runtimeType}');
          }
          
          if (unitData is Map<String, dynamic>) {
            final textUnit = TextUnit(
              originalText: unitData['originalText']?.toString() ?? '',
              translatedText: unitData['translatedText']?.toString() ?? '',
              pinyin: unitData['pinyin']?.toString() ?? '',
              sourceLanguage: unitData['sourceLanguage']?.toString() ?? 'zh-CN',
              targetLanguage: unitData['targetLanguage']?.toString() ?? 'ko',
            );
            textUnits.add(textUnit);

            if (kDebugMode && i < 3) {
              debugPrint('   Unit ${i+1}: "${textUnit.originalText}" → "${textUnit.translatedText}"');
            }
          } else if (unitData is Map) {
            // Map<Object?, Object?> 타입인 경우 변환
            final convertedUnit = Map<String, dynamic>.from(unitData);
            final textUnit = TextUnit(
              originalText: convertedUnit['originalText']?.toString() ?? '',
              translatedText: convertedUnit['translatedText']?.toString() ?? '',
              pinyin: convertedUnit['pinyin']?.toString() ?? '',
              sourceLanguage: convertedUnit['sourceLanguage']?.toString() ?? 'zh-CN',
              targetLanguage: convertedUnit['targetLanguage']?.toString() ?? 'ko',
            );
            textUnits.add(textUnit);

            if (kDebugMode && i < 3) {
              debugPrint('   Unit ${i+1} (변환됨): "${textUnit.originalText}" → "${textUnit.translatedText}"');
            }
          } else {
            if (kDebugMode) {
              debugPrint('⚠️ Unit $i가 올바른 형식이 아님: ${unitData.runtimeType}');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ Unit $i 파싱 실패: $e');
          }
        }
      }

      if (kDebugMode) {
        debugPrint('✅ 서버 응답 파싱 완료: ${textUnits.length}개 TextUnit 생성');
      }

      return textUnits;

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 서버 응답 파싱 중 오류: $e');
      }
      return [];
    }
  }

  /// 노트 목록 캐싱 (노트 생성 완료 후)
  Future<void> _cacheNotesAfterCompletion() async {
    try {
      if (kDebugMode) {
        debugPrint('📊 노트 목록 캐싱 시작');
      }
      
      // 현재 사용자의 노트만 가져옴
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;
      
      final snapshot = await _firestore
          .collection('notes')
          .where('userId', isEqualTo: userId)
          .get();
      
      final notes = <Note>[];
      for (final doc in snapshot.docs) {
        try {
          final note = Note.fromFirestore(doc);
          notes.add(note);
          
          if (kDebugMode) {
            debugPrint('🔄 노트 캐싱: ${note.id}');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ 노트 파싱 실패: ${doc.id}, 오류: $e');
          }
        }
      }
      
      // 노트 목록 캐싱
      await _cacheManager.cacheNotes(notes);
      
      if (kDebugMode) {
        debugPrint('✅ 노트 목록 캐싱 완료: ${notes.length}개');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 노트 목록 캐싱 실패: $e');
      }
    }
  }
}
