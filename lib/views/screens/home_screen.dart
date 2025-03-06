import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../../viewmodels/home_viewmodel.dart';
import '../../widgets/note_list_item.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/loading_dialog.dart';
import '../../services/note_service.dart';
import '../../services/page_service.dart';
import '../../services/image_service.dart';
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
                    ElevatedButton.icon(
                      onPressed: () => _showImagePickerBottomSheet(context),
                      icon: const Icon(Icons.add),
                      label: const Text('새 노트 만들기'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '오른쪽 하단의 + 버튼을 눌러 새 노트를 만들 수도 있습니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey),
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

class _ImagePickerBottomSheet extends StatefulWidget {
  _ImagePickerBottomSheet({Key? key}) : super(key: key);

  @override
  State<_ImagePickerBottomSheet> createState() =>
      _ImagePickerBottomSheetState();
}

class _ImagePickerBottomSheetState extends State<_ImagePickerBottomSheet> {
  final ImageService _imageService = ImageService();
  final NoteService _noteService = NoteService();

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
    // 바텀 시트를 닫기 전에 전역 키를 사용하여 컨텍스트 저장
    final navigatorContext = Navigator.of(context).context;

    Navigator.pop(context); // 바텀 시트 닫기

    try {
      final images = await _imageService.pickMultipleImages();

      if (images.isNotEmpty) {
        // 저장된 컨텍스트를 사용하여 로딩 다이얼로그 표시
        if (navigatorContext.mounted) {
          LoadingDialog.show(navigatorContext, message: '노트 생성 중...');
          await _createNoteWithImages(navigatorContext, images);
        }
      }
    } catch (e) {
      if (navigatorContext.mounted) {
        ScaffoldMessenger.of(navigatorContext).showSnackBar(
          SnackBar(content: Text('이미지 선택 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  Future<void> _takePhotoAndCreateNote(BuildContext context) async {
    // 바텀 시트를 닫기 전에 전역 키를 사용하여 컨텍스트 저장
    final navigatorContext = Navigator.of(context).context;

    Navigator.pop(context); // 바텀 시트 닫기

    try {
      final image = await _imageService.takePhoto();

      if (image != null) {
        // 저장된 컨텍스트를 사용하여 로딩 다이얼로그 표시
        if (navigatorContext.mounted) {
          LoadingDialog.show(navigatorContext, message: '노트 생성 중...');
          await _createNoteWithImages(navigatorContext, [image]);
        }
      } else {
        // 사용자가 사진 촬영을 취소한 경우
        if (navigatorContext.mounted) {
          ScaffoldMessenger.of(navigatorContext).showSnackBar(
            const SnackBar(content: Text('사진 촬영이 취소되었습니다.')),
          );
        }
      }
    } catch (e) {
      if (navigatorContext.mounted) {
        ScaffoldMessenger.of(navigatorContext).showSnackBar(
          SnackBar(content: Text('사진 촬영 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  Future<void> _createNoteWithImages(
      BuildContext context, List<File> images) async {
    if (images.isEmpty) return;

    try {
      print("노트 생성 시작: ${images.length}개 이미지");

      // 여러 이미지로 노트 생성 (진행 상황 업데이트 무시)
      final note = await _noteService.createNoteWithMultipleImages(
        imageFiles: images,
        silentProgress: true, // 진행 상황 업데이트 무시
        progressCallback: null, // 콜백 없음
      );

      print("노트 생성 완료: ${note?.id}");

      // 다이얼로그 닫기 (먼저 실행)
      LoadingDialog.hide(context);

      // 노트 생성 완료 후 노트 상세 화면으로 이동
      if (context.mounted && note != null && note.id != null) {
        print("노트 상세 화면으로 이동 시도");

        // Provider 사용 없이 바로 노트 상세 화면으로 이동
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => NoteDetailScreen(noteId: note.id!),
          ),
        );

        print("노트 상세 화면으로 이동 완료");

        // 나중에 홈 화면으로 돌아왔을 때 노트 목록이 새로고침되도록 알림
        // (이 부분은 선택 사항)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('노트가 생성되었습니다. 홈 화면으로 돌아가면 목록이 업데이트됩니다.'),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        print("노트 생성 실패 또는 ID 없음: ${note?.id}");
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('노트 생성에 실패했습니다.')),
          );
        }
      }
    } catch (e) {
      print("노트 생성 중 오류 발생: $e");

      // 다이얼로그 닫기
      LoadingDialog.hide(context);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('노트 생성 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }
}
