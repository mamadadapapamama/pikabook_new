import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/note_service.dart';
import '../../../core/services/media/image_service.dart';
import 'services/page_service.dart';
import '../../../core/services/text_processing/ocr_service.dart';
import '../../core/services/text_processing/text_cleaner_service.dart';
import '../../core/services/text_processing/text_mode_seperation_service.dart';
import '../../core/services/authentication/user_preferences_service.dart';
import '../../core/models/processed_text.dart';
import '../../core/services/common/usage_limit_service.dart';
import 'post_llm_workflow.dart';

/// 전처리 워크플로우: 빠른 노트 생성 (3-5초 목표)
/// OCR → 텍스트 정리 → 모드별 분리 → 기본 페이지 생성 → 후처리 스케줄링
class PreLLMWorkflow {
  // 서비스 인스턴스
  final NoteService _noteService = NoteService();
  final ImageService _imageService = ImageService();
  final PageService _pageService = PageService();
  final OcrService _ocrService = OcrService();
  final TextCleanerService _textCleanerService = TextCleanerService();
  final TextModeSeparationService _textSeparationService = TextModeSeparationService();
  final UserPreferencesService _preferencesService = UserPreferencesService();
  final UsageLimitService _usageLimitService = UsageLimitService();
  final PostLLMWorkflow _postLLMWorkflow = PostLLMWorkflow();

  /// 빠른 노트 생성 메인 메서드 (이미지 업로드만 완료 후 즉시 반환)
  Future<String> createNoteQuickly(List<File> imageFiles) async {
    if (imageFiles.isEmpty) {
      throw Exception('이미지가 없습니다.');
    }

    if (kDebugMode) {
      debugPrint('🚀 전처리 워크플로우 시작: ${imageFiles.length}개 이미지');
    }

    try {
      // 1. 노트 메타데이터 생성 (빠름)
      final noteId = await _noteService.createNote();
      
      // 2. 사용자 설정 로드 (캐시됨)
      final userPrefs = await _preferencesService.getPreferences();
      
      // 3. 이미지 업로드만 빠르게 처리하고 기본 페이지 생성
      final List<String> pageIds = [];
      final List<String> imageUrls = [];
      
      for (int i = 0; i < imageFiles.length; i++) {
        if (kDebugMode) {
          debugPrint('📷 이미지 ${i+1}/${imageFiles.length} 업로드 시작');
        }
        
        // 이미지 업로드만 수행
        final imageUrl = await _imageService.uploadImage(imageFiles[i]);
        imageUrls.add(imageUrl);
        
        if (kDebugMode) {
          debugPrint('✅ 이미지 ${i+1} 업로드 완료: $imageUrl');
        }
        
        // 기본 페이지 생성 (텍스트 없이)
        final pageId = await _createBasicPage(
          noteId: noteId,
          pageNumber: i,
          imageUrl: imageUrl,
          originalText: '', // 빈 텍스트로 시작
        );
        pageIds.add(pageId);
        
        if (kDebugMode) {
          debugPrint('✅ 기본 페이지 ${i+1} 생성 완료: $pageId');
        }
      }
      
      // 4. 첫 번째 이미지를 노트 썸네일로 설정
      if (imageUrls.isNotEmpty) {
        await _updateNoteThumbnail(noteId, imageUrls[0]);
      }
      
      // 5. 백그라운드 OCR 및 텍스트 처리 시작
      _startBackgroundProcessing(noteId, imageFiles, pageIds, userPrefs);
      
      if (kDebugMode) {
        debugPrint('🎉 빠른 노트 생성 완료: $noteId (${pageIds.length}개 페이지)');
        debugPrint('📋 OCR 및 텍스트 처리는 백그라운드에서 진행됩니다');
      }
      
      return noteId;
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 빠른 노트 생성 실패: $e');
      }
      rethrow;
    }
  }

  /// 백그라운드에서 OCR 및 텍스트 처리 시작
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
          debugPrint('🔄 백그라운드 OCR 및 텍스트 처리 시작: $noteId');
        }
        
        final mode = userPrefs.useSegmentMode ? TextProcessingMode.segment : TextProcessingMode.paragraph;
        final List<PageProcessingData> pageDataList = [];
        
        // 각 이미지에 대해 OCR 및 텍스트 처리
        for (int i = 0; i < imageFiles.length; i++) {
          try {
            if (kDebugMode) {
              debugPrint('🔍 백그라운드 OCR 시작: 이미지 ${i+1}/${imageFiles.length}');
            }
            
            final pageData = await _processImageWithOCR(
              imageFile: imageFiles[i],
              pageId: pageIds[i],
              pageNumber: i,
              mode: mode,
              userPrefs: userPrefs,
            );
            
            if (pageData != null) {
              pageDataList.add(pageData);
              
              // 페이지별로 즉시 업데이트 (실시간 반영)
              await _updatePageWithOCRResult(pageData);
              
              if (kDebugMode) {
                debugPrint('✅ 백그라운드 OCR 완료: 페이지 ${i+1}');
              }
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('⚠️ 백그라운드 OCR 실패: 페이지 ${i+1}, 오류: $e');
            }
            // 개별 페이지 실패는 전체 프로세스를 중단시키지 않음
          }
        }
        
        // 모든 OCR이 완료되면 후처리 작업 스케줄링
        if (pageDataList.isNotEmpty) {
          await _schedulePostProcessing(noteId, pageDataList, userPrefs);
          
          if (kDebugMode) {
            debugPrint('🎉 백그라운드 처리 완료: $noteId (${pageDataList.length}개 페이지)');
          }
        }
        
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ 백그라운드 처리 실패: $noteId, 오류: $e');
        }
      }
    });
  }

  /// 백그라운드에서 OCR 및 텍스트 처리
  Future<PageProcessingData?> _processImageWithOCR({
    required File imageFile,
    required String pageId,
    required int pageNumber,
    required TextProcessingMode mode,
    required dynamic userPrefs,
  }) async {
    try {
      String extractedText = '';
      String cleanedText = '';
      List<String> textSegments = [];
      
      // 1. OCR 텍스트 추출
      if (kDebugMode) {
        debugPrint('🔍 OCR 텍스트 추출 시작: 페이지 $pageId');
      }
      
      extractedText = await _ocrService.recognizeText(imageFile);
      
      if (kDebugMode) {
        debugPrint('✅ OCR 완료: ${extractedText.length}자');
        if (extractedText.isNotEmpty) {
          final preview = extractedText.length > 30 ? 
              '${extractedText.substring(0, 30)}...' : extractedText;
          debugPrint('OCR 결과 미리보기: "$preview"');
        }
      }
      
      // 2. 텍스트 정리 (중국어만 추출)
      if (extractedText.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('🧹 텍스트 정리 시작');
        }
        
        cleanedText = _textCleanerService.cleanText(extractedText);
        
        if (kDebugMode) {
          debugPrint('✅ 텍스트 정리 완료: ${extractedText.length}자 → ${cleanedText.length}자');
        }
      }
      
      // 3. 모드별 텍스트 분리
      if (cleanedText.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('📝 텍스트 분리 시작: ${mode.toString()}');
        }
        
        textSegments = _textSeparationService.separateByMode(cleanedText, mode);
        
        if (kDebugMode) {
          debugPrint('✅ 텍스트 분리 완료: ${textSegments.length}개 조각');
        }
      } else if (extractedText.isNotEmpty) {
        // 정리된 텍스트가 없으면 원본 텍스트로 분리
        textSegments = _textSeparationService.separateByMode(extractedText, mode);
        if (kDebugMode) {
          debugPrint('✅ 원본 텍스트 분리 완료: ${textSegments.length}개 조각');
        }
      }
      
      // 4. 이미지 파일 크기 계산
      int fileSize = 0;
      try {
        fileSize = await imageFile.length();
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ 파일 크기 계산 실패: $e');
        }
      }
      
      // 5. PageProcessingData 생성 (이미지 URL을 PageService에서 가져오기)
      String imageUrl = '';
      try {
        final page = await _pageService.getPage(pageId);
        imageUrl = page?.imageUrl ?? '';
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ 페이지에서 이미지 URL 가져오기 실패: $e');
        }
      }
      
      final pageData = PageProcessingData(
        pageId: pageId,
        imageUrl: imageUrl,
        textSegments: textSegments,
        mode: mode,
        sourceLanguage: userPrefs.sourceLanguage,
        targetLanguage: userPrefs.targetLanguage,
        imageFileSize: fileSize,
        ocrSuccess: extractedText.isNotEmpty,
      );
      
      if (kDebugMode) {
        debugPrint('📊 백그라운드 PageProcessingData 생성 완료:');
        debugPrint('   페이지 ID: ${pageData.pageId}');
        debugPrint('   텍스트 세그먼트: ${pageData.textSegments.length}개');
        debugPrint('   OCR 성공: ${pageData.ocrSuccess}');
      }
      
      return pageData;
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 백그라운드 OCR 처리 실패: $pageId, 오류: $e');
      }
      return null;
    }
  }

  /// OCR 결과로 페이지 업데이트
  Future<void> _updatePageWithOCRResult(PageProcessingData pageData) async {
    try {
      // 추출된 텍스트를 페이지에 업데이트
      final originalText = pageData.textSegments.join(' ');
      
      await _pageService.updatePage(pageData.pageId, {
        'originalText': originalText,
        'ocrProcessedAt': FieldValue.serverTimestamp(),
        'ocrSuccess': pageData.ocrSuccess,
      });
      
      if (kDebugMode) {
        debugPrint('✅ 페이지 OCR 결과 업데이트 완료: ${pageData.pageId}');
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 페이지 OCR 결과 업데이트 실패: ${pageData.pageId}, 오류: $e');
      }
    }
  }

  /// 기본 페이지 생성 (번역 없이)
  Future<String> _createBasicPage({
    required String noteId,
    required int pageNumber,
    required String imageUrl,
    required String originalText,
  }) async {
    final page = await _pageService.createPage(
      noteId: noteId,
      originalText: originalText,
      pageNumber: pageNumber,
      imageUrl: imageUrl,
    );
    
    return page.id;
  }

  /// 노트 썸네일 업데이트
  Future<void> _updateNoteThumbnail(String noteId, String imageUrl) async {
    try {
      await _noteService.updateNoteThumbnail(noteId);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 썸네일 업데이트 실패 (무시): $e');
      }
    }
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

/// 페이지 처리 데이터 (전처리 → 후처리 전달용)
class PageProcessingData {
  final String pageId;
  final String imageUrl;
  final List<String> textSegments;
  final TextProcessingMode mode;
  final String sourceLanguage;
  final String targetLanguage;
  final int imageFileSize; // 이미지 파일 크기 (바이트)
  final bool ocrSuccess; // OCR 성공 여부

  PageProcessingData({
    required this.pageId,
    required this.imageUrl,
    required this.textSegments,
    required this.mode,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.imageFileSize,
    required this.ocrSuccess,
  });

  Map<String, dynamic> toJson() => {
    'pageId': pageId,
    'imageUrl': imageUrl,
    'textSegments': textSegments,
    'mode': mode.toString(),
    'sourceLanguage': sourceLanguage,
    'targetLanguage': targetLanguage,
    'imageFileSize': imageFileSize,
    'ocrSuccess': ocrSuccess,
  };

  factory PageProcessingData.fromJson(Map<String, dynamic> json) {
    return PageProcessingData(
      pageId: json['pageId'],
      imageUrl: json['imageUrl'],
      textSegments: List<String>.from(json['textSegments']),
      mode: TextProcessingMode.values.firstWhere(
        (e) => e.toString() == json['mode']
      ),
      sourceLanguage: json['sourceLanguage'],
      targetLanguage: json['targetLanguage'],
      imageFileSize: json['imageFileSize'] ?? 0,
      ocrSuccess: json['ocrSuccess'] ?? false,
    );
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
    'userPrefs': userPrefs.toJson(), // UserPreferences의 toJson 필요
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
      userPrefs: json['userPrefs'], // UserPreferences.fromJson으로 변경 필요
      createdAt: DateTime.parse(json['createdAt']),
      priority: json['priority'],
      retryCount: json['retryCount'] ?? 0,
    );
  }
}
