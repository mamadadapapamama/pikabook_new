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
import '../cache/note_cache_service.dart';
import 'page_service.dart';
import '../media/image_service.dart';
import '../text_processing/enhanced_ocr_service.dart';
import '../common/usage_limit_service.dart';
import '../text_processing/llm_text_processing.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// 노트 서비스: 노트 메타데이터 관리만 담당합니다. (Note CRUD)
class NoteService {
  // 서비스 인스턴스
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final PageService _pageService = PageService();
  final ImageService _imageService = ImageService();
  final LLMTextProcessing _textProcessingService = LLMTextProcessing();
  final EnhancedOcrService _ocrService = EnhancedOcrService();
  final UsageLimitService _usageLimitService = UsageLimitService();
  final NoteCacheService _cacheService = NoteCacheService();

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
        
        // 스트림에서 로드된 노트를 자동으로 캐시 (NoteCacheService 사용)
        _cacheService.cacheNotes(notes);
        
        return notes;
      });
    } catch (e) {
      debugPrint('[NoteService] getNotes 메서드에서 오류 발생: $e');
      return Stream.value([]);
    }
  }

  /// 노트 생성
  Future<String> createNote({
    required String title,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다.');
      }

      final now = DateTime.now();
      final noteData = {
        'title': title,
        'createdAt': now,
        'updatedAt': now,
        'userId': user.uid,
        'isFavorite': false,
        'flashcardCount': 0,
      };

      final docRef = await _notesCollection.add(noteData);
      return docRef.id;
    } catch (e) {
      debugPrint('노트 생성 중 오류 발생: $e');
      rethrow;
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
      debugPrint('즐겨찾기 상태 변경 완료: $noteId -> $isFavorite');
    } catch (e) {
      debugPrint('즐겨찾기 토글 중 오류 발생: $e');
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
  
  /// 캐시된 노트 목록 가져오기 (NoteCacheService로 위임)
  Future<List<Note>> getCachedNotes() async {
    return _cacheService.getCachedNotes();
  }
  
  /// 마지막 캐시 시간 조회 (NoteCacheService로 위임)
  Future<DateTime?> getLastCacheTime() async {
    return _cacheService.getLastCacheTime();
  }
}
