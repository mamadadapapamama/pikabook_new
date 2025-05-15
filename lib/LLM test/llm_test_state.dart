import 'package:flutter/foundation.dart';

class LLMTestState {
  final String? imagePath;
  final String ocrText;
  final String llmProcessedText;
  final bool isProcessing;
  final String? error;
  final Duration? processingTime;

  LLMTestState({
    this.imagePath,
    this.ocrText = '',
    this.llmProcessedText = '',
    this.isProcessing = false,
    this.error,
    this.processingTime,
  });

  LLMTestState copyWith({
    String? imagePath,
    String? ocrText,
    String? llmProcessedText,
    bool? isProcessing,
    String? error,
    Duration? processingTime,
  }) {
    return LLMTestState(
      imagePath: imagePath ?? this.imagePath,
      ocrText: ocrText ?? this.ocrText,
      llmProcessedText: llmProcessedText ?? this.llmProcessedText,
      isProcessing: isProcessing ?? this.isProcessing,
      error: error,
      processingTime: processingTime ?? this.processingTime,
    );
  }
}