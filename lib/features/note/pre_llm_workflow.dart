import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/note_service.dart';
import '../../../core/services/media/image_service.dart';
import 'services/page_service.dart';
import '../../core/services/text_processing/text_processing_orchestrator.dart';
import '../../core/services/authentication/user_preferences_service.dart';
import '../../core/models/processed_text.dart';
import '../../core/models/processing_status.dart';
import '../../core/models/page_processing_data.dart';
import '../../core/services/common/usage_limit_service.dart';
import 'post_llm_workflow.dart';

/// 전처리 워크플로우: 빠른 노트 생성 (3-5초 목표)
/// 노트/이미지 생성 → TextProcessingOrchestrator → 후처리 스케줄링
class PreLLMWorkflow {
  // 서비스 인스턴스
  final NoteService _noteService = NoteService();
  final ImageService _imageService = ImageService();
  final PageService _pageService = PageService();
  final TextProcessingOrchestrator _textProcessingOrchestrator = TextProcessingOrchestrator();
  final UserPreferencesService _preferencesService = UserPreferencesService();
  final UsageLimitService _usageLimitService = UsageLimitService();
  final PostLLMWorkflow _postLLMWorkflow = PostLLMWorkflow();

  /// 빠른 노트 생성 메인 메서드 (첫 번째 이미지 업로드 및 첫 페이지 생성 후 반환)
  Future<String> createNoteQuickly(List<File> imageFiles) async {
    if (imageFiles.isEmpty) {
      throw Exception('이미지가 없습니다.');
    }

    if (kDebugMode) {
      debugPrint('🚀 전처리 워크플로우 시작: ${imageFiles.length}개 이미지');
    }

    try {
      // 1. 노트 메타데이터 생성 (빠름, 1-2초)
      final noteId = await _noteService.createNote();
      
      if (kDebugMode) {
        debugPrint('✅ 노트 메타데이터 생성 완료: $noteId');
      }
      
      // 2. 사용자 설정 로드 (캐시됨)
      final userPrefs = await _preferencesService.getPreferences();
      
      // 3. 첫 번째 이미지 업로드 및 첫 페이지 생성 (await로 완료 대기)
      if (kDebugMode) {
        debugPrint('📷 첫 번째 이미지 업로드 시작 (상세페이지 이동 전 필수)');
      }
      
      // 첫 번째 이미지 업로드
      final firstImageUrl = await _imageService.uploadImage(imageFiles[0]);
      
      if (kDebugMode) {
        debugPrint('✅ 첫 번째 이미지 업로드 완료: $firstImageUrl');
      }
      
      // 첫 번째 페이지 생성
      final firstPageId = await _pageService.createPage(
        noteId: noteId,
        originalText: '', // 빈 텍스트로 시작
        pageNumber: 1,
        imageUrl: firstImageUrl,
      );
      
      if (kDebugMode) {
        debugPrint('✅ 첫 번째 페이지 생성 완료: ${firstPageId.id}');
      }
      
      // 4. 노트 메타데이터 업데이트 (썸네일)
      await _noteService.updateNoteMetadata(
        noteId: noteId,
        thumbnailUrl: firstImageUrl,
        pageCount: imageFiles.length,
        updateTimestamp: false, // OCR 처리 중에는 타임스탬프 업데이트 안함
      );
      
      // 5. 나머지 이미지들은 백그라운드에서 처리
      if (imageFiles.length > 1) {
        _startRemainingImagesProcessing(noteId, imageFiles, userPrefs, firstPageId.id);
      } else {
        // 이미지가 1개뿐이면 바로 텍스트 처리 시작 (첫 번째 이미지 포함)
        _startBackgroundProcessing(noteId, [imageFiles[0]], [firstPageId.id], userPrefs);
      }
      
      if (kDebugMode) {
        debugPrint('🎉 빠른 노트 생성 완료: $noteId (첫 페이지 준비됨, 백그라운드 처리 시작됨)');
      }
      
      return noteId;
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 빠른 노트 생성 실패: $e');
      }
      rethrow;
    }
  }

  /// 나머지 이미지들 백그라운드 업로드 + 텍스트 처리
  void _startRemainingImagesProcessing(
    String noteId, 
    List<File> allImageFiles, // 첫 번째 이미지 포함 모든 이미지
    dynamic userPrefs,
    String firstPageId,
  ) {
    // 백그라운드에서 비동기 처리
    Future.microtask(() async {
      try {
        if (kDebugMode) {
          debugPrint('🔄 나머지 이미지 백그라운드 업로드 시작: $noteId (${allImageFiles.length-1}개 추가 이미지)');
        }
        
        final List<String> allPageIds = [firstPageId];
        final List<File> remainingImages = allImageFiles.sublist(1); // 첫 번째 제외
        
        // 나머지 이미지들 업로드 + 페이지 생성
        for (int i = 0; i < remainingImages.length; i++) {
          if (kDebugMode) {
            debugPrint('📷 이미지 ${i+2}/${allImageFiles.length} 업로드 시작');
          }
          
          // 이미지 업로드
          final imageUrl = await _imageService.uploadImage(remainingImages[i]);
          
          if (kDebugMode) {
            debugPrint('✅ 이미지 ${i+2} 업로드 완료: $imageUrl');
          }
          
          // 페이지 생성
          final pageId = await _pageService.createPage(
            noteId: noteId,
            originalText: '', // 빈 텍스트로 시작
            pageNumber: i + 2, // 첫 번째는 이미 1번이므로 2번부터
            imageUrl: imageUrl,
          );
          allPageIds.add(pageId.id);
          
          if (kDebugMode) {
            debugPrint('✅ 페이지 ${i+2} 생성 완료: ${pageId.id}');
          }
        }
        
        // 페이지 수 업데이트
          await _noteService.updateNoteMetadata(
            noteId: noteId,
          pageCount: allPageIds.length,
          updateTimestamp: false,
          );
        
        // 모든 이미지에 대해 텍스트 처리 시작 (첫 번째 이미지 포함)
        _startBackgroundProcessing(noteId, allImageFiles, allPageIds, userPrefs);
        
        if (kDebugMode) {
          debugPrint('🎉 나머지 이미지 처리 완료: $noteId (${allPageIds.length}개 페이지)');
        }
        
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ 나머지 이미지 처리 실패: $noteId, 오류: $e');
        }
      }
    });
  }

  /// 백그라운드에서 텍스트 처리 시작
  void _startBackgroundProcessing(
    String noteId,
    List<File> imageFiles,
    List<String> pageIds,
    dynamic userPrefs,
  ) {
    // 백그라운드에서 비동기 처리
    Future.microtask(() async {
      try {
        if (kDebugMode) {
          debugPrint('🔄 백그라운드 텍스트 처리 시작: $noteId (${imageFiles.length}개 이미지)');
          debugPrint('📋 TextProcessingOrchestrator를 사용한 통합 처리');
        }
        
        final mode = userPrefs.useSegmentMode ? TextProcessingMode.segment : TextProcessingMode.paragraph;
        final List<PageProcessingData> pageDataList = [];
        
        // 각 이미지에 대해 TextProcessingOrchestrator 사용
        for (int i = 0; i < imageFiles.length; i++) {
          try {
            if (kDebugMode) {
              debugPrint('📄 이미지 ${i+1}/${imageFiles.length} 처리 시작');
            }
            
            final pageData = await _textProcessingOrchestrator.processImageText(
              imageFile: imageFiles[i],
              pageId: pageIds[i],
              mode: mode,
              sourceLanguage: userPrefs.sourceLanguage,
              targetLanguage: userPrefs.targetLanguage,
            );
            
            if (pageData != null) {
              pageDataList.add(pageData);
              
              if (kDebugMode) {
                debugPrint('✅ 이미지 ${i+1} 처리 완료 → 페이지 업데이트됨');
              }
            } else {
              if (kDebugMode) {
                debugPrint('⚠️ 이미지 ${i+1} 처리 실패 → 건너뜀');
              }
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('❌ 이미지 ${i+1} 처리 실패: $e');
            }
            
            // 중국어 감지 실패의 경우 전체 노트 생성 중단
            if (e.toString().contains('중국어가 없습니다')) {
              if (kDebugMode) {
                debugPrint('🛑 중국어 감지 실패로 전체 노트 생성 중단');
              }
              
              // 노트 상태를 실패로 업데이트 (Firestore 직접 업데이트)
              try {
                await FirebaseFirestore.instance.collection('notes').doc(noteId).update({
                  'processingStatus': ProcessingStatus.failed.toString(),
                  'errorMessage': e.toString(),
                  'errorType': 'NO_CHINESE_DETECTED',
                  'failedAt': FieldValue.serverTimestamp(),
                });
              } catch (updateError) {
                if (kDebugMode) {
                  debugPrint('⚠️ 노트 실패 상태 저장 실패: $updateError');
                }
              }
              
              // 백그라운드 처리에서는 rethrow하지 않고 조용히 종료
              // UI 매니저는 이미 성공 상태로 노트 상세 화면으로 이동함
              return; // rethrow 제거
            }
            
            // 기타 에러의 경우 페이지별 실패 처리 (기존 로직 유지)
            try {
              await _pageService.updatePage(pageIds[i], {
                'status': ProcessingStatus.failed.toString(),
                'errorMessage': e.toString(),
                'errorType': 'PROCESSING_ERROR',
                'ocrCompletedAt': FieldValue.serverTimestamp(),
              });
              
              if (kDebugMode) {
                debugPrint('📝 페이지 에러 상태 저장: ${pageIds[i]}');
              }
            } catch (updateError) {
              if (kDebugMode) {
                debugPrint('⚠️ 페이지 에러 상태 저장 실패: $updateError');
              }
            }
            
            // 개별 페이지 실패는 전체 프로세스를 중단시키지 않음
          }
        }
        
        // 모든 텍스트 처리가 완료되면 LLM 후처리 작업 스케줄링
        if (pageDataList.isNotEmpty) {
          await _schedulePostProcessing(noteId, pageDataList, userPrefs);
          
          // OCR 사용량 업데이트 (실제 처리된 페이지 수만큼)
          try {
            final successfulOcrPages = pageDataList.where((page) => page.ocrSuccess).length;
            if (successfulOcrPages > 0) {
              await _usageLimitService.updateUsageAfterNoteCreation(ocrPages: successfulOcrPages);
              if (kDebugMode) {
                debugPrint('📊 [PreLLM] OCR 사용량 업데이트: $successfulOcrPages개 페이지');
              }
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('⚠️ [PreLLM] OCR 사용량 업데이트 실패 (무시): $e');
            }
          }
          
          // 실제 처리된 페이지 수로 메타데이터 동기화
          if (pageDataList.length != imageFiles.length) {
            if (kDebugMode) {
              debugPrint('📊 페이지 수 불일치 감지: 예상 ${imageFiles.length}개 → 실제 ${pageDataList.length}개');
            }
            // OCR 처리 중이므로 타임스탬프를 업데이트하지 않음
            await _noteService.updateNoteMetadata(
              noteId: noteId,
              pageCount: pageDataList.length,
              updateTimestamp: false,
            );
          }
          
          if (kDebugMode) {
            debugPrint('🎉 백그라운드 처리 완료: $noteId');
            debugPrint('   성공한 페이지: ${pageDataList.length}/${imageFiles.length}개');
            debugPrint('   다음 단계: LLM 번역 및 병음 처리 (PostLLMWorkflow)');
          }
        } else {
          if (kDebugMode) {
            debugPrint('⚠️ 처리된 페이지가 없어 후처리 건너뜀');
          }
        }
        
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ 백그라운드 처리 전체 실패: $noteId, 오류: $e');
        }
      }
    });
  }

  /// 후처리 작업 스케줄링
  Future<void> _schedulePostProcessing(
    String noteId,
    List<PageProcessingData> pageDataList,
    dynamic userPrefs,
  ) async {
    if (pageDataList.isEmpty) {
      if (kDebugMode) {
        debugPrint('⚠️ 처리할 페이지가 없어 후처리 건너뜀');
      }
      return;
    }
    
    try {
      final job = PostProcessingJob(
        noteId: noteId,
        pages: pageDataList,
        userPrefs: userPrefs,
        createdAt: DateTime.now(),
        priority: await _getUserPriority(),
      );
      
      // 후처리 워크플로우에 작업 등록
      await _postLLMWorkflow.enqueueJob(job);
      
      if (kDebugMode) {
        debugPrint('📋 후처리 작업 스케줄링 완료: ${pageDataList.length}개 페이지');
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 후처리 스케줄링 실패: $e');
      }
    }
  }

  /// 사용자 우선순위 계산 (유료/무료 등)
  Future<int> _getUserPriority() async {
    // TODO: 실제 사용자 등급에 따른 우선순위 계산
    return 1; // 기본 우선순위
  }
}

/// 후처리 작업 정보
class PostProcessingJob {
  final String noteId;
  final List<PageProcessingData> pages;
  final dynamic userPrefs;
  final DateTime createdAt;
  final int priority;
  final int retryCount;

  PostProcessingJob({
    required this.noteId,
    required this.pages,
    required this.userPrefs,
    required this.createdAt,
    required this.priority,
    this.retryCount = 0,
  });

  PostProcessingJob copyWith({
    int? retryCount,
  }) {
    return PostProcessingJob(
      noteId: noteId,
      pages: pages,
      userPrefs: userPrefs,
      createdAt: createdAt,
      priority: priority,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'noteId': noteId,
    'pages': pages.map((p) => p.toJson()).toList(),
    'userPrefs': userPrefs is Map<String, dynamic> 
        ? userPrefs 
        : (userPrefs?.toJson?.call() ?? {}),
    'createdAt': createdAt.toIso8601String(),
    'priority': priority,
    'retryCount': retryCount,
  };

  factory PostProcessingJob.fromJson(Map<String, dynamic> json) {
    return PostProcessingJob(
      noteId: json['noteId'],
      pages: (json['pages'] as List)
          .map((p) => PageProcessingData.fromJson(p))
          .toList(),
      userPrefs: json['userPrefs'] ?? {}, // 안전하게 Map으로 처리
      createdAt: DateTime.parse(json['createdAt']),
      priority: json['priority'],
      retryCount: json['retryCount'] ?? 0,
    );
  }
}
