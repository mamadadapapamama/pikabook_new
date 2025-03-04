import 'package:flutter/material.dart';
import 'ocr_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '환영합니다! Pikabook에서 중국어 학습을 시작하세요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _navigateToOcrScreen(context),
              icon: const Icon(Icons.camera_alt),
              label: const Text('OCR로 텍스트 인식하기'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToOcrScreen(context),
        tooltip: 'OCR 스캔',
        child: const Icon(Icons.camera_alt),
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
}
