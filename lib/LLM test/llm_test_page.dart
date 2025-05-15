import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../LLM test/llm_text_processing.dart';
import '../LLM test/llm_test_controller.dart';

class LLMTestPage extends StatelessWidget {
  const LLMTestPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => LLMTestController(
        UnifiedTextProcessingService(),
      ),
      child: const _LLMTestView(),
    );
  }
}

class _LLMTestView extends StatelessWidget {
  const _LLMTestView();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LLMTestController>();
    final state = controller.state;

    return Scaffold(
      appBar: AppBar(
        title: const Text('OCR + LLM 테스트'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.imagePath != null)
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Image.file(
                  File(state.imagePath!),
                  fit: BoxFit.contain,
                ),
              ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: state.isProcessing ? null : controller.pickImage,
              icon: const Icon(Icons.image),
              label: const Text('이미지 선택'),
            ),
            const SizedBox(height: 16),
            if (state.ocrText.isNotEmpty) ...[
              const Text('OCR 결과:', style: TextStyle(fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(state.ocrText),
              ),
              const SizedBox(height: 16),
            ],
            if (state.llmProcessedText.isNotEmpty) ...[
              const Text('LLM 처리 결과:', style: TextStyle(fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade50,
                ),
                child: Text(
                  state.llmProcessedText,
                  style: const TextStyle(height: 1.5),
                ),
              ),
            ],
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text(
                  '에러: ${state.error}',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            if (state.processingTime != null)
              Text(
                '처리 시간: ${state.processingTime!.inMilliseconds}ms',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: state.isProcessing ? null : controller.processImage,
              child: state.isProcessing
                  ? const CircularProgressIndicator()
                  : const Text('OCR + LLM 처리 시작'),
            ),
          ],
        ),
      ),
    );
  }
}
