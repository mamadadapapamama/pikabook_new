import 'package:flutter/material.dart';
import 'dart:io';
import '../models/page.dart' as page_model;
import '../models/processed_text.dart';
import '../models/text_processing_mode.dart';
import '../models/flash_card.dart';
import '../utils/text_display_mode.dart';
import 'text_section_widget.dart';
import 'processed_text_widget.dart';
import '../services/page_content_service.dart';
import '../services/dictionary_service.dart';
import 'dictionary_result_widget.dart';
import 'page_image_widget.dart';
import 'text_display_toggle_widget.dart';

/// 페이지 내의 이미지, 텍스트 처리상태, 처리된 텍스트 등을 표시
/// 텍스트모드전환, 사전 검색 등 처리
/// 텍스트 처리중 상태, 플래시카드 단어 목록 등 관리 (counter와 하이라이터를 위해)

class PageContentWidget extends StatefulWidget {
  final page_model.Page page;
  final File? imageFile;
  final bool isLoadingImage;
  final String noteId;
  final Function(String, String, {String? pinyin}) onCreateFlashCard;
  final TextProcessingMode textProcessingMode;
  final List<FlashCard>? flashCards;

  const PageContentWidget({
    super.key,
    required this.page,
    required this.imageFile,
    required this.isLoadingImage,
    required this.noteId,
    required this.onCreateFlashCard,
    this.textProcessingMode = TextProcessingMode.languageLearning,
    this.flashCards,
  });

  @override
  State<PageContentWidget> createState() => _PageContentWidgetState();
}

class _PageContentWidgetState extends State<PageContentWidget> {
  TextDisplayMode _textDisplayMode = TextDisplayMode.both;
  final PageContentService _pageContentService = PageContentService();

  ProcessedText? _processedText;
  bool _isProcessingText = false;
  Set<String> _flashcardWords = {};

  @override
  void initState() {
    super.initState();
    _processPageText();
    _updateFlashcardWords();
  }

  @override
  void didUpdateWidget(PageContentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 페이지가 변경되면 TTS 중지
    if (oldWidget.page.id != widget.page.id) {
      _pageContentService.stopSpeaking();
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
    if (widget.page.originalText.isEmpty && widget.imageFile == null) return;

    setState(() {
      _isProcessingText = true;
    });

    final startTime = DateTime.now();
    debugPrint('페이지 텍스트 처리 시작: ${widget.page.id}');

    try {
      final processedText = await _pageContentService.processPageText(
        page: widget.page,
        imageFile: widget.imageFile,
        textProcessingMode: widget.textProcessingMode,
      );

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      debugPrint(
          '페이지 텍스트 처리 완료: ${widget.page.id}, 소요 시간: ${duration.inMilliseconds}ms');

      if (mounted) {
        setState(() {
          _processedText = processedText;
          _isProcessingText = false;
        });
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

  @override
  void dispose() {
    // 화면을 나갈 때 TTS 중지
    _pageContentService.stopSpeaking();
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
            PageImageWidget(
              imageFile: widget.imageFile,
              imageUrl: widget.page.imageUrl,
              pageId: widget.page.id,
              isLoading: widget.isLoadingImage,
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
                  'ProcessedText 표시: 원본 텍스트 ${_processedText!.fullOriginalText.length}자, '
                  '번역 텍스트 ${_processedText!.fullTranslatedText?.length ?? 0}자, '
                  '세그먼트 ${_processedText!.segments?.length ?? 0}개, '
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
                onCreateFlashCard: (word, meaning, {String? pinyin}) {
                  widget.onCreateFlashCard(word, meaning, pinyin: pinyin);
                  // 사전 검색 결과도 함께 표시
                  _showDictionaryResult(word);
                },
                flashCards: widget.flashCards,
                showTranslation: true,
              );
            }),
          ]
          // 기존 방식으로 텍스트 표시 (처리된 텍스트가 없는 경우)
          else ...[
            // 텍스트 표시 모드 토글 버튼
            TextDisplayToggleWidget(
              currentMode: _textDisplayMode,
              onModeChanged: (mode) {
                setState(() {
                  _textDisplayMode = mode;
                });
              },
              originalText: widget.page.originalText,
            ),
            const SizedBox(height: 20),

            // 원본 텍스트 표시
            if (_textDisplayMode == TextDisplayMode.both ||
                _textDisplayMode == TextDisplayMode.originalOnly) ...[
              TextSectionWidget(
                title: '원문',
                text: widget.page.originalText,
                isOriginal: true,
                onDictionaryLookup: _showDictionaryResult,
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
                onDictionaryLookup: _showDictionaryResult,
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

  // 사전 결과 표시
  void _showDictionaryResult(String word) async {
    // 디버그 로그 추가
    debugPrint('사전 검색 요청: $word');

    // 이미 플래시카드에 있는 단어인지 확인
    FlashCard? existingCard;
    if (widget.flashCards != null) {
      for (final card in widget.flashCards!) {
        if (card.front == word) {
          existingCard = card;
          debugPrint('플래시카드에 이미 있는 단어: $word');
          break;
        }
      }
    }

    try {
      // 플래시카드에 이미 있는 단어인 경우, 플래시카드 정보로 사전 결과 표시
      if (existingCard != null) {
        if (!mounted) return;

        final customEntry = DictionaryEntry(
          word: existingCard.front,
          pinyin: existingCard.pinyin ?? '',
          meaning: existingCard.back,
          examples: [],
        );

        DictionaryResultWidget.showDictionaryBottomSheet(
          context: context,
          entry: customEntry,
          onCreateFlashCard: widget.onCreateFlashCard,
        );
        return;
      }

      // 사전 서비스에서 단어 검색
      final entry = await _pageContentService.lookupWord(word);

      if (entry != null) {
        if (mounted) {
          DictionaryResultWidget.showDictionaryBottomSheet(
            context: context,
            entry: entry,
            onCreateFlashCard: widget.onCreateFlashCard,
          );
        }
      } else {
        // 사전에서 찾을 수 없는 경우, 바로 플래시카드 추가 다이얼로그 표시
        if (!mounted) return;

        // 커스텀 다이얼로그 표시
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('새 플래시카드 추가'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('단어: $word'),
                const SizedBox(height: 16),
                const Text('사전에서 찾을 수 없습니다. 직접 의미를 입력하시겠습니까?'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onCreateFlashCard(word, '직접 의미 입력 필요', pinyin: null);
                },
                child: const Text('추가'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint('사전 검색 중 오류 발생: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('사전 검색 중 오류가 발생했습니다: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // 플래시카드 단어 목록 업데이트
  void _updateFlashcardWords() {
    setState(() {
      _flashcardWords =
          _pageContentService.extractFlashcardWords(widget.flashCards);
      debugPrint('플래시카드 단어 목록 업데이트: ${_flashcardWords.length}개');
    });
  }
}
