import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/note.dart';
import '../../models/page.dart' as page_model;
import '../../services/note_service.dart';
import '../../services/page_service.dart';
import '../../services/image_service.dart';
import '../../widgets/loading_indicator.dart';

class CreateNoteScreen extends StatefulWidget {
  const CreateNoteScreen({Key? key}) : super(key: key);

  @override
  State<CreateNoteScreen> createState() => _CreateNoteScreenState();
}

class _CreateNoteScreenState extends State<CreateNoteScreen> {
  final NoteService _noteService = NoteService();
  final PageService _pageService = PageService();
  final ImageService _imageService = ImageService();

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _tagsController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  List<File> _selectedImages = [];

  @override
  void dispose() {
    _titleController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  // 갤러리에서 여러 이미지 선택
  Future<void> _pickImages() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final images = await _imageService.pickMultipleImages();

      if (images.isNotEmpty) {
        setState(() {
          _selectedImages.addAll(images);
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '이미지를 선택하는 중 오류가 발생했습니다: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 카메라로 사진 촬영
  Future<void> _takePhoto() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final image = await _imageService.takePhoto();

      if (image != null) {
        setState(() {
          _selectedImages.add(image);
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '사진을 촬영하는 중 오류가 발생했습니다: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 선택한 이미지 제거
  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  // 이미지 순서 변경
  void _reorderImages(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _selectedImages.removeAt(oldIndex);
      _selectedImages.insert(newIndex, item);
    });
  }

  // 노트 생성
  Future<void> _createNote() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('최소 한 장 이상의 이미지를 선택해주세요.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 노트 제목과 태그 가져오기
      final title = _titleController.text.trim();
      final tags = _tagsController.text.isEmpty
          ? <String>[]
          : _tagsController.text.split(',').map((tag) => tag.trim()).toList();

      // 노트 생성
      final note = await _noteService.createNote(
        title: title,
        content: '',
        tags: tags,
      );

      if (note?.id == null) {
        throw Exception('노트 생성에 실패했습니다.');
      }

      // 각 이미지에 대해 페이지 생성
      for (int i = 0; i < _selectedImages.length; i++) {
        // 여기서는 텍스트 추출 및 번역 로직이 필요합니다.
        // 현재는 임시로 빈 텍스트를 사용합니다.
        await _pageService.createPage(
          noteId: note!.id!,
          originalText: '원본 텍스트 ${i + 1}', // 실제로는 OCR로 추출한 텍스트
          translatedText: '번역된 텍스트 ${i + 1}', // 실제로는 번역 API로 번역한 텍스트
          pageNumber: i,
          imageFile: _selectedImages[i],
        );
      }

      // 성공 메시지 표시 및 이전 화면으로 돌아가기
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('노트가 성공적으로 생성되었습니다.')),
        );
        Navigator.of(context).pop(true); // 생성 성공 결과 반환
      }
    } catch (e) {
      setState(() {
        _errorMessage = '노트를 생성하는 중 오류가 발생했습니다: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('새 노트 만들기'),
        actions: [
          if (_selectedImages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _isLoading ? null : _createNote,
              tooltip: '노트 생성',
            ),
        ],
      ),
      body: _isLoading
          ? const LoadingIndicator(message: '처리 중...')
          : _buildBody(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBody() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          // 에러 메시지 표시
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(8.0),
              margin: const EdgeInsets.all(8.0),
              color: Colors.red[100],
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),

          // 노트 정보 입력 폼
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: '노트 제목',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '제목을 입력해주세요.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _tagsController,
                  decoration: const InputDecoration(
                    labelText: '태그 (쉼표로 구분)',
                    border: OutlineInputBorder(),
                    hintText: '예: 중국어, 7과, 회화',
                  ),
                ),
              ],
            ),
          ),

          // 선택된 이미지 목록
          Expanded(
            child: _selectedImages.isEmpty
                ? _buildEmptyState()
                : _buildImageList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '이미지를 선택해주세요',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _pickImages,
            icon: const Icon(Icons.photo_library),
            label: const Text('갤러리에서 선택'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _takePhoto,
            icon: const Icon(Icons.camera_alt),
            label: const Text('카메라로 촬영'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageList() {
    return ReorderableListView.builder(
      itemCount: _selectedImages.length,
      onReorder: _reorderImages,
      itemBuilder: (context, index) {
        return Card(
          key: ValueKey(_selectedImages[index].path),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            contentPadding: const EdgeInsets.all(8),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.file(
                _selectedImages[index],
                width: 60,
                height: 60,
                fit: BoxFit.cover,
              ),
            ),
            title: Text('이미지 ${index + 1}'),
            subtitle: Text(
              '${(_selectedImages[index].lengthSync() / 1024).toStringAsFixed(1)} KB',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_red_eye),
                  onPressed: () {
                    // TODO: 이미지 미리보기
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('이미지 미리보기 기능은 추후 업데이트 예정입니다.')),
                    );
                  },
                  tooltip: '미리보기',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _removeImage(index),
                  tooltip: '삭제',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return BottomAppBar(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _pickImages,
                icon: const Icon(Icons.photo_library),
                label: const Text('갤러리'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _takePhoto,
                icon: const Icon(Icons.camera_alt),
                label: const Text('카메라'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
