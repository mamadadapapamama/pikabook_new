import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/page.dart' as page_model;
import 'image_service.dart';
import 'ocr_service.dart';
import 'translation_service.dart';
import 'page_cache_service.dart';

class PageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImageService _imageService = ImageService();
  final OcrService _ocrService = OcrService();
  final TranslationService _translationService = TranslationService();
  final PageCacheService _cacheService = PageCacheService();

  // 페이지 컬렉션 참조
  CollectionReference get _pagesCollection => _firestore.collection('pages');

  // 특정 노트의 페이지 쿼리
  Query getPagesForNoteQuery(String noteId) {
    return _pagesCollection
        .where('noteId', isEqualTo: noteId)
        .orderBy('pageNumber');
  }

  // 페이지 생성
  Future<page_model.Page> createPage({
    required String noteId,
    required String originalText,
    required String translatedText,
    required int pageNumber,
    File? imageFile,
  }) async {
    try {
      // 사용자 확인
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다.');
      }

      // 이미지 업로드 (있는 경우)
      String? imageUrl;
      if (imageFile != null) {
        imageUrl = await _imageService.uploadImage(imageFile);
      }

      // 페이지 데이터 생성
      final now = DateTime.now();
      final pageData = page_model.Page(
        originalText: originalText,
        translatedText: translatedText,
        pageNumber: pageNumber,
        imageUrl: imageUrl,
        createdAt: now,
        updatedAt: now,
      );

      // Firestore에 페이지 추가
      final pageRef = await _pagesCollection.add({
        ...pageData.toFirestore(),
        'userId': user.uid,
        'noteId': noteId,
      });

      // ID가 포함된 페이지 객체 반환
      final newPage = page_model.Page(
        id: pageRef.id,
        originalText: originalText,
        translatedText: translatedText,
        pageNumber: pageNumber,
        imageUrl: imageUrl,
        createdAt: now,
        updatedAt: now,
      );

      // 캐시에 새 페이지 저장
      _cacheService.cachePage(pageRef.id, newPage);

      return newPage;
    } catch (e) {
      debugPrint('페이지 생성 중 오류 발생: $e');
      throw Exception('페이지를 생성할 수 없습니다: $e');
    }
  }

  // 이미지로 페이지 생성 (OCR 및 번역 포함)
  Future<page_model.Page> createPageWithImage({
    required String noteId,
    required int pageNumber,
    required File imageFile,
    String? targetLanguage,
  }) async {
    try {
      // 이미지에서 텍스트 추출 (OCR)
      final extractedText = await _ocrService.extractText(imageFile);

      // 추출된 텍스트 번역
      final translatedText = await _translationService.translateText(
        extractedText,
        targetLanguage: targetLanguage,
      );

      // 페이지 생성
      return await createPage(
        noteId: noteId,
        originalText: extractedText,
        translatedText: translatedText,
        pageNumber: pageNumber,
        imageFile: imageFile,
      );
    } catch (e) {
      debugPrint('이미지로 페이지 생성 중 오류 발생: $e');
      throw Exception('이미지로 페이지를 생성할 수 없습니다: $e');
    }
  }

  // 페이지 가져오기 (캐시 활용)
  Future<page_model.Page?> getPageById(String pageId) async {
    try {
      // 1. 캐시에서 페이지 확인
      final cachedPage = _cacheService.getPage(pageId);
      if (cachedPage != null) {
        debugPrint('캐시에서 페이지 $pageId 로드됨');
        return cachedPage;
      }

      // 2. Firestore에서 페이지 가져오기
      debugPrint('Firestore에서 페이지 $pageId 로드 시작');
      final doc = await _pagesCollection.doc(pageId).get();
      if (!doc.exists) {
        return null;
      }

      // 3. 페이지 객체 생성 및 캐시에 저장
      final page = page_model.Page.fromFirestore(doc);
      if (page.id != null) {
        _cacheService.cachePage(page.id!, page);
      }

      debugPrint('Firestore에서 페이지 $pageId 로드 완료 및 캐시에 저장됨');
      return page;
    } catch (e) {
      debugPrint('페이지 조회 중 오류 발생: $e');
      throw Exception('페이지를 조회할 수 없습니다: $e');
    }
  }

  // 노트의 모든 페이지 가져오기 (캐시 활용)
  Future<List<page_model.Page>> getPagesForNote(String noteId) async {
    try {
      debugPrint('노트 $noteId의 페이지 조회 시작');

      // 1. 캐시에서 모든 페이지 확인
      if (_cacheService.hasAllPagesForNote(noteId)) {
        final cachedPages = _cacheService.getPagesForNote(noteId);
        debugPrint('캐시에서 노트 $noteId의 페이지 ${cachedPages.length}개 로드됨');

        // 페이지가 1개만 있는 경우 Firestore에서 다시 확인 (캐시 문제 가능성)
        if (cachedPages.length <= 1) {
          debugPrint('캐시에 페이지가 1개만 있어 Firestore에서 다시 확인합니다.');
          // 캐시 무시하고 계속 진행
        } else {
          return cachedPages;
        }
      }

      // 2. Firestore에서 페이지 가져오기
      debugPrint('Firestore에서 노트 $noteId의 페이지 로드 시작');
      final snapshot = await getPagesForNoteQuery(noteId).get();
      debugPrint('노트 $noteId의 페이지 쿼리 결과: ${snapshot.docs.length}개 문서');

      // 결과가 없으면 노트 문서에서 페이지 ID 목록 확인
      if (snapshot.docs.isEmpty) {
        debugPrint('페이지 쿼리 결과가 없어 노트 문서에서 페이지 ID 목록을 확인합니다.');
        final noteDoc = await _firestore.collection('notes').doc(noteId).get();
        if (noteDoc.exists) {
          final data = noteDoc.data() as Map<String, dynamic>?;
          final pageIds = data?['pages'] as List<dynamic>?;

          if (pageIds != null && pageIds.isNotEmpty) {
            debugPrint('노트 문서에서 ${pageIds.length}개의 페이지 ID를 찾았습니다.');

            // 각 페이지 ID로 페이지 문서 조회
            final List<page_model.Page> pages = [];
            for (final pageId in pageIds) {
              try {
                final pageDoc =
                    await _pagesCollection.doc(pageId.toString()).get();
                if (pageDoc.exists) {
                  final page = page_model.Page.fromFirestore(pageDoc);
                  pages.add(page);
                  debugPrint(
                      '페이지 ${page.id} 로드 성공 (pageNumber: ${page.pageNumber})');
                }
              } catch (e) {
                debugPrint('페이지 $pageId 로드 중 오류: $e');
              }
            }

            // 페이지 번호 순으로 정렬
            pages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));

            // 캐시에 페이지 저장
            _cacheService.cachePages(noteId, pages);

            debugPrint(
                '노트 $noteId의 페이지 ${pages.length}개 로드 완료 및 캐시에 저장됨 (ID 목록 사용)');
            return pages;
          }
        }
      }

      final pages = snapshot.docs
          .map((doc) => page_model.Page.fromFirestore(doc))
          .toList();

      // 페이지 번호 순으로 정렬
      pages.sort((a, b) => a.pageNumber.compareTo(b.pageNumber));

      // 각 페이지 정보 로깅
      for (final page in pages) {
        debugPrint(
            '페이지 정보: id=${page.id}, pageNumber=${page.pageNumber}, imageUrl=${page.imageUrl != null}');
      }

      // 3. 캐시에 페이지 저장
      _cacheService.cachePages(noteId, pages);

      debugPrint('노트 $noteId의 페이지 ${pages.length}개 로드 완료 및 캐시에 저장됨');
      return pages;
    } catch (e) {
      debugPrint('노트의 페이지 목록 조회 중 오류 발생: $e');
      throw Exception('페이지 목록을 조회할 수 없습니다: $e');
    }
  }

  // 페이지 업데이트
  Future<void> updatePage(
    String pageId, {
    String? originalText,
    String? translatedText,
    int? pageNumber,
    File? imageFile,
  }) async {
    try {
      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (originalText != null) {
        updates['originalText'] = originalText;
      }

      if (translatedText != null) {
        updates['translatedText'] = translatedText;
      }

      if (pageNumber != null) {
        updates['pageNumber'] = pageNumber;
      }

      // 이미지 업로드 (있는 경우)
      if (imageFile != null) {
        // 기존 이미지 URL 가져오기
        final pageDoc = await _pagesCollection.doc(pageId).get();
        final data = pageDoc.data() as Map<String, dynamic>?;
        final existingImageUrl = data?['imageUrl'] as String?;

        // 기존 이미지 삭제
        if (existingImageUrl != null && existingImageUrl.isNotEmpty) {
          await _imageService.deleteImage(existingImageUrl);
        }

        // 새 이미지 업로드
        final newImageUrl = await _imageService.uploadImage(imageFile);
        updates['imageUrl'] = newImageUrl;

        // 이미지가 변경되었고 원본 텍스트가 제공되지 않은 경우, OCR 수행
        if (originalText == null) {
          final extractedText = await _ocrService.extractText(imageFile);
          updates['originalText'] = extractedText;

          // 번역 텍스트가 제공되지 않은 경우, 번역 수행
          if (translatedText == null) {
            final translatedText =
                await _translationService.translateText(extractedText);
            updates['translatedText'] = translatedText;
          }
        }
      }

      // Firestore 업데이트
      await _pagesCollection.doc(pageId).update(updates);

      // 캐시에서 페이지 제거 (업데이트된 데이터로 다시 로드되도록)
      _cacheService.removePage(pageId);

      // 업데이트된 페이지 다시 로드하여 캐시 갱신
      await getPageById(pageId);
    } catch (e) {
      debugPrint('페이지 업데이트 중 오류 발생: $e');
      throw Exception('페이지를 업데이트할 수 없습니다: $e');
    }
  }

  // 페이지 텍스트 번역
  Future<String> translatePageText(String pageId,
      {String? targetLanguage}) async {
    try {
      // 페이지 정보 가져오기
      final page = await getPageById(pageId);
      if (page == null) {
        throw Exception('페이지를 찾을 수 없습니다.');
      }

      // 원본 텍스트 번역
      final translatedText = await _translationService.translateText(
        page.originalText,
        targetLanguage: targetLanguage,
      );

      // 번역 결과 저장
      await updatePage(
        pageId,
        translatedText: translatedText,
      );

      return translatedText;
    } catch (e) {
      debugPrint('페이지 텍스트 번역 중 오류 발생: $e');
      throw Exception('페이지 텍스트를 번역할 수 없습니다: $e');
    }
  }

  // 페이지 삭제
  Future<void> deletePage(String pageId) async {
    try {
      // 페이지 정보 가져오기
      final pageDoc = await _pagesCollection.doc(pageId).get();
      final data = pageDoc.data() as Map<String, dynamic>?;
      final imageUrl = data?['imageUrl'] as String?;

      // 이미지 삭제 (있는 경우)
      if (imageUrl != null && imageUrl.isNotEmpty) {
        await _imageService.deleteImage(imageUrl);
      }

      // 페이지 문서 삭제
      await _pagesCollection.doc(pageId).delete();

      // 캐시에서 페이지 제거
      _cacheService.removePage(pageId);
    } catch (e) {
      debugPrint('페이지 삭제 중 오류 발생: $e');
      throw Exception('페이지를 삭제할 수 없습니다: $e');
    }
  }

  // 노트의 모든 페이지 삭제
  Future<void> deleteAllPagesForNote(String noteId) async {
    try {
      final snapshot = await getPagesForNoteQuery(noteId).get();

      // 각 페이지 삭제
      for (final doc in snapshot.docs) {
        await deletePage(doc.id);
      }

      // 노트의 모든 페이지를 캐시에서 제거
      _cacheService.removePagesForNote(noteId);
    } catch (e) {
      debugPrint('노트의 모든 페이지 삭제 중 오류 발생: $e');
      throw Exception('페이지를 삭제할 수 없습니다: $e');
    }
  }

  // 캐시 정리 (오래된 항목 제거)
  void clearOldCache() {
    _cacheService.clearOldCache();
  }

  // 전체 캐시 초기화
  void clearCache() {
    _cacheService.clearCache();
  }
}
