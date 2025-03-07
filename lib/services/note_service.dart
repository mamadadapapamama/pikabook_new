import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/note.dart';
import '../models/page.dart' as page_model;
import '../models/flash_card.dart';
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
      final user = _auth.currentUser;
      if (user == null) {
        return '#1 Note';
      }

      // Firestore에서 직접 노트 수 조회
      final snapshot =
          await _notesCollection.where('userId', isEqualTo: user.uid).get();

      final noteNumber = snapshot.docs.length + 1;
      final title = '#$noteNumber Note';
      debugPrint('자동 노트 제목 생성: $title (현재 노트 수: ${snapshot.docs.length})');
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

      // 노트 생성 (제목을 유지하고 추출된 텍스트는 페이지에만 사용)
      final note = await createNote(
        noteTitle,
        null, // 이미지 파일은 전달하지 않고 페이지 생성 시 사용
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
  Future<Map<String, dynamic>> createNoteWithMultipleImages({
    required List<File> imageFiles,
    String? title,
    List<String>? tags,
    String? targetLanguage,
    Function(int progress)? progressCallback,
    bool silentProgress = false, // 진행 상황 업데이트 무시 옵션
  }) async {
    try {
      if (imageFiles.isEmpty) {
        return {'success': false, 'message': '이미지가 없습니다.'};
      }

      print(
          'Starting note creation with multiple images: ${imageFiles.length}');

      // 노트 제목 설정 (제공되지 않은 경우 자동 생성)
      final generatedTitle = title ?? await _generateNoteTitle();

      // 첫 번째 이미지 처리 시작을 알림 (무시 옵션이 true일 때는 호출하지 않음)
      if (!silentProgress && progressCallback != null) {
        progressCallback(0);
      }

      // 현재 사용자 확인
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'message': '로그인이 필요합니다.'};
      }

      // 기본 노트 데이터 생성 (이미지 처리 없이)
      final now = DateTime.now();
      final noteData = {
        'userId': user.uid,
        'originalText': generatedTitle,
        'translatedText': '',
        'isFavorite': false,
        'flashcardCount': 0,
        'flashCards': [],
        'createdAt': now,
        'updatedAt': now,
        'extractedText': '',
      };

      // Firestore에 노트 추가
      final docRef = await _notesCollection.add(noteData);
      final noteId = docRef.id;

      // 페이지 ID를 수집할 리스트
      List<String> pageIds = [];
      page_model.Page? firstPage;

      // 모든 페이지의 구조를 먼저 생성 (내용 없이)
      for (int i = 0; i < imageFiles.length; i++) {
        try {
          // 빈 페이지 생성 (구조만)
          final emptyPage = await _pageService.createEmptyPage(
            noteId: noteId,
            pageNumber: i,
          );

          if (emptyPage != null && emptyPage.id != null) {
            pageIds.add(emptyPage.id!);
            print('빈 페이지 구조 생성 완료: 페이지 ${i}, ID: ${emptyPage.id}');

            // 첫 번째 페이지 저장
            if (i == 0) {
              firstPage = emptyPage;
            }
          }
        } catch (e) {
          print('페이지 구조 생성 중 오류 발생: $e');
        }
      }

      // Firestore에서 노트 문서 업데이트 (페이지 ID 목록)
      if (pageIds.isNotEmpty) {
        try {
          await _firestore.collection('notes').doc(noteId).update({
            'pages': pageIds,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          print('노트 문서 업데이트 완료: $noteId, 페이지 수: ${pageIds.length}');
        } catch (e) {
          print('노트 문서 업데이트 실패: $e');
        }
      }

      // 첫 번째 이미지만 먼저 처리 (내용 채우기)
      if (imageFiles.isNotEmpty && firstPage != null) {
        final firstImageFile = imageFiles[0];

        try {
          // 이미지 업로드
          final imageUrl = await _imageService.uploadImage(firstImageFile);
          if (imageUrl != null && imageUrl.isNotEmpty) {
            // 노트의 썸네일로 설정
            await _notesCollection.doc(noteId).update({
              'imageUrl': imageUrl,
            });

            // OCR로 텍스트 추출
            final extractedText = await _ocrService.extractText(firstImageFile);

            // 텍스트 번역
            String translatedText = '';
            if (extractedText.isNotEmpty) {
              translatedText = await _translationService.translateText(
                extractedText,
                targetLanguage: targetLanguage ?? 'ko',
              );

              // 노트 내용 업데이트
              await _notesCollection.doc(noteId).update({
                'originalText': extractedText,
                'translatedText': translatedText,
                'extractedText': extractedText,
              });
            }

            // 첫 번째 페이지 내용 업데이트
            final updatedFirstPage = await _pageService.updatePageContent(
              pageId: firstPage.id!,
              originalText: extractedText,
              translatedText: translatedText,
              imageFile: firstImageFile,
            );

            // 페이지 캐싱
            if (updatedFirstPage != null) {
              firstPage = updatedFirstPage;
              await _pageCacheService.cachePage(noteId, updatedFirstPage);
              print('첫 번째 페이지 내용 업데이트 완료: ${updatedFirstPage.id}');
            }

            // 진행 상황 업데이트 (첫 페이지 완료)
            if (!silentProgress && progressCallback != null) {
              progressCallback(100);
            }
          }
        } catch (e) {
          print('첫 번째 이미지 처리 중 오류 발생: $e');
        }
      }

      // 생성된 노트 가져오기
      final docSnapshot = await docRef.get();
      final note = Note.fromFirestore(docSnapshot);

      // 노트 캐싱
      await _noteCacheService.cacheNote(note);

      // 첫 번째 페이지 객체 가져오기
      List<page_model.Page> firstPages = [];
      if (firstPage != null) {
        firstPages.add(firstPage);
      } else if (pageIds.isNotEmpty) {
        final page = await _pageService.getPageById(pageIds[0]);
        if (page != null) {
          firstPages.add(page);
        }
      }

      // 첫 번째 페이지 처리 완료 후 결과 반환
      final result = {
        'success': true,
        'note': note,
        'pages': firstPages,
        'noteId': noteId,
        'processingComplete': false, // 항상 false로 설정 (나머지 페이지는 백그라운드에서 처리)
      };

      // 나머지 이미지는 백그라운드에서 처리 (진행 상황 업데이트 없이)
      if (imageFiles.length > 1) {
        // 백그라운드에서 나머지 페이지 내용 채우기
        Future.microtask(() {
          _fillRemainingPagesContent(
            noteId: noteId,
            imageFiles: imageFiles.sublist(1),
            pageIds: pageIds.sublist(1),
            targetLanguage: targetLanguage,
            progressCallback: progressCallback,
            silentProgress: true, // 항상 조용히 처리
          );
        });
      }

      return result;
    } catch (e) {
      print('Error creating note with multiple images: $e');
      return {'success': false, 'message': '노트 생성 중 오류 발생: $e'};
    }
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
      print('백그라운드 처리 시작: ${imageFiles.length}개 이미지의 내용 채우기');

      if (imageFiles.length != pageIds.length) {
        print(
            '이미지 수와 페이지 ID 수가 일치하지 않습니다: 이미지 ${imageFiles.length}개, 페이지 ID ${pageIds.length}개');
        return;
      }

      for (int i = 0; i < imageFiles.length; i++) {
        final imageFile = imageFiles[i];
        final pageId = pageIds[i];
        print('이미지 ${i + 1}/${imageFiles.length} 처리 중...');

        try {
          // 이미지 업로드
          final imageUrl = await _imageService.uploadImage(imageFile);
          if (imageUrl == null || imageUrl.isEmpty) {
            print('이미지 업로드 실패: 이미지 ${i + 1}');
            continue;
          }

          // OCR로 텍스트 추출
          final extractedText = await _ocrService.extractText(imageFile);
          print('OCR 텍스트 추출 완료: 이미지 ${i + 1}, 텍스트 길이: ${extractedText.length}');

          // 텍스트 번역
          String translatedText = '';
          if (extractedText.isNotEmpty) {
            translatedText = await _translationService.translateText(
              extractedText,
              targetLanguage: targetLanguage ?? 'ko',
            );
            print('번역 완료: 이미지 ${i + 1}, 번역 텍스트 길이: ${translatedText.length}');
          }

          // 페이지 내용 업데이트
          final updatedPage = await _pageService.updatePageContent(
            pageId: pageId,
            originalText: extractedText,
            translatedText: translatedText,
            imageFile: imageFile,
          );

          // 페이지 캐싱
          if (updatedPage != null) {
            await _pageCacheService.cachePage(noteId, updatedPage);
            print('페이지 내용 업데이트 완료: 이미지 ${i + 1}, 페이지 ID: ${pageId}');
          } else {
            print('페이지 내용 업데이트 실패: 이미지 ${i + 1}, 페이지 ID: ${pageId}');
          }
        } catch (e) {
          print('이미지 ${i + 1} 처리 중 오류 발생: $e');
          // 한 이미지 처리 실패해도 계속 진행
        }

        // 서버 부하 감소를 위한 약간의 지연
        await Future.delayed(Duration(milliseconds: 500));
      }

      print('백그라운드 처리 완료: ${pageIds.length} 페이지의 내용 채우기 완료, 노트 ID: $noteId');

      // 노트 객체 업데이트 (캐시 갱신)
      try {
        final noteDoc = await _notesCollection.doc(noteId).get();
        if (noteDoc.exists) {
          final updatedNote = Note.fromFirestore(noteDoc);
          await _noteCacheService.cacheNote(updatedNote);
          print('노트 캐시 업데이트 완료: $noteId');
        }
      } catch (e) {
        print('노트 캐시 업데이트 실패: $e');
      }
    } catch (e) {
      print('백그라운드 페이지 내용 채우기 중 오류 발생: $e');
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
}
