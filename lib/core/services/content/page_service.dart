import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../models/page.dart' as page_model;
import '../../models/processed_text.dart';
import '../../models/text_segment.dart';
import '../media/image_service.dart';
import '../text_processing/enhanced_ocr_service.dart';
import '../storage/unified_cache_service.dart';
import '../../../LLM test/llm_text_processing.dart';
import 'dart:convert';
import 'dart:math';

/// 페이지 서비스: 페이지 관리 (CRUD) 기능을 제공합니다.
/// 
class PageService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImageService _imageService = ImageService();
  final EnhancedOcrService _ocrService = EnhancedOcrService();
  final UnifiedTextProcessingService _textProcessingService = UnifiedTextProcessingService();

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

  /// 페이지 번호가 연속되지 않은 경우 재정렬 및 Firestore 업데이트 함수
  Future<void> _updatePageNumber(String pageId, int newPageNumber) async {
    try {
      final updateTask = _pagesCollection.doc(pageId).update({'pageNumber': newPageNumber});
      await updateTask; // 명시적 작업 완료 대기
      debugPrint('페이지 번호 업데이트 완료: $pageId -> $newPageNumber');
    } catch (e) {
      debugPrint('페이지 번호 업데이트 중 오류: $e');
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
        
        // 페이지 번호 업데이트가 필요한 경우 Firestore도 업데이트 (별도 함수로 분리)
        if (updatedPage.id != null) {
          _updatePageNumber(updatedPage.id!, i);
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

  /// 페이지 업데이트
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
      }

      // 명시적으로 업데이트 작업 완료 대기
      final updateTask = _pagesCollection.doc(pageId).update(updates);
      await updateTask;

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
      // Firestore에 업데이트하고 명시적으로 작업 완료 대기
      final updateTask = _pagesCollection.doc(pageId).update({
        'originalText': originalText,
        'translatedText': translatedText,
        'updatedAt': DateTime.now(),
      });
      await updateTask;

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

  /// 페이지 텍스트 번역
  /* 
  // 현재 미사용: MVP에서는 사용되지 않는 단순 번역 메서드
  // 이 메서드는 세그먼트 분할, pinyin 생성 등을 제공하지 않고 단순 번역만 수행함
  // 실제 텍스트 처리는 EnhancedOcrService와 ContentManager를 통해 이루어짐
  Future<String> translatePageText(String pageId, {String? targetLanguage}) async {
    try {
      // 페이지 정보 가져오기
      final page = await getPageById(pageId);
      if (page == null) {
        throw Exception('페이지를 찾을 수 없습니다.');
      }

      // 원본 텍스트 번역 - LLM 처리 사용
      final chineseText = await _textProcessingService.processWithLLM(page.originalText);
      final translatedText = chineseText.sentences.map((s) => s.translation).join('\n');

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
  */

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
      // 페이지 문서 업데이트하고 명시적으로 작업 완료 대기
      final updateTask = _pagesCollection.doc(pageId).update({
        'imageUrl': imageUrl,
        'updatedAt': DateTime.now(),
      });
      await updateTask;
      
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

  /// LLM을 사용하여 이미지 처리 및 페이지 생성
  Future<Map<String, dynamic>> processImageAndCreatePageLLM(
    String noteId,
    File imageFile, {
    required int pageNumber,
    String? existingImageUrl,
  }) async {
    try {
      if (!await imageFile.exists()) {
        return {'success': false, 'error': '이미지 파일이 존재하지 않습니다'};
      }
      
      final imageUrl = existingImageUrl != null && existingImageUrl.isNotEmpty
          ? existingImageUrl
          : await _imageService.uploadAndGetUrl(imageFile);
      
      // 1. OCR
      final extractedText = await _ocrService.extractText(imageFile);
      
      // 2. LLM 처리
      final llmService = UnifiedTextProcessingService();
      final chineseText = await llmService.processWithLLM(extractedText);
      
      // 3. 페이지 생성
      final page = await createPage(
        noteId: noteId,
        pageNumber: pageNumber,
        imageUrl: imageUrl,
        originalText: chineseText.originalText,
        translatedText: chineseText.sentences.map((s) => s.translation).join('\n'),
      );
      
      // 4. 세그먼트 정보(ProcessedText) 캐싱
      final processedText = ProcessedText(
        fullOriginalText: chineseText.originalText,
        fullTranslatedText: chineseText.sentences.map((s) => s.translation).join('\n'),
        segments: chineseText.sentences.map((s) => TextSegment(
          originalText: s.original,
          translatedText: s.translation,
          pinyin: s.pinyin,
          sourceLanguage: 'zh-CN',
          targetLanguage: 'ko',
        )).toList(),
        showFullText: false,
        showPinyin: true,
        showTranslation: true,
      );
      
      await _cacheService.setProcessedText(page.id!, processedText);
      
      // 5. 첫 페이지라면 노트 정보 업데이트
      if (pageNumber == 1) {
        await updateNoteFirstPageInfo(
          noteId,
          imageUrl,
          chineseText.originalText,
          chineseText.sentences.map((s) => s.translation).join('\n'),
        );
      }
      
      return {
        'success': true,
        'imageUrl': imageUrl,
        'extractedText': chineseText.originalText,
        'translatedText': chineseText.sentences.map((s) => s.translation).join('\n'),
        'pageId': page.id,
      };
    } catch (e) {
      debugPrint('LLM 이미지 처리 및 페이지 생성 중 오류 발생: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// 첫 페이지 정보로 노트 업데이트
  Future<void> updateNoteFirstPageInfo(String noteId, String imageUrl, String extractedText, String translatedText) async {
    try {
      final noteDoc = await _firestore.collection('notes').doc(noteId).get();
      if (!noteDoc.exists) return;
      
      final Map<String, dynamic> data = noteDoc.data() as Map<String, dynamic>;
      final bool imageUrlNeedsUpdate = data['imageUrl'] == null || 
                                     data['imageUrl'] == '' || 
                                     data['imageUrl'] == 'images/fallback_image.jpg';
      
      // 필요한 필드만 선택적으로 업데이트
      final Map<String, dynamic> updateData = {
        'updatedAt': DateTime.now(),
      };
      
      if (extractedText != '___PROCESSING___') {
        updateData['extractedText'] = extractedText;
      }
      
      if (translatedText.isNotEmpty) {
        updateData['translatedText'] = translatedText;
      } else if (data['translatedText'] != null && data['translatedText'].isNotEmpty) {
        updateData['translatedText'] = data['translatedText'];
      }
      
      // 이미지 URL은 필요한 경우에만 업데이트
      if (imageUrlNeedsUpdate) {
        updateData['imageUrl'] = imageUrl;
        debugPrint('노트 썸네일 설정: $noteId -> $imageUrl');
      }
      
      // 변경할 내용이 있을 때만 Firestore 업데이트
      if (updateData.length > 1) { // 'updatedAt'만 있는 경우가 아닐 때
        final updateTask = _firestore.collection('notes').doc(noteId).update(updateData);
        await updateTask; // 명시적으로 작업 완료 대기
        await _cacheService.removeCachedNote(noteId); // 캐시 갱신을 위해 제거
      }
    } catch (e) {
      debugPrint('노트 첫 페이지 정보 업데이트 중 오류: $e');
    }
  }

  /// 기존 방식으로 이미지 처리 및 페이지 생성 (LLM 사용 안함)
  Future<Map<String, dynamic>> processImageAndCreatePageLegacy(
    String noteId,
    File imageFile, {
    required int pageNumber,
    String? existingImageUrl,
    bool shouldProcess = true,
  }) async {
    try {
      if (!await imageFile.exists()) {
        return {'success': false, 'error': '이미지 파일이 존재하지 않습니다'};
      }

      // 이미지 업로드 (기존 URL이 있으면 사용)
      final imageUrl = existingImageUrl != null && existingImageUrl.isNotEmpty
          ? existingImageUrl
          : await _imageService.uploadAndGetUrl(imageFile);

      // 페이지 생성
      late page_model.Page page;
      if (shouldProcess) {
        // 텍스트 처리가 필요한 경우
        final extractedText = await _ocrService.extractText(imageFile);
        
        // TranslationService 대신 LLM 처리 사용
        final chineseText = await _textProcessingService.processWithLLM(extractedText);
        final translatedText = chineseText.sentences.map((s) => s.translation).join('\n');

        page = await createPage(
          noteId: noteId,
          pageNumber: pageNumber,
          imageUrl: imageUrl,
          originalText: extractedText,
          translatedText: translatedText,
        );
      } else {
        // 처리 마커만 생성 (나중에 처리하기 위한 임시 상태)
        page = await createPage(
          noteId: noteId,
          pageNumber: pageNumber,
          imageUrl: imageUrl,
          originalText: '___PROCESSING___',  // 특수 마커
          translatedText: '',
        );
      }

      return {
        'success': true,
        'imageUrl': imageUrl,
        'extractedText': page.originalText,
        'translatedText': page.translatedText,
        'pageId': page.id,
      };
    } catch (e) {
      debugPrint('이미지 처리 및 페이지 생성 중 오류 발생: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// 실제 사용할 메서드 - 이미지만 즉시 처리하고 텍스트 처리는 백그라운드로 진행
  Future<Map<String, dynamic>> processImageAndCreatePage(
    String noteId,
    File imageFile, {
    required int pageNumber,
    String? existingImageUrl,
    bool useLLM = true, // LLM 사용 여부 (문제 생기면 false로 롤백)
    bool shouldProcess = true,
  }) async {
    try {
      if (!await imageFile.exists()) {
        return {'success': false, 'error': '이미지 파일이 존재하지 않습니다'};
      }
      
      // 1. 이미지 업로드 (기존 URL이 있으면 사용)
      final imageUrl = existingImageUrl != null && existingImageUrl.isNotEmpty
          ? existingImageUrl
          : await _imageService.uploadAndGetUrl(imageFile);
      
      // 2. 빈 페이지 또는 처리 중 마커로 페이지 생성 (즉시 반환 위함)
      final page = await createPage(
        noteId: noteId,
        pageNumber: pageNumber,
        imageUrl: imageUrl,
        originalText: '___PROCESSING___',  // 처리 중 마커
        translatedText: '',
      );
      
      // 3. 백그라운드에서 텍스트 처리 진행
      Future.microtask(() async {
        try {
          if (kDebugMode) {
            debugPrint('🔄 페이지 ${page.id}: 백그라운드에서 텍스트 처리 시작');
          }
          
          if (useLLM) {
            // LLM 방식으로 처리
            // OCR 처리
            final extractedText = await _ocrService.extractText(imageFile);
            
            // LLM 처리
            final llmService = UnifiedTextProcessingService();
            final chineseText = await llmService.processWithLLM(extractedText);
            
            // 처리된 텍스트로 페이지 업데이트
            final updatedPage = await updatePage(
              page.id!,
              originalText: chineseText.originalText,
              translatedText: chineseText.sentences.map((s) => s.translation).join('\n'),
            );
            
            // 세그먼트 정보 캐싱
            if (updatedPage != null) {
              final processedText = ProcessedText(
                fullOriginalText: chineseText.originalText,
                fullTranslatedText: chineseText.sentences.map((s) => s.translation).join('\n'),
                segments: chineseText.sentences.map((s) => TextSegment(
                  originalText: s.original,
                  translatedText: s.translation,
                  pinyin: s.pinyin,
                  sourceLanguage: 'zh-CN',
                  targetLanguage: 'ko',
                )).toList(),
                showFullText: false,
                showPinyin: true,
                showTranslation: true,
              );
              
              await _cacheService.setProcessedText(page.id!, processedText);
              
              // 첫 페이지면 노트 정보 업데이트
              if (pageNumber == 1) {
                await updateNoteFirstPageInfo(
                  noteId,
                  imageUrl,
                  chineseText.originalText,
                  chineseText.sentences.map((s) => s.translation).join('\n'),
                );
              }
            }
          } else {
            // 레거시 방식으로 처리 (TranslationService 대신 LLM 사용)
            final extractedText = await _ocrService.extractText(imageFile);
            
            // LLM을 사용하여 번역
            final chineseText = await _textProcessingService.processWithLLM(extractedText);
            final translatedText = chineseText.sentences.map((s) => s.translation).join('\n');
            
            await updatePage(
              page.id!,
              originalText: extractedText,
              translatedText: translatedText,
            );
            
            // 첫 페이지면 노트 정보 업데이트
            if (pageNumber == 1) {
              await updateNoteFirstPageInfo(
                noteId,
                imageUrl,
                extractedText,
                translatedText
              );
            }
          }
          
          if (kDebugMode) {
            debugPrint('✅ 페이지 ${page.id}: 백그라운드 텍스트 처리 완료');
          }
          
          // 처리 완료 이벤트 발생 - UI 수동 갱신을 위한 스트림 이벤트 추가
          _firestore.collection('pages').doc(page.id).update({
            'lastProcessedAt': FieldValue.serverTimestamp(),
            'processingStatus': 'completed',
          });
        } catch (e) {
          if (kDebugMode) {
            debugPrint('❌ 백그라운드 텍스트 처리 중 오류: $e');
          }
        }
      });
      
      // 4. 이미지 URL과 페이지 ID만 즉시 반환 (텍스트 처리 기다리지 않음)
      return {
        'success': true,
        'imageUrl': imageUrl,
        'extractedText': '___PROCESSING___',
        'translatedText': '',
        'pageId': page.id,
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 페이지 생성 중 오류: $e');
      }
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
}
