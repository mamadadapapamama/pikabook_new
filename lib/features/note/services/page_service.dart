import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../core/models/processing_status.dart';

/// 페이지 서비스: 페이지 CRUD 작업만 담당합니다.
class PageService {
  // 싱글톤 패턴
  static final PageService _instance = PageService._internal();
  factory PageService() => _instance;
  PageService._internal() {
    if (kDebugMode) {
      debugPrint('📄 PageService: 생성자 호출됨');
    }
  }
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 페이지 컬렉션 참조
  CollectionReference get _pagesCollection => _firestore.collection('pages');

  // 특정 노트의 페이지 쿼리
  Query getPagesForNoteQuery(String noteId) {
    return _pagesCollection
        .where('noteId', isEqualTo: noteId)
        .orderBy('pageNumber');
  }

  /// 기본 페이지 생성 (텍스트 추출 완료 상태로 생성)
  /// 텍스트 처리는 TextProcessingService에서 별도로 처리
  Future<page_model.Page> createPage({
    required String noteId,
    required String originalText,
    required int pageNumber,
    String? imageUrl,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('📄 페이지 생성 시작: ${originalText.length}자');
      }

      // Firestore에 페이지 생성
      final pageRef = _pagesCollection.doc();
      final page = page_model.Page(
        id: pageRef.id,
        noteId: noteId,
        pageNumber: pageNumber,
        imageUrl: imageUrl,
        sourceLanguage: 'zh-CN',
        targetLanguage: 'ko',
      );

      // 기본 데이터로 페이지 저장
      final pageData = page.toJson();
      pageData.addAll({
        'originalText': originalText,
        'translatedText': '', // 빈 상태 (TextProcessingService에서 처리)
        'pinyin': '',         // 빈 상태 (TextProcessingService에서 처리)
        'processingStatus': ProcessingStatus.textExtracted.toString(),
        'readyForLLM': true,  // 텍스트 처리 대상임을 표시
        'showTypewriterEffect': true, // 새 페이지는 타이프라이터 효과 활성화
      });

      await pageRef.set(pageData);

      if (kDebugMode) {
        debugPrint('✅ 페이지 생성 완료: ${pageRef.id}');
        debugPrint('   - 이미지: ${imageUrl?.isNotEmpty ?? false ? "있음" : "없음"}');
        debugPrint('   - 원문: ${originalText.length}자');
        debugPrint('   - 상태: ${ProcessingStatus.textExtracted.displayName}');
      }

      return page;

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 페이지 생성 실패: $e');
      }
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
