import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../../core/services/content/note_service.dart';
import '../../../core/services/media/image_service.dart';
import '../../../core/services/content/page_service.dart';
import '../../../core/services/text_processing/ocr_service.dart';
import '../../core/services/text_processing/text_cleaner_service.dart';
import '../../core/services/text_processing/text_mode_seperation_service.dart';
import '../../core/services/authentication/user_preferences_service.dart';
import '../../core/models/processed_text.dart';
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
  final PostLLMWorkflow _postLLMWorkflow = PostLLMWorkflow();

  /// 빠른 노트 생성 메인 메서드
  Future<String> createNoteQuickly(List<File> imageFiles) async {
    if (imageFiles.isEmpty) {
      throw Exception('이미지가 없습니다.');
    }

    if (kDebugMode) {
      debugPrint('🚀 전처리 워크플로우 시작: ${imageFiles.length}개 이미지');
    }

    try {
      // 1. 노트 메타데이터 생성 (빠름)
      final noteId = await _createNoteMetadata();
      
      // 2. 사용자 설정 로드 (캐시됨)
      final userPrefs = await _preferencesService.getPreferences();
      final mode = userPrefs.useSegmentMode ? TextProcessingMode.segment : TextProcessingMode.paragraph;
      
      // 3. 이미지별 빠른 처리
      final List<PageProcessingData> pageDataList = [];
      
      for (int i = 0; i < imageFiles.length; i++) {
        if (kDebugMode) {
          debugPrint('📷 이미지 ${i+1}/${imageFiles.length} 처리 시작');
        }
        
        final pageData = await _processImageQuickly(
          imageFile: imageFiles[i],
          noteId: noteId,
          pageNumber: i,
          mode: mode,
          userPrefs: userPrefs,
        );
        
        if (pageData != null) {
          pageDataList.add(pageData);
        }
        
        if (kDebugMode) {
          debugPrint('✅ 이미지 ${i+1} 빠른 처리 완료');
        }
      }
      
      // 4. 첫 번째 이미지를 노트 썸네일로 설정
      if (pageDataList.isNotEmpty && pageDataList[0].imageUrl.isNotEmpty) {
        await _updateNoteThumbnail(noteId, pageDataList[0].imageUrl);
      }
      
      // 5. 후처리 작업 스케줄링
      await _schedulePostProcessing(noteId, pageDataList, userPrefs);
      
      if (kDebugMode) {
        debugPrint('🎉 전처리 워크플로우 완료: $noteId (${pageDataList.length}개 페이지)');
      }
      
      return noteId;
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 전처리 워크플로우 실패: $e');
      }
      rethrow;
    }
  }

  /// 노트 메타데이터 생성
  Future<String> _createNoteMetadata() async {
    return await _noteService.createNote();
  }

  /// 단일 이미지 빠른 처리
  Future<PageProcessingData?> _processImageQuickly({
    required File imageFile,
    required String noteId,
    required int pageNumber,
    required TextProcessingMode mode,
    required dynamic userPrefs,
  }) async {
    try {
      String imageUrl = '';
      String extractedText = '';
      String cleanedText = '';
      List<String> textSegments = [];
      
      // 1. 이미지 업로드 (병렬 가능하지만 현재는 순차)
      if (kDebugMode) {
        debugPrint('🔼 이미지 업로드 시작');
      }
      
      imageUrl = await _imageService.uploadImage(imageFile);
      
      if (kDebugMode) {
        debugPrint('✅ 이미지 업로드 완료: $imageUrl');
      }
      
      // 2. OCR 텍스트 추출
      if (kDebugMode) {
        debugPrint('🔍 OCR 텍스트 추출 시작');
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
      
      // 3. 텍스트 정리 (중국어만 추출)
      if (extractedText.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('🧹 텍스트 정리 시작');
        }
        
        cleanedText = _textCleanerService.cleanText(extractedText);
        
        if (kDebugMode) {
          debugPrint('✅ 텍스트 정리 완료: ${extractedText.length}자 → ${cleanedText.length}자');
        }
      }
      
      // 4. 모드별 텍스트 분리
      if (cleanedText.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('📝 텍스트 분리 시작: ${mode.toString()}');
          debugPrint('   정리된 텍스트: "${cleanedText.length > 50 ? cleanedText.substring(0, 50) + '...' : cleanedText}"');
        }
        
        textSegments = _textSeparationService.separateByMode(cleanedText, mode);
        
        if (kDebugMode) {
          debugPrint('✅ 텍스트 분리 완료: ${textSegments.length}개 조각');
          for (int i = 0; i < textSegments.length && i < 3; i++) {
            final preview = textSegments[i].length > 30 ? '${textSegments[i].substring(0, 30)}...' : textSegments[i];
            debugPrint('   조각 ${i+1}: "$preview"');
          }
          if (textSegments.length > 3) {
            debugPrint('   (${textSegments.length - 3}개 조각 더...)');
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint('⚠️ 정리된 텍스트가 비어있어 분리 건너뜀');
        }
      }
      
      // 5. 기본 페이지 생성 (번역 없이)
      final pageId = await _createBasicPage(
        noteId: noteId,
        pageNumber: pageNumber,
        imageUrl: imageUrl,
        originalText: cleanedText,
      );
      
      // 6. 후처리용 데이터 생성
      final pageData = PageProcessingData(
        pageId: pageId,
        imageUrl: imageUrl,
        textSegments: textSegments,
        mode: mode,
        sourceLanguage: userPrefs.sourceLanguage,
        targetLanguage: userPrefs.targetLanguage,
      );
      
      if (kDebugMode) {
        debugPrint('📊 PageProcessingData 생성 완료:');
        debugPrint('   페이지 ID: ${pageData.pageId}');
        debugPrint('   텍스트 세그먼트: ${pageData.textSegments.length}개');
        debugPrint('   모드: ${pageData.mode}');
        debugPrint('   언어: ${pageData.sourceLanguage} → ${pageData.targetLanguage}');
      }
      
      return pageData;
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 이미지 처리 실패: $e');
      }
      return null;
    }
  }

  /// 기본 페이지 생성 (번역 없이)
  Future<String> _createBasicPage({
    required String noteId,
    required int pageNumber,
    required String imageUrl,
    required String originalText,
  }) async {
    final page = await _pageService.createBasicPage(
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

  PageProcessingData({
    required this.pageId,
    required this.imageUrl,
    required this.textSegments,
    required this.mode,
    required this.sourceLanguage,
    required this.targetLanguage,
  });

  Map<String, dynamic> toJson() => {
    'pageId': pageId,
    'imageUrl': imageUrl,
    'textSegments': textSegments,
    'mode': mode.toString(),
    'sourceLanguage': sourceLanguage,
    'targetLanguage': targetLanguage,
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
