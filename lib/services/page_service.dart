import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/page.dart' as page_model;
import 'image_service.dart';
import 'ocr_service.dart';
import 'translation_service.dart';

class PageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImageService _imageService = ImageService();
  final OcrService _ocrService = OcrService();
  final TranslationService _translationService = TranslationService();

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
      return page_model.Page(
        id: pageRef.id,
        originalText: originalText,
        translatedText: translatedText,
        pageNumber: pageNumber,
        imageUrl: imageUrl,
        createdAt: now,
        updatedAt: now,
      );
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

  // 페이지 가져오기
  Future<page_model.Page?> getPageById(String pageId) async {
    try {
      final doc = await _pagesCollection.doc(pageId).get();
      if (!doc.exists) {
        return null;
      }
      return page_model.Page.fromFirestore(doc);
    } catch (e) {
      debugPrint('페이지 조회 중 오류 발생: $e');
      throw Exception('페이지를 조회할 수 없습니다: $e');
    }
  }

  // 노트의 모든 페이지 가져오기
  Future<List<page_model.Page>> getPagesForNote(String noteId) async {
    try {
      final snapshot = await getPagesForNoteQuery(noteId).get();
      return snapshot.docs
          .map((doc) => page_model.Page.fromFirestore(
              doc as DocumentSnapshot<Map<String, dynamic>>))
          .toList();
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
    } catch (e) {
      debugPrint('노트의 모든 페이지 삭제 중 오류 발생: $e');
      throw Exception('페이지를 삭제할 수 없습니다: $e');
    }
  }
}
