import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
      
      debugPrint('노트 서비스 캐시 정리 완료');
    } catch (e) {
      debugPrint('노트 캐시 정리 중 오류 발생: $e');
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
  Future<void> _setBackgroundProcessingStatus(
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
      await _setBackgroundProcessingStatus(noteId, true);

      if (imageFiles.length != pageIds.length) {
        debugPrint(
            '이미지 수와 페이지 ID 수가 일치하지 않습니다: 이미지 ${imageFiles.length}개, 페이지 ID ${pageIds.length}개');
        await _setBackgroundProcessingStatus(noteId, false);
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
          final imageUrl = await _imageService.uploadImage(imageFile);
          if (imageUrl == null || imageUrl.isEmpty) {
            debugPrint('이미지 업로드 실패: 이미지 ${i + 1}');
            continue;
          }

          // OCR로 텍스트 추출
          final extractedText = await _ocrService.extractText(imageFile);
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
          debugPrint('모든 이미지 처리 완료 ($processedCount/$totalCount), 오류: 0');
        }
      } catch (e) {
        debugPrint('노트 캐시 업데이트 실패: $e');
      }

      // 백그라운드 처리 상태 업데이트
      await _setBackgroundProcessingStatus(noteId, false);

      // 모든 이미지 처리 완료 후 플래그 업데이트
      await _notesCollection.doc(noteId).update({
        'isProcessingBackground': false,
        'processedImagesCount': processedCount,
        'imageCount': totalCount, // 전체 이미지 수 재확인
      });
    } catch (e) {
      debugPrint('백그라운드 페이지 내용 채우기 중 오류 발생: $e');
      await _setBackgroundProcessingStatus(noteId, false);
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

  /// 플래시카드 추가
  Future<Map<String, dynamic>> addFlashCard(String noteId, FlashCard flashCard) async {
    try {
      // 사용량 제한 확인
      final canAddFlashcard = await _usageLimitService.incrementFlashcardCount();
      if (!canAddFlashcard) {
        return {
          'success': false,
          'message': '무료 플래시카드 사용량 한도를 초과했습니다.',
          'limitExceeded': true,
        };
      }
      
      // 노트 가져오기
      final note = await getNoteById(noteId);
      if (note == null) {
        return {'success': false, 'message': '노트를 찾을 수 없습니다.'};
      }
      
      // 플래시카드 목록에 추가
      List<FlashCard> updatedFlashCards = List.from(note.flashCards);
      
      // 고유 ID 생성
      final newFlashCard = flashCard.copyWith(
        id: flashCard.id ?? const Uuid().v4(),
      );
      
      updatedFlashCards.add(newFlashCard);
      
      // Firestore 업데이트
      await _notesCollection.doc(noteId).update({
        'flashCards': updatedFlashCards.map((card) => card.toJson()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      // 캐시된 노트 업데이트
      final updatedNote = note.copyWith(flashCards: updatedFlashCards);
      await _cacheService.cacheNote(updatedNote);
      
      return {
        'success': true, 
        'flashCard': newFlashCard,
        'message': '플래시카드가 추가되었습니다.'
      };
    } catch (e) {
      debugPrint('플래시카드 추가 중 오류 발생: $e');
      return {'success': false, 'message': '플래시카드 추가 중 오류: $e'};
    }
  }

  // 여러 이미지로 노트 생성 (배치 처리)
  Future<Map<String, dynamic>> createNoteWithMultipleImages({
    required List<File> imageFiles,
    String? title,
    List<String>? tags,
    String? targetLanguage,
    String? noteSpace,
    Function(int progress)? progressCallback,
    bool silentProgress = false,
    bool waitForFirstPageProcessing = false,  // 첫 페이지 처리 완료까지 대기 여부
  }) async {
    try {
      if (imageFiles.isEmpty) {
        return {'success': false, 'message': '이미지가 없습니다.'};
      }
      
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
      final ocrIncremented = await _usageLimitService.incrementOcrPages(pageCount);
      
      // 페이지 카운트 증가 - 이미지 수만큼 증가
      await _usageLimitService.incrementPageCount(pageCount);
      
      debugPrint('Starting note creation with multiple images: ${imageFiles.length}');
      
      // 노트 기본 정보 생성
      final now = DateTime.now();
      String defaultTitle = title ?? await _generateNoteTitle();
      debugPrint('생성할 노트 제목: $defaultTitle');
      
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
      };
      
      // 2. Firestore에 노트 추가
      final docRef = await _notesCollection.add(noteData);
      final noteId = docRef.id;
      
      // 3. 첫 번째 이미지 처리 (업로드만 동기적으로 처리)
      if (imageFiles.isNotEmpty) {
        try {
          // 첫 번째 이미지 업로드
          final imageUrl = await _imageService.uploadImage(imageFiles[0]);
          
          // 노트에 이미지 URL 추가 (썸네일로 사용)
          await _notesCollection.doc(noteId).update({
            'imageUrl': imageUrl,
            'processingStatus': 'uploading', // 처리 상태 표시
          });
          
          // 첫번째 페이지 생성 (OCR 처리 없이)
          final page = await _pageService.createPage(
            noteId: noteId,
            originalText: '___PROCESSING___', // 특수 마커를 사용해 처리 중임을 표시
            translatedText: '',
            pageNumber: 1,
            imageFile: imageFiles[0]
          );
          
          // 페이지 캐싱
          if (page != null) {
            await _cacheService.cachePage(noteId, page);
          }
          
          // 나머지 이미지들에 대해 빈 페이지 생성 (비동기 처리만 위한 자리표시자)
          for (int i = 1; i < imageFiles.length; i++) {
            final placeholderPage = await _pageService.createPage(
              noteId: noteId,
              originalText: '___PROCESSING___',
              translatedText: '',
              pageNumber: i + 1,
              imageFile: imageFiles[i]
            );
            
            // 페이지 캐싱
            if (placeholderPage != null) {
              await _cacheService.cachePage(noteId, placeholderPage);
            }
          }
          
          // 진행률 콜백 호출 (첫 페이지 업로드 완료)
          if (progressCallback != null && !silentProgress) {
            progressCallback(1);
          }
        } catch (e) {
          // 첫 페이지 처리 실패 시 페이지 카운트 감소
          await _usageLimitService.decrementPageCount();
          // 오류가 있더라도 계속 진행
        }
      }
      
      // 4. 백그라운드에서 모든 이미지 처리 (처음부터 모든 이미지 OCR 처리)
      // 백그라운드 처리 플래그 설정
      await _notesCollection.doc(noteId).update({
        'isProcessingBackground': true,
        'totalImagesToProcess': imageFiles.length,
        'processedImagesCount': 0, // 모든 이미지가 OCR 처리 대기 중
      });
      
      // 백그라운드에서 모든 이미지 처리 (비동기)
      final backgroundProcessingFuture = _processAllImagesInBackground(
        noteId,
        imageFiles,
        targetLanguage,
      );
      
      // 첫 페이지 처리 완료까지 대기 옵션이 활성화된 경우
      if (waitForFirstPageProcessing) {
        debugPrint('첫 페이지 처리 완료 대기 모드 활성화');
        
        // 첫 페이지 처리 상태를 주기적으로 확인하는 함수
        Future<void> waitForFirstPageCompletion() async {
          bool isFirstPageProcessed = false;
          int maxAttempts = 40; // 최대 20초 대기 (0.5초 간격으로 40번)
          int attempt = 0;
          
          while (!isFirstPageProcessed && attempt < maxAttempts) {
            attempt++;
            
            // 0.5초 간격으로 대기하여 더 빠르게 반응
            await Future.delayed(const Duration(milliseconds: 500));
            
            try {
              // 노트 문서 검사
              final noteDoc = await _notesCollection.doc(noteId).get();
              if (noteDoc.exists) {
                final noteData = noteDoc.data() as Map<String, dynamic>?;
                isFirstPageProcessed = noteData?['firstPageProcessed'] == true;
                
                // 처리된 페이지 수 확인
                final int processedCount = noteData?['processedImagesCount'] ?? 0;
                
                if (isFirstPageProcessed) {
                  debugPrint('첫 페이지 처리 완료 감지: attempt=$attempt, processedCount=$processedCount');
                  break;
                } else if (processedCount > 0) {
                  // 적어도 하나의 이미지가 처리되었다면 진행 중인 것으로 간주
                  debugPrint('이미지 처리 진행 중: processedCount=$processedCount');
                }
              }
            } catch (e) {
              debugPrint('첫 페이지 처리 상태 확인 중 오류: $e');
            }
            
            // 로그 찍기 (첫 번째와 매 4번째 시도마다)
            if (attempt == 1 || attempt % 4 == 0) {
              debugPrint('첫 페이지 처리 완료 대기 중... (시도: $attempt/$maxAttempts)');
            }
          }
          
          // 대기 결과 로그
          if (isFirstPageProcessed) {
            debugPrint('첫 페이지 처리 완료 확인: $attempt번째 시도에 성공');
            
            // 추가 대기 (UI 준비 시간)
            await Future.delayed(const Duration(milliseconds: 800)); // 0.8초로 감소
            
            // 노트 캐시 갱신하여 최신 데이터로 만듦
            try {
              await getNoteWithPages(noteId, forceReload: true);
              debugPrint('노트 캐시 강제 갱신 완료: $noteId');
            } catch (e) {
              debugPrint('노트 캐시 갱신 중 오류: $e');
            }
          } else {
            debugPrint('첫 페이지 처리 타임아웃: $maxAttempts번 시도 후 계속 진행');
            
            // 타임아웃이 발생해도 로딩 화면을 계속 표시하지 않고 진행
            await _notesCollection.doc(noteId).update({
              'firstPageProcessed': true, // 강제로 처리 완료 표시
              'updatedAt': DateTime.now(),
            });
          }
          
          // 다음 화면 전환을 위한 추가 대기
          await Future.delayed(const Duration(milliseconds: 200)); // 0.2초로 감소
        }
        
        // 첫 페이지 처리 완료 대기
        await waitForFirstPageCompletion();
      }
      
      // 5. 노트 정보 반환
      final docSnapshot = await _notesCollection.doc(noteId).get();
      final note = Note.fromFirestore(docSnapshot);
      
      // 노트를 캐시에 저장
      await _cacheService.cacheNote(note);
      
      return {
        'success': true,
        'noteId': noteId,
        'note': note,
        'message': '노트가 생성되었습니다.',
        'isProcessingBackground': imageFiles.length > 1,
      };
    } catch (e) {
      debugPrint('Error creating note with multiple images: $e');
      return {'success': false, 'message': '노트 생성 중 오류 발생: $e'};
    }
  }
  
  /// 백그라운드에서 모든 이미지 처리 (비동기)
  Future<void> _processAllImagesInBackground(
    String noteId,
    List<File> imageFiles,
    String? targetLanguage,
  ) async {
    try {
      // 백그라운드 처리 상태 설정
      await _setNoteBackgroundProcessingState(noteId, true);
      
      final totalCount = imageFiles.length;
      int processedCount = 0;
      int errorCount = 0;
      
      debugPrint('백그라운드에서 ${imageFiles.length}개 이미지 처리 시작');
      
      // 기존 페이지 ID 가져오기 (이미 만들어진 첫 페이지가 있을 것)
      // 이 페이지를 업데이트하고 추가 페이지는 생성하지 않음
      List<String> existingPageIds = [];
      try {
        final pagesSnapshot = await _firestore
            .collection('pages')
            .where('noteId', isEqualTo: noteId)
            .get();
            
        if (pagesSnapshot.docs.isNotEmpty) {
          existingPageIds = pagesSnapshot.docs.map((doc) => doc.id).toList();
          debugPrint('이미 생성된 페이지 ID 목록: $existingPageIds');
        }
      } catch (e) {
        debugPrint('기존 페이지 가져오기 오류: $e');
      }
      
      // 모든 이미지 처리 (OCR 및 페이지 업데이트)
      for (int i = 0; i < imageFiles.length; i++) {
        File imageFile = imageFiles[i];
        
        try {
          // 첫 번째 이미지이고 기존 페이지가 있는 경우 - 기존 페이지 업데이트
          if (i == 0 && existingPageIds.isNotEmpty) {
            debugPrint('첫 번째 이미지는 이미 페이지가 생성되어 있어 업데이트만 수행');
            
            // 이미지 업로드
            final imageUrl = await _imageService.uploadImage(imageFile);
            if (imageUrl == null || imageUrl.isEmpty) {
              throw Exception('이미지 업로드에 실패했습니다.');
            }
            
            // OCR로 텍스트 추출
            final extractedText = await _ocrService.extractText(imageFile);
            
            // 텍스트 번역
            String translatedText = '';
            if (extractedText.isNotEmpty) {
              translatedText = await _translationService.translateText(
                extractedText,
                targetLanguage: targetLanguage ?? 'ko',
              );
            }
            
            // 기존 페이지 업데이트
            final firstPageId = existingPageIds[0];
            await _pageService.updatePageContent(
              firstPageId,
              extractedText,
              translatedText
            );
            
            // 썸네일 업데이트
            await _notesCollection.doc(noteId).update({
              'imageUrl': imageUrl,
              'extractedText': extractedText,
              'translatedText': translatedText,
              'updatedAt': DateTime.now(),
              'firstPageProcessed': true,
            });
            
            processedCount++;
          } 
          // 첫 번째가 아닌 이미지이거나, 기존 페이지가 없는 경우 새 페이지 생성
          else {
            // 이미지 처리 및 페이지 생성/업데이트
            final pageData = await _processImageAndCreatePage(
              noteId,
              imageFile,
              pageNumber: existingPageIds.isEmpty ? 1 : i + 1, // 기존 페이지가 없으면 1부터, 있으면 i+1
              targetLanguage: targetLanguage,
              shouldProcess: true, // OCR 처리 활성화
            );
            
            if (pageData != null) {
              processedCount++;
              
              // 첫 번째 이미지인 경우 노트의 썸네일 이미지로 설정
              if (i == 0) {
                // 노트 이미지 URL 업데이트
                await _notesCollection.doc(noteId).update({
                  'imageUrl': pageData['imageUrl'],
                  'updatedAt': DateTime.now(),
                  'extractedText': pageData['extractedText'] ?? '',
                  'translatedText': pageData['translatedText'] ?? '',
                  'firstPageProcessed': true,
                });
                
                // 캐시 정리 (썸네일 이미지가 업데이트되었으므로)
                await _cacheService.removeCachedNote(noteId);
              }
            }
          }
          
          // 처리 상태 업데이트
          await _notesCollection.doc(noteId).update({
            'processedImagesCount': processedCount,
            'updatedAt': DateTime.now(),
          });
          
        } catch (e) {
          debugPrint('이미지 ${i + 1} 처리 중 오류: $e');
          // 이미지 처리 실패 시 페이지 카운트 감소
          await _usageLimitService.decrementPageCount();
          // OCR 페이지 카운트도 롤백
          await _rollbackOcrPageCount();
          errorCount++;
        }
        
        // 처리 중인 페이지 상태 업데이트를 실시간으로 저장
        if (i == 0) {
          // 첫 페이지 처리 완료 시 SharedPreferences에 표시
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('first_page_processed_$noteId', true);
        }
      }
      
      // 모든 이미지 처리 완료 후 플래그 업데이트
      await _setNoteBackgroundProcessingState(noteId, false);
      
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
      debugPrint('모든 이미지 처리 완료 ($processedCount/$totalCount), 오류: $errorCount');
    } catch (e) {
      debugPrint('백그라운드 이미지 처리 중 오류 발생: $e');
      // 오류가 발생해도 처리 상태 업데이트
      await _setNoteBackgroundProcessingState(noteId, false);
    }
  }
  
  /// 노트의 백그라운드 처리 상태 설정
  Future<void> _setNoteBackgroundProcessingState(String noteId, bool isProcessing) async {
    try {
      await _notesCollection.doc(noteId).update({
        'isProcessingBackground': isProcessing,
      });
      
      debugPrint('백그라운드 처리 상태 설정: $noteId, 처리 중: $isProcessing');
    } catch (e) {
      debugPrint('백그라운드 처리 상태 설정 중 오류 발생: $e');
    }
  }

  // 이미지 처리 및 페이지 생성
  Future<Map<String, dynamic>> _processImageAndCreatePage(
    String noteId, 
    File imageFile, 
    {int pageNumber = 1, String? targetLanguage, bool shouldProcess = true}
  ) async {
    try {
      // 이미지 업로드
      final imageUrl = await _imageService.uploadImage(imageFile);
      if (imageUrl == null || imageUrl.isEmpty) {
        throw Exception('이미지 업로드에 실패했습니다.');
      }

      String extractedText = '';
      String translatedText = '';
      
      // shouldProcess가 true일 때만 OCR 및 번역 처리
      if (shouldProcess) {
        // OCR로 텍스트 추출
        extractedText = await _ocrService.extractText(imageFile);
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
        final noteDoc = await _notesCollection.doc(noteId).get();
        if (noteDoc.exists) {
          final note = Note.fromFirestore(noteDoc);
          
          // extractedText 필드 업데이트
          await _notesCollection.doc(noteId).update({
            'extractedText': extractedText == '___PROCESSING___' ? '' : extractedText,
            'translatedText': translatedText.isNotEmpty ? translatedText : note.translatedText,
          });
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

  /// 노트 이미지 URL 업데이트
  Future<bool> updateNoteImageUrl(String noteId, String imageUrl) async {
    try {
      // 노트의 이미지 URL 업데이트
      await _notesCollection.doc(noteId).update({
        'imageUrl': imageUrl,
        'updatedAt': DateTime.now(),
      });
      
      // 캐시에서 노트 제거 (다음에 불러올 때 최신 정보로 로드)
      await _cacheService.removeCachedNote(noteId);
      
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
}
