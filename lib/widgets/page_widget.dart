import 'package:flutter/material.dart';
import 'dart:io';
import '../models/page.dart' as page_model;
import '../services/tts_service.dart';

class PageWidget extends StatefulWidget {
  final page_model.Page page;
  final File? imageFile;

  const PageWidget({
    Key? key,
    required this.page,
    this.imageFile,
  }) : super(key: key);

  @override
  State<PageWidget> createState() => _PageWidgetState();
}

class _PageWidgetState extends State<PageWidget> {
  final TtsService _ttsService = TtsService();
  bool _isSpeaking = false;
  bool _showOriginalOnly = false;
  bool _showTranslationOnly = false;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    await _ttsService.init();
  }

  @override
  void dispose() {
    _ttsService.dispose();
    super.dispose();
  }

  Future<void> _speakText(String text, {String language = 'zh-CN'}) async {
    if (_isSpeaking) {
      await _ttsService.stop();
      setState(() {
        _isSpeaking = false;
      });
      return;
    }

    setState(() {
      _isSpeaking = true;
    });

    try {
      await _ttsService.setLanguage(language);
      await _ttsService.speak(text);

      // 재생이 완료되면 상태 업데이트
      Future.delayed(Duration(milliseconds: 500), () {
        if (_ttsService.state == TtsState.stopped && mounted) {
          setState(() {
            _isSpeaking = false;
          });
        }
      });
    } catch (e) {
      debugPrint('TTS 재생 중 오류 발생: $e');
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('음성 재생 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  void _toggleViewMode() {
    setState(() {
      if (!_showOriginalOnly && !_showTranslationOnly) {
        // 모두 보기 -> 원문만 보기
        _showOriginalOnly = true;
        _showTranslationOnly = false;
      } else if (_showOriginalOnly) {
        // 원문만 보기 -> 번역만 보기
        _showOriginalOnly = false;
        _showTranslationOnly = true;
      } else {
        // 번역만 보기 -> 모두 보기
        _showOriginalOnly = false;
        _showTranslationOnly = false;
      }
    });
  }

  String get _viewModeText {
    if (_showOriginalOnly) {
      return '원문만';
    } else if (_showTranslationOnly) {
      return '번역만';
    } else {
      return '모두 보기';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.imageFile != null) _buildImageSection(),
          const SizedBox(height: 16),
          _buildViewToggle(),
          const SizedBox(height: 16),
          if (!_showTranslationOnly)
            _buildTextSection('원문 (중국어)', widget.page.originalText, 'zh-CN'),
          if (!_showOriginalOnly && !_showTranslationOnly)
            const SizedBox(height: 16),
          if (!_showOriginalOnly)
            _buildTextSection('번역 (한국어)', widget.page.translatedText, 'ko-KR'),
        ],
      ),
    );
  }

  Widget _buildImageSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                widget.imageFile!,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 200,
                    width: double.infinity,
                    color: Colors.grey[200],
                    child: const Center(
                      child: Text('이미지를 불러올 수 없습니다.'),
                    ),
                  );
                },
              ),
            ),
            ButtonBar(
              alignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.fullscreen),
                  onPressed: () {
                    // TODO: 전체 화면으로 이미지 보기
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('전체 화면 보기는 추후 업데이트 예정입니다.')),
                    );
                  },
                  tooltip: '전체 화면으로 보기',
                ),
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () {
                    // TODO: 텍스트 편집 기능
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('텍스트 편집 기능은 추후 업데이트 예정입니다.')),
                    );
                  },
                  tooltip: '텍스트 편집',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewToggle() {
    return Center(
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment<String>(
            value: 'all',
            label: Text('모두 보기'),
            icon: Icon(Icons.view_agenda),
          ),
          ButtonSegment<String>(
            value: 'original',
            label: Text('원문만'),
            icon: Icon(Icons.text_fields),
          ),
          ButtonSegment<String>(
            value: 'translation',
            label: Text('번역만'),
            icon: Icon(Icons.translate),
          ),
        ],
        selected: {
          if (_showOriginalOnly)
            'original'
          else if (_showTranslationOnly)
            'translation'
          else
            'all'
        },
        onSelectionChanged: (Set<String> newSelection) {
          setState(() {
            final selected = newSelection.first;
            _showOriginalOnly = selected == 'original';
            _showTranslationOnly = selected == 'translation';
          });
        },
      ),
    );
  }

  Widget _buildTextSection(String title, String content, String language) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                IconButton(
                  icon: Icon(
                    _isSpeaking ? Icons.stop : Icons.volume_up,
                    size: 24,
                    color: _isSpeaking ? Colors.red : Colors.blue,
                  ),
                  onPressed: () => _speakText(content, language: language),
                  tooltip: _isSpeaking ? '중지' : '소리 듣기',
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
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
