import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../models/note.dart';
import '../../models/page.dart' as page_model;
import '../../models/flash_card.dart';
import 'page_service.dart';
import '../media/image_service.dart';
import '../storage/unified_cache_service.dart';
import '../text_processing/enhanced_ocr_service.dart';
import '../common/usage_limit_service.dart';
import '../text_processing/llm_text_processing.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
// 리팩토링으로 제거된 import

/// 노트 서비스: 노트 관리, 생성, 처리, 캐싱 로직을 담당합니다.
///  
class NoteService {
  // 서비스 인스턴스
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PageService _pageService = PageService();
  final ImageService _imageService = ImageService();
  final UnifiedTextProcessingService _textProcessingService = UnifiedTextProcessingService();
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
    debugPrint('[NoteService] getNotes 메서드 호출됨');
    
    // 오류 생성 없이 사용자 인증 상태 확인
    final User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      debugPrint('[NoteService] 사용자가 로그인되지 않음, 빈 노트 목록 반환');
      return Stream.value([]);
    }
    
    final String userId = currentUser.uid;
    debugPrint('[NoteService] 사용자 ID: $userId로 노트 조회 시작');
    
    try {
      // Firestore에서 사용자의 노트 쿼리
      final notesStream = _userNotesQuery.snapshots().map((snapshot) {
        final List<Note> notes = snapshot.docs.map((doc) {
          try {
            return Note.fromFirestore(doc);
          } catch (e) {
            debugPrint('[NoteService] 노트 변환 중 오류 (docId: ${doc.id}): $e');
            // 변환 오류 시 빈 노트 반환 (스트림 유지를 위해)
            return Note(
              id: doc.id,
              originalText: '오류 발생한 노트',
              translatedText: '오류 발생한 노트',
              extractedText: '',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );
          }
        }).toList();
        
        debugPrint('[NoteService] 노트 ${notes.length}개 로드됨');
        
        // 로드된 노트 캐싱 (백그라운드로 처리)
        if (notes.isNotEmpty) {
          Future.microtask(() async {
            try {
              await cacheNotes(notes);
              debugPrint('[NoteService] 노트 ${notes.length}개 캐싱 완료');
            } catch (e) {
              debugPrint('[NoteService] 노트 캐싱 중 오류: $e');
            }
          });
        }
        
        return notes;
      });
      
      // 스트림에 오류 핸들러 추가
      return notesStream.handleError((error, stackTrace) {
        debugPrint('[NoteService] 노트 스트림에서 오류 발생: $error');
        debugPrint('[NoteService] 스택 트레이스: $stackTrace');
        
        // 오류 발생 시 마지막으로 캐시된 노트를 조회하여 반환
        return Future.microtask(() async {
          final cachedNotes = await getCachedNotes();
          debugPrint('[NoteService] 오류 복구: 캐시에서 ${cachedNotes.length}개 노트 로드');
          return cachedNotes;
        });
      });
    } catch (e, stackTrace) {
      debugPrint('[NoteService] getNotes 메서드에서 오류 발생: $e');
      debugPrint('[NoteService] 스택 트레이스: $stackTrace');
      
      // 오류 발생 시 빈 목록 반환
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

  /// 노트 ID로 노트 가져오기 (캐싱 활용)
  Future<Note?> getNoteById(String noteId) async {
    debugPrint('📝 getNoteById 호출됨: $noteId');
    
    try {
      // 1. 캐시에서 노트 확인 (짧은 타임아웃 적용)
      Note? cachedNote;
      try {
        cachedNote = await Future.any([
          _cacheService.getCachedNote(noteId),
          Future.delayed(const Duration(milliseconds: 500), () => null)
        ]);
      } catch (e) {
        debugPrint('⚠️ 캐시 확인 중 오류 또는 타임아웃: $e');
        // 캐시 오류는 무시하고 계속 진행
      }
      
      if (cachedNote != null) {
        debugPrint('✅ 캐시에서 노트 찾음: ${cachedNote.id}, 제목: ${cachedNote.originalText}');
        return cachedNote;
      }
      
      debugPrint('🔄 캐시에서 노트를 찾지 못해 Firestore에서 조회 시작: $noteId');
      
      // 2. Firestore에서 노트 가져오기 (엄격한 타임아웃 적용)
      final docSnapshot = await _notesCollection.doc(noteId)
          .get()
          .timeout(const Duration(seconds: 5), onTimeout: () {
            debugPrint('⚠️ 노트 가져오기 타임아웃: $noteId');
            throw Exception('노트 가져오기 타임아웃');
          });
          
      if (!docSnapshot.exists) {
        debugPrint('❌ Firestore에 노트가 존재하지 않음: $noteId');
        return null;
      }
      
      // 3. 노트 객체 생성
      final note = Note.fromFirestore(docSnapshot);
      
      // 4. 캐시에 노트 저장 (백그라운드로 처리)
      if (note.id != null) {
        Future.microtask(() async {
          try {
            await _cacheService.cacheNote(note);
            debugPrint('✅ 백그라운드에서 Firestore 노트를 캐시에 저장 완료: ${note.id}');
          } catch (e) {
            debugPrint('⚠️ 백그라운드에서 노트 캐싱 중 오류 (무시됨): $e');
          }
        });
        
        debugPrint('✅ Firestore에서 노트 로드 성공: ${note.id}, 제목: ${note.originalText}');
      }
      
      return note;
    } catch (e, stackTrace) {
      debugPrint('❌ 노트를 가져오는 중 오류가 발생했습니다: $e');
      debugPrint('스택 트레이스: $stackTrace');
      return null;
    }
  }

  /// 노트 생성
  Future<String> createNote({
    required String title,
    required List<File> imageFiles,
    String? description,
  }) async {
    try {
      // 1. 노트 문서 생성
      final noteRef = _notesCollection.doc();
      final noteId = noteRef.id;
      
      // 2. 첫 번째 이미지 처리 및 썸네일 생성
      String? thumbnailUrl;
      String? firstImageUrl;
      
      if (imageFiles.isNotEmpty) {
        final firstImage = imageFiles[0];
        
        // 썸네일 생성
        thumbnailUrl = await _imageService.uploadAndGetUrl(firstImage, forThumbnail: true);
        
        // 첫 번째 이미지 업로드
        firstImageUrl = await _imageService.uploadImage(firstImage);
      }
      
      // 3. 노트 데이터 저장
      final noteData = {
        'title': title,
        'description': description ?? '',
        'thumbnailUrl': thumbnailUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'pageCount': imageFiles.length,
        'isProcessing': false,
        'processingProgress': 0,
      };
      
      await noteRef.set(noteData);
      
      // 4. 첫 번째 페이지 및 나머지 페이지 생성 (백그라운드 처리)
      if (imageFiles.isNotEmpty) {
        await _pageService.processImageAndCreatePage(
          noteId,
          imageFiles[0],
          pageNumber: 1,
          existingImageUrl: firstImageUrl,
        );
        for (int i = 1; i < imageFiles.length; i++) {
          await _pageService.processImageAndCreatePage(
            noteId,
            imageFiles[i],
            pageNumber: i + 1,
          );
        }
      }
      
      return noteId;
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
      final updateTask = _notesCollection.doc(noteId).update(updateData);
      await updateTask; // 명시적으로 작업 완료 대기

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
      
      // 페이지 카운트 감소 코드 삭제 - 페이지 사용량 제한이 없으므로
      // if (pageCount > 0) {
      //   // 페이지 수만큼 반복하여 카운트 감소
      //   for (int i = 0; i < pageCount; i++) {
      //     await _usageLimitService.decrementPageCount();
      //   }
      // }
    } catch (e) {
      debugPrint('노트 삭제 중 오류 발생: $e');
      rethrow;
    }
  }

  /// 즐겨찾기 토글
  Future<void> toggleFavorite(String noteId, bool isFavorite) async {
    try {
      final updateTask = _notesCollection.doc(noteId).update({
        'isFavorite': isFavorite,
        'updatedAt': DateTime.now(),
      });
      
      await updateTask; // 명시적으로 작업 완료 대기

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
      final updateTask = _notesCollection.doc(noteId).update({
        'isProcessingBackground': isProcessing,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      // 명시적으로 작업 완료 대기
      await updateTask;

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
  
  // LLM 기반 이미지 처리 메서드는 PageService로 이동되었습니다.
  // 이미지 처리 및 페이지 생성 메서드는 PageService로 이동되었습니다.
  // _updateNoteFirstPageInfo 메서드는 PageService로 이동되었습니다.

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
      
      // 순차적인 노트 제목 생성
      final noteTitle = await _generateSequentialNoteTitle();

      // 기본 노트 데이터 생성 (첫 번째 이미지 기준)
      final now = DateTime.now();
      final noteData = {
        'userId': user.uid,
        'originalText': noteTitle, // 순차적 제목 설정
        'translatedText': '',
        'isFavorite': false,
        'flashcardCount': 0,
        'imageCount': imageFiles.length, // 이미지 개수 설정
        'flashCards': [],
        'createdAt': now,
        'updatedAt': now,
        'isProcessingBackground': true, // 백그라운드 처리 상태 설정
      };

      // 첫 번째 이미지 썸네일 URL 미리 준비 (간단한 처리만 수행)
      String? firstImageUrl;
      if (imageFiles.isNotEmpty) {
        try {
          // 간단한 썸네일만 미리 생성 (최소한의 처리)
          firstImageUrl = await _imageService.uploadAndGetUrl(imageFiles[0], forThumbnail: true);
          if (firstImageUrl != null && firstImageUrl.isNotEmpty) {
            noteData['imageUrl'] = firstImageUrl; // 첫 이미지 URL을 노트 썸네일로 설정
          }
        } catch (e) {
          debugPrint('첫 이미지 썸네일 생성 중 오류 (무시됨): $e');
        }
      }

      // Firestore에 노트 추가
      final docRef = await _notesCollection.add(noteData);
      final noteId = docRef.id;
      
      // 모든 이미지 처리는 백그라운드로 이동 (로딩 시간 단축)
      _processAllImagesInBackground(noteId, imageFiles, firstImageUrl);
      
      // 즉시 성공 결과 반환 (처리 완료를 기다리지 않음)
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
  
  // 모든 이미지를 백그라운드에서 처리 (PageService 사용)
  Future<void> _processAllImagesInBackground(String noteId, List<File> imageFiles, String? firstImageUrl) async {
    // 백그라운드 처리 상태 설정
    await _setBackgroundProcessingState(noteId, true);
    
    try {
      // 첫 번째 이미지 처리 (이미 썸네일은 생성되었을 수 있음)
      if (imageFiles.isNotEmpty) {
        final firstPageResult = await _pageService.processImageAndCreatePage(
          noteId, 
          imageFiles[0],
          pageNumber: 1,
          existingImageUrl: firstImageUrl,
        );
        
        // 첫 페이지 처리 진행 상황 업데이트
        await _updateProcessingProgress(noteId, 1, imageFiles.length);
      }
      
      // 나머지 이미지 처리 (2번째 이미지부터)
      for (int i = 1; i < imageFiles.length; i++) {
        await _pageService.processImageAndCreatePage(
          noteId, 
          imageFiles[i],
          pageNumber: i + 1,
        );
        
        // 처리 진행 상황 업데이트
        await _updateProcessingProgress(noteId, i + 1, imageFiles.length);
        
        // 짧은 지연을 통해 이전 작업이 완료되도록 보장
        await Future.delayed(const Duration(milliseconds: 100));
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
        final updateTask = _notesCollection.doc(noteId).update({
          'processedPageCount': processedCount,
          'totalPageCount': totalCount,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        
        // 명시적으로 작업 완료 대기
        await updateTask;
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
      final updateTask = _notesCollection.doc(noteId).update({
        'isProcessingBackground': false,
        'processingCompleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      // 명시적으로 작업 완료 대기
      await updateTask;
      
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

  /// 노트에 속한 플래시카드 목록 가져오기
  Future<List<FlashCard>> getFlashcardsByNoteId(String noteId) async {
    try {
      // 캐시에서 플래시카드 가져오기 시도
      final cachedFlashcards = await _cacheService.getFlashcardsByNoteId(noteId);
      if (cachedFlashcards.isNotEmpty) {
        debugPrint('✅ 캐시에서 ${cachedFlashcards.length}개의 플래시카드를 찾았습니다.');
        return cachedFlashcards;
      }
      
      // Firestore에서 플래시카드 가져오기
      debugPrint('🔄 캐시에서 플래시카드를 찾지 못해 Firestore에서 조회 시작');
      final querySnapshot = await _firestore
          .collection('flashcards')
          .where('noteId', isEqualTo: noteId)
          .orderBy('createdAt', descending: true)
          .get();
      
      // 플래시카드 변환 및 반환
      final flashcards = querySnapshot.docs
          .map((doc) => FlashCard.fromJson({...doc.data() as Map<String, dynamic>, 'id': doc.id}))
          .toList();
      
      // 캐시에 저장
      if (flashcards.isNotEmpty) {
        await _cacheService.cacheFlashcards(flashcards);
        debugPrint('✅ ${flashcards.length}개의 플래시카드를 캐시에 저장했습니다.');
      }
      
      return flashcards;
    } catch (e) {
      debugPrint('❌ 플래시카드 목록을 가져오는 중 오류 발생: $e');
      return [];
    }
  }
  
  /// 플래시카드 저장
  Future<bool> saveFlashcard(FlashCard flashcard) async {
    try {
      // Firestore에 저장
      final flashcardRef = _firestore.collection('flashcards').doc(flashcard.id);
      await flashcardRef.set(flashcard.toJson());
      
      // 캐시에 저장
      await _cacheService.cacheFlashcard(flashcard);
      
      // 노트의 플래시카드 카운트 증가
      if (flashcard.noteId != null && flashcard.noteId!.isNotEmpty) {
        // 노트 가져오기
        final noteRef = _notesCollection.doc(flashcard.noteId);
        final noteSnapshot = await noteRef.get();
        
        if (noteSnapshot.exists) {
          // 노트에서 현재 플래시카드 카운트 가져오기
          final noteData = noteSnapshot.data() as Map<String, dynamic>;
          final currentCount = noteData['flashcardCount'] ?? 0;
          
          // 카운트 1 증가
          await noteRef.update({'flashcardCount': currentCount + 1});
          debugPrint('✅ 노트 ${flashcard.noteId}의 플래시카드 카운트 업데이트: ${currentCount + 1}');
        }
      }
      
      debugPrint('✅ 플래시카드 ${flashcard.id} 저장 완료');
      return true;
    } catch (e) {
      debugPrint('❌ 플래시카드 저장 중 오류 발생: $e');
      return false;
    }
  }

  /// 순차적인 노트 제목 생성 ('노트 1', '노트 2', ...)
  Future<String> _generateSequentialNoteTitle() async {
    try {
      // 현재 사용자의 노트 수 가져오기
      final user = _auth.currentUser;
      if (user == null) {
        return '노트 1'; // 기본값
      }
      
      // 사용자의 노트 수 확인
      final snapshot = await _notesCollection
          .where('userId', isEqualTo: user.uid)
          .count()
          .get();
      
      final noteCount = snapshot.count ?? 0; // null 체크 추가
      
      // 다음 번호로 노트 제목 생성
      return '노트 ${noteCount + 1}';
    } catch (e) {
      debugPrint('순차적 노트 제목 생성 중 오류: $e');
      // 오류 발생 시 기본값 반환
      return '노트 1';
    }
  }

  /// 현재 사용자의 노트 개수 가져오기
  Future<int> getNoteCount() async {
    try {
      final User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        debugPrint('[NoteService] 사용자가 로그인되지 않음, 노트 개수 0 반환');
        return 0;
      }
      
      final String userId = currentUser.uid;
      
      // Firestore에서 사용자의 노트 개수 조회
      final snapshot = await _firestore
          .collection('notes')
          .where('userId', isEqualTo: userId)
          .count()
          .get();
      
      final count = snapshot.count ?? 0;
      
      if (kDebugMode) {
        debugPrint('[NoteService] 노트 개수 조회 결과: $count');
      }
      
      return count;
    } catch (e) {
      debugPrint('[NoteService] 노트 개수 조회 중 오류: $e');
      
      // 오류 발생 시 캐시된 노트 개수 조회 시도
      try {
        final cachedNotes = await getCachedNotes();
        return cachedNotes.length;
      } catch (_) {
        // 모든 방법 실패 시 0 반환
        return 0;
      }
    }
  }
}
