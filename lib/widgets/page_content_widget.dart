import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../models/page.dart' as page_model;
import '../models/processed_text.dart';
import '../models/text_segment.dart';
import '../models/text_processing_mode.dart';
import '../services/dictionary_service.dart';
import '../services/flashcard_service.dart' hide debugPrint;
import '../services/tts_service.dart';
import '../services/enhanced_ocr_service.dart';
import '../services/language_detection_service.dart';
import '../services/translation_service.dart';
import '../utils/text_display_mode.dart';
import '../views/screens/full_image_screen.dart';
import 'text_section_widget.dart';
import 'processed_text_widget.dart';
import '../services/page_service.dart';

class PageContentWidget extends StatefulWidget {
  final page_model.Page page;
  final File? imageFile;
  final bool isLoadingImage;
  final String noteId;
  final Function(String, String, {String? pinyin}) onCreateFlashCard;
  final TextProcessingMode textProcessingMode;

  const PageContentWidget({
    Key? key,
    required this.page,
    required this.imageFile,
    required this.isLoadingImage,
    required this.noteId,
    required this.onCreateFlashCard,
    this.textProcessingMode = TextProcessingMode.languageLearning,
  }) : super(key: key);

  @override
  State<PageContentWidget> createState() => _PageContentWidgetState();
}

class _PageContentWidgetState extends State<PageContentWidget> {
  TextDisplayMode _textDisplayMode = TextDisplayMode.both;
  final DictionaryService _dictionaryService = DictionaryService();
  final TtsService _ttsService = TtsService();
  final EnhancedOcrService _ocrService = EnhancedOcrService();
  final LanguageDetectionService _languageDetectionService =
      LanguageDetectionService();
  final TranslationService _translationService = TranslationService();

  ProcessedText? _processedText;
  bool _isProcessingText = false;

  @override
  void initState() {
    super.initState();
    _ttsService.init();
    _processPageText();
  }

  @override
  void didUpdateWidget(PageContentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 페이지가 변경되면 TTS 중지
    if (oldWidget.page.id != widget.page.id) {
      _ttsService.stop();
      _processPageText();
    }

    // 텍스트 처리 모드가 변경되면 다시 처리
    if (oldWidget.textProcessingMode != widget.textProcessingMode) {
      _processPageText();
    }
  }

  // 페이지 텍스트 처리
  Future<void> _processPageText() async {
    if (widget.page.originalText.isEmpty) return;

    setState(() {
      _isProcessingText = true;
    });

    try {
      // 캐시된 텍스트 확인
      final originalText = widget.page.originalText;
      final translatedText = widget.page.translatedText;

      debugPrint(
          '페이지 텍스트 처리: 원본 텍스트 ${originalText.length}자, 번역 텍스트 ${translatedText.length}자');

      // 텍스트 처리 모드에 따라 다른 처리
      if (widget.textProcessingMode == TextProcessingMode.professionalReading) {
        // 전문 서적 모드: 전체 텍스트 표시
        final processedText = ProcessedText(
          fullOriginalText: originalText,
          fullTranslatedText: translatedText,
          showFullText: true,
        );

        if (mounted) {
          setState(() {
            _processedText = processedText;
            _isProcessingText = false;
          });
        }
      } else {
        // 언어 학습 모드: 문장별 처리
        if (widget.imageFile != null &&
            (originalText.isEmpty || translatedText.isEmpty)) {
          // 캐시된 텍스트가 없는 경우에만 OCR 처리
          debugPrint('캐시된 텍스트가 없어 OCR 처리 시작');
          final processedText = await _ocrService.processImage(
            widget.imageFile!,
            widget.textProcessingMode,
          );

          if (mounted) {
            setState(() {
              _processedText = processedText;
              _isProcessingText = false;
            });
          }

          // 처리된 텍스트를 페이지에 캐싱
          if (processedText.fullOriginalText.isNotEmpty) {
            await _updatePageCache(processedText);
          }
        } else {
          // 캐시된 텍스트 사용
          debugPrint('캐시된 텍스트 사용');

          // 텍스트 내용 확인
          debugPrint(
              '원본 텍스트 길이: ${originalText.length}, 처음 50자: ${originalText.substring(0, originalText.length > 50 ? 50 : originalText.length)}');
          debugPrint(
              '번역 텍스트 길이: ${translatedText.length}, 처음 50자: ${translatedText.substring(0, translatedText.length > 50 ? 50 : translatedText.length)}');

          // 문장 단위로 분리
          final originalSentences = _splitIntoSentences(originalText);

          // 각 문장별로 번역 수행
          final segments = <TextSegment>[];
          final StringBuffer combinedTranslation = StringBuffer();

          // 각 문장에 대해 핀인 생성 및 번역 수행
          for (int i = 0; i < originalSentences.length; i++) {
            final originalSentence = originalSentences[i];
            String pinyin = '';
            String sentenceTranslation = '';

            // 중국어가 포함된 문장에 대해서만 핀인 생성
            if (_languageDetectionService.containsChinese(originalSentence)) {
              try {
                // 문장에서 중국어 문자만 추출하여 핀인 생성
                final chineseCharsOnly = _extractChineseChars(originalSentence);
                if (chineseCharsOnly.isNotEmpty) {
                  final generatedPinyin = await _languageDetectionService
                      .generatePinyin(chineseCharsOnly);
                  pinyin = generatedPinyin;
                  debugPrint('핀인 생성 성공 (중국어 문자만): $pinyin');
                }

                // 캐시에서 번역 확인 (임시 구현)
                String? cachedTranslation;
                try {
                  cachedTranslation = await _translationService.getTranslation(
                      originalSentence, 'ko');
                } catch (e) {
                  debugPrint('캐시된 번역 조회 중 오류: $e');
                  cachedTranslation = null;
                }

                // 캐시에 없으면 번역 수행 및 캐싱
                if (cachedTranslation == null || cachedTranslation.isEmpty) {
                  final newTranslation = await _translationService
                      .translateText(originalSentence, targetLanguage: 'ko');
                  sentenceTranslation = newTranslation;

                  // 번역 결과 캐싱 (임시 구현)
                  if (sentenceTranslation.isNotEmpty) {
                    try {
                      await _translationService.cacheTranslation(
                          originalSentence, sentenceTranslation, 'ko');
                    } catch (e) {
                      debugPrint('번역 캐싱 중 오류: $e');
                    }
                  }
                } else {
                  sentenceTranslation = cachedTranslation;
                  debugPrint('캐시된 번역 사용: $sentenceTranslation');
                }

                debugPrint('문장 번역 완료: $sentenceTranslation');

                // 번역 결과 추가
                if (combinedTranslation.isNotEmpty) {
                  combinedTranslation.write('\n');
                }
                combinedTranslation.write(sentenceTranslation);
              } catch (e) {
                debugPrint('핀인 생성 또는 번역 실패: $e');
              }
            } else {
              // 중국어가 없는 문장도 번역 시도
              try {
                // 캐시에서 번역 확인 (임시 구현)
                String? cachedTranslation;
                try {
                  cachedTranslation = await _translationService.getTranslation(
                      originalSentence, 'ko');
                } catch (e) {
                  debugPrint('캐시된 번역 조회 중 오류: $e');
                  cachedTranslation = null;
                }

                // 캐시에 없으면 번역 수행 및 캐싱
                if (cachedTranslation == null || cachedTranslation.isEmpty) {
                  final newTranslation = await _translationService
                      .translateText(originalSentence, targetLanguage: 'ko');
                  sentenceTranslation = newTranslation;

                  // 번역 결과 캐싱 (임시 구현)
                  if (sentenceTranslation.isNotEmpty) {
                    try {
                      await _translationService.cacheTranslation(
                          originalSentence, sentenceTranslation, 'ko');
                    } catch (e) {
                      debugPrint('번역 캐싱 중 오류: $e');
                    }
                  }
                } else {
                  sentenceTranslation = cachedTranslation;
                  debugPrint('캐시된 번역 사용: $sentenceTranslation');
                }

                // 번역 결과 추가
                if (combinedTranslation.isNotEmpty) {
                  combinedTranslation.write('\n');
                }
                combinedTranslation.write(sentenceTranslation);
              } catch (e) {
                sentenceTranslation = originalSentence; // 번역 실패 시 원본 사용

                // 번역 결과 추가
                if (combinedTranslation.isNotEmpty) {
                  combinedTranslation.write('\n');
                }
                combinedTranslation.write(sentenceTranslation);
              }
            }

            segments.add(TextSegment(
              originalText: originalSentence,
              translatedText: sentenceTranslation,
              pinyin: pinyin,
            ));
          }

          debugPrint('생성된 세그먼트 수: ${segments.length}');

          // 전체 번역 텍스트 생성
          final fullTranslatedText = combinedTranslation.toString();
          debugPrint('생성된 전체 번역 텍스트: ${fullTranslatedText.length}자');

          final processedText = ProcessedText(
            fullOriginalText: originalText,
            fullTranslatedText: fullTranslatedText,
            segments: segments,
            showFullText: false, // 문장별 모드로 시작
          );

          if (mounted) {
            setState(() {
              _processedText = processedText;
              _isProcessingText = false;
            });
          }

          // 처리된 텍스트를 페이지에 캐싱
          await _updatePageCache(processedText);
        }
      }
    } catch (e) {
      debugPrint('텍스트 처리 중 오류 발생: $e');
      if (mounted) {
        setState(() {
          _isProcessingText = false;
        });
      }
    }
  }

  // 페이지 캐시 업데이트
  Future<void> _updatePageCache(ProcessedText processedText) async {
    try {
      // 페이지 ID가 없으면 업데이트 불가
      final pageId = widget.page.id;
      if (pageId == null || pageId.isEmpty) {
        debugPrint('페이지 ID가 없어 캐시 업데이트를 건너뜁니다.');
        return;
      }

      // 페이지 서비스 가져오기
      final pageService = PageService();

      // 페이지 업데이트
      await pageService.updatePageContent(
        pageId,
        processedText.fullOriginalText,
        processedText.fullTranslatedText ?? '',
      );

      debugPrint('페이지 캐시 업데이트 완료: $pageId');
    } catch (e) {
      debugPrint('페이지 캐시 업데이트 중 오류 발생: $e');
    }
  }

  // 텍스트를 문장 단위로 분리
  List<String> _splitIntoSentences(String text) {
    if (text.isEmpty) return [];

    debugPrint('문장 분리 시작: 텍스트 길이 ${text.length}자');

    // 문장 구분자 패턴 (마침표, 느낌표, 물음표, 쉼표 등 뒤에 공백이 있을 수도 있음)
    final pattern = RegExp(r'(?<=[。！？!?\.,，、])\s*');

    // 문장 구분자로 분리
    final sentences = text.split(pattern);

    // 빈 문장 제거
    final result = sentences.where((s) => s.trim().isNotEmpty).toList();

    // 결과 확인
    debugPrint('분리된 문장 수: ${result.length}');
    if (result.isNotEmpty) {
      for (int i = 0; i < result.length && i < 3; i++) {
        debugPrint('문장 $i: ${result[i]}');
      }
    }

    return result;
  }

  @override
  void dispose() {
    // 화면을 나갈 때 TTS 중지
    _ttsService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: ValueKey('page_${widget.page.id}'),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 이미지 표시
          if (widget.page.imageUrl != null) ...[
            Center(
              child: widget.isLoadingImage
                  ? Container(
                      width: double.infinity,
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('이미지 로딩 중...'),
                          ],
                        ),
                      ),
                    )
                  : GestureDetector(
                      onTap: () => _openFullScreenImage(context),
                      child: Hero(
                        tag: 'image_${widget.page.id}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              widget.imageFile != null
                                  ? Image.file(
                                      widget.imageFile!,
                                      height: 200,
                                      width: double.infinity,
                                      fit: BoxFit.contain,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        return Container(
                                          width: double.infinity,
                                          height: 150,
                                          color: Colors.grey[200],
                                          child: const Center(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.image_not_supported,
                                                    size: 48,
                                                    color: Colors.grey),
                                                SizedBox(height: 8),
                                                Text('이미지를 불러올 수 없습니다.'),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    )
                                  : Container(
                                      width: double.infinity,
                                      height: 150,
                                      color: Colors.grey[200],
                                      child: const Center(
                                        child: Text('이미지를 찾을 수 없습니다.'),
                                      ),
                                    ),
                              // 확대 아이콘 오버레이
                              Positioned(
                                right: 8,
                                bottom: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Icon(
                                    Icons.zoom_in,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 20),
          ],

          // 텍스트 처리 중 표시
          if (_isProcessingText)
            const Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('텍스트 처리 중...'),
                ],
              ),
            )
          // 처리된 텍스트가 있는 경우
          else if (_processedText != null) ...[
            Builder(builder: (context) {
              debugPrint(
                  'ProcessedText 표시: 원본 텍스트 ${_processedText!.fullOriginalText.length}자, ' +
                      '번역 텍스트 ${_processedText!.fullTranslatedText?.length ?? 0}자, ' +
                      '세그먼트 ${_processedText!.segments?.length ?? 0}개, ' +
                      '전체 텍스트 모드: ${_processedText!.showFullText}');

              return ProcessedTextWidget(
                processedText: _processedText!,
                onTts: _speakText,
                onDictionaryLookup: _showDictionarySnackbar,
                onCreateFlashCard: (word, meaning) {
                  widget.onCreateFlashCard(word, meaning);
                },
              );
            }),
          ]
          // 기존 방식으로 텍스트 표시 (처리된 텍스트가 없는 경우)
          else ...[
            // 텍스트 표시 모드 토글 버튼
            _buildTextDisplayToggle(),
            const SizedBox(height: 20),

            // 원본 텍스트 표시
            if (_textDisplayMode == TextDisplayMode.both ||
                _textDisplayMode == TextDisplayMode.originalOnly) ...[
              TextSectionWidget(
                title: '원문',
                text: widget.page.originalText,
                isOriginal: true,
                onDictionaryLookup: _showDictionarySnackbar,
                onCreateFlashCard: widget.onCreateFlashCard,
                translatedText: widget.page.translatedText,
              ),
              const SizedBox(height: 24),
            ],

            // 번역 텍스트 표시
            if (_textDisplayMode == TextDisplayMode.both ||
                _textDisplayMode == TextDisplayMode.translationOnly) ...[
              TextSectionWidget(
                title: '번역',
                text: widget.page.translatedText,
                isOriginal: false,
                onDictionaryLookup: _showDictionarySnackbar,
                onCreateFlashCard: widget.onCreateFlashCard,
                translatedText: widget.page.originalText,
              ),
            ],
          ],
        ],
      ),
    );
  }

  // 전체 화면 이미지 뷰어 열기
  void _openFullScreenImage(BuildContext context) {
    if (widget.imageFile == null && widget.page.imageUrl == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FullImageScreen(
          imageFile: widget.imageFile,
          imageUrl: widget.page.imageUrl,
          title: '이미지 보기',
        ),
      ),
    );
  }

  // TTS로 텍스트 읽기
  Future<void> _speakText(String text) async {
    if (text.isEmpty) return;

    try {
      // 중국어로 언어 설정
      await _ttsService.setLanguage('zh-CN');
      // 텍스트 읽기
      await _ttsService.speak(text);
    } catch (e) {
      debugPrint('TTS 실행 중 오류 발생: $e');
    }
  }

  Widget _buildTextDisplayToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 텍스트 표시 모드 토글 버튼
          ToggleButtons(
            isSelected: [
              _textDisplayMode == TextDisplayMode.both,
              _textDisplayMode == TextDisplayMode.originalOnly,
              _textDisplayMode == TextDisplayMode.translationOnly,
            ],
            onPressed: (index) {
              setState(() {
                switch (index) {
                  case 0:
                    _textDisplayMode = TextDisplayMode.both;
                    break;
                  case 1:
                    _textDisplayMode = TextDisplayMode.originalOnly;
                    break;
                  case 2:
                    _textDisplayMode = TextDisplayMode.translationOnly;
                    break;
                }
              });
            },
            borderRadius: BorderRadius.circular(8),
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('모두 보기'),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('원문만'),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('번역만'),
              ),
            ],
          ),

          // TTS 버튼 (원문 읽기)
          IconButton(
            icon: const Icon(Icons.volume_up),
            tooltip: '원문 읽기',
            onPressed: () => _speakText(widget.page.originalText),
          ),
        ],
      ),
    );
  }

  // 사전 스낵바 표시
  void _showDictionarySnackbar(String word) {
    final entry = _dictionaryService.lookupWord(word);

    if (entry == null) {
      // 사전에 없는 단어일 경우
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('사전에서 찾을 수 없는 단어: $word'),
          action: SnackBarAction(
            label: '플래시카드에 추가',
            onPressed: () {
              widget.onCreateFlashCard(word, '직접 의미 입력 필요');
            },
          ),
          duration: const Duration(seconds: 5),
        ),
      );
      return;
    }

    // 사전에 있는 단어일 경우
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  entry.word,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  entry.pinyin,
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
            Text('의미: ${entry.meaning}'),
          ],
        ),
        action: SnackBarAction(
          label: '플래시카드에 추가',
          onPressed: () {
            widget.onCreateFlashCard(entry.word, entry.meaning,
                pinyin: entry.pinyin);
          },
        ),
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // 문자열에서 중국어 문자만 추출
  String _extractChineseChars(String text) {
    // 중국어 문자 패턴 (유니코드 범위: 4E00-9FFF)
    final chinesePattern = RegExp(r'[\u4e00-\u9fff]');

    // 중국어 문자만 추출
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (chinesePattern.hasMatch(char)) {
        buffer.write(char);
      }
    }

    return buffer.toString();
  }
}
