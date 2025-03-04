import 'package:flutter/material.dart';
import '../models/note.dart';
import '../services/note_service.dart';

class HomeViewModel extends ChangeNotifier {
  final NoteService _noteService = NoteService();

  List<Note> _notes = [];
  bool _isLoading = true;
  String? _error;

  List<Note> get notes => _notes;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasNotes => _notes.isNotEmpty;

  // 생성자에서 노트 목록을 불러옵니다.
  HomeViewModel() {
    _loadNotes();
  }

  // 노트 목록을 불러오는 메서드
  void _loadNotes() {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      print('노트 목록 불러오기 시작');
      // Firestore에서 노트 목록을 스트림으로 구독합니다.
      _noteService.getNotes().listen((notesList) {
        print('노트 목록 수신: ${notesList.length}개');
        _notes = notesList;
        _isLoading = false;
        _error = null;
        notifyListeners();
      }, onError: (e) {
        print('노트 목록 스트림 오류: $e');
        _isLoading = false;
        _error = '노트 목록을 불러오는 중 오류가 발생했습니다: $e';
        notifyListeners();
      });
    } catch (e) {
      print('노트 목록 불러오기 오류: $e');
      _isLoading = false;
      _error = '노트 목록을 불러오는 중 오류가 발생했습니다: $e';
      notifyListeners();
    }
  }

  // 노트 목록 다시 불러오기
  void refreshNotes() {
    _loadNotes();
  }

  // 노트 즐겨찾기 토글 메서드
  Future<void> toggleFavorite(String noteId, bool isFavorite) async {
    try {
      await _noteService.toggleFavorite(noteId, isFavorite);
    } catch (e) {
      print('즐겨찾기 설정 오류: $e');
      _error = '즐겨찾기 설정 중 오류가 발생했습니다: $e';
      notifyListeners();
    }
  }

  // 노트 삭제 메서드
  Future<void> deleteNote(String noteId) async {
    try {
      await _noteService.deleteNote(noteId);
    } catch (e) {
      print('노트 삭제 오류: $e');
      _error = '노트 삭제 중 오류가 발생했습니다: $e';
      notifyListeners();
    }
  }
}
