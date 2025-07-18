import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/note.dart';
import '../home_viewmodel.dart';
import '../note_list_item.dart';
import '../../note/view/note_detail_screen.dart';

/// 📝 HomeScreen 노트 리스트 위젯
/// 
/// 책임:
/// - 노트 리스트 표시
/// - 활성 배너들 표시 (노트 리스트 위에 겹쳐서)
/// - Pull-to-refresh 기능
/// - 노트 삭제 처리
class HomeNotesList extends StatelessWidget {
  final List<Widget> activeBanners;
  final Function() onRefresh;

  const HomeNotesList({
    super.key,
    required this.activeBanners,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeViewModel>(
      builder: (context, viewModel, _) {
        return Stack(
          children: [
            // 📝 노트 리스트 (전체 화면)
            RefreshIndicator(
              onRefresh: () async {
                await viewModel.refreshNotes();
                onRefresh(); // 구독 상태도 함께 새로고침
              },
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
                itemCount: viewModel.notes.length,
                itemBuilder: (context, index) {
                  final note = viewModel.notes[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: NoteListItem(
                      note: note,
                      onDismissed: () => _deleteNote(viewModel, note),
                      onNoteTapped: (selectedNote) => _navigateToNoteDetail(context, selectedNote),
                    ),
                  );
                },
              ),
            ),
            
            // 🎯 플로팅 배너들 (노트 리스트 위에 겹쳐서 표시)
            if (activeBanners.isNotEmpty)
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Column(
                  children: activeBanners,
                ),
              ),
          ],
        );
      },
    );
  }



  /// 📖 노트 상세 화면으로 이동
  void _navigateToNoteDetail(BuildContext context, Note note) {
    Navigator.push(
      context,
      NoteDetailScreenMVVM.route(note: note),
    );
  }

  /// 🗑️ 노트 삭제
  void _deleteNote(HomeViewModel viewModel, Note note) {
    viewModel.deleteNote(note.id);
  }
} 