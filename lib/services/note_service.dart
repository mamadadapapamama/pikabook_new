import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';
import '../models/page.dart';
import 'page_service.dart';
import 'image_service.dart';
import 'ocr_service.dart';
import 'translation_service.dart';

class NoteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PageService _pageService = PageService();
  final ImageService _imageService = ImageService();
  final OcrService _ocrService = OcrService();
  final TranslationService _translationService = TranslationService();

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
        debugPrint('페이징된 노트 목록 수신: ${snapshot.docs.length}개');
        return snapshot.docs.map((doc) => Note.fromFirestore(doc)).toList();
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

      return snapshot.docs.map((doc) => Note.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('추가 노트를 가져오는 중 오류 발생: $e');
      return [];
    }
  }

  // 노트 목록 가져오기 (기존 메서드)
  Stream<List<Note>> getNotes() {
    try {
      return _userNotesQuery.snapshots().map((snapshot) {
        return snapshot.docs.map((doc) => Note.fromFirestore(doc)).toList();
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
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString(_cachedNotesKey);

      if (cachedData == null || cachedData.isEmpty) {
        return [];
      }

      final List<dynamic> decodedData = jsonDecode(cachedData);
      return decodedData.map((item) => Note.fromJson(item)).toList();
    } catch (e) {
      debugPrint('캐시된 노트를 가져오는 중 오류 발생: $e');
      return [];
    }
  }

  // 노트 캐싱
  Future<void> cacheNotes(List<Note> notes) async {
    try {
      // Timestamp 오류를 방지하기 위해 각 노트를 JSON으로 변환
      final List<Map<String, dynamic>> jsonNotes = [];

      for (final note in notes) {
        try {
          // 각 노트를 개별적으로 JSON으로 변환하여 오류 발생 시 해당 노트만 건너뜀
          final noteJson = note.toJson();
          jsonNotes.add(noteJson);
        } catch (e) {
          debugPrint('노트 JSON 변환 중 오류 발생 (건너뜀): $e');
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final encodedData = jsonEncode(jsonNotes);
      await prefs.setString(_cachedNotesKey, encodedData);
      debugPrint('${jsonNotes.length}개 노트 캐싱 완료');
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
  Future<Note?> createNote({
    String title = '',
    String content = '',
    String? originalText,
    String? translatedText,
    String? imageUrl,
    List<String>? tags,
  }) async {
    try {
      // 현재 사용자 확인
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('사용자가 로그인되어 있지 않습니다. 익명 로그인 시도...');
        try {
          // 익명 로그인 시도
          final userCredential = await _auth.signInAnonymously();
          debugPrint('익명 로그인 성공: ${userCredential.user?.uid}');
        } catch (authError) {
          debugPrint('익명 로그인 실패: $authError');
          throw Exception('사용자가 로그인되어 있지 않습니다. 익명 로그인 시도 실패: $authError');
        }
      }

      // 로그인 후 다시 확인
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('사용자가 로그인되어 있지 않습니다.');
      }

      // 원본 텍스트와 번역 텍스트 설정
      final finalOriginalText = originalText ?? title;
      final finalTranslatedText = translatedText ?? content;

      // 노트 데이터 생성
      final noteData = {
        'userId': currentUser.uid,
        'originalText': finalOriginalText,
        'translatedText': finalTranslatedText,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'imageUrl': imageUrl,
        'tags': tags ?? [],
        'isFavorite': false,
        'flashCards': [],
        'pages': [],
        'extractedText': finalOriginalText,
        'flashcardCount': 0,
        'reviewCount': 0,
      };

      // Firestore에 노트 추가
      final docRef = await _notesCollection.add(noteData);

      // 생성된 노트 객체 반환
      return Note(
        id: docRef.id,
        originalText: finalOriginalText,
        translatedText: finalTranslatedText,
        imageUrl: imageUrl,
        tags: tags ?? [],
        flashCards: [],
        pages: [],
        extractedText: finalOriginalText,
        userId: currentUser.uid,
      );
    } catch (e) {
      debugPrint('노트 생성 중 오류가 발생했습니다: $e');
      throw Exception('노트 생성 중 오류가 발생했습니다: $e');
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

      // 노트 생성
      final note = await createNote(
        title: noteTitle,
        originalText: extractedText,
        translatedText: translatedText,
        imageUrl: imageUrl,
        tags: tags,
      );

      if (note?.id != null) {
        // 첫 번째 페이지 생성
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
      final generatedTitle =
          title ?? 'Note ${DateTime.now().toString().substring(0, 16)}';

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
      List<Future<Page?>> pageFutures = [];

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
      List<Page> updatedPages = [];
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

  // 자동 노트 제목 생성
  Future<String> _generateNoteTitle() async {
    try {
      final notes = await getNotes().first;
      return '#${notes.length + 1} Note';
    } catch (e) {
      debugPrint('자동 노트 제목 생성 중 오류 발생: $e');
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

  // 노트와 페이지를 함께 가져오기 (캐싱 활용)
  Future<Map<String, dynamic>> getNoteWithPages(String noteId) async {
    try {
      // 노트 정보 가져오기
      final note = await getNoteById(noteId);
      if (note == null) {
        throw Exception('노트를 찾을 수 없습니다.');
      }

      // 페이지 정보 가져오기 (캐싱 활용)
      final pages = await _pageService.getPagesForNote(noteId);

      return {
        'note': note,
        'pages': pages,
      };
    } catch (e) {
      debugPrint('노트와 페이지를 가져오는 중 오류가 발생했습니다: $e');
      throw Exception('노트와 페이지를 가져오는 중 오류가 발생했습니다: $e');
    }
  }

  // 노트 업데이트
  Future<void> updateNote(String noteId, Note note) async {
    try {
      await _notesCollection.doc(noteId).update({
        'originalText': note.originalText,
        'translatedText': note.translatedText,
        'updatedAt': FieldValue.serverTimestamp(),
        'imageUrl': note.imageUrl,
        'tags': note.tags,
        'isFavorite': note.isFavorite,
        'flashCards': note.flashCards.map((card) => card.toJson()).toList(),
        'pages': note.pages.map((page) => page.id).toList(),
        'extractedText': note.extractedText,
        'flashcardCount': note.flashcardCount,
        'reviewCount': note.reviewCount,
      });
    } catch (e) {
      debugPrint('노트 업데이트 중 오류가 발생했습니다: $e');
      throw Exception('노트 업데이트 중 오류가 발생했습니다: $e');
    }
  }

  // 노트 삭제
  Future<void> deleteNote(String noteId) async {
    try {
      // 노트에 연결된 모든 페이지 삭제
      await _pageService.deleteAllPagesForNote(noteId);

      // 노트 문서 삭제
      await _notesCollection.doc(noteId).delete();
    } catch (e) {
      debugPrint('노트 삭제 중 오류가 발생했습니다: $e');
      throw Exception('노트 삭제 중 오류가 발생했습니다: $e');
    }
  }

  // 노트 즐겨찾기 토글
  Future<void> toggleFavorite(String noteId, bool isFavorite) async {
    try {
      await _notesCollection.doc(noteId).update({
        'isFavorite': isFavorite,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('노트 즐겨찾기 설정 중 오류가 발생했습니다: $e');
      throw Exception('노트 즐겨찾기 설정 중 오류가 발생했습니다: $e');
    }
  }
}
