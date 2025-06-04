import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../core/models/note.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../core/models/flash_card.dart';
import '../../../core/services/cache/cache_manager.dart';
import 'page_service.dart';
import '../../../core/services/media/image_service.dart';
import '../../../core/services/text_processing/ocr_service.dart';
import '../../../core/services/common/usage_limit_service.dart';
import '../../../core/services/text_processing/llm_text_processing.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// 노트 서비스: 노트 메타데이터 관리만 담당합니다. (Note CRUD)

class NoteService {
  // 서비스 인스턴스
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PageService _pageService = PageService(); // 싱글톤 사용
  final ImageService _imageService = ImageService();
  final LLMTextProcessing _textProcessingService = LLMTextProcessing();
  final OcrService _ocrService = OcrService();
  final UsageLimitService _usageLimitService = UsageLimitService();
  final CacheManager _cacheService = CacheManager();

  // PageService의 게터
  PageService get pageService => _pageService;

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

      if (lastNote != null && lastNote.createdAt != null) {
        query = query.startAfter([lastNote.createdAt]);
      }

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
    
    final User? currentUser = _auth.currentUser;
    if (currentUser == null) {
      debugPrint('[NoteService] 사용자가 로그인되지 않음, 빈 노트 목록 반환');
      return Stream.value([]);
    }
    
    final String userId = currentUser.uid;
    debugPrint('[NoteService] 사용자 ID: $userId로 노트 조회 시작');
    
    try {
      return _userNotesQuery.snapshots().map((snapshot) {
        final List<Note> notes = snapshot.docs.map((doc) {
          try {
            return Note.fromFirestore(doc);
          } catch (e) {
            debugPrint('[NoteService] 노트 변환 중 오류 (docId: ${doc.id}): $e');
            return Note(
              id: doc.id,
              userId: userId,
              title: '오류 발생한 노트',
              description: '오류가 발생한 노트입니다.',
            );
          }
        }).toList();
        
        debugPrint('[NoteService] 노트 ${notes.length}개 로드됨');
        
        // 자동 캐싱 제거 - 필요한 경우에만 수동으로 캐싱
        // _cacheService.cacheNotes(notes);
        
        return notes;
      });
    } catch (e) {
      debugPrint('[NoteService] getNotes 메서드에서 오류 발생: $e');
      return Stream.value([]);
    }
  }

  /// 노트 생성
  Future<String> createNote({
    String? title,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다.');
      }
      
      // 제목이 null이거나 '새 노트'인 경우, 새로운 제목 생성
      String noteTitle = title ?? '새 노트';
      if (title == null || title == '새 노트') {
        // 사용자의 노트 수 조회
        final noteCount = await _getUserNoteCount();
        // 노트 번호는 현재 노트 수 + 1
        noteTitle = '노트 ${noteCount + 1}';
      }
      
      final now = DateTime.now();
      final noteData = {
        'title': noteTitle,
        'createdAt': now,
        'updatedAt': now,
        'userId': user.uid,
        'isFavorite': false,
        'flashcardCount': 0,
      };

      final docRef = await _notesCollection.add(noteData);
      final noteId = docRef.id;
      
      // 생성된 노트를 캐시에 추가
      final newNote = Note(
        id: noteId,
        userId: user.uid,
        title: noteTitle,
        createdAt: now,
        updatedAt: now,
        isFavorite: false,
        flashcardCount: 0,
      );
      await _cacheService.addNoteToCache(newNote);
      
      if (kDebugMode) {
        debugPrint('노트 메타데이터 생성 완료: $noteId');
      }
      
      return noteId;
    } catch (e) {
      debugPrint('노트 생성 중 오류 발생: $e');
      rethrow;
    }
  }

  /// 사용자의 현재 노트 수 가져오기
  Future<int> _getUserNoteCount() async {
    try {
      final snapshot = await _userNotesQuery.get();
      return snapshot.docs.length;
    } catch (e) {
      debugPrint('노트 수 가져오기 중 오류 발생: $e');
      return 0; // 오류 발생 시 0 반환
    }
  }

  /// 노트 업데이트
  Future<void> updateNote(String noteId, Note updatedNote) async {
    try {
      final Map<String, dynamic> updateData = {
        'title': updatedNote.title,
        'isFavorite': updatedNote.isFavorite,
        'flashcardCount': updatedNote.flashcardCount,
        'updatedAt': DateTime.now(),
      };

      await _notesCollection.doc(noteId).update(updateData);
      debugPrint('노트 업데이트 완료: $noteId');
    } catch (e) {
      debugPrint('노트 업데이트 중 오류 발생: $e');
      rethrow;
    }
  }

  /// 노트 삭제
  Future<void> deleteNote(String noteId) async {
    try {
      await _notesCollection.doc(noteId).delete();
      debugPrint('노트 삭제 완료: $noteId');
      
      // 캐시에서 노트 제거
      await _cacheService.removeNoteFromCache(noteId);
    } catch (e) {
      debugPrint('노트 삭제 중 오류 발생: $e');
      rethrow;
    }
  }

  /// 노트 ID로 노트 가져오기
  Future<Note?> getNoteById(String noteId) async {
    try {
      final docSnapshot = await _notesCollection.doc(noteId).get();
      if (!docSnapshot.exists) {
        return null;
      }
      return Note.fromFirestore(docSnapshot);
    } catch (e) {
      debugPrint('노트 조회 중 오류 발생: $e');
      return null;
    }
  }

  /// 노트의 첫 페이지 이미지를 썸네일로 업데이트
  Future<bool> updateNoteThumbnail(String noteId) async {
    try {
      // 노트의 첫 페이지 가져오기
      final pagesSnapshot = await _firestore
          .collection('pages')
          .where('noteId', isEqualTo: noteId)
          .orderBy('pageNumber')
          .limit(1)
          .get();
      
      if (pagesSnapshot.docs.isEmpty) {
        if (kDebugMode) {
          debugPrint('노트에 페이지가 없습니다: $noteId');
        }
        return false;
      }
      
      final firstPage = page_model.Page.fromFirestore(pagesSnapshot.docs.first);
      if (firstPage.imageUrl == null || firstPage.imageUrl!.isEmpty) {
        if (kDebugMode) {
          debugPrint('첫 페이지에 이미지가 없습니다: ${firstPage.id}');
        }
        return false;
      }
      
      // 이미지가 상대 경로인 경우 Firebase URL로 변환
      String imageUrl = firstPage.imageUrl!;
      if (!imageUrl.startsWith('http')) {
        try {
          imageUrl = await _imageService.getImageUrl(imageUrl);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('이미지 URL 변환 실패: $e');
          }
          // 원래 URL 사용
        }
      }
      
      // 노트 업데이트
      await _notesCollection.doc(noteId).update({
        'firstImageUrl': imageUrl,
        'updatedAt': DateTime.now(),
      });
      
      if (kDebugMode) {
        debugPrint('노트 썸네일 업데이트 완료: $noteId -> $imageUrl');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('노트 썸네일 업데이트 실패: $e');
      }
      return false;
    }
  }
  
  /// 모든 노트의 썸네일 업데이트 (한 번에 처리)
  Future<int> updateAllNoteThumbnails() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다.');
      }
      
      // 모든 노트 가져오기
      final notesSnapshot = await _notesCollection
          .where('userId', isEqualTo: user.uid)
          .get();
      
      int successCount = 0;
      
      // 각 노트의 썸네일 업데이트
      for (final doc in notesSnapshot.docs) {
        final noteId = doc.id;
        final success = await updateNoteThumbnail(noteId);
        if (success) successCount++;
      }
      
      if (kDebugMode) {
        debugPrint('모든 노트 썸네일 업데이트 완료: $successCount/${notesSnapshot.docs.length}');
      }
      
      return successCount;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('모든 노트 썸네일 업데이트 실패: $e');
      }
      return 0;
    }
  }

  /// 현재 사용자의 노트 개수 가져오기
  Future<int> getNoteCount() async {
    try {
      final User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        return 0;
      }
      
      final snapshot = await _notesCollection
          .where('userId', isEqualTo: currentUser.uid)
          .count()
          .get();
      
      return snapshot.count ?? 0;
    } catch (e) {
      debugPrint('노트 개수 조회 중 오류: $e');
        return 0;
    }
  }
  
  /// 캐시된 노트 목록 가져오기
  Future<List<Note>> getCachedNotes() async {
    return _cacheService.getCachedNotes();
  }
  
  /// 마지막 캐시 시간 조회
  Future<DateTime?> getLastCacheTime() async {
    return _cacheService.getLastCacheTime();
  }
}
