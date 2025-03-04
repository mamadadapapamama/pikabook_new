import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../viewmodels/home_viewmodel.dart';
import '../../widgets/note_list_item.dart';
import '../../widgets/loading_indicator.dart';
import 'ocr_screen.dart';
import 'note_detail_screen.dart';
import 'create_note_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HomeViewModel(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pikabook'),
          actions: [
            IconButton(
              icon: const Icon(Icons.camera_alt),
              onPressed: () => _navigateToOcrScreen(context),
              tooltip: 'OCR 스캔',
            ),
          ],
        ),
        body: Consumer<HomeViewModel>(
          builder: (context, viewModel, child) {
            if (viewModel.isLoading) {
              return const LoadingIndicator(message: '노트 불러오는 중...');
            }

            if (viewModel.error != null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(viewModel.error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => viewModel.refreshNotes(),
                      child: const Text('다시 시도'),
                    ),
                  ],
                ),
              );
            }

            if (!viewModel.hasNotes) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.note_alt_outlined,
                        size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      '저장된 노트가 없습니다.\n새 노트를 만들어보세요!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _navigateToCreateNoteScreen(context),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('갤러리에서 선택'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton.icon(
                          onPressed: () => _navigateToOcrScreen(context),
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('카메라로 촬영'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              itemCount: viewModel.notes.length,
              itemBuilder: (context, index) {
                final note = viewModel.notes[index];
                return NoteListItem(
                  note: note,
                  onTap: () => _navigateToNoteDetail(context, note.id!),
                  onFavoriteToggle: (isFavorite) {
                    if (note.id != null) {
                      viewModel.toggleFavorite(note.id!, isFavorite);
                    }
                  },
                  onDelete: () {
                    if (note.id != null) {
                      viewModel.deleteNote(note.id!);
                    }
                  },
                );
              },
            );
          },
        ),
        floatingActionButton: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FloatingActionButton(
              heroTag: 'createNote',
              onPressed: () => _navigateToCreateNoteScreen(context),
              tooltip: '갤러리에서 이미지 선택',
              child: const Icon(Icons.photo_library),
            ),
            const SizedBox(height: 16),
            FloatingActionButton(
              heroTag: 'ocrScan',
              onPressed: () => _navigateToOcrScreen(context),
              tooltip: 'OCR 스캔',
              child: const Icon(Icons.camera_alt),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToOcrScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const OcrScreen(),
      ),
    );
  }

  void _navigateToCreateNoteScreen(BuildContext context) {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (context) => const CreateNoteScreen(),
      ),
    )
        .then((result) {
      if (result == true) {
        // 노트가 생성되었으면 목록 새로고침
        Provider.of<HomeViewModel>(context, listen: false).refreshNotes();
      }
    });
  }

  void _navigateToNoteDetail(BuildContext context, String noteId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NoteDetailScreen(noteId: noteId),
      ),
    );
  }
}
