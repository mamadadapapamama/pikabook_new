import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/note.dart';

class NoteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 컬렉션 참조
  CollectionReference get _notesCollection => _firestore.collection('notes');

  // 현재 사용자의 노트 컬렉션 참조
  Query get _userNotesQuery => _notesCollection
      .where('userId', isEqualTo: _auth.currentUser?.uid)
      .orderBy('updatedAt', descending: true);

  // 노트 생성
  Future<String> createNote({
    required String originalText,
    required String translatedText,
    String? imageUrl,
    List<String>? tags,
  }) async {
    try {
      // 현재 사용자 확인
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('사용자가 로그인되어 있지 않습니다.');
      }

      // 노트 데이터 생성
      final noteData = {
        'userId': user.uid,
        'originalText': originalText,
        'translatedText': translatedText,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'imageUrl': imageUrl,
        'tags': tags ?? [],
        'isFavorite': false,
        'flashCards': [],
        'pages': [],
        'extractedText': originalText,
        'flashcardCount': 0,
        'reviewCount': 0,
      };

      // Firestore에 노트 추가
      final docRef = await _notesCollection.add(noteData);
      return docRef.id;
    } catch (e) {
      throw Exception('노트 생성 중 오류가 발생했습니다: $e');
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
      print('노트 목록을 가져오는 중 오류가 발생했습니다: $e');
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
      print('노트를 가져오는 중 오류가 발생했습니다: $e');
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
        'pages': note.pages,
        'extractedText': note.extractedText,
        'flashcardCount': note.flashcardCount,
        'reviewCount': note.reviewCount,
      });
    } catch (e) {
      print('노트 업데이트 중 오류가 발생했습니다: $e');
      throw Exception('노트 업데이트 중 오류가 발생했습니다: $e');
    }
  }

  // 노트 삭제
  Future<void> deleteNote(String noteId) async {
    try {
      await _notesCollection.doc(noteId).delete();
    } catch (e) {
      print('노트 삭제 중 오류가 발생했습니다: $e');
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
      print('노트 즐겨찾기 설정 중 오류가 발생했습니다: $e');
      throw Exception('노트 즐겨찾기 설정 중 오류가 발생했습니다: $e');
    }
  }
}
