import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../models/page.dart' as page_model;
import '../text_processing/llm_text_processing.dart';

/// 페이지 서비스: 페이지 CRUD 작업만 담당합니다.
class PageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final LLMTextProcessing _llmProcessor = LLMTextProcessing();

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

  /// 페이지 생성
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

      // 2. LLM 처리 (번역 + 병음)
      final processed = await _llmProcessor.processText(
        extractedText,
        sourceLanguage: 'zh-CN',
        targetLanguage: 'ko',
        needPinyin: true,
      );

      // 3. TTS 생성
      final ttsPath = await _llmProcessor.generateTTS(extractedText, 'zh-CN');

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
      return page_model.Page.fromJson(doc.data() as Map<String, dynamic>);
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
          .map((doc) => page_model.Page.fromJson(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('노트의 페이지 목록 조회 중 오류 발생: $e');
      return [];
    }
  }
}
