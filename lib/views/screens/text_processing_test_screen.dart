import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/processed_text.dart';
import '../../models/text_processing_mode.dart';
import '../../models/text_segment.dart';
import '../../services/enhanced_ocr_service.dart';
import '../../services/tts_service.dart';
import '../../widgets/processed_text_widget.dart';

/// 텍스트 처리 테스트 화면
class TextProcessingTestScreen extends StatefulWidget {
  const TextProcessingTestScreen({Key? key}) : super(key: key);

  @override
  State<TextProcessingTestScreen> createState() =>
      _TextProcessingTestScreenState();
}

class _TextProcessingTestScreenState extends State<TextProcessingTestScreen> {
  // 서비스
  final EnhancedOcrService _ocrService = EnhancedOcrService();
  final TtsService _ttsService = TtsService();

  // 상태 변수
  TextProcessingMode _mode = TextProcessingMode.languageLearning;
  bool _isProcessing = false;
  ProcessedText? _processedText;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _ttsService.init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('텍스트 처리 테스트'),
        actions: [
          // 모드 전환 버튼
          IconButton(
            icon: Icon(_mode == TextProcessingMode.professionalReading
                ? Icons.menu_book
                : Icons.school),
            onPressed: _toggleMode,
            tooltip: _mode == TextProcessingMode.professionalReading
                ? '전문 서적 모드'
                : '언어 학습 모드',
          ),
          // 더미 데이터 버튼
          IconButton(
            icon: const Icon(Icons.data_array),
            onPressed: _loadDummyData,
            tooltip: '더미 데이터 로드',
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickImage,
        child: const Icon(Icons.camera_alt),
        tooltip: '이미지 선택',
      ),
    );
  }

  /// 화면 본문 구성
  Widget _buildBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 현재 모드 표시
          _buildModeIndicator(),

          const SizedBox(height: 16),

          // 처리 중 표시
          if (_isProcessing)
            const Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('텍스트 처리 중...'),
                ],
              ),
            )

          // 오류 메시지 표시
          else if (_errorMessage != null)
            Center(
              child: Column(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.red,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )

          // 처리된 텍스트 표시
          else if (_processedText != null)
            ProcessedTextWidget(
              processedText: _processedText!,
              onTts: _speakText,
              onDictionaryLookup: _lookupDictionary,
              onCreateFlashCard: _createFlashCard,
            )

          // 안내 메시지 표시
          else
            Center(
              child: Column(
                children: [
                  Icon(
                    _mode == TextProcessingMode.professionalReading
                        ? Icons.menu_book
                        : Icons.school,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _mode == TextProcessingMode.professionalReading
                        ? '전문 서적 모드: 전체 텍스트 번역'
                        : '언어 학습 모드: 문장별 번역 및 핀인',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '이미지를 선택하여 텍스트를 추출하세요.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 현재 모드 표시 위젯
  Widget _buildModeIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: _mode == TextProcessingMode.professionalReading
            ? Colors.blue.shade100
            : Colors.green.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _mode == TextProcessingMode.professionalReading
                ? Icons.menu_book
                : Icons.school,
            size: 18,
            color: _mode == TextProcessingMode.professionalReading
                ? Colors.blue.shade800
                : Colors.green.shade800,
          ),
          const SizedBox(width: 8),
          Text(
            _mode == TextProcessingMode.professionalReading
                ? '전문 서적 모드'
                : '언어 학습 모드',
            style: TextStyle(
              color: _mode == TextProcessingMode.professionalReading
                  ? Colors.blue.shade800
                  : Colors.green.shade800,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 모드 전환
  void _toggleMode() {
    setState(() {
      _mode = _mode == TextProcessingMode.professionalReading
          ? TextProcessingMode.languageLearning
          : TextProcessingMode.professionalReading;
    });
  }

  /// 이미지 선택
  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile == null) return;

      setState(() {
        _isProcessing = true;
        _errorMessage = null;
      });

      // 이미지 처리
      final imageFile = File(pickedFile.path);
      final processedText = await _ocrService.processImage(imageFile, _mode);

      setState(() {
        _processedText = processedText;
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '텍스트 처리 중 오류가 발생했습니다: $e';
        _isProcessing = false;
      });
    }
  }

  /// TTS로 텍스트 읽기
  void _speakText(String text) {
    _ttsService.speak(text);
  }

  /// 사전 검색
  void _lookupDictionary(String word) {
    // TODO: 사전 검색 구현
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('사전 검색: $word')),
    );
  }

  /// 플래시카드 생성
  void _createFlashCard(String word, String meaning) {
    // TODO: 플래시카드 생성 구현
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('플래시카드 생성: $word - $meaning')),
    );
  }

  /// 테스트용 더미 데이터 생성
  ProcessedText _createDummyData() {
    if (_mode == TextProcessingMode.professionalReading) {
      return ProcessedText(
        fullOriginalText: '这是一个测试文本。这是中文的示例。我喜欢学习中文，因为它很有趣。',
        fullTranslatedText:
            '이것은 테스트 텍스트입니다. 이것은 중국어 예시입니다. 나는 중국어 공부를 좋아합니다, 왜냐하면 재미있기 때문입니다.',
        showFullText: true,
      );
    } else {
      return ProcessedText(
        fullOriginalText: '这是一个测试文本。这是中文的示例。我喜欢学习中文，因为它很有趣。',
        fullTranslatedText:
            '이것은 테스트 텍스트입니다. 이것은 중국어 예시입니다. 나는 중국어 공부를 좋아합니다, 왜냐하면 재미있기 때문입니다.',
        segments: [
          TextSegment(
            originalText: '这是一个测试文本。',
            pinyin: 'zhè shì yī gè cè shì wén běn.',
            translatedText: '이것은 테스트 텍스트입니다.',
          ),
          TextSegment(
            originalText: '这是中文的示例。',
            pinyin: 'zhè shì zhōng wén de shì lì.',
            translatedText: '이것은 중국어 예시입니다.',
          ),
          TextSegment(
            originalText: '我喜欢学习中文，',
            pinyin: 'wǒ xǐ huān xué xí zhōng wén,',
            translatedText: '나는 중국어 공부를 좋아합니다,',
          ),
          TextSegment(
            originalText: '因为它很有趣。',
            pinyin: 'yīn wèi tā hěn yǒu qù.',
            translatedText: '왜냐하면 재미있기 때문입니다.',
          ),
        ],
        showFullText: false,
      );
    }
  }

  /// 더미 데이터 로드
  void _loadDummyData() {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    // 잠시 지연 후 더미 데이터 로드 (로딩 효과를 위해)
    Future.delayed(const Duration(seconds: 1), () {
      setState(() {
        _processedText = _createDummyData();
        _isProcessing = false;
      });
    });
  }
}
