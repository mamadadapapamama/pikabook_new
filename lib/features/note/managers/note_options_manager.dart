import 'package:flutter/material.dart';
import '../../../core/models/note.dart';
import '../../../core/services/content/note_service.dart';
import '../../../core/services/cache/unified_cache_service.dart';
import '../../../core/widgets/edit_title_dialog.dart';
import '../../../core/widgets/delete_note_dialog.dart';
import '../view/note_action_bottom_sheet.dart';

// 노트 상세 화면의 옵션 메뉴 관리. 제목 편집, 삭제
class NoteOptionsManager {
  final NoteService _noteService = NoteService();
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  
  void showMoreOptions(BuildContext context, Note? note, {
    required Function onTitleEditing,
    required Function onNoteDeleted,
  }) {
    if (note == null) return;
    
    // NoteActionBottomSheet 위젯 사용
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NoteActionBottomSheet(
        onEditTitle: () {
          _showEditTitleDialog(context, note, onTitleEditing);
        },
        onDeleteNote: () {
          confirmDelete(context, note.id, onDeleted: onNoteDeleted);
        },
        onToggleFullTextMode: () {
          // 사용하지 않음
        },
        isFullTextMode: false, // 사용하지 않음
      ),
    );
  }
  
  void _showEditTitleDialog(BuildContext context, Note note, Function onTitleEditing) {
    showDialog(
      context: context,
      builder: (context) => EditTitleDialog(
        currentTitle: note.title,
        onTitleUpdated: (newTitle) {
          updateNoteTitle(note.id, newTitle).then((success) {
            if (success) {
              onTitleEditing();
            }
          });
        },
      ),
    );
  }
  
  Future<bool> updateNoteTitle(String noteId, String newTitle) async {
    try {
      final note = await _noteService.getNoteById(noteId);
      if (note == null) return false;
      
      final updatedNote = note.copyWith(title: newTitle);
      await _noteService.updateNote(noteId, updatedNote);
      
      // 캐시 업데이트 - 노트 제목 변경 후 캐시도 갱신
      await _clearRelatedCache(noteId);
      
      return true;
    } catch (e) {
      debugPrint('노트 제목 업데이트 중 오류 발생: $e');
      return false;
    }
  }
  
  void confirmDelete(BuildContext context, String noteId, {required Function onDeleted}) {
    // DeleteNoteDialog 위젯 사용
    showDialog(
      context: context,
      builder: (context) => DeleteNoteDialog(
        onConfirm: () {
          deleteNote(context, noteId).then((success) {
            if (success) {
              onDeleted();
            }
          });
        },
      ),
    );
  }
  
  Future<bool> deleteNote(BuildContext context, String noteId) async {
    try {
      // 노트 삭제 전에 관련 캐시 정리
      await _clearRelatedCache(noteId);
      
      // 노트 삭제
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
  
  // 노트 관련 캐시 정리
  Future<void> _clearRelatedCache(String noteId) async {
    try {
      // 플래시카드 캐시 정리
      await _cacheService.clearFlashcardCache(noteId);
      
      // 노트와 관련된 다른 캐시도 필요하다면 여기에 추가
      debugPrint('노트 관련 캐시 정리 완료: $noteId');
    } catch (e) {
      debugPrint('캐시 정리 중 오류 발생: $e');
    }
  }
}
