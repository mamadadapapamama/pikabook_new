import 'package:flutter/material.dart';
import '../models/note.dart';
import '../services/content/note_service.dart';
import '../widgets/edit_title_dialog.dart';

class NoteOptionsManager {
  final NoteService _noteService = NoteService();
  
  void showMoreOptions(BuildContext context, Note? note, {
    required Function onTitleEditing,
    required Function(bool) onFavoriteToggle,
    required Function onNoteDeleted,
  }) {
    if (note == null) return;
    
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('제목 편집'),
            onTap: () {
              Navigator.pop(context);
              _showEditTitleDialog(context, note, onTitleEditing);
            },
          ),
          ListTile(
            leading: Icon(note.isFavorite ? Icons.star : Icons.star_border),
            title: Text(note.isFavorite ? '즐겨찾기 해제' : '즐겨찾기 추가'),
            onTap: () {
              Navigator.pop(context);
              toggleFavorite(note.id!, !note.isFavorite).then((success) {
                if (success) {
                  onFavoriteToggle(!note.isFavorite);
                }
              });
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('노트 삭제', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              confirmDelete(context, note.id!, onDeleted: () {
                onNoteDeleted();
              });
            },
          ),
        ],
      ),
    );
  }
  
  void _showEditTitleDialog(BuildContext context, Note note, Function onTitleEditing) {
    showDialog(
      context: context,
      builder: (context) => EditTitleDialog(
        currentTitle: note.originalText,
        onTitleUpdated: (newTitle) {
          updateNoteTitle(note.id!, newTitle).then((success) {
            if (success) {
              onTitleEditing();
            }
          });
        },
      ),
    );
  }
  
  Future<bool> toggleFavorite(String noteId, bool isFavorite) async {
    try {
      await _noteService.toggleFavorite(noteId, isFavorite);
      return true;
    } catch (e) {
      debugPrint('즐겨찾기 토글 중 오류 발생: $e');
      return false;
    }
  }
  
  Future<bool> updateNoteTitle(String noteId, String newTitle) async {
    try {
      final note = await _noteService.getNoteById(noteId);
      if (note == null) return false;
      
      final updatedNote = note.copyWith(originalText: newTitle);
      await _noteService.updateNote(noteId, updatedNote);
      return true;
    } catch (e) {
      debugPrint('노트 제목 업데이트 중 오류 발생: $e');
      return false;
    }
  }
  
  void confirmDelete(BuildContext context, String noteId, {required Function onDeleted}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('노트 삭제'),
        content: const Text('이 노트를 정말 삭제하시겠습니까? 이 작업은 취소할 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              deleteNote(context, noteId).then((success) {
                if (success) {
                  onDeleted();
                }
              });
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }
  
  Future<bool> deleteNote(BuildContext context, String noteId) async {
    try {
      await _noteService.deleteNote(noteId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('노트가 삭제되었습니다.')),
      );
      return true;
    } catch (e) {
      debugPrint('노트 삭제 중 오류 발생: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('노트 삭제 중 오류가 발생했습니다: $e')),
      );
      return false;
    }
  }
}
