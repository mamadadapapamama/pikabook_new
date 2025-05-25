import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../core/models/processing_status.dart';
import '../../../core/services/text_processing/llm_text_processing.dart';
import '../../../core/services/tts/tts_api_service.dart';

/// 페이지 서비스: 페이지 CRUD 작업만 담당합니다.
class PageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final LLMTextProcessing _llmProcessor = LLMTextProcessing();
  final TtsApiService _ttsService = TtsApiService();

  // 생성자 로그 추가
  PageService() {
    debugPrint('📄 PageService: 생성자 호출됨');
  }

  // 페이지 컬렉션 참조
  CollectionReference get _pagesCollection => _firestore.collection('pages');

  // 특정 노트의 페이지 쿼리
  Query getPagesForNoteQuery(String noteId) {
    return _pagesCollection
        .where('noteId', isEqualTo: noteId)
        .orderBy('pageNumber');
  }

  /// 기본 페이지 생성 (LLM 처리 없이 빠른 생성)
  /// 이미지 + 중국어 원문만 저장하고, 번역/병음은 후처리에서 처리
  Future<page_model.Page> createBasicPage({
    required String noteId,
    required String originalText,
    required int pageNumber,
    String? imageUrl,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('📄 기본 페이지 생성 시작: ${originalText.length}자');
      }

      // 1. Firestore에 기본 페이지 생성
      final pageRef = _pagesCollection.doc();
      final page = page_model.Page(
        id: pageRef.id,
        noteId: noteId,
        pageNumber: pageNumber,
        imageUrl: imageUrl,
        sourceLanguage: 'zh-CN',
        targetLanguage: 'ko',
      );

      // 2. 기본 데이터로 페이지 저장
      final pageData = page.toJson();
      pageData.addAll({
        'originalText': originalText,
        'translatedText': '', // 빈 상태 (후처리에서 채움)
        'pinyin': '',         // 빈 상태 (후처리에서 채움)
        'processingStatus': ProcessingStatus.textExtracted.toString(),
        'readyForLLM': true,  // 후처리 대상임을 표시
      });

      await pageRef.set(pageData);

      if (kDebugMode) {
        debugPrint('✅ 기본 페이지 생성 완료: ${pageRef.id}');
        debugPrint('   - 이미지: ${imageUrl?.isNotEmpty ?? false ? "있음" : "없음"}');
        debugPrint('   - 원문: ${originalText.length}자');
        debugPrint('   - 상태: ${ProcessingStatus.textExtracted.displayName}');
      }

      return page;

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 기본 페이지 생성 실패: $e');
      }
      rethrow;
    }
  }

  /// 페이지 생성 (기존 방식 - LLM 처리 포함)
  Future<page_model.Page> createPage({
    required String noteId,
    required String extractedText,
    required int pageNumber,
    String? imageUrl,
  }) async {
    try {
      // 1. Firestore에 페이지 생성
      final pageRef = _pagesCollection.doc();
      final page = page_model.Page(
        id: pageRef.id,
        noteId: noteId,
        pageNumber: pageNumber,
        imageUrl: imageUrl,
        sourceLanguage: 'zh-CN',
        targetLanguage: 'ko',
      );

      await pageRef.set(page.toJson());

      if (extractedText.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('페이지 텍스트 처리 시작: ${extractedText.length}자');
        }
        
        try {
          // 2. LLM 처리 (번역 + 병음)
          final processed = await _llmProcessor.processText(
            extractedText,
            sourceLanguage: 'zh-CN',
            targetLanguage: 'ko',
            needPinyin: true,
          );
          
          if (kDebugMode) {
            debugPrint('LLM 처리 완료: ${processed.fullTranslatedText.length}자 번역됨');
          }
          
          // 처리된 텍스트 정보를 페이지 문서에 업데이트
          final Map<String, dynamic> processedData = {
            'originalText': extractedText,
            'translatedText': processed.fullTranslatedText,
            'processedAt': FieldValue.serverTimestamp(),
          };
          
          // Pinyin 정보가 있으면 추가
          if (processed.units.isNotEmpty) {
            final pinyin = processed.units[0].pinyin;
            if (pinyin != null && pinyin.isNotEmpty) {
              processedData['pinyin'] = pinyin;
            }
          }
          
          // 전체 처리된 객체도 저장
          processedData['processedText'] = {
            'fullOriginalText': processed.fullOriginalText,
            'fullTranslatedText': processed.fullTranslatedText,
            'sourceLanguage': processed.sourceLanguage,
            'targetLanguage': processed.targetLanguage,
            'mode': processed.mode.toString(),
            'displayMode': processed.displayMode.toString(),
          };
          
          // Firestore에 처리된 데이터 업데이트
          await _pagesCollection.doc(pageRef.id).update(processedData);
          
          if (kDebugMode) {
            debugPrint('페이지 텍스트 처리 결과 저장 완료: ${pageRef.id}');
          }
        } catch (llmError) {
          if (kDebugMode) {
            debugPrint('LLM 처리 중 오류 발생: $llmError');
          }
          
          // LLM 처리 실패해도 원본 텍스트는 저장
          await _pagesCollection.doc(pageRef.id).update({
            'originalText': extractedText,
            'processError': llmError.toString(),
          });
        }
      } else {
        if (kDebugMode) {
          debugPrint('추출된 텍스트가 없어 LLM 처리 건너뜀');
        }
      }

      // 3. TTS 생성 - TtsApiService 사용
      try {
        await _ttsService.initialize(); // TTS 서비스 초기화 확인
        // 실제 TTS 처리는 페이지 상세화면에서 진행
      } catch (ttsError) {
        debugPrint('TTS 초기화 또는 생성 중 오류 (무시됨): $ttsError');
        // TTS 실패는 무시하고 계속 진행
      }

      return page;
    } catch (e) {
      debugPrint('페이지 생성 중 오류 발생: $e');
      rethrow;
    }
  }

  /// 페이지 업데이트
  Future<void> updatePage(String pageId, Map<String, dynamic> data) async {
    try {
      await _pagesCollection.doc(pageId).update(data);
      debugPrint('페이지 업데이트 완료: $pageId');
    } catch (e) {
      debugPrint('페이지 업데이트 중 오류 발생: $e');
      rethrow;
    }
  }

  /// 페이지 삭제
  Future<void> deletePage(String pageId) async {
    try {
      // 1. Firestore에서 페이지 삭제
      await _pagesCollection.doc(pageId).delete();
      debugPrint('페이지 삭제 완료: $pageId');
    } catch (e) {
      debugPrint('페이지 삭제 중 오류 발생: $e');
      rethrow;
    }
  }

  /// 페이지 가져오기
  Future<page_model.Page?> getPage(String pageId) async {
    try {
      final doc = await _pagesCollection.doc(pageId).get();
      if (!doc.exists) return null;
      return page_model.Page.fromFirestore(doc);
    } catch (e) {
      debugPrint('페이지 조회 중 오류 발생: $e');
      return null;
    }
  }

  /// 노트의 모든 페이지 가져오기
  Future<List<page_model.Page>> getPagesForNote(String noteId) async {
    try {
      final querySnapshot = await getPagesForNoteQuery(noteId).get();
      return querySnapshot.docs
          .map((doc) => page_model.Page.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('노트의 페이지 목록 조회 중 오류 발생: $e');
      return [];
    }
  }
}
