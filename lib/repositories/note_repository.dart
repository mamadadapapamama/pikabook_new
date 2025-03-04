import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pikabook_new/models/note.dart';
import 'package:pikabook_new/data/mock_data.dart';
// import 'package:pikabook_new/models/flash_card.dart';

class NoteRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'notes';

  // 메모리 내 저장소 (백업용)
  final Map<String, Note> _notes = {};

  // 생성자에서 목 데이터 로드 (Firebase 연결 실패 시 사용)
  NoteRepository() {
    final mockNotes = MockData.getNotes();
    for (final note in mockNotes) {
      _notes[note.id] = note;
    }
  }

  // 노트 생성
  Future<Note> createNote(Note note) async {
    try {
      // 새 문서 ID 생성
      final docRef = _firestore.collection(_collection).doc();

      // ID와 타임스탬프 추가
      final newNote = note.copyWith(
        id: docRef.id,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Firestore에 저장
      await docRef.set(newNote.toJson());

      return newNote;
    } catch (e) {
      print('Error creating note: $e');

      // 오류 발생 시 로컬 저장소 사용
      final newNote = note.copyWith(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      _notes[newNote.id] = newNote;
      return newNote;
    }
  }

  // 노트 조회
  Future<Note?> getNote(String id) async {
    try {
      final docSnapshot =
          await _firestore.collection(_collection).doc(id).get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data() as Map<String, dynamic>;
        data['id'] = docSnapshot.id; // ID 추가
        return Note.fromJson(data);
      }

      return null;
    } catch (e) {
      print('Error getting note: $e');

      // 오류 발생 시 로컬 저장소 사용
      return _notes[id];
    }
  }

  // 노트 목록 조회
  Future<List<Note>> getNotes() async {
    try {
      final querySnapshot = await _firestore
          .collection(_collection)
          .where('isDeleted', isEqualTo: false)
          .orderBy('updatedAt', descending: true)
          .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id; // ID 추가
        return Note.fromJson(data);
      }).toList();
    } catch (e) {
      print('Error getting notes: $e');

      // 오류 발생 시 로컬 저장소 사용
      return _notes.values.toList();
    }
  }

  // 노트 업데이트
  Future<Note> updateNote(Note note) async {
    try {
      // 업데이트 시간 갱신
      final updatedNote = note.copyWith(
        updatedAt: DateTime.now(),
      );

      // Firestore 업데이트
      await _firestore
          .collection(_collection)
          .doc(note.id)
          .update(updatedNote.toJson());

      return updatedNote;
    } catch (e) {
      print('Error updating note: $e');

      // 오류 발생 시 로컬 저장소 사용
      final updatedNote = note.copyWith(
        updatedAt: DateTime.now(),
      );

      _notes[note.id] = updatedNote;
      return updatedNote;
    }
  }

  // 노트 삭제 (소프트 삭제)
  Future<void> deleteNote(String id) async {
    try {
      // 소프트 삭제 (isDeleted 플래그 설정)
      await _firestore
          .collection(_collection)
          .doc(id)
          .update({'isDeleted': true});
    } catch (e) {
      print('Error deleting note: $e');

      // 오류 발생 시 로컬 저장소 사용
      if (_notes.containsKey(id)) {
        final note = _notes[id]!;
        _notes[id] = note.copyWith(isDeleted: true);
      }
    }
  }

  // 노트 영구 삭제
  Future<void> permanentlyDeleteNote(String id) async {
    try {
      await _firestore.collection(_collection).doc(id).delete();

      // 로컬 저장소에서도 삭제
      _notes.remove(id);
    } catch (e) {
      print('Error permanently deleting note: $e');

      // 오류 발생 시 로컬 저장소만 삭제
      _notes.remove(id);
    }
  }
}
