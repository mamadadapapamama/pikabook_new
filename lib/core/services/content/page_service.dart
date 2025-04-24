import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../models/page.dart' as page_model;
import '../../models/processed_text.dart';
import '../media/image_service.dart';
import '../storage/unified_cache_service.dart';
import 'dart:convert';

/// 페이지 서비스: 페이지 관리 (CRUD) 기능을 제공합니다.
/// 
class PageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImageService _imageService = ImageService();
  // 아래 서비스 의존성 제거
  // final EnhancedOcrService _ocrService = EnhancedOcrService();
  // final TranslationService _translationService = TranslationService();
  // final UnifiedCacheService _cacheService = UnifiedCacheService();

  // UnifiedCacheService 직접 사용 대신 getter 또는 메서드로 접근 고려
  UnifiedCacheService get _cacheService => UnifiedCacheService();

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

  /// 페이지 생성 (단순 버전)
  Future<page_model.Page> createPage({
    required String noteId,
    required String originalText,
    required String translatedText,
    required int pageNumber,
    File? imageFile,
    String? imageUrl, // 이미지 URL도 받을 수 있도록 추가
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('로그인이 필요합니다.');

      String? finalImageUrl = imageUrl;
      if (imageFile != null && finalImageUrl == null) {
        finalImageUrl = await _imageService.uploadImage(imageFile);
      }

      final now = DateTime.now();
      final pageData = page_model.Page(
        originalText: originalText,
        translatedText: translatedText,
        pageNumber: pageNumber,
        imageUrl: finalImageUrl,
        createdAt: now,
        updatedAt: now,
      );

      final pageRef = await _pagesCollection.add({
        ...pageData.toFirestore(),
        'userId': user.uid,
        'noteId': noteId,
      });

      final newPage = page_model.Page(
        id: pageRef.id,
        originalText: originalText,
        translatedText: translatedText,
        pageNumber: pageNumber,
        imageUrl: finalImageUrl,
        createdAt: now,
        updatedAt: now,
      );

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
      return null; // 오류 발생 시 null 반환하여 호출부에서 처리하도록 함
    }
  }

  /// 노트의 모든 페이지 가져오기 (캐시 활용)
  Future<List<page_model.Page>> getPagesForNote(String noteId, {bool forceReload = false}) async {
    try {
      debugPrint('📄 getPagesForNote 호출: noteId=$noteId, forceReload=$forceReload');
      
      // 1. forceReload가 true인 경우 서버에서만 로드
      if (forceReload) {
        debugPrint('🔄 강제 로드 모드: 캐시를 완전히 건너뛰고 서버에서 직접 로드합니다.');
        
        // Firestore에서 페이지 가져오기
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
        
        // 서버에서 가져온 페이지로 캐시 업데이트 (백그라운드로 처리)
        Future.microtask(() async {
          try {
            await _cacheService.cachePages(noteId, serverPages);
            debugPrint('✅ 백그라운드에서 서버 데이터로 캐시 업데이트 완료');
          } catch (e) {
            debugPrint('⚠️ 백그라운드 캐시 업데이트 중 오류 (무시됨): $e');
          }
        });
        
        return serverPages;
      }
      
      // 2. 일반 모드: 캐시에서 먼저 페이지 확인
      List<page_model.Page> cachedPages = [];
      cachedPages = await _cacheService.getPagesForNote(noteId);
      
      if (cachedPages.isNotEmpty) {
        debugPrint('✅ 캐시에서 노트 $noteId의 페이지 ${cachedPages.length}개 로드됨');
        
        // 서버와 동기화는 백그라운드에서 진행 (UI를 막지 않기 위해)
        Future.microtask(() async {
          try {
            await _syncPagesWithServer(noteId, cachedPages);
          } catch (e) {
            debugPrint('⚠️ 백그라운드 페이지 동기화 중 오류 (무시됨): $e');
          }
        });
        
        return cachedPages;
      }
      
      // 3. 캐시에 없는 경우 서버에서 페이지 로드
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
      
      // 오류 발생 시 빈 배열 반환
      return [];
    }
  }
  
  /// 서버와 페이지 동기화 (백그라운드 작업용)
  Future<void> _syncPagesWithServer(String noteId, List<page_model.Page> cachedPages) async {
    try {
      debugPrint('🔄 서버와 페이지 동기화 시작: noteId=$noteId');
      
      // 서버에서 페이지 가져오기
      final snapshot = await _pagesCollection
        .where('noteId', isEqualTo: noteId)
        .orderBy('pageNumber')
        .get();
      
      final serverPages = snapshot.docs
        .map((doc) => page_model.Page.fromFirestore(doc))
        .toList();
      
      // 서버와 캐시 페이지 병합
      final mergedPages = _mergePages(cachedPages, serverPages);
      
      // 변경사항이 있는 경우에만 캐시 업데이트
      if (mergedPages.length != cachedPages.length) {
        await _cacheService.cachePages(noteId, mergedPages);
        debugPrint('✅ 서버와 동기화 후 캐시 업데이트 완료 (페이지 수 변경: ${cachedPages.length} → ${mergedPages.length})');
      }
    } catch (e) {
      debugPrint('⚠️ 서버와 페이지 동기화 중 오류: $e');
      // 오류는 무시하고 캐시된 데이터 사용 유지
    }
  }

  /// 캐시와 서버에서 가져온 페이지 병합
  List<page_model.Page> _mergePages(List<page_model.Page> cachedPages, List<page_model.Page> serverPages) {
    // ID 기준으로 페이지 맵 생성 
    final Map<String, page_model.Page> mergedPagesMap = {};
    
    // 캐시된 페이지 먼저 추가 
    for (final page in cachedPages) {
      if (page.id != null) {
        mergedPagesMap[page.id!] = page;
      }
    }
    
    // 서버 페이지 추가 (동일 ID는 서버 버전으로 업데이트)
    for (final page in serverPages) {
      if (page.id != null) {
        mergedPagesMap[page.id!] = page;
      }
    }
    
    // 맵을 리스트로 변환하고 페이지 번호로 정렬
    final mergedPages = mergedPagesMap.values.toList()
      ..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    
    // 페이지 번호가 연속되지 않은 경우 재정렬
    for (int i = 0; i < mergedPages.length; i++) {
      if (mergedPages[i].pageNumber != i) {
        final updatedPage = mergedPages[i].copyWith(pageNumber: i);
        mergedPages[i] = updatedPage;
        
        // 페이지 번호 업데이트가 필요한 경우 Firestore도 업데이트
        if (updatedPage.id != null) {
          _pagesCollection.doc(updatedPage.id).update({'pageNumber': i});
        }
      }
    }
    
    debugPrint('페이지 병합 결과: 로컬=${cachedPages.length}개, 서버=${serverPages.length}개, 병합 후=${mergedPages.length}개');
    
    // 결과가 비어있으면 서버 페이지만 반환
    if (mergedPages.isEmpty && serverPages.isNotEmpty) {
      return serverPages;
    }
    
    return mergedPages;
  }

  /// 페이지 업데이트 (단순 버전)
  Future<page_model.Page?> updatePage(
    String pageId, {
    String? originalText,
    String? translatedText,
    int? pageNumber,
    File? imageFile,
    String? imageUrl, // 이미지 URL 직접 업데이트 지원
  }) async {
    try {
      final pageDoc = await _pagesCollection.doc(pageId).get();
      if (!pageDoc.exists) throw Exception('페이지를 찾을 수 없습니다.');

      final data = pageDoc.data() as Map<String, dynamic>?;
      final noteId = data?['noteId'] as String?;
      final existingImageUrl = data?['imageUrl'] as String?;

      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (originalText != null) updates['originalText'] = originalText;
      if (translatedText != null) updates['translatedText'] = translatedText;
      if (pageNumber != null) updates['pageNumber'] = pageNumber;
      if (imageUrl != null) updates['imageUrl'] = imageUrl; // 직접 URL 업데이트

      // 이미지 파일이 제공된 경우 업로드 및 URL 업데이트
      if (imageFile != null) {
        if (existingImageUrl != null && existingImageUrl.isNotEmpty) {
          await _imageService.deleteImage(existingImageUrl).catchError((e) => print("기존 이미지 삭제 오류(무시): $e"));
        }
        final newImageUrl = await _imageService.uploadImage(imageFile);
        updates['imageUrl'] = newImageUrl;
        // OCR/번역 로직 제거
      }

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

  /// 빈 페이지 구조만 생성 (내용 없음)
  Future<page_model.Page?> createEmptyPage({
    required String noteId,
    required int pageNumber,
    String? imageUrl,
  }) async {
    try {
      // 사용자 확인
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다.');
      }

      // 빈 페이지 데이터 생성
      final now = DateTime.now();
      final pageData = page_model.Page(
        originalText: '',
        translatedText: '',
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
        originalText: '',
        translatedText: '',
        pageNumber: pageNumber,
        imageUrl: imageUrl,
        createdAt: now,
        updatedAt: now,
      );

      // 캐시에 새 페이지 저장
      await _cacheService.cachePage(noteId, newPage);

      debugPrint('빈 페이지 구조 생성 완료: ID=${pageRef.id}, 페이지 번호=$pageNumber, 이미지 URL=${imageUrl != null}');
      return newPage;
    } catch (e) {
      debugPrint('빈 페이지 구조 생성 중 오류 발생: $e');
      return null;
    }
  }

  /// 페이지 내용 업데이트
  Future<page_model.Page?> updatePageContent(
      String pageId, String originalText, String translatedText) async {
    try {
      // Firestore에 업데이트
      await _pagesCollection.doc(pageId).update({
        'originalText': originalText,
        'translatedText': translatedText,
        'updatedAt': DateTime.now(),
      });

      // 업데이트된 페이지 객체 반환
      final pageDoc = await _pagesCollection.doc(pageId).get();
      if (pageDoc.exists) {
        final updatedPage = page_model.Page.fromFirestore(pageDoc);

        // 노트 ID 확인
        final data = pageDoc.data() as Map<String, dynamic>?;
        final noteId = data?['noteId'] as String?;

        // 노트 ID가 있으면 페이지 객체 캐싱
        if (noteId != null && updatedPage.id != null) {
          await _cacheService.cachePage(noteId, updatedPage);
          
          // 캐시 텍스트 저장
          await _cacheService.cacheText('page_original', pageId, originalText);
          await _cacheService.cacheText('page_translated', pageId, translatedText);
          
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



  /// 개별 페이지 삭제 - MVP 이후 UI 제공 예정
  Future<void> deletePage(String pageId) async {
    // Implementation needed
  }

  /// 노트의 모든 페이지 삭제
  Future<void> deleteAllPagesForNote(String noteId) async {
    try {
      final snapshot = await getPagesForNoteQuery(noteId).get();

      // 각 페이지 삭제
      for (final doc in snapshot.docs) {
        await deletePage(doc.id);
      }

      // 노트의 모든 페이지를 캐시에서 제거
      await _cacheService.removePagesForNote(noteId);
    } catch (e) {
      debugPrint('노트의 모든 페이지 삭제 중 오류 발생: $e');
      throw Exception('페이지를 삭제할 수 없습니다: $e');
    }
  }

  /// 전체 캐시 초기화
  void clearCache() {
    _cacheService.clearCache();
  }

  /// 처리된 텍스트 캐싱
  Future<void> cacheProcessedText(
    String pageId,
    dynamic processedText,
    String textProcessingMode,
  ) async {
    try {
      await _cacheService.cacheProcessedText(
        pageId,
        textProcessingMode,
        processedText,
      );
      debugPrint('처리된 텍스트 캐싱 완료: 페이지 ID=$pageId, 모드=$textProcessingMode');
    } catch (e) {
      debugPrint('처리된 텍스트 캐싱 중 오류 발생: $e');
    }
  }

  /// 캐시된 처리 텍스트 가져오기
  Future<dynamic> getCachedProcessedText(
    String pageId,
    String textProcessingMode,
  ) async {
    try {
      final cachedData = await _cacheService.getCachedProcessedText(
        pageId,
        textProcessingMode,
      );
      
      if (cachedData != null) {
        // JSON 맵인 경우 ProcessedText 객체로 변환
        if (cachedData is Map<String, dynamic>) {
          try {
            return ProcessedText.fromJson(cachedData);
          } catch (e) {
            debugPrint('캐시된 데이터에서 ProcessedText 변환 중 오류: $e');
            return null;
          }
        } else if (cachedData is String) {
          // 문자열인 경우 JSON으로 파싱 시도
          try {
            final Map<String, dynamic> jsonData = jsonDecode(cachedData);
            return ProcessedText.fromJson(jsonData);
          } catch (e) {
            debugPrint('캐시된 문자열 파싱 중 오류: $e');
            return null;
          }
        }
        
        // 이미 ProcessedText 객체인 경우
        if (cachedData is ProcessedText) {
          return cachedData;
        }
      }
      return null;
    } catch (e) {
      debugPrint('캐시된 처리 텍스트 조회 중 오류 발생: $e');
      return null;
    }
  }

  /// 페이지 이미지 URL 업데이트
  Future<bool> updatePageImageUrl(String pageId, String imageUrl) async {
    try {
      // 페이지 문서 업데이트
      await _pagesCollection.doc(pageId).update({
        'imageUrl': imageUrl,
        'updatedAt': DateTime.now(),
      });
      
      // 업데이트된 페이지 가져오기
      final pageDoc = await _pagesCollection.doc(pageId).get();
      if (pageDoc.exists) {
        final data = pageDoc.data() as Map<String, dynamic>?;
        final noteId = data?['noteId'] as String?;
        
        if (noteId != null) {
          // 업데이트된 페이지 객체 캐시에 저장
          final updatedPage = page_model.Page.fromFirestore(pageDoc);
          await _cacheService.cachePage(noteId, updatedPage);
          debugPrint('페이지 이미지 URL 업데이트 및 캐시 갱신 완료: $pageId');
        }
      }
      
      return true;
    } catch (e) {
      debugPrint('페이지 이미지 URL 업데이트 중 오류 발생: $e');
      return false;
    }
  }
}
