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

class NoteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PageService _pageService = PageService();
  final ImageService _imageService = ImageService();
  final TranslationService _translationService = TranslationService();
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  final EnhancedOcrService _ocrService = EnhancedOcrService();
  final UsageLimitService _usageLimitService = UsageLimitService();

  // SharedPreferences 키
  static const String _cachedNotesKey = 'cached_notes';
  static const String _lastCacheTimeKey = 'last_cache_time';

  // 컬렉션 참조
  CollectionReference get _notesCollection => _firestore.collection('notes');

  // 현재 사용자의 노트 컬렉션 참조
  Query get _userNotesQuery => _notesCollection
      .where('userId', isEqualTo: _auth.currentUser?.uid)
      .orderBy('createdAt', descending: true);

  // 페이징된 노트 목록 가져오기
  Stream<List<Note>> getPagedNotes({int limit = 10}) {
    try {
      return _userNotesQuery.limit(limit).snapshots().map((snapshot) {
        final notes =
            snapshot.docs.map((doc) => Note.fromFirestore(doc)).toList();

        // 백그라운드 캐싱 제거 - 특정 액션 완료 시점에만 캐싱하도록 변경
        debugPrint('페이징된 노트 목록 수신: ${notes.length}개');
        return notes;
      });
    } catch (e) {
      debugPrint('페이징된 노트 목록을 가져오는 중 오류 발생: $e');
      return Stream.value([]);
    }
  }

  // 추가 노트 가져오기 (페이징)
  Future<List<Note>> getMoreNotes({Note? lastNote, int limit = 10}) async {
    try {
      Query query = _userNotesQuery;

      // 마지막 노트가 있으면 해당 노트 이후부터 쿼리
      if (lastNote != null && lastNote.createdAt != null) {
        query = query.startAfter([lastNote.createdAt]);
      }

      // 제한된 수의 노트 가져오기
      final snapshot = await query.limit(limit).get();
      final notes =
          snapshot.docs.map((doc) => Note.fromFirestore(doc)).toList();

      // 백그라운드 캐싱 제거 - 특정 액션 완료 시점에만 캐싱하도록 변경
      return notes;
    } catch (e) {
      debugPrint('추가 노트를 가져오는 중 오류 발생: $e');
      return [];
    }
  }

  // 노트 목록 가져오기 (기존 메서드)
  Stream<List<Note>> getNotes() {
    try {
      return _userNotesQuery.snapshots().map((snapshot) {
        final notes =
            snapshot.docs.map((doc) => Note.fromFirestore(doc)).toList();

        // 백그라운드 캐싱 제거 - 특정 액션 완료 시점에만 캐싱하도록 변경
        return notes;
      });
    } catch (e) {
      // 오류 발생 시 빈 리스트 반환
      debugPrint('노트 목록을 가져오는 중 오류가 발생했습니다: $e');
      return Stream.value([]);
    }
  }

  // 캐시된 노트 가져오기
  Future<List<Note>> getCachedNotes() async {
    try {
      // 새로운 캐시 서비스 사용
      return await _cacheService.getCachedNotes();
    } catch (e) {
      debugPrint('캐시된 노트를 가져오는 중 오류 발생: $e');
      return [];
    }
  }

  // 노트 캐싱 (이전 방식 - 호환성 유지)
  Future<void> cacheNotes(List<Note> notes) async {
    try {
      // 새로운 캐시 서비스 사용
      await _cacheService.cacheNotes(notes);
    } catch (e) {
      debugPrint('노트 캐싱 중 오류 발생: $e');
    }
  }

  // 마지막 캐시 시간 저장
  Future<void> saveLastCacheTime(DateTime time) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastCacheTimeKey, time.toIso8601String());
    } catch (e) {
      debugPrint('캐시 시간 저장 중 오류 발생: $e');
    }
  }

  // 마지막 캐시 시간 가져오기
  Future<DateTime?> getLastCacheTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timeString = prefs.getString(_lastCacheTimeKey);

      if (timeString == null || timeString.isEmpty) {
        return null;
      }

      return DateTime.parse(timeString);
    } catch (e) {
      debugPrint('캐시 시간 가져오기 중 오류 발생: $e');
      return null;
    }
  }

  // 캐시 초기화
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cachedNotesKey);
      await prefs.remove(_lastCacheTimeKey);
      
      debugPrint('노트 캐시 지우기 완료');
    } catch (e) {
      debugPrint('노트 캐시 지우기 중 오류 발생: $e');
    }
  }

  /// 노트 캐시 정리 (메모리 최적화)
  Future<void> cleanupCache() async {
    try {
      // 캐시 서비스를 통해 정리
      await _cacheService.cleanupOldCache();
      
      // 페이지 캐시 히스토리 기록 정리
      await _cleanPageCacheHistory();
      
      // 이미지 캐시도 정리 시도
      await _imageService.clearImageCache();
      
      // 노트 생성 중 멈춘 백그라운드 프로세싱 상태 초기화
      await _cleanupStaleBackgroundProcessingState();
      
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

  /// 페이지 캐시 히스토리 정리
  Future<void> _cleanPageCacheHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // pages_updated_ 관련 오래된 항목 찾기
      final allKeys = prefs.getKeys();
      final oldUpdateFlags = <String>[];
      
      // 오래된 페이지 업데이트 플래그 찾기
      for (final key in allKeys) {
        if (key.startsWith('pages_updated_') || key.startsWith('updated_page_count_')) {
          // 키에서 노트 ID 추출
          final noteId = key.split('_').last;
          
          // 해당 노트가 캐시에 있는지 확인
          final note = await _cacheService.getCachedNote(noteId);
          
          // 캐시에 노트가 없으면 관련 플래그 삭제
          if (note == null) {
            oldUpdateFlags.add(key);
          }
        }
      }
      
      // 오래된 플래그 제거
      if (oldUpdateFlags.isNotEmpty) {
        debugPrint('오래된 페이지 업데이트 플래그 ${oldUpdateFlags.length}개 제거');
        for (final key in oldUpdateFlags) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      debugPrint('페이지 캐시 히스토리 정리 중 오류 발생: $e');
    }
  }

  // 노트 생성
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

  // 노트 업데이트
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

  // 노트 삭제
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

      // 페이지 캐시에서도 삭제
      await _cacheService.removePagesForNote(noteId);
      
      // 페이지 카운트 감소
      if (pageCount > 0) {
        for (int i = 0; i < pageCount; i++) {
          await _usageLimitService.decrementPageCount();
        }
      }
    } catch (e) {
      debugPrint('노트 삭제 중 오류 발생: $e');
      rethrow;
    }
  }

  // 즐겨찾기 토글
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

  // 노트와 페이지를 함께 가져오기 (캐싱 활용)
  Future<Map<String, dynamic>> getNoteWithPages(String noteId, {bool forceReload = false}) async {
    try {
      Note? note;
      List<page_model.Page> pages = [];
      bool isFromCache = false;
      bool isProcessing = false;

      debugPrint('노트 $noteId와 페이지 로드 시작');

      // 1. 통합 캐시 서비스에서 노트와 페이지 가져오기
      final cacheResult = await _cacheService.getNoteWithPages(noteId);
      note = cacheResult['note'] as Note?;
      pages = (cacheResult['pages'] as List<dynamic>).cast<page_model.Page>();
      isFromCache = cacheResult['isFromCache'] as bool;

      // 2. 캐시에 노트가 없으면 Firestore에서 가져오기
      if (note == null) {
        final docSnapshot = await _notesCollection.doc(noteId).get();
        if (docSnapshot.exists) {
          note = Note.fromFirestore(docSnapshot);
          // 노트 캐싱 - 노트 로드 완료 시점에 캐싱
          await _cacheService.cacheNote(note);
          debugPrint('Firestore에서 노트 로드 및 캐싱: $noteId');
        } else {
          throw Exception('노트를 찾을 수 없습니다.');
        }
      } else {
        debugPrint('캐시에서 노트 로드: $noteId');
      }

      // 3. 백그라운드 처리 상태 확인
      isProcessing = await _checkBackgroundProcessingStatus(noteId);

      // 4. 캐시에 페이지가 없거나 불완전하면 Firestore에서 가져오기
      if (pages.isEmpty) {
        debugPrint('Firestore에서 노트 $noteId의 페이지 로드 시작');
        pages = await _pageService.getPagesForNote(noteId);

        // 페이지 캐싱 - 페이지 로드 완료 시점에 캐싱
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

  // 백그라운드 처리 상태 확인
  Future<bool> _checkBackgroundProcessingStatus(String noteId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'processing_note_$noteId';
      return prefs.getBool(key) ?? false;
    } catch (e) {
      debugPrint('백그라운드 처리 상태 확인 중 오류 발생: $e');
      return false;
    }
  }

  // 백그라운드 처리 상태 설정
  Future<void> _setBackgroundProcessingState(
      String noteId, bool isProcessing) async {
    try {
      // SharedPreferences에 상태 저장 (임시)
      final prefs = await SharedPreferences.getInstance();
      final key = 'processing_note_$noteId';
      await prefs.setBool(key, isProcessing);

      // Firestore 노트 문서에도 상태 저장 (영구적)
      await _notesCollection.doc(noteId).update({
        'isProcessingBackground': isProcessing,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      debugPrint('백그라운드 처리 상태 설정: $noteId, 처리 중: $isProcessing');
    } catch (e) {
      debugPrint('백그라운드 처리 상태 설정 중 오류 발생: $e');
    }
  }

  // 이미지 미리 로드 (백그라운드에서 처리)
  void _preloadImagesInBackground(List<page_model.Page> pages) {
    Future.microtask(() async {
      for (final page in pages) {
        if (page.imageUrl != null && page.imageUrl!.isNotEmpty) {
          await _imageService.getImageBytes(page.imageUrl);
        }
      }
      debugPrint('${pages.length}개 페이지의 이미지 미리 로드 완료');
    });
  }

  // 나머지 페이지 내용 채우기 (백그라운드)
  Future<void> _fillRemainingPagesContent({
    required String noteId,
    required List<File> imageFiles,
    required List<String> pageIds,
    String? targetLanguage,
    Function(int progress)? progressCallback,
    bool silentProgress = false,
  }) async {
    try {
      debugPrint('백그라운드 처리 시작: ${imageFiles.length}개 이미지의 내용 채우기');

      // 백그라운드 처리 상태 설정
      await _setBackgroundProcessingState(noteId, true);

      if (imageFiles.length != pageIds.length) {
        debugPrint(
            '이미지 수와 페이지 ID 수가 일치하지 않습니다: 이미지 ${imageFiles.length}개, 페이지 ID ${pageIds.length}개');
        await _setBackgroundProcessingState(noteId, false);
        return;
      }

      // 처리 진행 상황 추적
      int processedCount = 0;
      final totalCount = imageFiles.length;

      // 처리된 페이지 목록
      final List<page_model.Page> processedPages = [];

      for (int i = 0; i < imageFiles.length; i++) {
        final imageFile = imageFiles[i];
        final pageId = pageIds[i];
        debugPrint('이미지 ${i + 1}/${imageFiles.length} 처리 중...');

        try {
          // 이미지 업로드
          String imageUrl = '';
          try {
            imageUrl = await _imageService.uploadImage(imageFile);
            // 만약 빈 문자열이 반환되면, 기본 fallback 경로 사용
            if (imageUrl.isEmpty) {
              debugPrint('이미지 업로드 결과가 비어있습니다 - 기본 경로 사용');
              imageUrl = 'images/fallback_image.jpg';
            }
          } catch (uploadError) {
            debugPrint('이미지 업로드 중 오류: $uploadError - 기본 경로 사용');
            imageUrl = 'images/fallback_image.jpg';
          }

          // OCR로 텍스트 추출
          final extractedText = await _ocrService.extractText(imageFile, skipUsageCount: true);
          debugPrint(
              'OCR 텍스트 추출 완료: 이미지 ${i + 1}, 텍스트 길이: ${extractedText.length}');

          // 텍스트 번역
          String translatedText = '';
          if (extractedText.isNotEmpty) {
            translatedText = await _translationService.translateText(
              extractedText,
              targetLanguage: targetLanguage ?? 'ko',
            );
            debugPrint(
                '번역 완료: 이미지 ${i + 1}, 번역 텍스트 길이: ${translatedText.length}');
          }

          // 페이지 내용 업데이트
          final updatedPage = await _pageService.updatePageContent(
            pageId,
            extractedText,
            translatedText,
          );

          // 페이지 캐싱 - 페이지 업데이트 완료 시점에 캐싱
          if (updatedPage != null) {
            processedPages.add(updatedPage);
            debugPrint('페이지 내용 업데이트 완료: 이미지 ${i + 1}, 페이지 ID: ${pageId}');

            // 진행 상황 업데이트
            processedCount++;
            if (!silentProgress && progressCallback != null) {
              final progress = (processedCount * 100) ~/ totalCount;
              progressCallback(progress);
            }
          } else {
            debugPrint('페이지 내용 업데이트 실패: 이미지 ${i + 1}, 페이지 ID: ${pageId}');
          }
        } catch (e) {
          debugPrint('이미지 ${i + 1} 처리 중 오류 발생: $e');
          // 한 이미지 처리 실패해도 계속 진행
        }

        // 서버 부하 감소를 위한 약간의 지연
        await Future.delayed(Duration(milliseconds: 500));
      }

      debugPrint(
          '백그라운드 처리 완료: ${processedCount} 페이지의 내용 채우기 완료, 노트 ID: $noteId');

      // 노트 객체 업데이트 (캐시 갱신) - 모든 페이지 처리 완료 시점에 캐싱
      try {
        // 노트 문서의 모든 페이지 ID 가져오기
        final noteDoc = await _notesCollection.doc(noteId).get();
        if (noteDoc.exists) {
          final data = noteDoc.data() as Map<String, dynamic>?;
          List<String> allPageIds = [];
          
          // 노트 문서에서 이미 저장된 전체 페이지 ID 목록 가져오기
          if (data != null && data['pages'] is List) {
            allPageIds = List<String>.from(data['pages'] as List);
            debugPrint('노트 문서에서 가져온 전체 페이지 ID 목록: ${allPageIds.length}개');
          }
          
          // 페이지 ID 목록이 비어있거나 완전하지 않다면 모든 페이지 쿼리하여 확인
          if (allPageIds.isEmpty || allPageIds.length < pageIds.length + 1) {
            debugPrint('노트의 전체 페이지 쿼리 시작');
            // 노트에 속한 모든 페이지 쿼리 (페이지 번호순)
            final pagesSnapshot = await _firestore
                .collection('pages')
                .where('noteId', isEqualTo: noteId)
                .orderBy('pageNumber')
                .get();
            
            if (pagesSnapshot.docs.isNotEmpty) {
              allPageIds = pagesSnapshot.docs.map((doc) => doc.id).toList();
              debugPrint('쿼리로 찾은 전체 페이지 ID 목록: ${allPageIds.length}개, 페이지 번호 순');
            } else {
              debugPrint('노트에 속한 페이지가 없거나 쿼리 실패');
              // 백업 방법: 처리된 페이지 ID와 이번에 처리한 페이지 ID 합치기
              allPageIds = pageIds;
            }
          }

          // 노트 문서에 모든 페이지 ID 목록 업데이트
          await _notesCollection.doc(noteId).update({
            'pages': allPageIds,
            'processedPageCount': processedCount,
            'totalPageCount': allPageIds.length,
            'imageCount': imageFiles.length,
            'isProcessingBackground': false,
            'processingCompleted': true,
            'updatedAt': FieldValue.serverTimestamp(),
          });

          debugPrint('노트 문서의 페이지 ID 목록 업데이트 완료: ${allPageIds.length}개');

          // 업데이트된 노트 객체 캐싱
          final updatedNoteDoc = await _notesCollection.doc(noteId).get();
          final updatedNote = Note.fromFirestore(updatedNoteDoc);
          await _cacheService.cacheNote(updatedNote);
          debugPrint('노트 캐시 업데이트 완료: $noteId');
          
          // 페이지 목록도 캐시 업데이트
          await _cacheService.cachePages(noteId, processedPages);
          debugPrint('${processedPages.length}개 페이지 캐싱 완료 (노트 ID: $noteId)');
          
          // 노트 문서에 처리 완료 플래그 추가
          await _notesCollection.doc(noteId).update({
            'processingCompleted': true,
            'updatedAt': DateTime.now(),
          });
          
          // 처리 완료를 SharedPreferences에 저장하여 UI에 알림
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('pages_updated_$noteId', true);
          await prefs.setInt('updated_page_count_$noteId', processedCount);
          
          // 처리 결과 로그
          // debugPrint('모든 이미지 처리 완료 ($processedCount/$totalCount), 오류: 0');
        }
      } catch (e) {
        debugPrint('노트 캐시 업데이트 실패: $e');
      }

      // 백그라운드 처리 상태 업데이트
      await _setBackgroundProcessingState(noteId, false);

      // 모든 이미지 처리 완료 후 플래그 업데이트
      await _notesCollection.doc(noteId).update({
        'isProcessingBackground': false,
        'processedImagesCount': processedCount,
        'imageCount': totalCount, // 전체 이미지 수 재확인
      });
    } catch (e) {
      debugPrint('백그라운드 페이지 내용 채우기 중 오류 발생: $e');
      await _setBackgroundProcessingState(noteId, false);
    }
  }
  
  /// 백그라운드에서 모든 이미지 처리 (비동기)
  Future<void> _processAllImagesInBackground(
    String noteId,
    List<File> imageFiles,
    String? targetLanguage,
  ) async {
    try {
      // Firebase 초기화 확인 - Firebase.app() 사용
      try {
        Firebase.app();
      } catch (e) {
        debugPrint('Firebase가 초기화되지 않았습니다: $e');
        return;
      }
      
      // 백그라운드 처리 상태 설정
      await _setBackgroundProcessingState(noteId, true);
      
      final totalCount = imageFiles.length;
      int successCount = 0;
      int failCount = 0;
      
      // 기존 페이지 ID 가져오기
      List<String> existingPageIds = [];
      try {
        final pagesSnapshot = await _firestore
            .collection('pages')
            .where('noteId', isEqualTo: noteId)
            .orderBy('pageNumber')
            .get();
            
        if (pagesSnapshot.docs.isNotEmpty) {
          existingPageIds = pagesSnapshot.docs.map((doc) => doc.id).toList();
        }
      } catch (e) {
        debugPrint('기존 페이지 가져오기 오류: $e');
      }
      
      // 이미지 수만큼 페이지가 이미 생성되었는지 확인
      if (existingPageIds.length > totalCount) {
        // 생성된 페이지가 이미지 수보다 많은 경우, 초과 페이지 삭제
        for (int i = totalCount; i < existingPageIds.length; i++) {
          try {
            await _pageService.deletePage(existingPageIds[i]);
          } catch (e) {
            debugPrint('초과 페이지 삭제 중 오류: $e');
          }
        }
        // 필요한 페이지만 남기고 나머지는 제거
        existingPageIds = existingPageIds.sublist(0, totalCount);
      }
      
      // 첫 번째 이미지 먼저 처리 (우선 순위)
      if (imageFiles.isNotEmpty) {
        try {
          final File firstImage = imageFiles[0];
          String? pageId = existingPageIds.isNotEmpty ? existingPageIds[0] : null;
          
          // 첫 번째 이미지 처리 및 페이지 생성
          final result = await _processImageAndCreatePage(
            noteId,
            firstImage,
            pageNumber: 1,
            pageId: pageId,
            skipOcrUsageCount: true,
          );
          
          if (result['success'] == true) {
            successCount++;
            
            // 첫 페이지 처리 완료 플래그 설정
            await _notesCollection.doc(noteId).update({
              'firstPageProcessed': true,
              'updatedAt': FieldValue.serverTimestamp(),
            });
            
            // 로컬 저장소에도 첫 페이지 처리 완료 상태 저장
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('first_page_processed_$noteId', true);
            
            debugPrint('첫 번째 페이지 처리 완료 및 플래그 설정');
          }
        } catch (e) {
          debugPrint('첫 번째 이미지 처리 중 오류 발생: $e');
          failCount++;
        }
        
        // 나머지 이미지 처리 (두 번째 이미지부터)
        for (int i = 1; i < imageFiles.length; i++) {
          try {
            final File imageFile = imageFiles[i];
            String? pageId = (i < existingPageIds.length) ? existingPageIds[i] : null;
            
            // 이미지 처리 및 페이지 생성
            final result = await _processImageAndCreatePage(
              noteId,
              imageFile,
              pageNumber: i + 1,
              pageId: pageId,
              skipOcrUsageCount: true,
            );
            
            if (result['success'] == true) {
              successCount++;
            } else {
              failCount++;
            }
          } catch (e) {
            debugPrint('이미지 ${i+1} 처리 중 오류 발생: $e');
            failCount++;
          }
        }
      }
      
      // 마무리 (백그라운드 처리 상태 업데이트)
      await _setBackgroundProcessingState(noteId, false);
      
      // 처리 완료 플래그 업데이트
      await _notesCollection.doc(noteId).update({
        'processingCompleted': true,
        'processedImagesCount': successCount + failCount,
        'totalImages': totalCount,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      // 처리 완료를 SharedPreferences에 저장하여 UI에 알림
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('pages_updated_$noteId', true);
      await prefs.setInt('updated_page_count_$noteId', successCount + failCount);
      
      debugPrint('백그라운드 이미지 처리 완료: 총 $totalCount개, 성공 $successCount개, 실패 $failCount개');
    } catch (e) {
      debugPrint('백그라운드 이미지 처리 중 오류: $e');
      
      // 백그라운드 처리 상태 업데이트
      try {
        await _setBackgroundProcessingState(noteId, false);
      } catch (stateError) {
        debugPrint('백그라운드 처리 상태 업데이트 중 오류: $stateError');
      }
    }
  }

  // 여러 이미지로 노트 생성 (배치 처리) - 간소화 버전
  Future<Map<String, dynamic>> createNoteWithMultipleImages({
    required List<File> imageFiles,
    String? title,
    List<String>? tags,
    String? targetLanguage,
    String? noteSpace,
    Function(int progress)? progressCallback,
    bool silentProgress = false,
    bool waitForFirstPageProcessing = false,
  }) async {
    try {
      // Firebase 초기화 확인
      if (Firebase.apps.isEmpty) {
        debugPrint('Firebase가 초기화되지 않았습니다.');
        return {'success': false, 'message': 'Firebase가 초기화되지 않았습니다. 앱을 다시 시작해주세요.'};
      }
      
      if (imageFiles.isEmpty) {
        return {'success': false, 'message': '이미지가 없습니다.'};
      }
      
      // 이미지 파일 유효성 검사
      List<File> validImageFiles = [];
      for (var file in imageFiles) {
        try {
          if (file.existsSync() && file.lengthSync() > 0) {
            validImageFiles.add(file);
          } else {
            debugPrint('유효하지 않은 이미지 파일: ${file.path}');
          }
        } catch (e) {
          debugPrint('이미지 파일 확인 중 오류: $e');
          // 오류 발생 시 해당 파일 건너뛰기
        }
      }
      
      if (validImageFiles.isEmpty) {
        return {'success': false, 'message': '유효한 이미지가 없습니다.'};
      }
      
      // 유효한 이미지만 사용
      imageFiles = validImageFiles;
      
      // 사용자 확인
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'message': '로그인이 필요합니다.'};
      }
      
      // 페이지 사용량 제한 확인 - 이미지 수만큼 페이지를 추가할 수 있는지 확인
      final int pageCount = imageFiles.length;
      final canAddPages = await _usageLimitService.canAddPage(pageCount);
      if (!canAddPages) {
        return {
          'success': false,
          'message': '무료 페이지 사용량 한도를 초과했습니다. 관리자에게 문의해주세요.',
          'limitExceeded': true,
        };
      }
      
      // OCR 페이지 추가 가능 여부 확인 (단, 페이지가 있으면 일부라도 처리)
      final canAddOcrPages = await _usageLimitService.canAddOcrPages(pageCount);
      if (!canAddOcrPages) {
        return {
          'success': false,
          'message': 'OCR 서비스 사용량 한도를 초과했습니다. 관리자에게 문의해주세요.',
          'limitExceeded': true,
        };
      }
      
      // OCR 페이지 카운트 증가 (허용된 만큼만 증가)
      await _usageLimitService.incrementOcrPages(pageCount);
      
      // 페이지 카운트 증가 - 이미지 수만큼 증가
      await _usageLimitService.incrementPageCount(pageCount);
      
      // 노트 기본 정보 생성
      final now = DateTime.now();
      String defaultTitle = title ?? await _generateNoteTitle();
      
      // 1. 노트 생성
      final Map<String, dynamic> noteData = {
        'userId': user.uid,
        'originalText': defaultTitle,
        'translatedText': '',
        'isFavorite': false,
        'flashcardCount': 0,
        'flashCards': [],
        'createdAt': now,
        'updatedAt': now,
        'tags': tags ?? [],
        'noteSpace': noteSpace ?? 'default',
        'imageCount': imageFiles.length, // 전체 이미지 수 설정
        'pageCount': imageFiles.length, // 페이지 수를 이미지 수와 동일하게 설정
        'totalPages': imageFiles.length, // 총 페이지 수도 명시적으로 설정
        'pages': [], // 빈 페이지 배열 초기화
        'firstPageProcessed': false, // 첫 페이지 처리 상태 추가
        'imageUrl': '', // 썸네일 이미지 URL 필드 초기화
      };
      
      // 2. Firestore에 노트 추가 (중요: 노트 ID 즉시 반환)
      final docRef = await _notesCollection.add(noteData);
      final noteId = docRef.id;
      
      debugPrint('노트 ID 생성 성공: $noteId');
      
      // 진행률 콜백 호출 (노트 생성 완료)
      if (progressCallback != null && !silentProgress) {
        progressCallback(20); // 20% 진행
      }
      
      // 3. 백그라운드에서 이미지 처리 시작 (비동기적으로 실행)
      _processAllImagesInBackground(noteId, imageFiles, targetLanguage);
      
      // 4. 노트 정보 반환
      final docSnapshot = await _notesCollection.doc(noteId).get();
      final note = Note.fromFirestore(docSnapshot);
      
      // 노트를 캐시에 저장
      await _cacheService.cacheNote(note);
      
      // 결과 반환 (성공)
      return {
        'success': true,
        'noteId': noteId,
        'message': '노트가 생성되었습니다.',
        'totalPages': imageFiles.length,
        'title': defaultTitle,
      };
    } catch (e) {
      debugPrint('노트 생성 중 오류 발생: $e');
      
      // 결과 반환 (실패)
      return {
        'success': false,
        'message': '노트 생성 중 오류가 발생했습니다: $e',
      };
    }
  }

  /// 노트 이미지 URL 업데이트
  Future<bool> updateNoteImageUrl(String noteId, String imageUrl) async {
    try {
      // 현재 노트 정보 확인 (캐시된 정보 우선 확인)
      final cachedNote = await _cacheService.getCachedNote(noteId);
      
      // 이미 동일한 URL이면 불필요한 업데이트 방지
      if (cachedNote != null && cachedNote.imageUrl == imageUrl) {
        debugPrint('이미지 URL이 이미 동일하여 업데이트 생략: $noteId');
        return true;
      }
      
      // 노트의 이미지 URL 업데이트
      await _notesCollection.doc(noteId).update({
        'imageUrl': imageUrl,
        'updatedAt': DateTime.now(),
      });
      
      // 노트 캐시 갱신 (캐싱된 노트가 있는 경우)
      if (cachedNote != null) {
        final updatedNote = cachedNote.copyWith(imageUrl: imageUrl);
        await _cacheService.cacheNote(updatedNote);
        debugPrint('노트 이미지 URL 캐시 업데이트 완료: $noteId');
      } else {
        // 캐시에서 노트 제거 (다음에 불러올 때 최신 정보로 로드)
        await _cacheService.removeCachedNote(noteId);
      }
      
      return true;
    } catch (e) {
      debugPrint('노트 이미지 URL 업데이트 중 오류 발생: $e');
      return false;
    }
  }

  /// 이미지 처리 오류 시 OCR 페이지 카운트 롤백
  Future<void> _rollbackOcrPageCount() async {
    try {
      await _usageLimitService.decrementOcrPages(1);
      debugPrint('OCR 페이지 카운트 롤백 완료');
    } catch (e) {
      debugPrint('OCR 페이지 카운트 롤백 중 오류: $e');
    }
  }

  /// 노트의 첫 페이지 처리 상태 확인
  Future<Map<String, dynamic>> checkFirstPageProcessingStatus(String noteId) async {
    try {
      // 우선 로컬 저장소 확인 (더 빠름)
      bool localProcessed = false;
      try {
        final prefs = await SharedPreferences.getInstance();
        localProcessed = prefs.getBool('first_page_processed_$noteId') ?? false;
        
        // 로컬에서 처리됨으로 나오면 Firestore 확인 건너뛸 수 있음
        if (localProcessed) {
          return {
            'processed': true,
            'message': '첫 페이지 처리 완료 (로컬)',
            'firestore': true,  // 최적화를 위해 Firestore 조회 생략
            'local': true
          };
        }
      } catch (e) {
        debugPrint('로컬 저장소에서 첫 페이지 처리 상태 확인 중 오류: $e');
        // 오류가 발생해도 계속 진행
      }
      
      // 필요한 경우에만 Firestore 확인
      final noteDoc = await _notesCollection.doc(noteId).get();
      if (!noteDoc.exists) {
        return {'processed': false, 'message': '노트를 찾을 수 없습니다.'};
      }
      
      final data = noteDoc.data() as Map<String, dynamic>;
      final bool firstPageProcessed = data['firstPageProcessed'] ?? false;
      
      // 처리 완료 시 로컬 저장소에도 표시 (다음 확인 최적화)
      if (firstPageProcessed && !localProcessed) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('first_page_processed_$noteId', true);
          debugPrint('첫 페이지 처리 상태를 로컬에 캐싱 완료');
        } catch (e) {
          debugPrint('로컬 저장소에 첫 페이지 처리 상태 저장 중 오류: $e');
        }
      }
      
      return {
        'processed': firstPageProcessed,
        'message': firstPageProcessed ? '첫 페이지 처리 완료' : '첫 페이지 처리 중',
        'firestore': firstPageProcessed,
        'local': localProcessed
      };
    } catch (e) {
      debugPrint('첫 페이지 처리 상태 확인 중 오류: $e');
      return {'processed': false, 'message': '오류: $e'};
    }
  }

  // Firebase 초기화 상태 확인
  bool _isFirebaseInitialized() {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (e) {
      debugPrint('Firebase 초기화 상태 확인 중 오류: $e');
      return false;
    }
  }

  // Firebase 초기화 상태 확인 및 처리
  Future<bool> _ensureFirebaseInitialized() async {
    if (!_isFirebaseInitialized()) {
      try {
        debugPrint('Firebase가 초기화되지 않았습니다. 초기화를 시도합니다.');
        // Firebase가 초기화되지 않은 경우 대체 동작 (로컬 저장)
        return false;
      } catch (e) {
        debugPrint('Firebase 초기화 시도 중 오류: $e');
        return false;
      }
    }
    return true;
  }

  // 특정 노트 가져오기
  Future<Note?> getNoteById(String noteId) async {
    try {
      final docSnapshot = await _notesCollection.doc(noteId).get();
      if (docSnapshot.exists) {
        return Note.fromFirestore(docSnapshot);
      }
      return null;
    } catch (e) {
      debugPrint('노트를 가져오는 중 오류가 발생했습니다: $e');
      throw Exception('노트를 가져오는 중 오류가 발생했습니다: $e');
    }
  }
  
  // 자동 노트 제목 생성
  Future<String> _generateNoteTitle() async {
    try {
      // 현재 사용자의 노트 수 가져오기
      final user = _auth.currentUser;
      if (user == null) {
        return '노트 1';
      }

      // Firestore에서 직접 노트 수 조회
      final snapshot =
          await _notesCollection.where('userId', isEqualTo: user.uid).get();

      final noteNumber = snapshot.docs.length + 1;
      final title = '노트 $noteNumber';
      debugPrint('자동 노트 제목 생성: $title (현재 노트 수: ${snapshot.docs.length})');
      return title;
    } catch (e) {
      debugPrint('자동 노트 제목 생성 중 오류 발생: $e');
      // 오류 발생 시 기본값 사용
      return '노트 1';
    }
  }

  // 노트 내용을 플래시카드로 추가
  Future<bool> addNoteToFlashcards(String noteId) async {
    try {
      // 노트 정보 가져오기
      final note = await getNoteById(noteId);
      if (note == null) {
        throw Exception('노트를 찾을 수 없습니다.');
      }

      // 이미 플래시카드가 있는지 확인
      bool hasExistingCard = false;
      for (var card in note.flashCards) {
        if (card.front == note.originalText) {
          hasExistingCard = true;
          break;
        }
      }

      // 이미 동일한 플래시카드가 있으면 추가하지 않음
      if (hasExistingCard) {
        return false;
      }

      // 새 플래시카드 생성
      final newCard = FlashCard(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        front: note.originalText,
        back: note.translatedText,
        pinyin: '', // 핀인은 빈 값으로 설정
        createdAt: DateTime.now(),
        noteId: noteId,
      );

      // 플래시카드 목록에 추가
      final updatedFlashCards = [...note.flashCards, newCard];

      // 노트 업데이트
      final updatedNote = note.copyWith(
        flashCards: updatedFlashCards,
        flashcardCount: updatedFlashCards.length,
      );

      // Firestore에 업데이트
      await updateNote(noteId, updatedNote);

      return true;
    } catch (e) {
      debugPrint('플래시카드 추가 중 오류 발생: $e');
      return false;
    }
  }

  // 이미지 처리 및 페이지 생성
  Future<Map<String, dynamic>> _processImageAndCreatePage(
    String noteId, 
    File imageFile, 
    {int pageNumber = 1, String? pageId, String? targetLanguage, bool shouldProcess = true, bool skipOcrUsageCount = false}
  ) async {
    try {
      // 이미지 업로드
      String imageUrl = '';
      try {
        // 이미지 업로드 전에 이미지 해시값 계산 (중복 업로드 방지)
        imageUrl = await _imageService.uploadImage(imageFile);
        // 만약 빈 문자열이 반환되면, 기본 fallback 경로 사용
        if (imageUrl.isEmpty) {
          debugPrint('이미지 업로드 결과가 비어있습니다 - 기본 경로 사용');
          imageUrl = 'images/fallback_image.jpg';
        }
      } catch (uploadError) {
        debugPrint('이미지 업로드 중 오류: $uploadError - 기본 경로 사용');
        imageUrl = 'images/fallback_image.jpg';
      }

      String extractedText = '';
      String translatedText = '';
      
      // shouldProcess가 true일 때만 OCR 및 번역 처리
      if (shouldProcess) {
        // OCR로 텍스트 추출
        extractedText = await _ocrService.extractText(imageFile, skipUsageCount: skipOcrUsageCount);
        if (extractedText.isEmpty) {
          debugPrint('OCR 텍스트 추출 실패 또는 텍스트 없음');
        }

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
        debugPrint('OCR 및 번역 처리 건너뛰기 - 특수 마커 사용');
      }

      // 페이지 생성
      final page = await _pageService.createPage(
        noteId: noteId,
        originalText: extractedText,
        translatedText: translatedText,
        pageNumber: pageNumber,
        imageFile: imageFile,
      );

      // 페이지 캐싱
      if (page != null) {
        await _cacheService.cachePage(noteId, page);
      }

      // 노트 업데이트 (첫 페이지 내용으로 노트 내용 업데이트)
      if (pageNumber == 1) {
        // 첫 페이지만 실행하기 위한 추가 확인
        final noteDoc = await _notesCollection.doc(noteId).get();
        if (noteDoc.exists) {
          final note = Note.fromFirestore(noteDoc);
          final bool imageUrlNeedsUpdate = note.imageUrl == null || note.imageUrl!.isEmpty || note.imageUrl == 'images/fallback_image.jpg';
          
          // 필요한 필드만 선택적으로 업데이트하여 불필요한 문서 쓰기 감소
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
          
          // 이미지 URL은 필요한 경우에만 업데이트 (불필요한 변경 방지)
          if (imageUrlNeedsUpdate) {
            updateData['imageUrl'] = imageUrl;
            debugPrint('노트 썸네일 설정: $noteId -> $imageUrl');
          }
          
          // 변경할 내용이 있을 때만 Firestore 업데이트
          if (updateData.length > 1) { // 'updatedAt'만 있는 경우가 아닐 때
            await _notesCollection.doc(noteId).update(updateData);
            
            // 이전 캐시 제거 (다음 로드에서 최신 정보 사용)
            await _cacheService.removeCachedNote(noteId);
          }
        }
      }

      // 처리 결과 반환
      return {
        'success': true,
        'imageUrl': imageUrl,
        'extractedText': extractedText,
        'translatedText': translatedText,
        'pageId': page?.id,
      };
    } catch (e) {
      debugPrint('이미지 처리 및 페이지 생성 중 오류 발생: $e');
      rethrow;
    }
  }
}
