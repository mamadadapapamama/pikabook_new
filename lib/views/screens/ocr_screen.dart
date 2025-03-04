import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/loading_indicator.dart';

class OcrScreen extends StatefulWidget {
  const OcrScreen({Key? key}) : super(key: key);

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  final ImagePicker _picker = ImagePicker();
  File? _selectedImage;
  String? _extractedText;
  String? _translatedText;
  bool _isLoading = false;
  bool _isProcessing = false;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(source: source);
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
    }
  }

  Future<void> _processImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      // TODO: OCR 서비스 연동
      // 임시 데이터
      await Future.delayed(const Duration(seconds: 2));
      setState(() {
        _extractedText = "这是一个示例文本。\n这是中文OCR的结果。";
        _translatedText = "이것은 예시 텍스트입니다.\n이것은 중국어 OCR 결과입니다.";
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
      // TODO: 노트 저장 로직 구현
      await Future.delayed(const Duration(seconds: 1));

      // 저장 성공 후 이전 화면으로 돌아가기
      if (mounted) {
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
                    onPressed: () => _pickImage(ImageSource.camera),
                    type: ButtonType.outline,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: CustomButton(
                    text: '갤러리',
                    icon: Icons.photo_library,
                    onPressed: () => _pickImage(ImageSource.gallery),
                    type: ButtonType.outline,
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
