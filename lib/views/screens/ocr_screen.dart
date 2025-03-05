import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/loading_indicator.dart';
import '../../services/google_cloud_service.dart';
import '../../services/note_service.dart';
import '../../services/image_service.dart';

class OcrScreen extends StatefulWidget {
  const OcrScreen({Key? key}) : super(key: key);

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  final ImagePicker _picker = ImagePicker();
  final GoogleCloudService _cloudService = GoogleCloudService();
  final NoteService _noteService = NoteService();
  final ImageService _imageService = ImageService();

  File? _selectedImage;
  String? _extractedText;
  String? _translatedText;
  String? _errorMessage;
  bool _isLoading = false;
  bool _isProcessing = false;
  bool _isPickingImage = false;
  // 사용자 설정에서 가져온 번역 언어 (한국어 또는 영어)
  // 실제로는 사용자 설정에서 가져와야 함
  String _targetLanguage = 'ko'; // 기본값: 한국어

  @override
  void initState() {
    super.initState();
    _loadUserPreferences();
  }

  // 사용자 설정 로드 (온보딩에서 선택한 번역 언어)
  Future<void> _loadUserPreferences() async {
    // TODO: 실제 구현에서는 SharedPreferences나 다른 저장소에서 사용자 설정을 로드
    // 예시: _targetLanguage = await UserPreferences.getTranslationLanguage() ?? 'ko';
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_isPickingImage) return;

    setState(() {
      _isPickingImage = true;
      _errorMessage = null;
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
      setState(() {
        _errorMessage = '이미지를 선택하는 중 오류가 발생했습니다: $e';
      });
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
      _errorMessage = null;
    });

    try {
      // OCR로 텍스트 추출 (중국어 원문)
      final extractedText =
          await _cloudService.extractTextFromImage(_selectedImage!);

      if (extractedText.isEmpty) {
        throw Exception('텍스트를 추출할 수 없습니다.');
      }

      // 추출된 텍스트 번역 (한국어 또는 영어로)
      final translatedText = await _cloudService.translateText(
        extractedText,
        targetLanguage: _targetLanguage,
      );

      setState(() {
        _extractedText = extractedText;
        _translatedText = translatedText;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = '이미지 처리 중 오류가 발생했습니다: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('이미지 처리 중 오류가 발생했습니다: $e')),
      );
    }
  }

  Future<void> _saveAsNote() async {
    if (_extractedText == null ||
        _translatedText == null ||
        _selectedImage == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 노트 저장 로직 구현
      final note = await _noteService.createNoteWithImage(
        _selectedImage!,
        title: '이미지 노트 ${DateTime.now().toString().substring(0, 16)}',
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
        _errorMessage = '노트 저장 중 오류가 발생했습니다: $e';
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
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    _buildErrorSection(_errorMessage!),
                  ],
                  if (_extractedText != null) ...[
                    const SizedBox(height: 16),
                    _buildTextSection('추출된 텍스트 (중국어)', _extractedText!),
                    const SizedBox(height: 16),
                    _buildTextSection(
                        '번역 (${_targetLanguage == 'ko' ? '한국어' : '영어'})',
                        _translatedText!),
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
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library),
                    label: const Text('갤러리'),
                    onPressed: _isPickingImage
                        ? null
                        : () {
                            _pickImage(ImageSource.gallery);
                          },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('카메라'),
                    onPressed: _isPickingImage
                        ? null
                        : () {
                            _pickImage(ImageSource.camera);
                          },
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
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                content,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorSection(String errorMessage) {
    return Card(
      elevation: 2,
      color: Colors.red[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red[700]),
                const SizedBox(width: 8),
                Text(
                  '오류',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage,
              style: TextStyle(color: Colors.red[700]),
            ),
          ],
        ),
      ),
    );
  }
}
