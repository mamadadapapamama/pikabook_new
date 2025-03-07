import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';
import '../models/page.dart' as page_model;
import 'page_service.dart';
import 'image_service.dart';
import 'ocr_service.dart';
import 'translation_service.dart';
import 'note_cache_service.dart';
import 'page_cache_service.dart';

class NoteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PageService _pageService = PageService();
  final ImageService _imageService = ImageService();
  final OcrService _ocrService = OcrService();
  final TranslationService _translationService = TranslationService();
  final NoteCacheService _noteCacheService = NoteCacheService();
  final PageCacheService _pageCacheService = PageCacheService();

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

        // 백그라운드에서 노트 캐싱
        _noteCacheService.cacheNotes(notes);

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

      // 백그라운드에서 노트 캐싱
      _noteCacheService.cacheNotes(notes);

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

        // 백그라운드에서 노트 캐싱
        _noteCacheService.cacheNotes(notes);

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
      return await _noteCacheService.getCachedNotes();
    } catch (e) {
      debugPrint('캐시된 노트를 가져오는 중 오류 발생: $e');
      return [];
    }
  }

  // 노트 캐싱 (이전 방식 - 호환성 유지)
  Future<void> cacheNotes(List<Note> notes) async {
    try {
      // 새로운 캐시 서비스 사용
      await _noteCacheService.cacheNotes(notes);
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
      debugPrint('노트 캐시 초기화 완료');
    } catch (e) {
      debugPrint('캐시 초기화 중 오류 발생: $e');
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
      await _noteCacheService.cacheNote(note);

      return note;
    } catch (e) {
      debugPrint('노트 생성 중 오류 발생: $e');
      rethrow;
    }
  }

  // 노트 업데이트
  Future<void> updateNote(String noteId, Note updatedNote) async {
    try {
      // Firestore에 업데이트
      await _notesCollection.doc(noteId).update({
        'originalText': updatedNote.originalText,
        'translatedText': updatedNote.translatedText,
        'isFavorite': updatedNote.isFavorite,
        'flashcardCount': updatedNote.flashcardCount,
        'flashCards': updatedNote.flashCards,
        'updatedAt': DateTime.now(),
      });

      // 캐시 업데이트
      await _noteCacheService.cacheNote(updatedNote);
    } catch (e) {
      debugPrint('노트 업데이트 중 오류 발생: $e');
      rethrow;
    }
  }

  // 노트 삭제
  Future<void> deleteNote(String noteId) async {
    try {
      // 노트에 연결된 페이지 삭제
      await _pageService.deleteAllPagesForNote(noteId);

      // Firestore에서 노트 삭제
      await _notesCollection.doc(noteId).delete();

      // 캐시에서 노트 삭제
      await _noteCacheService.removeCachedNote(noteId);

      // 페이지 캐시에서도 삭제
      await _pageCacheService.removePagesForNote(noteId);
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
      final cachedNote = await _noteCacheService.getCachedNote(noteId);
      if (cachedNote != null) {
        final updatedNote = cachedNote.copyWith(isFavorite: isFavorite);
        await _noteCacheService.cacheNote(updatedNote);
      }
    } catch (e) {
      debugPrint('즐겨찾기 토글 중 오류 발생: $e');
      rethrow;
    }
  }

  // 노트와 페이지를 함께 가져오기 (캐싱 활용)
  Future<Map<String, dynamic>> getNoteWithPages(String noteId) async {
    try {
      Note? note;
      List<page_model.Page> pages = [];
      bool isFromCache = false;

      // 1. 캐시에서 노트 확인
      note = await _noteCacheService.getCachedNote(noteId);

      // 2. 캐시에 노트가 없으면 Firestore에서 가져오기
      if (note == null) {
        final docSnapshot = await _notesCollection.doc(noteId).get();
        if (docSnapshot.exists) {
          note = Note.fromFirestore(docSnapshot);
          // 노트 캐싱
          await _noteCacheService.cacheNote(note);
        } else {
          throw Exception('노트를 찾을 수 없습니다.');
        }
      } else {
        isFromCache = true;
        debugPrint('캐시에서 노트 로드: $noteId');
      }

      // 3. 캐시에서 페이지 확인
      final hasAllPages = await _pageCacheService.hasAllPagesForNote(noteId);

      if (hasAllPages) {
        // 캐시에 모든 페이지가 있으면 캐시에서 가져오기
        pages = await _pageCacheService.getPagesForNote(noteId);
        isFromCache = true;
        debugPrint('캐시에서 페이지 로드: ${pages.length}개');
      } else {
        // 캐시에 페이지가 없으면 Firestore에서 가져오기
        pages = await _pageService.getPagesForNote(noteId);
        // 페이지 캐싱
        await _pageCacheService.cachePages(noteId, pages);
      }

      return {
        'note': note,
        'pages': pages,
        'isFromCache': isFromCache,
      };
    } catch (e) {
      debugPrint('노트와 페이지를 가져오는 중 오류 발생: $e');
      rethrow;
    }
  }

  // 자동 노트 제목 생성
  Future<String> _generateNoteTitle() async {
    try {
      // 현재 사용자의 노트 수 가져오기
      final notes = await getNotes().first;
      final noteNumber = notes.length + 1;
      final title = '#$noteNumber Note';
      debugPrint('자동 노트 제목 생성: $title (현재 노트 수: ${notes.length})');
      return title;
    } catch (e) {
      debugPrint('자동 노트 제목 생성 중 오류 발생: $e');
      // 오류 발생 시 기본값 사용
      return '#1 Note';
    }
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

  // 이미지로 노트 생성 (OCR 및 번역 포함)
  Future<Note?> createNoteWithImage(
    File imageFile, {
    String? title,
    List<String>? tags,
    String? targetLanguage,
  }) async {
    try {
      // 이미지 업로드
      final imageUrl = await _imageService.uploadImage(imageFile);

      // 이미지에서 텍스트 추출 (OCR)
      final extractedText = await _ocrService.extractText(imageFile);

      // 추출된 텍스트 번역
      final translatedText = await _translationService.translateText(
        extractedText,
        targetLanguage: targetLanguage,
      );

      // 노트 제목 설정 (제공되지 않은 경우 자동 생성)
      final noteTitle = title ?? await _generateNoteTitle();
      debugPrint('노트 제목 설정: $noteTitle');

      // 노트 생성 (제목과 추출된 텍스트를 분리)
      final note = await createNote(
        noteTitle,
        imageFile,
      );

      if (note?.id != null) {
        // 첫 번째 페이지 생성 (OCR로 추출된 텍스트를 페이지 내용으로 사용)
        await _pageService.createPage(
          noteId: note!.id!,
          originalText: extractedText,
          translatedText: translatedText,
          pageNumber: 0,
          imageFile: imageFile,
        );
      }

      return note;
    } catch (e) {
      debugPrint('이미지로 노트 생성 중 오류 발생: $e');
      throw Exception('이미지로 노트를 생성할 수 없습니다: $e');
    }
  }

  // 여러 이미지로 노트 생성
  Future<Note?> createNoteWithMultipleImages({
    required List<File> imageFiles,
    String? title,
    List<String>? tags,
    String? targetLanguage,
    Function(int progress)? progressCallback,
    bool silentProgress = false, // 진행 상황 업데이트 무시 옵션
  }) async {
    try {
      if (imageFiles.isEmpty) {
        return null;
      }

      print(
          'Starting note creation with multiple images: ${imageFiles.length}');

      // 첫 번째 이미지로 노트 생성
      final firstImageFile = imageFiles[0];

      // 노트 제목 설정 (제공되지 않은 경우 자동 생성)
      final generatedTitle = title ?? await _generateNoteTitle();

      // 첫 번째 이미지 처리 시작을 알림 (무시 옵션이 true일 때는 호출하지 않음)
      if (!silentProgress && progressCallback != null) {
        progressCallback(0);
      }

      // 첫 번째 이미지로 노트 생성
      final note = await createNoteWithImage(
        firstImageFile,
        title: generatedTitle,
        tags: tags,
        targetLanguage: targetLanguage,
      );

      if (note == null) {
        return null;
      }

      // 추가 이미지가 없으면 바로 반환
      if (imageFiles.length == 1) {
        return note;
      }

      print(
          'Processing additional ${imageFiles.length - 1} images for note: ${note.id}');

      // 페이지 ID를 수집할 리스트
      List<String> pageIds = [];

      // 첫 번째 페이지 ID 가져오기
      final firstPages = await _pageService.getPagesForNote(note.id!);
      if (firstPages.isNotEmpty) {
        for (var page in firstPages) {
          if (page.id != null) {
            pageIds.add(page.id!);
          }
        }
      }

      // 나머지 이미지 병렬 처리
      final remainingImages = imageFiles.sublist(1);
      int processedCount = 1; // 첫 번째 이미지는 이미 처리됨

      // 병렬 처리를 위한 Future 리스트
      List<Future<page_model.Page?>> pageFutures = [];

      for (int i = 0; i < remainingImages.length; i++) {
        final imageFile = remainingImages[i];

        // 서버 부하 감소를 위한 약간의 지연
        await Future.delayed(Duration(milliseconds: 500));

        // 페이지 생성 Future 추가
        pageFutures.add(_pageService
            .createPageWithImage(
          noteId: note.id!,
          imageFile: imageFile,
          pageNumber: i + 1, // 첫 번째 페이지는 이미 생성되었으므로 i+1
          targetLanguage: targetLanguage,
        )
            .then((page) {
          // 각 이미지 처리 후 진행 상황 업데이트 (무시 옵션이 true일 때는 호출하지 않음)
          processedCount++;
          if (!silentProgress && progressCallback != null) {
            final progress =
                (processedCount * 100 ~/ imageFiles.length).clamp(0, 100);
            progressCallback(progress);
          }
          return page;
        }));
      }

      // 모든 페이지 생성 완료 대기
      final pages = await Future.wait(pageFutures);

      // 성공적으로 생성된 페이지의 ID만 수집
      for (final page in pages) {
        if (page != null && page.id != null) {
          pageIds.add(page.id!);
        }
      }

      // Firestore에서 노트 문서 업데이트
      await _firestore.collection('notes').doc(note.id).update({
        'pages': pageIds,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      print('Updated note with ${pageIds.length} page IDs in Firestore');

      // 모든 페이지 객체 가져오기
      List<page_model.Page> updatedPages = [];
      for (String pageId in pageIds) {
        final page = await _pageService.getPageById(pageId);
        if (page != null) {
          updatedPages.add(page);
        }
      }

      print('Retrieved ${updatedPages.length} page objects');

      // 업데이트된 페이지 목록으로 새 노트 객체 생성
      final updatedNote = Note(
        id: note.id,
        originalText: note.originalText,
        translatedText: note.translatedText,
        createdAt: note.createdAt,
        updatedAt: DateTime.now(),
        imageUrl: note.imageUrl,
        tags: note.tags,
        isFavorite: note.isFavorite,
        flashCards: note.flashCards,
        pages: updatedPages,
        extractedText: note.extractedText,
        flashcardCount: note.flashcardCount,
        reviewCount: note.reviewCount,
        userId: note.userId,
      );

      print('Successfully created note with ${updatedPages.length} pages');
      return updatedNote;
    } catch (e) {
      print('Error creating note with multiple images: $e');
      return null;
    }
  }

  // 이미지 처리 및 페이지 생성
  Future<void> _processImageAndCreatePage(String noteId, File imageFile) async {
    try {
      // 이미지 업로드
      final imageUrl = await _imageService.uploadImage(imageFile);
      if (imageUrl == null || imageUrl.isEmpty) {
        throw Exception('이미지 업로드에 실패했습니다.');
      }

      // OCR로 텍스트 추출
      final extractedText = await _ocrService.extractText(imageFile);
      if (extractedText.isEmpty) {
        debugPrint('OCR 텍스트 추출 실패 또는 텍스트 없음');
      }

      // 텍스트 번역
      String translatedText = '';
      if (extractedText.isNotEmpty) {
        translatedText = await _translationService.translateText(
          extractedText,
          targetLanguage: 'ko',
        );
      }

      // 페이지 생성
      final page = await _pageService.createPage(
        noteId: noteId,
        originalText: extractedText,
        translatedText: translatedText,
        pageNumber: 1,
        imageFile: imageFile,
      );

      // 페이지 캐싱
      if (page != null) {
        await _pageCacheService.cachePage(noteId, page);
      }

      // 노트 업데이트 (첫 페이지 내용으로 노트 내용 업데이트)
      final noteDoc = await _notesCollection.doc(noteId).get();
      if (noteDoc.exists) {
        final note = Note.fromFirestore(noteDoc);
        final updatedNote = note.copyWith(
          originalText:
              extractedText.isNotEmpty ? extractedText : note.originalText,
          translatedText:
              translatedText.isNotEmpty ? translatedText : note.translatedText,
        );

        await updateNote(noteId, updatedNote);
      }
    } catch (e) {
      debugPrint('이미지 처리 및 페이지 생성 중 오류 발생: $e');
      rethrow;
    }
  }
}
