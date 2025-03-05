import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../../viewmodels/home_viewmodel.dart';
import '../../widgets/note_list_item.dart';
import '../../widgets/loading_indicator.dart';
import '../../services/note_service.dart';
import '../../services/page_service.dart';
import '../../services/image_service.dart';
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
                          onPressed: () => _showImagePickerBottomSheet(context),
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
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showImagePickerBottomSheet(context),
          tooltip: '새 노트 만들기',
          child: const Icon(Icons.add),
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

  void _showImagePickerBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _ImagePickerBottomSheet(),
    );
  }

  void _navigateToNoteDetail(BuildContext context, String noteId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => NoteDetailScreen(noteId: noteId),
      ),
    );
  }
}

class _ImagePickerBottomSheet extends StatelessWidget {
  final ImageService _imageService = ImageService();
  final NoteService _noteService = NoteService();

  _ImagePickerBottomSheet({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '새 노트 만들기',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildOptionButton(
                context,
                icon: Icons.photo_library,
                label: '갤러리에서 선택',
                onTap: () => _pickImagesAndCreateNote(context),
              ),
              _buildOptionButton(
                context,
                icon: Icons.camera_alt,
                label: '카메라로 촬영',
                onTap: () => _takePhotoAndCreateNote(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildOptionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 120,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 48, color: Theme.of(context).primaryColor),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImagesAndCreateNote(BuildContext context) async {
    Navigator.pop(context); // 바텀 시트 닫기

    try {
      final images = await _imageService.pickMultipleImages();
      if (images.isNotEmpty) {
        await _createNoteWithImages(context, images);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지 선택 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  Future<void> _takePhotoAndCreateNote(BuildContext context) async {
    Navigator.pop(context); // 바텀 시트 닫기

    try {
      final image = await _imageService.takePhoto();
      if (image != null) {
        await _createNoteWithImages(context, [image]);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('사진 촬영 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  Future<void> _createNoteWithImages(
      BuildContext context, List<File> images) async {
    if (images.isEmpty) return;

    try {
      // 로딩 표시
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('노트 생성 중...')),
        );
      }

      // 여러 이미지로 노트 생성
      final note = await _noteService.createNoteWithMultipleImages(images);

      // 성공 메시지 표시
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('노트가 성공적으로 생성되었습니다.')),
        );

        // 노트 목록 새로고침
        Provider.of<HomeViewModel>(context, listen: false).refreshNotes();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('노트 생성 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }
}
