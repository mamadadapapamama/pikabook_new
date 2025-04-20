import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/note.dart';
import '../models/page.dart' as page_model;
import '../models/flash_card.dart';
import 'page_service.dart';
import 'image_service.dart';
import 'translation_service.dart';
import 'unified_cache_service.dart';
import 'enhanced_ocr_service.dart';
import 'usage_limit_service.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';

/// 노트 서비스: 노트 관리, 생성, 처리, 캐싱 로직을 담당합니다.
/// 
class NoteService {
  // 서비스 인스턴스
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PageService _pageService = PageService();
  final ImageService _imageService = ImageService();
  final TranslationService _translationService = TranslationService();
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  final EnhancedOcrService _ocrService = EnhancedOcrService();
  final UsageLimitService _usageLimitService = UsageLimitService();

  // 컬렉션 참조
  CollectionReference get _notesCollection => _firestore.collection('notes');

  // 현재 사용자의 노트 컬렉션 참조
  Query get _userNotesQuery => _notesCollection
      .where('userId', isEqualTo: _auth.currentUser?.uid)
      .orderBy('createdAt', descending: true);

  /// 페이징된 노트 목록 가져오기
  Stream<List<Note>> getPagedNotes({int limit = 10}) {
    try {
      return _userNotesQuery.limit(limit).snapshots().map((snapshot) {
        final notes = snapshot.docs.map((doc) => Note.fromFirestore(doc)).toList();
        debugPrint('페이징된 노트 목록 수신: ${notes.length}개');
        return notes;
      });
    } catch (e) {
      debugPrint('페이징된 노트 목록을 가져오는 중 오류 발생: $e');
      return Stream.value([]);
    }
  }

  /// 추가 노트 가져오기 (페이징)
  Future<List<Note>> getMoreNotes({Note? lastNote, int limit = 10}) async {
    try {
      Query query = _userNotesQuery;

      // 마지막 노트가 있으면 해당 노트 이후부터 쿼리
      if (lastNote != null && lastNote.createdAt != null) {
        query = query.startAfter([lastNote.createdAt]);
      }

      // 제한된 수의 노트 가져오기
      final snapshot = await query.limit(limit).get();
      return snapshot.docs.map((doc) => Note.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('추가 노트를 가져오는 중 오류 발생: $e');
      return [];
    }
  }

  /// 모든 노트 목록 가져오기 (스트림)
  Stream<List<Note>> getNotes() {
    try {
      return _userNotesQuery.snapshots().map((snapshot) {
        final notes = snapshot.docs.map((doc) => Note.fromFirestore(doc)).toList();
        return notes;
      });
    } catch (e) {
      debugPrint('노트 목록을 가져오는 중 오류가 발생했습니다: $e');
      return Stream.value([]);
    }
  }

  /// 캐시된 노트 목록 가져오기
  Future<List<Note>> getCachedNotes() async {
    try {
      return await _cacheService.getCachedNotes();
    } catch (e) {
      debugPrint('캐시된 노트를 가져오는 중 오류 발생: $e');
      return [];
    }
  }

  /// 노트 목록 캐싱
  Future<void> cacheNotes(List<Note> notes) async {
    try {
      await _cacheService.cacheNotes(notes);
    } catch (e) {
      debugPrint('노트 캐싱 중 오류 발생: $e');
    }
  }

  /// 캐시 초기화
  Future<void> clearCache() async {
    try {
      // UnifiedCacheService를 통해 캐시 초기화
      _cacheService.clearCache();
      
      // 백그라운드 처리 상태 초기화
      await _cleanupStaleBackgroundProcessingState();
      
      debugPrint('노트 서비스 캐시 초기화 완료');
    } catch (e) {
      debugPrint('노트 캐시 초기화 중 오류 발생: $e');
    }
  }

  /// 캐시 정리 (메모리 최적화)
  Future<void> cleanupCache() async {
    try {
      // 캐시 서비스를 통해 정리
      await _cacheService.cleanupOldCache();
      
      // 백그라운드 처리 상태 초기화
      await _cleanupStaleBackgroundProcessingState();
      
      // 이미지 캐시도 정리 시도
      await _imageService.clearImageCache();
      
      debugPrint('노트 서비스 캐시 정리 완료');
    } catch (e) {
      debugPrint('노트 캐시 정리 중 오류 발생: $e');
    }
  }
  
  /// 멈춘 백그라운드 프로세싱 상태 정리
  Future<void> _cleanupStaleBackgroundProcessingState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // SharedPreferences의 모든 키 가져오기
      final allKeys = prefs.getKeys();
      
      // 백그라운드 처리 관련 키 찾기
      final staleProcessingKeys = <String>[];
      
      for (var key in allKeys) {
        // 백그라운드 처리 상태 키 찾기
        if (key.startsWith('processing_note_') || 
            key.startsWith('pages_updated_') || 
            key.startsWith('updated_page_count_') ||
            key.startsWith('first_page_processed_')) {
          staleProcessingKeys.add(key);
        }
      }
      
      // 오래된 키 삭제
      for (var key in staleProcessingKeys) {
        await prefs.remove(key);
      }
      
      if (staleProcessingKeys.isNotEmpty) {
        debugPrint('${staleProcessingKeys.length}개의 멈춘 백그라운드 처리 상태를 정리했습니다.');
      }
    } catch (e) {
      debugPrint('백그라운드 처리 상태 정리 중 오류: $e');
    }
  }

  /// 특정 노트 가져오기
  Future<Note?> getNoteById(String noteId) async {
    try {
      // 1. 캐시에서 노트 찾기 시도
      final cachedNote = await _cacheService.getCachedNote(noteId);
      if (cachedNote != null) {
        debugPrint('캐시에서 노트 $noteId 로드됨');
        return cachedNote;
      }
      
      // 2. Firestore에서 노트 가져오기
      final docSnapshot = await _notesCollection.doc(noteId).get();
      if (!docSnapshot.exists) {
        return null;
      }
      
      // 3. 노트 객체 생성 및 캐시에 저장
      final note = Note.fromFirestore(docSnapshot);
      if (note.id != null) {
        await _cacheService.cacheNote(note);
        debugPrint('Firestore에서 노트 $noteId 로드 완료 및 캐시에 저장됨');
      }
      
      return note;
    } catch (e) {
      debugPrint('노트를 가져오는 중 오류가 발생했습니다: $e');
      return null;
    }
  }

  /// 노트 생성
  Future<Note> createNote(String title, File? imageFile) async {
    try {
      // 현재 사용자 확인
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다.');
      }

      // 기본 노트 데이터 생성
      final now = DateTime.now();
      final noteData = {
        'userId': user.uid,
        'originalText': title,
        'translatedText': '',
        'isFavorite': false,
        'flashcardCount': 0,
        'flashCards': [],
        'createdAt': now,
        'updatedAt': now,
      };

      // Firestore에 노트 추가
      final docRef = await _notesCollection.add(noteData);
      final noteId = docRef.id;

      // 이미지가 있으면 처리
      if (imageFile != null) {
        await _processImageAndCreatePage(noteId, imageFile);
      }

      // 생성된 노트 가져오기
      final docSnapshot = await docRef.get();
      final note = Note.fromFirestore(docSnapshot);

      // 노트 캐싱
      await _cacheService.cacheNote(note);

      return note;
    } catch (e) {
      debugPrint('노트 생성 중 오류 발생: $e');
      rethrow;
    }
  }

  /// 노트 업데이트
  Future<void> updateNote(String noteId, Note updatedNote) async {
    try {
      // 업데이트할 필드 설정 (flashCards는 제외하고 처리)
      final Map<String, dynamic> updateData = {
        'originalText': updatedNote.originalText,
        'translatedText': updatedNote.translatedText,
        'isFavorite': updatedNote.isFavorite,
        'flashcardCount': updatedNote.flashcardCount,
        'updatedAt': DateTime.now(),
      };

      // 플래시카드가 있는 경우에만 추가 (객체 형식이 아닌 JSON 형식으로 저장)
      if (updatedNote.flashCards.isNotEmpty) {
        updateData['flashCards'] = updatedNote.flashCards.map((card) => card.toJson()).toList();
      }

      // Firestore에 업데이트
      await _notesCollection.doc(noteId).update(updateData);

      // 캐시 업데이트
      await _cacheService.cacheNote(updatedNote);
      
      debugPrint('노트 업데이트 완료: $noteId, 제목: ${updatedNote.originalText}, 플래시카드: ${updatedNote.flashCards.length}개');
    } catch (e) {
      debugPrint('노트 업데이트 중 오류 발생: $e');
      rethrow;
    }
  }

  /// 노트 삭제
  Future<void> deleteNote(String noteId) async {
    try {
      // 페이지 개수 확인 후 사용량 감소
      final pages = await _pageService.getPagesForNote(noteId);
      final pageCount = pages.length;
      
      // 노트에 연결된 페이지 삭제
      await _pageService.deleteAllPagesForNote(noteId);

      // Firestore에서 노트 삭제
      await _notesCollection.doc(noteId).delete();

      // 캐시에서 노트 삭제
      await _cacheService.removeCachedNote(noteId);
      
      // 페이지 카운트 감소
      if (pageCount > 0) {
        // 페이지 수만큼 반복하여 카운트 감소
        for (int i = 0; i < pageCount; i++) {
          await _usageLimitService.decrementPageCount();
        }
      }
    } catch (e) {
      debugPrint('노트 삭제 중 오류 발생: $e');
      rethrow;
    }
  }

  /// 즐겨찾기 토글
  Future<void> toggleFavorite(String noteId, bool isFavorite) async {
    try {
      await _notesCollection.doc(noteId).update({
        'isFavorite': isFavorite,
        'updatedAt': DateTime.now(),
      });

      // 캐시된 노트 업데이트
      final cachedNote = await _cacheService.getCachedNote(noteId);
      if (cachedNote != null) {
        final updatedNote = cachedNote.copyWith(isFavorite: isFavorite);
        await _cacheService.cacheNote(updatedNote);
      }
    } catch (e) {
      debugPrint('즐겨찾기 토글 중 오류 발생: $e');
      rethrow;
    }
  }

  /// 노트와 페이지를 함께 가져오기 (캐싱 활용)
  Future<Map<String, dynamic>> getNoteWithPages(String noteId, {bool forceReload = false}) async {
    try {
      Note? note;
      List<page_model.Page> pages = [];
      bool isFromCache = false;
      bool isProcessing = false;

      // 1. 통합 캐시 서비스에서 노트와 페이지 가져오기 (forceReload가 아닌 경우)
      if (!forceReload) {
        final cacheResult = await _cacheService.getNoteWithPages(noteId);
        note = cacheResult['note'] as Note?;
        pages = (cacheResult['pages'] as List<dynamic>).cast<page_model.Page>();
        isFromCache = cacheResult['isFromCache'] as bool;
        
        if (note != null) {
          debugPrint('캐시에서 노트와 ${pages.length}개 페이지 로드: $noteId');
        }
      }

      // 2. 캐시에 노트가 없으면 Firestore에서 가져오기
      if (note == null) {
        final docSnapshot = await _notesCollection.doc(noteId).get();
        if (docSnapshot.exists) {
          note = Note.fromFirestore(docSnapshot);
          // 노트 캐싱
          await _cacheService.cacheNote(note);
          debugPrint('Firestore에서 노트 로드 및 캐싱: $noteId');
        } else {
          throw Exception('노트를 찾을 수 없습니다.');
        }
      }

      // 3. 백그라운드 처리 상태 확인
      isProcessing = await _checkBackgroundProcessingStatus(noteId);

      // 4. 캐시에 페이지가 없거나 강제 새로고침이면 Firestore에서 가져오기
      if (pages.isEmpty || forceReload) {
        debugPrint('Firestore에서 노트 $noteId의 페이지 로드 시작');
        pages = await _pageService.getPagesForNote(noteId, forceReload: forceReload);

        // 페이지 캐싱
        if (pages.isNotEmpty) {
          await _cacheService.cachePages(noteId, pages);
          debugPrint('노트 $noteId의 페이지 ${pages.length}개 캐싱 완료');
        }
      }

      // 5. 이미지 미리 로드 (백그라운드에서 처리)
      if (pages.isNotEmpty) {
        _preloadImagesInBackground(pages);
      }

      return {
        'note': note,
        'pages': pages,
        'isFromCache': isFromCache,
        'isProcessingBackground': isProcessing,
      };
    } catch (e) {
      debugPrint('노트와 페이지를 가져오는 중 오류 발생: $e');
      rethrow;
    }
  }

  /// 백그라운드 처리 상태 확인
  Future<bool> _checkBackgroundProcessingStatus(String noteId) async {
    try {
      // 1. 메모리 & 로컬 저장소 먼저 확인 (더 빠름)
      final prefs = await SharedPreferences.getInstance();
      final key = 'processing_note_$noteId';
      final localProcessing = prefs.getBool(key) ?? false;
      
      if (localProcessing) {
        return true;
      }
      
      // 2. Firestore에서 상태 확인
      final docSnapshot = await _notesCollection.doc(noteId).get();
      if (docSnapshot.exists) {
        final data = docSnapshot.data() as Map<String, dynamic>?;
        final isProcessing = data?['isProcessingBackground'] as bool? ?? false;
        final isCompleted = data?['processingCompleted'] as bool? ?? false;
        
        // 처리 중이면서 완료되지 않은 경우에만 true
        return isProcessing && !isCompleted;
      }
      
      return false;
    } catch (e) {
      debugPrint('백그라운드 처리 상태 확인 중 오류 발생: $e');
      return false;
    }
  }

  /// 백그라운드 처리 상태 설정
  Future<void> _setBackgroundProcessingState(String noteId, bool isProcessing) async {
    try {
      // 1. SharedPreferences에 상태 저장 (로컬 UI 업데이트용)
      final prefs = await SharedPreferences.getInstance();
      final key = 'processing_note_$noteId';
      await prefs.setBool(key, isProcessing);

      // 2. Firestore 노트 문서에도 상태 저장 (영구적)
      await _notesCollection.doc(noteId).update({
        'isProcessingBackground': isProcessing,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('백그라운드 처리 상태 설정: $noteId, 처리 중: $isProcessing');
    } catch (e) {
      debugPrint('백그라운드 처리 상태 설정 중 오류 발생: $e');
    }
  }

  /// 이미지 미리 로드 (백그라운드)
  void _preloadImagesInBackground(List<page_model.Page> pages) {
    Future.microtask(() async {
      try {
        int loadedCount = 0;
        for (final page in pages) {
          if (page.imageUrl != null && page.imageUrl!.isNotEmpty) {
            await _imageService.getImageBytes(page.imageUrl);
            loadedCount++;
          }
        }
        debugPrint('$loadedCount/${pages.length}개 페이지의 이미지 미리 로드 완료');
      } catch (e) {
        debugPrint('이미지 미리 로드 중 오류: $e');
      }
    });
  }
  
  /// 이미지 처리 및 페이지 생성
  Future<Map<String, dynamic>> _processImageAndCreatePage(
    String noteId, 
    File imageFile, 
    {int pageNumber = 1, String? pageId, String? targetLanguage, bool shouldProcess = true, bool skipOcrUsageCount = false}
  ) async {
    try {
      // 1. 이미지 업로드
      String imageUrl = '';
      try {
        imageUrl = await _imageService.uploadImage(imageFile);
        if (imageUrl.isEmpty) {
          debugPrint('이미지 업로드 결과가 비어있습니다 - 기본 경로 사용');
          imageUrl = 'images/fallback_image.jpg';
        }
      } catch (uploadError) {
        debugPrint('이미지 업로드 중 오류: $uploadError - 기본 경로 사용');
        imageUrl = 'images/fallback_image.jpg';
      }

      // 2. OCR 및 번역 처리
      String extractedText = '';
      String translatedText = '';
      
      if (shouldProcess) {
        // OCR로 텍스트 추출
        extractedText = await _ocrService.extractText(imageFile, skipUsageCount: skipOcrUsageCount);
        
        // 텍스트 번역
        if (extractedText.isNotEmpty) {
          translatedText = await _translationService.translateText(
            extractedText,
            targetLanguage: targetLanguage ?? 'ko',
          );
        }
      } else {
        // 처리하지 않는 경우 특수 마커 사용
        extractedText = '___PROCESSING___';
        translatedText = '';
      }

      // 3. 페이지 생성
      final page = await _pageService.createPage(
        noteId: noteId,
        originalText: extractedText,
        translatedText: translatedText,
        pageNumber: pageNumber,
        imageFile: imageFile,
      );

      // 4. 첫 페이지인 경우 노트 썸네일 업데이트
      if (pageNumber == 1) {
        await _updateNoteFirstPageInfo(noteId, imageUrl, extractedText, translatedText);
      }

      // 5. 결과 반환
      return {
        'success': true,
        'imageUrl': imageUrl,
        'extractedText': extractedText,
        'translatedText': translatedText,
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
  
  /// 첫 페이지 정보로 노트 업데이트
  Future<void> _updateNoteFirstPageInfo(String noteId, String imageUrl, String extractedText, String translatedText) async {
    try {
      final noteDoc = await _notesCollection.doc(noteId).get();
      if (!noteDoc.exists) return;
      
      final note = Note.fromFirestore(noteDoc);
      final bool imageUrlNeedsUpdate = note.imageUrl == null || note.imageUrl!.isEmpty || note.imageUrl == 'images/fallback_image.jpg';
      
      // 필요한 필드만 선택적으로 업데이트
      final Map<String, dynamic> updateData = {
        'updatedAt': DateTime.now(),
      };
      
      if (extractedText != '___PROCESSING___') {
        updateData['extractedText'] = extractedText;
      }
      
      if (translatedText.isNotEmpty) {
        updateData['translatedText'] = translatedText;
      } else if (note.translatedText.isNotEmpty) {
        updateData['translatedText'] = note.translatedText;
      }
      
      // 이미지 URL은 필요한 경우에만 업데이트
      if (imageUrlNeedsUpdate) {
        updateData['imageUrl'] = imageUrl;
        debugPrint('노트 썸네일 설정: $noteId -> $imageUrl');
      }
      
      // 변경할 내용이 있을 때만 Firestore 업데이트
      if (updateData.length > 1) { // 'updatedAt'만 있는 경우가 아닐 때
        await _notesCollection.doc(noteId).update(updateData);
        await _cacheService.removeCachedNote(noteId); // 캐시 갱신을 위해 제거
      }
    } catch (e) {
      debugPrint('노트 첫 페이지 정보 업데이트 중 오류: $e');
    }
  }

  // 여러 이미지로 노트 생성 (ImagePickerBottomSheet에서 사용)
  Future<Map<String, dynamic>> createNoteWithMultipleImages({
    required List<File> imageFiles,
    bool waitForFirstPageProcessing = false,
  }) async {
    try {
      if (imageFiles.isEmpty) {
        return {
          'success': false,
          'message': '이미지 파일이 없습니다',
        };
      }

      // 현재 사용자 확인
      final user = _auth.currentUser;
      if (user == null) {
        return {
          'success': false,
          'message': '로그인이 필요합니다',
        };
      }

      // 기본 노트 데이터 생성 (첫 번째 이미지 기준)
      final now = DateTime.now();
      final noteData = {
        'userId': user.uid,
        'originalText': '새 노트', // 기본 제목 설정
        'translatedText': '',
        'isFavorite': false,
        'flashcardCount': 0,
        'imageCount': imageFiles.length, // 이미지 개수 설정
        'flashCards': [],
        'createdAt': now,
        'updatedAt': now,
        'isProcessingBackground': true, // 백그라운드 처리 상태 설정
      };

      // Firestore에 노트 추가
      final docRef = await _notesCollection.add(noteData);
      final noteId = docRef.id;
      
      // 첫 번째 이미지 즉시 처리 (나머지는 백그라운드에서)
      if (imageFiles.isNotEmpty) {
        // 첫 번째 이미지는 동기적으로 처리
        await _processImageAndCreatePage(
          noteId, 
          imageFiles[0],
          shouldProcess: waitForFirstPageProcessing,
        );
        
        // 2번째 이미지부터는 백그라운드에서 처리
        if (imageFiles.length > 1) {
          _processRemainingImagesInBackground(noteId, imageFiles.sublist(1));
        }
      }

      return {
        'success': true,
        'noteId': noteId,
        'imageCount': imageFiles.length,
      };
    } catch (e) {
      debugPrint('여러 이미지로 노트 생성 중 오류 발생: $e');
      return {
        'success': false,
        'message': '노트 생성 중 오류가 발생했습니다: $e',
      };
    }
  }
  
  // 나머지 이미지 백그라운드 처리
  Future<void> _processRemainingImagesInBackground(String noteId, List<File> imageFiles) async {
    // 백그라운드 처리 상태 설정
    await _setBackgroundProcessingState(noteId, true);
    
    try {
      // 각 이미지에 대해 순차적으로 페이지 생성
      for (int i = 0; i < imageFiles.length; i++) {
        final pageNumber = i + 2; // 첫 번째 이미지는 이미 처리됨
        
        await _processImageAndCreatePage(
          noteId, 
          imageFiles[i],
          pageNumber: pageNumber,
        );
        
        // 처리 진행 상황 업데이트
        await _updateProcessingProgress(noteId, pageNumber, imageFiles.length + 1);
      }
      
      // 모든 처리 완료 후 상태 업데이트
      await _completeProcessing(noteId);
    } catch (e) {
      debugPrint('이미지 백그라운드 처리 중 오류 발생: $e');
      // 오류가 발생해도 처리 완료 표시
      await _completeProcessing(noteId);
    }
  }
  
  // 처리 진행 상황 업데이트
  Future<void> _updateProcessingProgress(String noteId, int processedCount, int totalCount) async {
    try {
      // 로컬 상태 저장 (SharedPreferences)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('updated_page_count_$noteId', processedCount);
      
      // Firestore 업데이트 (매 페이지마다 하면 비효율적이므로 50% 간격으로만 업데이트)
      if (processedCount == totalCount || processedCount % max(1, (totalCount ~/ 2)) == 0) {
        await _notesCollection.doc(noteId).update({
          'processedPageCount': processedCount,
          'totalPageCount': totalCount,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('처리 진행 상황 업데이트 중 오류: $e');
    }
  }
  
  // 처리 완료 표시
  Future<void> _completeProcessing(String noteId) async {
    try {
      // 로컬 상태 업데이트
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('processing_note_$noteId');
      
      // Firestore 업데이트
      await _notesCollection.doc(noteId).update({
        'isProcessingBackground': false,
        'processingCompleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      debugPrint('노트 $noteId의 백그라운드 처리 완료');
    } catch (e) {
      debugPrint('처리 완료 표시 중 오류: $e');
    }
  }
  
  /// 마지막 캐시 시간 저장 (HomeViewModel에서 사용)
  Future<void> saveLastCacheTime(DateTime time) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _auth.currentUser?.uid;
      if (userId != null) {
        final key = 'last_cache_time_$userId';
        await prefs.setString(key, time.toIso8601String());
      }
    } catch (e) {
      debugPrint('마지막 캐시 시간 저장 중 오류: $e');
    }
  }
  
  /// 마지막 캐시 시간 가져오기 (HomeViewModel에서 사용)
  Future<DateTime?> getLastCacheTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = _auth.currentUser?.uid;
      if (userId != null) {
        final key = 'last_cache_time_$userId';
        final timeStr = prefs.getString(key);
        if (timeStr != null) {
          return DateTime.parse(timeStr);
        }
      }
      return null;
    } catch (e) {
      debugPrint('마지막 캐시 시간 가져오기 중 오류: $e');
      return null;
    }
  }
  
  /// 노트 이미지 URL 업데이트 (NoteListItem에서 사용)
  Future<void> updateNoteImageUrl(String noteId, String imageUrl) async {
    try {
      // Firestore에 업데이트
      await _notesCollection.doc(noteId).update({
        'imageUrl': imageUrl,
        'updatedAt': DateTime.now(),
      });
      
      // 캐시된 노트 업데이트
      final cachedNote = await _cacheService.getCachedNote(noteId);
      if (cachedNote != null) {
        final updatedNote = cachedNote.copyWith(imageUrl: imageUrl);
        await _cacheService.cacheNote(updatedNote);
      }
      
      debugPrint('노트 $noteId의 이미지 URL 업데이트 완료: $imageUrl');
    } catch (e) {
      debugPrint('노트 이미지 URL 업데이트 중 오류: $e');
      rethrow;
    }
  }
}
