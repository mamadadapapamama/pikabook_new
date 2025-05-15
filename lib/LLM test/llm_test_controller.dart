import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'llm_text_processing.dart';
import '../core/services/text_processing/enhanced_ocr_service.dart';
import '../core/services/text_processing/text_cleaner_service.dart';
import 'llm_test_state.dart';
import '../core/models/chinese_text.dart';

class LLMTestController extends ChangeNotifier {
  final UnifiedTextProcessingService _processingService;
  final ImagePicker _imagePicker = ImagePicker();
  LLMTestState _state = LLMTestState();

  LLMTestController(this._processingService);

  LLMTestState get state => _state;

  Future<void> pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        _state = _state.copyWith(
          imagePath: image.path,
          error: null,
        );
        notifyListeners();
      }
    } catch (e) {
      _state = _state.copyWith(error: '이미지 선택 중 오류 발생: $e');
      notifyListeners();
    }
  }

  Future<void> processImage() async {
    if (_state.imagePath == null) {
      _state = _state.copyWith(error: '이미지를 먼저 선택해주세요.');
      notifyListeners();
      return;
    }

    _state = _state.copyWith(
      isProcessing: true,
      error: null,
      processingTime: null,
    );
    notifyListeners();

    final stopwatch = Stopwatch()..start();

    try {
      // OCR 처리
      final ocrResult = await EnhancedOcrService().extractText(File(_state.imagePath!));
      debugPrint('OCR 결과: ' + ocrResult);
      // 텍스트 클리너로 정제
      final cleanedText = TextCleanerService().cleanText(ocrResult);
      _state = _state.copyWith(ocrText: cleanedText);
      notifyListeners();

      // LLM 처리
      final llmResult = await _processingService.processWithLLM(cleanedText);
      stopwatch.stop();

      // ChineseText 객체를 사람이 읽을 수 있는 형태로 변환
      final formattedText = _formatChineseText(llmResult);

      _state = _state.copyWith(
        llmProcessedText: formattedText,
        isProcessing: false,
        processingTime: stopwatch.elapsed,
      );
    } catch (e) {
      _state = _state.copyWith(
        isProcessing: false,
        error: e.toString(),
      );
    }

    notifyListeners();
  }

  // ChineseText 객체를 읽기 쉬운 형태의 문자열로 변환
  String _formatChineseText(ChineseText chineseText) {
    if (chineseText.sentences.isEmpty) {
      return "처리된 결과가 없습니다.";
    }

    final StringBuffer buffer = StringBuffer();
    buffer.writeln("원본 텍스트: ${chineseText.originalText}");
    buffer.writeln("\n처리된 문장들:");

    for (int i = 0; i < chineseText.sentences.length; i++) {
      final sentence = chineseText.sentences[i];
      buffer.writeln("\n--- 문장 ${i+1} ---");
      buffer.writeln("중국어: ${sentence.original}");
      buffer.writeln("병음: ${sentence.pinyin}");
      buffer.writeln("번역: ${sentence.translation}");
    }

    return buffer.toString();
  }
}
