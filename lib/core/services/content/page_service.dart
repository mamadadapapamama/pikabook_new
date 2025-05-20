import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../models/page.dart' as page_model;
import '../storage/unified_cache_service.dart';

/// 페이지 서비스: 페이지 CRUD 작업만 담당합니다.
class PageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UnifiedCacheService _cacheService = UnifiedCacheService();

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
    required String originalText,
    required String translatedText,
    required int pageNumber,
    String? imageUrl,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('로그인이 필요합니다.');

      final now = DateTime.now();
      final pageData = page_model.Page(
        id: null, // Firestore에서 자동 생성
        noteId: noteId,
        originalText: originalText,
        translatedText: translatedText,
        pageNumber: pageNumber,
        imageUrl: imageUrl,
        createdAt: now,
        updatedAt: now,
      );

      final pageRef = await _pagesCollection.add({
        ...pageData.toFirestore(),
        'userId': user.uid,
        'noteId': noteId,
      });

      final newPage = pageData.copyWith(id: pageRef.id);
      await _cacheService.cachePage(noteId, newPage);
      return newPage;
    } catch (e) {
      debugPrint('페이지 생성 중 오류 발생: $e');
      throw Exception('페이지를 생성할 수 없습니다: $e');
    }
  }

  /// 페이지 가져오기 (캐시 활용)
  Future<page_model.Page?> getPageById(String pageId) async {
    try {
      // 1. 캐시에서 페이지 찾기 시도
      final cachedPage = await _cacheService.getCachedPage(pageId);
      if (cachedPage != null) {
        debugPrint('캐시에서 페이지 $pageId 로드됨');
        return cachedPage;
      }

      // 2. Firestore에서 페이지 가져오기
      final pageDoc = await _pagesCollection.doc(pageId).get();
      if (!pageDoc.exists) {
        return null;
      }

      // 3. 페이지 객체 생성 및 캐시에 저장
      final page = page_model.Page.fromFirestore(pageDoc);
      if (page.id != null) {
        final data = pageDoc.data() as Map<String, dynamic>?;
        final noteId = data?['noteId'] as String?;

        if (noteId != null) {
          await _cacheService.cachePage(noteId, page);
          debugPrint('Firestore에서 페이지 $pageId 로드 완료 및 캐시에 저장됨');
        }
      }

      return page;
    } catch (e) {
      debugPrint('페이지 조회 중 오류 발생: $e');
      return null;
    }
  }

  /// 노트의 모든 페이지 가져오기 (캐시 활용)
  Future<List<page_model.Page>> getPagesForNote(String noteId, {bool forceReload = false}) async {
    try {
      debugPrint('📄 getPagesForNote 호출: noteId=$noteId, forceReload=$forceReload');
      
      // 캐시에서 페이지 가져오기 시도 (forceReload가 아닌 경우)
      if (!forceReload) {
        final cachedPages = await _cacheService.getCachedPages(noteId);
        if (cachedPages.isNotEmpty) {
          debugPrint('캐시에서 ${cachedPages.length}개 페이지 로드: $noteId');
          return cachedPages;
        }
      }
      
      // 캐시에 없는 경우 서버에서 페이지 로드
      debugPrint('⚠️ 캐시에서 페이지를 찾지 못함, 서버에서 직접 로드');
      final snapshot = await _pagesCollection
        .where('noteId', isEqualTo: noteId)
        .orderBy('pageNumber')
        .get()
        .timeout(const Duration(seconds: 5), onTimeout: () {
          debugPrint('⚠️ 서버에서 페이지 가져오기 타임아웃');
          throw Exception('서버에서 페이지 가져오기 타임아웃');
        });
      
      final serverPages = snapshot.docs
        .map((doc) => page_model.Page.fromFirestore(doc))
        .toList();
        
      debugPrint('✅ Firestore에서 노트 $noteId의 페이지 ${serverPages.length}개 로드됨');
      
      // 서버 데이터로 캐시 업데이트
      await _cacheService.cachePages(noteId, serverPages);
      debugPrint('✅ 서버 데이터로 캐시 업데이트 완료');
      
      return serverPages;
    } catch (e, stackTrace) {
      debugPrint('❌ 노트 $noteId의 페이지를 가져오는 중 오류 발생: $e');
      debugPrint('스택 트레이스: $stackTrace');
      return [];
    }
  }

  /// 페이지 업데이트
  Future<page_model.Page?> updatePage(
    String pageId, {
    String? originalText,
    String? translatedText,
    int? pageNumber,
    String? imageUrl,
  }) async {
    try {
      final pageDoc = await _pagesCollection.doc(pageId).get();
      if (!pageDoc.exists) throw Exception('페이지를 찾을 수 없습니다.');

      final data = pageDoc.data() as Map<String, dynamic>?;
      final noteId = data?['noteId'] as String?;

      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (originalText != null) updates['originalText'] = originalText;
      if (translatedText != null) updates['translatedText'] = translatedText;
      if (pageNumber != null) updates['pageNumber'] = pageNumber;
      if (imageUrl != null) updates['imageUrl'] = imageUrl;

      await _pagesCollection.doc(pageId).update(updates);

      final updatedDoc = await _pagesCollection.doc(pageId).get();
      if (updatedDoc.exists) {
        final updatedPage = page_model.Page.fromFirestore(updatedDoc);
        if (noteId != null) {
          await _cacheService.cachePage(noteId, updatedPage);
          debugPrint('페이지 $pageId 업데이트 및 캐시 갱신 완료');
        }
        return updatedPage;
      }
      return null;
    } catch (e) {
      debugPrint('페이지 업데이트 중 오류 발생: $e');
      throw Exception('페이지를 업데이트할 수 없습니다: $e');
    }
  }

  /// 페이지 내용 업데이트
  Future<page_model.Page?> updatePageContent(
      String pageId, String originalText, String translatedText) async {
    try {
      await _pagesCollection.doc(pageId).update({
        'originalText': originalText,
        'translatedText': translatedText,
        'updatedAt': DateTime.now(),
      });

      final pageDoc = await _pagesCollection.doc(pageId).get();
      if (pageDoc.exists) {
        final updatedPage = page_model.Page.fromFirestore(pageDoc);
        final data = pageDoc.data() as Map<String, dynamic>?;
        final noteId = data?['noteId'] as String?;

        if (noteId != null && updatedPage.id != null) {
          await _cacheService.cachePage(noteId, updatedPage);
          debugPrint('페이지 객체 및 텍스트 캐시 업데이트 완료: ${updatedPage.id}');
        }

        return updatedPage;
      }
      return null;
    } catch (e) {
      debugPrint('페이지 내용 업데이트 중 오류 발생: $e');
      throw Exception('페이지 내용을 업데이트할 수 없습니다: $e');
    }
  }

  /// 노트의 모든 페이지 삭제
  Future<void> deleteAllPagesForNote(String noteId) async {
    try {
      final querySnapshot = await _pagesCollection
          .where('noteId', isEqualTo: noteId)
          .get();

      final batch = _firestore.batch();
      for (var doc in querySnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      await _cacheService.removeCachedPages(noteId);
      debugPrint('노트 $noteId의 모든 페이지 삭제 완료');
    } catch (e) {
      debugPrint('노트의 모든 페이지 삭제 중 오류 발생: $e');
      rethrow;
    }
  }

  /// 전체 캐시 초기화
  void clearCache() {
    _cacheService.clearCache();
  }
}
