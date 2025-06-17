import 'package:flutter/material.dart';
import '../../../core/models/note.dart';
import '../../../core/utils/error_handler.dart';
import '../services/note_service.dart';
import '../../../core/services/cache/cache_manager.dart';
import '../../../core/widgets/edit_dialog.dart';
import '../../../core/widgets/delete_note_dialog.dart';
import '../view/note_action_bottom_sheet.dart';

// 노트 상세 화면의 옵션 메뉴 관리. 제목 편집, 삭제
class NoteOptionsManager {
  final NoteService _noteService = NoteService();
  final CacheManager _cacheManager = CacheManager();
  
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
      builder: (context) => EditDialog.forNoteTitle(
        currentTitle: note.title,
        onTitleUpdated: (newTitle) async {
          onTitleEditing();
          
          try {
            final updatedNote = note.copyWith(title: newTitle);
            await _noteService.updateNote(note.id!, updatedNote);
          } catch (e) {
            print('노트 제목 업데이트 오류: $e');
          }
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
      
      ErrorHandler.showSuccessSnackBar(context, '노트가 삭제되었습니다');
      return true;
    } catch (e) {
      debugPrint('노트 삭제 중 오류 발생: $e');
      ErrorHandler.showErrorSnackBar(context, e, ErrorContext.noteDelete);
      return false;
    }
  }
  
  // 노트 관련 캐시 정리
  Future<void> _clearRelatedCache(String noteId) async {
    try {
      // 노트의 모든 캐시 정리 (플래시카드 포함)
      await _cacheManager.clearNoteCache(noteId);
      
      debugPrint('노트 관련 캐시 정리 완료: $noteId');
    } catch (e) {
      debugPrint('캐시 정리 중 오류 발생: $e');
    }
  }
}
