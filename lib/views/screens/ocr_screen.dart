import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/loading_indicator.dart';
import '../../services/google_cloud_service.dart';
import '../../services/note_service.dart';

class OcrScreen extends StatefulWidget {
  const OcrScreen({Key? key}) : super(key: key);

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  final ImagePicker _picker = ImagePicker();
  final GoogleCloudService _cloudService = GoogleCloudService();
  final NoteService _noteService = NoteService();

  File? _selectedImage;
  String? _extractedText;
  String? _translatedText;
  bool _isLoading = false;
  bool _isProcessing = false;
  bool _isPickingImage = false;

  Future<void> _pickImage(ImageSource source) async {
    if (_isPickingImage) return;

    setState(() {
      _isPickingImage = true;
    });

    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 70,
        maxWidth: 1000,
        maxHeight: 1000,
      );

      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
          _extractedText = null;
          _translatedText = null;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('이미지를 선택하는 중 오류가 발생했습니다: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPickingImage = false;
        });
      }
    }
  }

  Future<void> _processImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final extractedText =
          await _cloudService.extractTextFromImage(_selectedImage!);

      if (extractedText.isEmpty) {
        throw Exception('텍스트를 추출할 수 없습니다.');
      }

      final translatedText = await _cloudService.translateText(extractedText);

      setState(() {
        _extractedText = extractedText;
        _translatedText = translatedText;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('이미지 처리 중 오류가 발생했습니다: $e')),
      );
    }
  }

  Future<void> _saveAsNote() async {
    if (_extractedText == null || _translatedText == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // 노트 저장 로직 구현
      final noteId = await _noteService.createNote(
        originalText: _extractedText!,
        translatedText: _translatedText!,
        imageUrl: _selectedImage?.path,
      );

      // 저장 성공 메시지 표시
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('노트가 성공적으로 저장되었습니다.')),
        );

        // 이전 화면으로 돌아가기
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('노트 저장 중 오류가 발생했습니다: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('이미지 텍스트 인식'),
        actions: [
          if (_extractedText != null)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _isLoading ? null : _saveAsNote,
              tooltip: '노트로 저장',
            ),
        ],
      ),
      body: _isLoading
          ? const LoadingIndicator(message: '저장 중...')
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildImageSection(),
                  const SizedBox(height: 16),
                  if (_selectedImage != null && _extractedText == null)
                    CustomButton(
                      text: '텍스트 인식하기',
                      onPressed: _isProcessing
                          ? null
                          : () {
                              _processImage();
                            },
                      isLoading: _isProcessing,
                    ),
                  if (_extractedText != null) ...[
                    const SizedBox(height: 16),
                    _buildTextSection('추출된 텍스트 (중국어)', _extractedText!),
                    const SizedBox(height: 16),
                    _buildTextSection('번역 (한국어)', _translatedText!),
                    const SizedBox(height: 24),
                    CustomButton(
                      text: '노트로 저장하기',
                      onPressed: () {
                        _saveAsNote();
                      },
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildImageSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '이미지 선택',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (_selectedImage != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  _selectedImage!,
                  height: 200,
                  fit: BoxFit.cover,
                  cacheHeight: 400,
                  cacheWidth: 400,
                  frameBuilder:
                      (context, child, frame, wasSynchronouslyLoaded) {
                    if (frame == null) {
                      return Container(
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    return child;
                  },
                ),
              )
            else
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text('이미지를 선택해주세요'),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Expanded(
                  child: CustomButton(
                    text: '카메라',
                    icon: Icons.camera_alt,
                    onPressed: _isPickingImage
                        ? null
                        : () => _pickImage(ImageSource.camera),
                    type: ButtonType.outline,
                    isLoading: _isPickingImage && _selectedImage == null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: CustomButton(
                    text: '갤러리',
                    icon: Icons.photo_library,
                    onPressed: _isPickingImage
                        ? null
                        : () => _pickImage(ImageSource.gallery),
                    type: ButtonType.outline,
                    isLoading: _isPickingImage && _selectedImage == null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextSection(String title, String content) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                IconButton(
                  icon: const Icon(Icons.volume_up, size: 20),
                  onPressed: () {
                    // TODO: TTS 기능 구현
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('TTS 기능은 아직 준비 중입니다.')),
                    );
                  },
                  tooltip: '소리 듣기',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                content,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
