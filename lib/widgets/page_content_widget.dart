import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import '../models/page.dart' as page_model;
import '../models/processed_text.dart';
import '../models/text_segment.dart';
import '../models/text_processing_mode.dart';
import '../models/flash_card.dart';
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
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/unified_cache_service.dart';
import '../services/chinese_segmenter_service.dart';

class PageContentWidget extends StatefulWidget {
  final page_model.Page page;
  final File? imageFile;
  final bool isLoadingImage;
  final String noteId;
  final Function(String, String, {String? pinyin}) onCreateFlashCard;
  final TextProcessingMode textProcessingMode;
  final List<FlashCard>? flashCards;

  const PageContentWidget({
    Key? key,
    required this.page,
    required this.imageFile,
    required this.isLoadingImage,
    required this.noteId,
    required this.onCreateFlashCard,
    this.textProcessingMode = TextProcessingMode.languageLearning,
    this.flashCards,
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
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  final ChineseSegmenterService _segmenterService = ChineseSegmenterService();

  ProcessedText? _processedText;
  bool _isProcessingText = false;
  Set<String> _flashcardWords = {};

  @override
  void initState() {
    super.initState();
    _ttsService.init();
    _processPageText();
    _updateFlashcardWords();
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

    // 플래시카드 목록이 변경되면 업데이트
    if (oldWidget.flashCards != widget.flashCards) {
      _updateFlashcardWords();
      debugPrint(
          '플래시카드 목록이 변경되어 _flashcardWords 업데이트됨: ${_flashcardWords.length}개');
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
      final pageId = widget.page.id;

      debugPrint(
          '페이지 텍스트 처리 시작: 페이지 ID=$pageId, 원본 텍스트 ${originalText.length}자, 번역 텍스트 ${translatedText.length}자');

      // 이미지 파일이 있고 텍스트가 없는 경우 OCR 처리
      if (widget.imageFile != null &&
          (originalText.isEmpty || translatedText.isEmpty)) {
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
        // 기존 텍스트 처리
        debugPrint('기존 텍스트 처리 시작');
        final processedText = await _ocrService.processText(
          originalText,
          translatedText,
          widget.textProcessingMode,
        );

        if (mounted) {
          setState(() {
            _processedText = processedText;
            _isProcessingText = false;
          });
        }

        // 번역 텍스트가 변경된 경우에만 페이지 캐시 업데이트
        if (translatedText != processedText.fullTranslatedText) {
          debugPrint('번역 텍스트가 변경되어 페이지 캐시 업데이트');
          await _updatePageCache(processedText);
        } else {
          debugPrint('번역 텍스트가 동일하여 페이지 캐시 업데이트 건너뜀');
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

              // 플래시카드 목록 디버그 출력
              if (widget.flashCards != null) {
                debugPrint(
                    'ProcessedTextWidget에 전달할 flashCards 수: ${widget.flashCards!.length}');
                if (widget.flashCards!.isNotEmpty) {
                  debugPrint(
                      '첫 번째 플래시카드: ${widget.flashCards![0].front} - ${widget.flashCards![0].back}');
                }
              } else {
                debugPrint('ProcessedTextWidget에 전달할 flashCards가 null입니다.');
              }

              // _flashcardWords 디버그 출력
              debugPrint('현재 _flashcardWords 수: ${_flashcardWords.length}');
              if (_flashcardWords.isNotEmpty) {
                debugPrint(
                    '_flashcardWords 첫 5개: ${_flashcardWords.take(5).join(', ')}');
              }

              return ProcessedTextWidget(
                processedText: _processedText!,
                onTts: _speakText,
                onDictionaryLookup: _showDictionarySnackbar,
                onCreateFlashCard: (word, meaning, {String? pinyin}) {
                  widget.onCreateFlashCard(word, meaning, pinyin: pinyin);
                },
                flashCards: widget.flashCards,
                showTranslation: true,
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
                flashcardWords: _flashcardWords,
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
                flashcardWords: _flashcardWords,
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
    // 디버그 로그 추가
    debugPrint('사전 검색 요청: $word');

    // 사전 서비스에서 단어 검색
    final entry = _dictionaryService.lookupWord(word);

    if (entry == null) {
      // 사전에 없는 단어일 경우 Papago API로 검색 시도
      debugPrint('사전에 없는 단어, Papago API로 검색 시도: $word');
      _dictionaryService.lookupWordWithFallback(word).then((apiEntry) {
        if (apiEntry != null) {
          _showDictionaryBottomSheet(apiEntry);
        } else {
          // API 검색도 실패한 경우 스낵바 표시
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('사전에서 찾을 수 없는 단어: $word'),
              action: SnackBarAction(
                label: '플래시카드에 추가',
                onPressed: () {
                  widget.onCreateFlashCard(word, '직접 의미 입력 필요', pinyin: null);
                },
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      });
      return;
    }

    // 사전에 있는 단어일 경우 바로 bottom sheet 표시
    _showDictionaryBottomSheet(entry);
  }

  // 사전 결과를 bottom sheet으로 표시
  void _showDictionaryBottomSheet(DictionaryEntry entry) {
    debugPrint('사전 결과 bottom sheet 표시: ${entry.word}');

    // 스낵바 제거 (중복 방지)
    ScaffoldMessenger.of(context).clearSnackBars();

    // Bottom Sheet 표시
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 단어 제목
              Text(
                entry.word,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              // 발음 정보
              if (entry.pinyin.isNotEmpty)
                Text(
                  '발음: ${entry.pinyin}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                  ),
                ),

              const SizedBox(height: 8),

              // 의미 정보
              Text(
                '의미: ${entry.meaning}',
                style: const TextStyle(fontSize: 16),
              ),

              const SizedBox(height: 16),

              // 버튼 영역
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // TTS 버튼
                  ElevatedButton.icon(
                    onPressed: () {
                      _speakText(entry.word);
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.volume_up),
                    label: const Text('읽기'),
                  ),

                  // 플래시카드 추가 버튼
                  ElevatedButton.icon(
                    onPressed: () {
                      widget.onCreateFlashCard(
                        entry.word,
                        entry.meaning,
                        pinyin: entry.pinyin,
                      );
                      Navigator.pop(context);

                      // 추가 완료 메시지
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('플래시카드에 추가되었습니다'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_card),
                    label: const Text('플래시카드 추가'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // 플래시카드 단어 목록 추출
  Set<String> _extractFlashcardWords() {
    final Set<String> flashcardWords = {};
    if (widget.flashCards != null && widget.flashCards!.isNotEmpty) {
      for (final card in widget.flashCards!) {
        flashcardWords.add(card.front);
      }
    }
    return flashcardWords;
  }

  // 플래시카드 단어 목록 업데이트
  void _updateFlashcardWords() {
    setState(() {
      _flashcardWords = _extractFlashcardWords();
      debugPrint('플래시카드 단어 목록 업데이트: ${_flashcardWords.length}개');
    });
  }
}
