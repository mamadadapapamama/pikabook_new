import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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

  // 컬렉션 참조
  CollectionReference get _notesCollection => _firestore.collection('notes');

  // 현재 사용자의 노트 컬렉션 참조
  Query get _userNotesQuery => _notesCollection
      .where('userId', isEqualTo: _auth.currentUser?.uid)
      .orderBy('createdAt', descending: true);

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
  Future<Note?> createNoteWithMultipleImages(
    List<File> imageFiles, {
    String? title,
    List<String>? tags,
    String? targetLanguage,
    Function(int, int)? progressCallback,
  }) async {
    try {
      if (imageFiles.isEmpty) {
        throw Exception('이미지 파일이 제공되지 않았습니다.');
      }

      // 노트 제목 설정 (제공되지 않은 경우 자동 생성)
      final noteTitle = title ?? await _generateNoteTitle();

      // 첫 번째 이미지로 노트 생성
      debugPrint('노트 생성 시작: ${imageFiles.length}개 이미지');
      final note = await createNoteWithImage(
        imageFiles.first,
        title: noteTitle,
        tags: tags,
        targetLanguage: targetLanguage,
      );

      if (note?.id != null) {
        // 진행 상황 업데이트 (첫 번째 이미지 완료)
        if (progressCallback != null) {
          progressCallback(1, imageFiles.length);
        }

        // 나머지 이미지가 있는 경우에만 처리
        if (imageFiles.length > 1) {
          debugPrint('추가 이미지 처리 시작: ${imageFiles.length - 1}개');

          // 나머지 이미지로 페이지 생성 (병렬 처리)
          final futures = <Future>[];

          for (int i = 1; i < imageFiles.length; i++) {
            final future = _pageService
                .createPageWithImage(
              noteId: note!.id!,
              pageNumber: i,
              imageFile: imageFiles[i],
              targetLanguage: targetLanguage,
            )
                .then((_) {
              // 각 이미지 처리 완료 시 진행 상황 업데이트
              if (progressCallback != null) {
                progressCallback(i + 1, imageFiles.length);
              }
            });

            futures.add(future);

            // 서버 부하를 줄이기 위해 약간의 지연 추가
            if (i < imageFiles.length - 1) {
              await Future.delayed(const Duration(milliseconds: 500));
            }
          }

          // 모든 페이지 생성 완료 대기
          await Future.wait(futures);
          debugPrint('모든 이미지 처리 완료');
        }
      }

      return note;
    } catch (e) {
      debugPrint('여러 이미지로 노트 생성 중 오류 발생: $e');
      throw Exception('여러 이미지로 노트를 생성할 수 없습니다: $e');
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

  // 노트 목록 가져오기
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
