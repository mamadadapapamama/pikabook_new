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
      final pageId = widget.page.id;

      debugPrint(
          '페이지 텍스트 처리 시작: 페이지 ID=$pageId, 원본 텍스트 ${originalText.length}자, 번역 텍스트 ${translatedText.length}자');

      // 캐시된 핀인 확인 (페이지 처리 전에 미리 로드)
      Map<String, String> pinyinCache = {};
      if (pageId != null && pageId.isNotEmpty) {
        try {
          pinyinCache = await _loadPinyinCache(pageId);
          debugPrint('핀인 캐시 미리 로드: ${pinyinCache.length}개 항목');
        } catch (e) {
          debugPrint('핀인 캐시 미리 로드 중 오류: $e');
        }
      }

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
          debugPrint(
              '캐시된 텍스트 사용: 원본=${originalText.length}자, 번역=${translatedText.length}자');

          // 문장 단위로 분리
          final originalSentences = _splitIntoSentences(originalText);
          debugPrint('분리된 문장 수: ${originalSentences.length}개');

          // 각 문장별로 번역 수행
          final segments = <TextSegment>[];
          final StringBuffer combinedTranslation = StringBuffer();

          // 번역된 텍스트가 있으면 문장 단위로 분리
          List<String> translatedSentences = [];
          if (translatedText.isNotEmpty) {
            translatedSentences = _splitIntoSentences(translatedText);
            debugPrint('분리된 번역 문장 수: ${translatedSentences.length}개');
          }

          // 캐시된 번역 문장 수와 원본 문장 수가 일치하면 캐시된 번역 사용
          bool useExistingTranslation = translatedSentences.isNotEmpty;

          if (originalSentences.length == translatedSentences.length) {
            debugPrint('기존 번역 문장 수가 일치하여 캐시된 번역 사용');

            // 문장 수가 일치하는 경우 직접 매핑하여 세그먼트 생성
            for (int i = 0; i < originalSentences.length; i++) {
              final originalSentence = originalSentences[i];
              final translatedSentence = translatedSentences[i];
              String pinyin = '';

              // 중국어가 포함된 문장에 대해서만 핀인 생성
              if (_languageDetectionService.containsChinese(originalSentence)) {
                try {
                  // 캐시에서 핀인 확인
                  if (pinyinCache.containsKey(originalSentence)) {
                    pinyin = pinyinCache[originalSentence]!;
                    debugPrint('캐시된 핀인 사용 (문장 $i): $pinyin');
                  } else {
                    // 문장에서 중국어 문자만 추출하여 핀인 생성
                    final chineseCharsOnly =
                        _extractChineseChars(originalSentence);
                    if (chineseCharsOnly.isNotEmpty) {
                      final generatedPinyin = await _languageDetectionService
                          .generatePinyin(chineseCharsOnly);
                      pinyin = generatedPinyin;
                      debugPrint('핀인 생성 성공 (문장 $i): $pinyin');

                      // 핀인 캐시에 추가
                      pinyinCache[originalSentence] = pinyin;
                    }
                  }
                } catch (e) {
                  debugPrint('핀인 생성 실패 (문장 $i): $e');
                }
              }

              segments.add(TextSegment(
                originalText: originalSentence,
                translatedText: translatedSentence,
                pinyin: pinyin,
              ));

              // 전체 번역 텍스트 구성
              if (combinedTranslation.isNotEmpty) {
                combinedTranslation.write('\n');
              }
              combinedTranslation.write(translatedSentence);
            }

            // 핀인 캐시 저장
            await _savePinyinCache(pageId, pinyinCache);

            // 처리 완료 후 다음 단계로 진행
            final processedText = ProcessedText(
              fullOriginalText: originalText,
              fullTranslatedText: combinedTranslation.toString(),
              segments: segments,
              showFullText: false, // 문장별 모드로 시작
            );

            if (mounted) {
              setState(() {
                _processedText = processedText;
                _isProcessingText = false;
              });
            }

            // 번역 텍스트가 변경된 경우에만 페이지 캐시 업데이트
            if (translatedText != combinedTranslation.toString()) {
              debugPrint('번역 텍스트가 변경되어 페이지 캐시 업데이트');
              await _updatePageCache(processedText);
            } else {
              debugPrint('번역 텍스트가 동일하여 페이지 캐시 업데이트 건너뜀');
            }

            return; // 처리 완료
          } else if (translatedSentences.isNotEmpty) {
            debugPrint(
                '번역 문장 수 불일치: 원본=${originalSentences.length}, 번역=${translatedSentences.length}, 매핑 시도');

            // 문장 수가 불일치하더라도 기존 번역을 최대한 활용
            final mappedSegments = _mapOriginalAndTranslatedSentences(
                originalSentences, translatedSentences);

            // 매핑된 세그먼트 사용
            if (mappedSegments.isNotEmpty) {
              // 각 문장에 대해 핀인 생성 및 번역 수행
              for (int i = 0; i < mappedSegments.length; i++) {
                final originalSentence = mappedSegments[i].originalText;
                final sentenceTranslation =
                    mappedSegments[i].translatedText ?? '';
                String pinyin = '';

                // 중국어가 포함된 문장에 대해서만 핀인 생성
                if (_languageDetectionService
                    .containsChinese(originalSentence)) {
                  try {
                    // 캐시에서 핀인 확인
                    if (pinyinCache.containsKey(originalSentence)) {
                      pinyin = pinyinCache[originalSentence]!;
                      debugPrint('캐시된 핀인 사용 (문장 $i): $pinyin');
                    } else {
                      // 문장에서 중국어 문자만 추출하여 핀인 생성
                      final chineseCharsOnly =
                          _extractChineseChars(originalSentence);
                      if (chineseCharsOnly.isNotEmpty) {
                        final generatedPinyin = await _languageDetectionService
                            .generatePinyin(chineseCharsOnly);
                        pinyin = generatedPinyin;
                        debugPrint('핀인 생성 성공 (문장 $i): $pinyin');

                        // 핀인 캐시에 추가
                        pinyinCache[originalSentence] = pinyin;
                      }
                    }
                  } catch (e) {
                    debugPrint('핀인 생성 실패 (문장 $i): $e');
                  }
                }

                segments.add(TextSegment(
                  originalText: originalSentence,
                  translatedText: sentenceTranslation,
                  pinyin: pinyin,
                ));

                // 전체 번역 텍스트 구성
                if (combinedTranslation.isNotEmpty) {
                  combinedTranslation.write('\n');
                }
                combinedTranslation.write(sentenceTranslation);
              }

              // 핀인 캐시 저장
              await _savePinyinCache(pageId, pinyinCache);

              // 처리 완료 후 다음 단계로 진행
              final processedText = ProcessedText(
                fullOriginalText: originalText,
                fullTranslatedText: combinedTranslation.toString(),
                segments: segments,
                showFullText: false, // 문장별 모드로 시작
              );

              if (mounted) {
                setState(() {
                  _processedText = processedText;
                  _isProcessingText = false;
                });
              }

              // 번역 텍스트가 변경된 경우에만 페이지 캐시 업데이트
              if (translatedText != combinedTranslation.toString()) {
                debugPrint('번역 텍스트가 변경되어 페이지 캐시 업데이트');
                await _updatePageCache(processedText);
              } else {
                debugPrint('번역 텍스트가 동일하여 페이지 캐시 업데이트 건너뜀');
              }

              return; // 처리 완료
            }
          } else {
            debugPrint('캐시된 번역 없음, 새로 번역 시작');
          }

          // 각 문장에 대해 핀인 생성 및 번역 수행
          for (int i = 0; i < originalSentences.length; i++) {
            final originalSentence = originalSentences[i];
            String pinyin = '';
            String sentenceTranslation = '';

            // 중국어가 포함된 문장에 대해서만 핀인 생성
            if (_languageDetectionService.containsChinese(originalSentence)) {
              try {
                // 캐시에서 핀인 확인
                if (pinyinCache.containsKey(originalSentence)) {
                  pinyin = pinyinCache[originalSentence]!;
                  debugPrint('캐시된 핀인 사용 (문장 $i): $pinyin');
                } else {
                  // 문장에서 중국어 문자만 추출하여 핀인 생성
                  final chineseCharsOnly =
                      _extractChineseChars(originalSentence);
                  if (chineseCharsOnly.isNotEmpty) {
                    final generatedPinyin = await _languageDetectionService
                        .generatePinyin(chineseCharsOnly);
                    pinyin = generatedPinyin;
                    debugPrint('핀인 생성 성공 (문장 $i): $pinyin');

                    // 핀인 캐시에 추가
                    pinyinCache[originalSentence] = pinyin;
                  }
                }

                // 번역 수행
                // 캐시에서 번역 확인
                String? cachedTranslation;
                try {
                  cachedTranslation = await _translationService.getTranslation(
                      originalSentence, 'ko');
                  if (cachedTranslation != null &&
                      cachedTranslation.isNotEmpty) {
                    debugPrint(
                        '번역 캐시에서 로드 (문장 $i): ${cachedTranslation.length}자');
                  }
                } catch (e) {
                  debugPrint('캐시된 번역 조회 중 오류 (문장 $i): $e');
                  cachedTranslation = null;
                }

                // 캐시에 없으면 번역 수행 및 캐싱
                if (cachedTranslation == null || cachedTranslation.isEmpty) {
                  debugPrint('새로운 번역 요청 (문장 $i): ${originalSentence.length}자');
                  final newTranslation = await _translationService
                      .translateText(originalSentence, targetLanguage: 'ko');
                  sentenceTranslation = newTranslation;

                  // 번역 결과 캐싱
                  if (sentenceTranslation.isNotEmpty) {
                    try {
                      await _translationService.cacheTranslation(
                          originalSentence, sentenceTranslation, 'ko');
                      debugPrint('번역 결과 캐싱 완료 (문장 $i)');
                    } catch (e) {
                      debugPrint('번역 캐싱 중 오류 (문장 $i): $e');
                    }
                  }
                } else {
                  sentenceTranslation = cachedTranslation;
                }
              } catch (e) {
                debugPrint('핀인 생성 또는 번역 실패 (문장 $i): $e');
              }
            } else {
              // 중국어가 없는 문장 처리
              // 번역 시도
              try {
                // 캐시에서 번역 확인
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

                  // 번역 결과 캐싱
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
              } catch (e) {
                sentenceTranslation = originalSentence; // 번역 실패 시 원본 사용
              }
            }

            segments.add(TextSegment(
              originalText: originalSentence,
              translatedText: sentenceTranslation,
              pinyin: pinyin,
            ));

            // 번역 결과 추가
            if (combinedTranslation.isNotEmpty) {
              combinedTranslation.write('\n');
            }
            combinedTranslation.write(sentenceTranslation);
          }

          // 핀인 캐시 저장
          await _savePinyinCache(pageId, pinyinCache);

          debugPrint('생성된 세그먼트 수: ${segments.length}개');

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

          // 번역 텍스트가 변경된 경우에만 페이지 캐시 업데이트
          if (translatedText != fullTranslatedText) {
            debugPrint('번역 텍스트가 변경되어 페이지 캐시 업데이트');
            await _updatePageCache(processedText);
          } else {
            debugPrint('번역 텍스트가 동일하여 페이지 캐시 업데이트 건너뜀');
          }
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

  // 텍스트를 문장 단위로 분리 (개선된 버전)
  List<String> _splitIntoSentences(String text) {
    if (text.isEmpty) return [];

    // 개선된 문장 구분자 패턴
    // 중국어 문장 구분자(。！？), 영어 문장 구분자(.!?), 쉼표(,，), 기타 구분자(、:;) 등을 포함
    // 구분자 뒤에 공백이 있을 수도 있고, 줄바꿈 문자도 문장 구분자로 처리
    final pattern = RegExp(r'(?<=[。！？!?\.,，、:;；：])\s*|[\n\r]+');

    // 문장 구분자로 분리
    final sentences = text.split(pattern);

    // 빈 문장 제거 및 정리
    return sentences.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  // 원본 문장과 번역 문장을 최대한 매핑하는 함수 추가
  List<TextSegment> _mapOriginalAndTranslatedSentences(
      List<String> originalSentences, List<String> translatedSentences) {
    final segments = <TextSegment>[];
    final int originalCount = originalSentences.length;
    final int translatedCount = translatedSentences.length;

    debugPrint('원본 문장 수: $originalCount, 번역 문장 수: $translatedCount');

    // 문장 수가 같으면 1:1 매핑
    if (originalCount == translatedCount) {
      for (int i = 0; i < originalCount; i++) {
        segments.add(TextSegment(
          originalText: originalSentences[i],
          translatedText: translatedSentences[i],
          pinyin: '',
        ));
      }
      return segments;
    }

    // 문장 수가 다른 경우 최대한 매핑 시도
    // 1. 원본 문장 수가 더 많은 경우: 번역 문장을 비율에 맞게 분배
    if (originalCount > translatedCount) {
      final double ratio = originalCount / translatedCount;
      for (int i = 0; i < originalCount; i++) {
        final int translatedIndex = (i / ratio).floor();
        final String translatedText = translatedIndex < translatedCount
            ? translatedSentences[translatedIndex]
            : '';

        segments.add(TextSegment(
          originalText: originalSentences[i],
          translatedText: translatedText,
          pinyin: '',
        ));
      }
    }
    // 2. 번역 문장 수가 더 많은 경우: 원본 문장을 비율에 맞게 분배
    else {
      final double ratio = translatedCount / originalCount;
      for (int i = 0; i < originalCount; i++) {
        final int startIndex = (i * ratio).floor();
        final int endIndex = ((i + 1) * ratio).floor();

        // 해당 원본 문장에 매핑되는 번역 문장들을 결합
        final StringBuffer combinedTranslation = StringBuffer();
        for (int j = startIndex; j < endIndex && j < translatedCount; j++) {
          if (combinedTranslation.isNotEmpty) {
            combinedTranslation.write(' ');
          }
          combinedTranslation.write(translatedSentences[j]);
        }

        segments.add(TextSegment(
          originalText: originalSentences[i],
          translatedText: combinedTranslation.toString(),
          pinyin: '',
        ));
      }
    }

    return segments;
  }

  @override
  void dispose() {
    // 화면을 나갈 때 TTS 중지
    _ttsService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 플래시카드 단어 목록 추출
    final Set<String> flashcardWords = _extractFlashcardWords();

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
                onCreateFlashCard: (word, meaning, {String? pinyin}) {
                  widget.onCreateFlashCard(word, meaning, pinyin: pinyin);
                },
                flashCards: widget.flashCards,
                noteId: widget.noteId,
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
                flashcardWords: flashcardWords,
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
                flashcardWords: flashcardWords,
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

    // 간단한 스낵바로 먼저 표시 (디버깅용)
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('사전 검색 결과: ${entry.word} - ${entry.meaning}'),
        duration: const Duration(seconds: 1),
      ),
    );

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

  // 문자열에서 중국어 문자만 추출
  String _extractChineseChars(String text) {
    final RegExp chineseRegex = RegExp(r'[\u4e00-\u9fff]+');
    final Iterable<Match> matches = chineseRegex.allMatches(text);
    final StringBuffer buffer = StringBuffer();
    for (final match in matches) {
      buffer.write(match.group(0));
    }
    return buffer.toString();
  }

  // 핀인 캐싱 메서드 수정
  Future<Map<String, String>> _loadPinyinCache(String? pageId) async {
    if (pageId == null || pageId.isEmpty) return {};

    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'pinyin_cache_$pageId';
      final cachedData = prefs.getString(cacheKey);

      if (cachedData != null && cachedData.isNotEmpty) {
        final Map<String, dynamic> jsonData = json.decode(cachedData);
        final Map<String, String> pinyinCache = {};

        jsonData.forEach((key, value) {
          if (value is String) {
            pinyinCache[key] = value;
          }
        });

        debugPrint('핀인 캐시 로드 성공: ${pinyinCache.length}개 항목');
        return pinyinCache;
      }
    } catch (e) {
      debugPrint('핀인 캐시 로드 중 오류 발생: $e');
    }
    return {};
  }

  Future<void> _savePinyinCache(
      String? pageId, Map<String, String> cache) async {
    if (pageId == null || pageId.isEmpty || cache.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'pinyin_cache_$pageId';
      final jsonData = json.encode(cache);
      await prefs.setString(cacheKey, jsonData);
      debugPrint('핀인 캐시 저장 성공: ${cache.length}개 항목');
    } catch (e) {
      debugPrint('핀인 캐시 저장 중 오류 발생: $e');
    }
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
}
