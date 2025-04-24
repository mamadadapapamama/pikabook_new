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
import '../text_processing/translation_service.dart';
import '../storage/unified_cache_service.dart';
import '../text_processing/enhanced_ocr_service.dart';
import '../common/usage_limit_service.dart';
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
  Future<Note> createNote(String title, File? imageFile) async {
    try {
      // 현재 사용자 확인
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다.');
      }

      // 기본 노트 데이터 생성
      final now = DateTime.now();
      
      // 빈 제목이거나 '새 노트'인 경우 순차적 이름 부여
      String noteTitle = title;
      if (title.isEmpty || title == '새 노트') {
        noteTitle = await _generateSequentialNoteTitle();
      }
      
      final noteData = {
        'userId': user.uid,
        'originalText': noteTitle,
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

      // 생성된 노트 가져오기
      final docSnapshot = await docRef.get();
      final note = Note.fromFirestore(docSnapshot);

      // 노트 캐싱
      await _cacheService.cacheNote(note);

      // 이미지가 있는 경우, 페이지 생성을 PageService에 위임해야 함을 명시
      if (imageFile != null) {
        debugPrint('노트 생성: 이미지 처리는 PageService 또는 ContentManager에서 처리해야 합니다.');
      }

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
  
  // 주의: 노트의 첫 페이지 정보 업데이트는 ContentManager나 Workflow에서 처리해야 합니다.
  // 아래 메서드는 임시로 남겨두지만, 추후 제거 예정
  Future<void> _updateNoteFirstPageInfo(String noteId, String imageUrl, String originalText, String translatedText) async {
    debugPrint('⚠️ 경고: _updateNoteFirstPageInfo 메서드는 ContentManager나 Workflow로 이동해야 합니다.');
    
    try {
      // 노트 기본 정보만 업데이트
      final Map<String, dynamic> updateData = {
        'imageUrl': imageUrl,
        'updatedAt': DateTime.now(),
      };
      
      if (originalText != '___PROCESSING___') {
        updateData['extractedText'] = originalText;
      }
      
      if (translatedText.isNotEmpty) {
        updateData['translatedText'] = translatedText;
      }
      
      await _notesCollection.doc(noteId).update(updateData);
      await _cacheService.removeCachedNote(noteId); // 캐시 갱신을 위해 제거
    } catch (e) {
      debugPrint('노트 첫 페이지 정보 업데이트 중 오류: $e');
    }
  }
  
  // 기타 복잡한 오케스트레이션 메서드들은 제거하고, ContentManager나 Workflow에서 처리하도록 리팩토링
}
