import 'package:flutter/material.dart';
import 'dart:io';
import '../models/page.dart' as page_model;
import '../models/processed_text.dart';
import '../models/flash_card.dart';
import '../models/dictionary_entry.dart';
import 'processed_text_widget.dart';
import '../services/page_content_service.dart';
import 'dictionary_result_widget.dart';
import 'package:flutter/foundation.dart'; // kDebugMode 사용하기 위한 import
import 'dot_loading_indicator.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import '../utils/segment_utils.dart';
import '../services/text_reader_service.dart'; // TTS 서비스 추가
import '../services/usage_limit_service.dart';
import '../widgets/common/usage_dialog.dart';
import '../services/translation_service.dart';
import '../services/enhanced_ocr_service.dart';
import '../services/dictionary/dictionary_service.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

/// PageContentWidget은 노트의 페이지 전체 컨텐츠를 관리하고 표시하는 위젯입니다.
///
/// ## 주요 기능
/// - 페이지 이미지 및 텍스트 로딩/처리 상태 관리
/// - 사전 검색 및 바텀시트 표시
/// - 플래시카드 관련 상태 관리
/// - 텍스트 모드 전환(세그먼트/전체) 처리
/// - TTS(Text-to-Speech) 기능 관리
/// - ProcessedTextWidget과 상호작용 관리
///
/// ## ProcessedTextWidget과의 관계
/// - PageContentWidget: 페이지 전체 관리 (컨테이너 역할)
///   - 텍스트 처리 상태, 이미지 로딩, 사전 검색 등 페이지 수준의 기능 담당
///   - 플래시카드 데이터 처리 및 관리
///   - TTS(Text-to-Speech) 기능 담당
///   - ProcessedTextWidget에 필요한 데이터와, 사용자 이벤트 콜백 제공
///
/// - ProcessedTextWidget: 텍스트 표시 전문 (컴포넌트 역할)
///   - 텍스트 렌더링 및 텍스트 관련 상호작용만 담당
///   - 세그먼트/전체 텍스트 표시, 병음/번역 표시, 하이라이팅 등
///
/// 이 구조를 통해 UI 로직과 텍스트 처리 로직이 깔끔하게 분리됨

class PageContentWidget extends StatefulWidget {
  final page_model.Page page;
  final File? imageFile;
  final bool isLoadingImage;
  final String noteId;
  final Function(String, String, {String? pinyin}) onCreateFlashCard;
  final List<FlashCard>? flashCards;
  final Function(int)? onDeleteSegment;
  final bool useSegmentMode;

  const PageContentWidget({
    super.key,
    required this.page,
    required this.imageFile,
    required this.isLoadingImage,
    required this.noteId,
    required this.onCreateFlashCard,
    this.flashCards,
    this.onDeleteSegment,
    this.useSegmentMode = true,
  });

  @override
  State<PageContentWidget> createState() => _PageContentWidgetState();
}

class _PageContentWidgetState extends State<PageContentWidget> {
  bool _isProcessingText = false;
  ProcessedText? _processedText;
  
  // 서비스 객체 선언 변경
  late PageContentService _pageContentService;
  late TextReaderService _textReaderService;
  
  Set<String> _flashcardWords = {};
  int? _playingSegmentIndex; // 현재 재생 중인 세그먼트 인덱스 추가

  // 클래스 레벨 변수로 스타일 정의
  late final TextStyle _originalTextStyle;
  late final TextStyle _pinyinTextStyle;
  late final TextStyle _translatedTextStyle;

  // TTS 사용량 제한 확인 변수
  bool _isCheckingTtsLimit = false;
  Map<String, dynamic>? _ttsLimitStatus;
  Map<String, double>? _ttsUsagePercentages;

  // 번역 서비스 추가
  final TranslationService _translationService = TranslationService();
  // OCR 서비스 추가
  final EnhancedOcrService _ocrService = EnhancedOcrService();

  @override
  void initState() {
    super.initState();
    
    // 서비스 초기화
    _pageContentService = PageContentService();
    _textReaderService = TextReaderService();
    
    // 플래시카드 단어 목록 업데이트
    _updateFlashcardWords();
    
    // 스타일 초기화
    _initStyles();
    
    // 비동기 데이터 로드
    if (widget.page.id != null) {
      // 이미 처리된 텍스트가 있는지 확인
      _processedText = _pageContentService.getProcessedText(widget.page.id!);
      
      if (_processedText == null) {
        // 텍스트 처리 상태로 변경
        setState(() {
          _isProcessingText = true;
        });
        
        // 비동기로 페이지 처리
        _processPageText();
      }
    }
  }

  @override
  void didUpdateWidget(PageContentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 페이지가 변경되면 TTS 중지
    if (oldWidget.page.id != widget.page.id) {
      _pageContentService.stopSpeaking();
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
      );

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      // debugPrint(
      //     '페이지 텍스트 처리 완료: ${widget.page.id}, 소요 시간: ${duration.inMilliseconds}ms');

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
    _textReaderService.dispose(); // TTS 서비스 정리
    super.dispose();
  }

  // TTS 초기화 메서드 추가
  void _initTextReader() async {
    await _textReaderService.init();
    
    // TTS 상태 변경 콜백 설정
    _textReaderService.setOnPlayingStateChanged((segmentIndex) {
      if (mounted) {
        setState(() {
          _playingSegmentIndex = segmentIndex;
        });
        debugPrint('페이지 콘텐츠 TTS 상태 변경: segmentIndex=$segmentIndex');
      }
    });
    
    // TTS 재생 완료 콜백 설정
    _textReaderService.setOnPlayingCompleted(() {
      if (mounted) {
        setState(() {
          _playingSegmentIndex = null;
        });
        debugPrint('페이지 콘텐츠 TTS 재생 완료');
      }
    });
  }

  // TTS 제한 확인
  Future<bool> _checkTtsLimit() async {
    if (_isCheckingTtsLimit) return false;
    _isCheckingTtsLimit = true;
    
    try {
      final usageLimitService = UsageLimitService();
      _ttsLimitStatus = await usageLimitService.checkFreeLimits();
      _ttsUsagePercentages = await usageLimitService.getUsagePercentages();
      
      _isCheckingTtsLimit = false;
      return _ttsLimitStatus?['ttsLimitReached'] == true;
    } catch (e) {
      debugPrint('TTS 제한 확인 중 오류: $e');
      _isCheckingTtsLimit = false;
      return false;
    }
  }

  // TTS 재생 메서드 추가
  void _playTts(String text, {int? segmentIndex}) async {
    if (text.isEmpty) return;
    
    // TTS 제한 확인
    bool isLimitReached = await _checkTtsLimit();
    if (isLimitReached) {
      // TTS 제한에 도달한 경우 다이얼로그 표시
      if (mounted) {
        UsageDialog.show(
          context,
          limitStatus: _ttsLimitStatus!,
          usagePercentages: _ttsUsagePercentages!,
          onContactSupport: () {
            // TODO: 지원팀 문의 기능 구현
          },
        );
      }
      return;
    }
    
    if (_playingSegmentIndex == segmentIndex) {
      // 이미 재생 중인 세그먼트를 다시 클릭한 경우 중지
      _textReaderService.stop();
      
      // 명시적으로 상태 업데이트 (콜백이 호출되지 않을 수 있어 추가)
      if (mounted) {
        setState(() {
          _playingSegmentIndex = null;
        });
        debugPrint('페이지 콘텐츠 TTS 중지 (사용자에 의해)');
      }
    } else {
      // 새로운 세그먼트 재생
      // 상태 먼저 업데이트
      if (mounted) {
        setState(() {
          _playingSegmentIndex = segmentIndex;
        });
      }
      
      try {
        if (segmentIndex != null) {
          await _textReaderService.readSegment(text, segmentIndex);
        } else {
          await _textReaderService.readText(text);
        }
        
        // 안전장치: 10초 후 재생이 여전히 진행 중인 경우 상태 리셋
        Future.delayed(const Duration(seconds: 10), () {
          if (mounted && _playingSegmentIndex == segmentIndex) {
            setState(() {
              _playingSegmentIndex = null;
            });
            debugPrint('페이지 콘텐츠 TTS 타임아웃으로 상태 리셋');
          }
        });
      } catch (e) {
        // 오류 발생 시 상태 리셋
        if (mounted) {
          setState(() {
            _playingSegmentIndex = null;
          });
          debugPrint('페이지 콘텐츠 TTS 재생 중 오류: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: ValueKey('page_${widget.page.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 텍스트 처리 중 표시
          if (_isProcessingText)
            const DotLoadingIndicator(message: '텍스트 처리 중이에요!')
          // 특수 처리 중 마커가 있는 경우
          else if (widget.page.originalText == '___PROCESSING___')
            const DotLoadingIndicator(message: '텍스트 처리 중이에요!')
          // 처리된 텍스트가 있는 경우
          else if (_processedText != null) ...[
            Builder(builder: (context) {
              // 항상 최신 ProcessedText 객체를 가져옴
              final ProcessedText displayedText;
              if (widget.page.id != null) {
                // 캐시에서 최신 상태 가져오기 (있으면)
                final cachedText = _pageContentService.getProcessedText(widget.page.id!);
                displayedText = cachedText ?? _processedText!;
                
                // 상태 디버깅
                debugPrint('표시할 ProcessedText: hashCode=${displayedText.hashCode}, '
                    'showFullText=${displayedText.showFullText}, '
                    'showPinyin=${displayedText.showPinyin}, '
                    'showTranslation=${displayedText.showTranslation}');
              } else {
                displayedText = _processedText!;
              }
            
              debugPrint(
                  'ProcessedText 표시: 원본 텍스트 ${displayedText.fullOriginalText.length}자, '
                  '번역 텍스트 ${displayedText.fullTranslatedText?.length ?? 0}자, '
                  'segments ${displayedText.segments?.length ?? 0}개');
                  
              // 개별 노트에 이미 설정된 값이 있으면 그것을 우선 사용
              // 설정된 값이 없는 경우에만 전역 세그먼트 모드 설정 적용
              final bool useExistingMode = displayedText.showFullTextModified;
              final bool showFullText = useExistingMode 
                  ? displayedText.showFullText 
                  : !widget.useSegmentMode;
                  
              debugPrint('뷰 모드 적용: useExistingMode=$useExistingMode, '
                  'existingMode=${displayedText.showFullText}, '
                  'globalMode=${!widget.useSegmentMode}, '
                  'finalMode=$showFullText');
                  
              final updatedText = displayedText.copyWith(
                showFullText: showFullText,
                showFullTextModified: true, // 수정됨 표시
                showPinyin: displayedText.showPinyin,
                showTranslation: displayedText.showTranslation,
              );
              
              // 모드 변경 적용 로깅
              debugPrint('세그먼트 모드 적용: useSegmentMode=${widget.useSegmentMode}, '
                'showFullText=$showFullText');
              
              // 업데이트된 설정으로 ProcessedText 저장
              if (widget.page.id != null) {
                _pageContentService.setProcessedText(widget.page.id!, updatedText);
              }
                  
              return ProcessedTextWidget(
                // 캐시 무효화를 위한 키 추가 (ProcessedText 상태가 변경될 때마다 새 위젯 생성)
                key: ValueKey('pt_${widget.page.id}_${updatedText.hashCode}_'
                    '${updatedText.showFullText}_'
                    '${updatedText.showPinyin}_'
                    '${updatedText.showTranslation}'),
                processedText: updatedText,
                onDictionaryLookup: _lookupWord,
                onCreateFlashCard: widget.onCreateFlashCard,
                flashCards: widget.flashCards,
                onDeleteSegment: widget.onDeleteSegment,
                onPlayTts: _playTts,
                playingSegmentIndex: _playingSegmentIndex,
                // UI 스타일 전달 - 클래스 레벨 스타일 변수 사용
                originalTextStyle: _originalTextStyle,
                pinyinTextStyle: _pinyinTextStyle,
                translatedTextStyle: _translatedTextStyle,
              );
            }),
          ]
          // 처리된 텍스트가 없는 경우 (특수 처리 중 문자열이 아닌 경우)
          else if ((widget.page.originalText.isNotEmpty && widget.page.originalText != '___PROCESSING___') || widget.isLoadingImage)
            const Center(
              child: DotLoadingIndicator(message: '텍스트 처리 중...'),
            )
          // 빈 페이지인 경우
          else
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.text_snippet_outlined, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('처리된 텍스트가 없습니다.'),
                  if (widget.page.id != null) ...[
                    const SizedBox(height: 16),
                    _buildAddTextButton(),
                  ],
                ],
              ),
            ),
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
          isExistingFlashcard: true,
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
            isExistingFlashcard: false,
          );
        }
      } else {
        // 사전에서 찾을 수 없는 경우, API로도 찾을 수 없는 경우
        if (!mounted) return;
        
        // 오류 메시지 표시
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('단어 "$word"를 사전에서 찾을 수 없습니다.')),
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

  Widget _buildAddTextButton() {
    // Implementation of _buildAddTextButton method
    // This method should return a Widget representing the "Add Text" button
    // For now, we'll return a placeholder
    return TextButton(
      onPressed: () {
        // Implementation of onPressed
      },
      child: const Text('텍스트 추가'),
    );
  }

  void _lookupWord(String word) {
    if (word.isEmpty) return;
    
    debugPrint('단어 사전 검색 시작: "$word"');
    
    // 플래시카드 단어 목록에서 이미 있는지 확인
    FlashCard? existingCard;
    if (widget.flashCards != null) {
      existingCard = widget.flashCards!.firstWhere(
        (card) => card.front == word,
        orElse: () => FlashCard(
          id: '',
          front: '',
          back: '',
          pinyin: '',
          createdAt: DateTime.now(),
        ),
      );
      if (existingCard.front.isEmpty) existingCard = null;
    }
    
    // 사전 검색 및 바텀시트 표시
    _showDictionaryBottomSheet(word, existingCard);
  }
  
  // 사전 검색 결과 바텀시트 표시
  Future<void> _showDictionaryBottomSheet(String word, FlashCard? existingCard) async {
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
          isExistingFlashcard: true,
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
            isExistingFlashcard: false,
          );
        }
      } else {
        // 내부 사전에서 찾지 못한 경우, DictionaryService를 직접 사용하여 Papago API로 검색
        final dictionaryService = DictionaryService();
        final result = await dictionaryService.lookupWord(word);
        
        if (result['success'] == true && result['entry'] != null) {
          final apiEntry = result['entry'] as DictionaryEntry;
          
          if (mounted) {
            DictionaryResultWidget.showDictionaryBottomSheet(
              context: context,
              entry: apiEntry,
              onCreateFlashCard: widget.onCreateFlashCard,
              isExistingFlashcard: false,
            );
          }
        } else {
          // 그래도 찾지 못한 경우에만 스낵바 표시
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('단어 "$word"를 사전에서 찾을 수 없습니다.')),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('사전 검색 중 오류 발생: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('사전 검색 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  /// **세그먼트 텍스트 표시 위젯**
  Widget _buildSegmentedView() {
    List<Widget> segmentWidgets = [];
    
    // 세그먼트가 없으면 전체 텍스트 표시로 대체
    if (_processedText == null ||
        _processedText!.segments == null ||
        _processedText!.segments!.isEmpty) {
      return _buildFullTextView();
    }
    
    // 세그먼트 위젯 생성
    for (int i = 0; i < _processedText!.segments!.length; i++) {
      final segment = _processedText!.segments![i];
      
      // 디버깅 정보 출력
      if (kDebugMode) {
        debugPrint('세그먼트 $i 원본 텍스트: "${segment.originalText}"');
        debugPrint('세그먼트 $i 번역 텍스트: "${segment.translatedText}"');
        debugPrint('세그먼트 $i 핀인: "${segment.pinyin}"');
      }

      // 원본 텍스트가 비어있으면
      if (segment.originalText.isEmpty) {
        if (kDebugMode) {
          debugPrint('세그먼트 $i 원본 텍스트가 비어있어 건너뜁니다.');
        }
        continue;
      }

      // 세그먼트 위젯 생성 (Dismissible로 감싸기)
      segmentWidgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: SegmentUtils.buildDismissibleSegment(
            key: ValueKey('segment_$i'),
            direction: DismissDirection.startToEnd,
            borderRadius: BorderRadius.circular(SpacingTokens.radiusXs),
            onDelete: () {
              if (widget.onDeleteSegment != null) {
                widget.onDeleteSegment!(i);
              }
            },
            confirmDismiss: (direction) async {
              // 세그먼트 삭제 콜백이 없으면 삭제하지 않음
              if (widget.onDeleteSegment == null) return false;
              return await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('문장 삭제'),
                  content: const Text('이 문장을 삭제하시겠습니까?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('취소'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('삭제'),
                      style: TextButton.styleFrom(foregroundColor: ColorTokens.primary),
                    ),
                  ],
                ),
              ) ?? false;
            },
            // 단일 컨테이너로 간소화
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(
                  color: ColorTokens.primarylight,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(SpacingTokens.radiusXs),
              ),
              padding: const EdgeInsets.all(0.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 원본 텍스트 표시 (항상 표시)
                  _buildSelectableText(
                    segment.originalText,
                    _originalTextStyle,
                  ),

                  // 핀인 표시 (showPinyin이 true일 때만)
                  if (segment.pinyin != null && 
                      segment.pinyin!.isNotEmpty && 
                      _processedText!.showPinyin)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Text(
                        segment.pinyin!,
                        style: _pinyinTextStyle,
                      ),
                    ),

                  // 번역 텍스트 표시 (showTranslation이 true일 때만)
                  if (_processedText!.showTranslation && 
                      segment.translatedText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0, bottom: 4.0),
                      child: _buildSelectableText(
                        segment.translatedText!,
                        _translatedTextStyle,
                      ),
                    ),
                  
                  // 구분선 추가 (마지막 세그먼트가 아닌 경우)
                  if (i < _processedText!.segments!.length - 1)
                    const Divider(height: 24, thickness: 1),
                  
                  // 마지막 세그먼트에는 여백 추가
                  if (i == _processedText!.segments!.length - 1)
                    const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 세그먼트 위젯이 없으면 전체 텍스트 표시
    if (segmentWidgets.isEmpty) {
      if (kDebugMode) {
        debugPrint('세그먼트 위젯이 없어 전체 텍스트를 표시합니다.');
      }
      return _buildFullTextView();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: segmentWidgets,
    );
  }
  
  /// **전체 텍스트 표시 위젯**
  Widget _buildFullTextView() {
    // _processedText 체크
    if (_processedText == null) {
      return const SizedBox.shrink();
    }
    
    // 디버그 로그 추가
    debugPrint('_buildFullTextView 호출 - 전체 문장 모드 렌더링');
    
    // 전체 너비를 사용하도록 Container로 감싸기
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 0), // 가로 패딩 제거
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 원본 텍스트 표시
          _buildSelectableText(_processedText!.fullOriginalText, _originalTextStyle),

          // 번역 텍스트 표시 (번역이 있고 showTranslation이 true인 경우)
          if (_processedText!.fullTranslatedText != null && 
              _processedText!.showTranslation)
            Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child:
                  _buildSelectableText(_processedText!.fullTranslatedText!, _translatedTextStyle),
            ),
        ],
      ),
    );
  }
  
  // 선택 가능한 텍스트 위젯 생성
  Widget _buildSelectableText(String text, [TextStyle? style]) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // 항상 제공된 스타일을 사용
    // 기본 스타일 정의는 이 메서드 밖에서 처리
    final effectiveStyle = style;
    
    return SelectableText(
      text,
      style: effectiveStyle,
    );
  }

  // 스타일 초기화 메서드
  void _initStyles() {
    _originalTextStyle = TypographyTokens.subtitle2Cn.copyWith(
      fontSize: 20,
      height: 1.6,
      fontWeight: FontWeight.w500,
      color: ColorTokens.textPrimary,
    );
    
    _pinyinTextStyle = TypographyTokens.body2.copyWith(
      color: ColorTokens.textGrey,
      fontWeight: FontWeight.w400,
      fontSize: 12,
      height: 1.2,
    );
    
    _translatedTextStyle = TypographyTokens.body2.copyWith(
      color: ColorTokens.textSecondary,
      fontSize: 15,
    );
  }

  /// 뷰 모드 전환
  Future<void> _toggleViewMode() async {
    if (_processedText == null) return;

    try {
      // 현재 모드
      final bool currentIsFullMode = _processedText!.showFullText;
      // 새 모드 (전환)
      final bool newIsFullMode = !currentIsFullMode;
      
      debugPrint('뷰 모드 전환: ${currentIsFullMode ? "전체" : "세그먼트"} -> ${newIsFullMode ? "전체" : "세그먼트"}');
      
      // 현재 ProcessedText 복제
      ProcessedText updatedText = _processedText!.toggleDisplayMode();
      
      // 1. 전체 모드로 전환하는데 전체 번역이 없는 경우
      if (newIsFullMode && 
          (updatedText.fullTranslatedText == null || updatedText.fullTranslatedText!.isEmpty)) {
        debugPrint('전체 번역 모드로 전환했으나 번역이 없어 전체 번역 수행 시작...');
        
        // 전체 번역 수행
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );
        
        try {
          final fullTranslatedText = await _translationService.translateText(
            updatedText.fullOriginalText,
            sourceLanguage: 'zh-CN',
            targetLanguage: 'ko'
          );
          
          // 번역 결과 업데이트
          updatedText = updatedText.copyWith(fullTranslatedText: fullTranslatedText);
          debugPrint('전체 번역 완료: ${fullTranslatedText.length}자');
        } catch (e) {
          debugPrint('전체 번역 중 오류 발생: $e');
        } finally {
          // 로딩 다이얼로그 닫기
          if (context.mounted) Navigator.of(context).pop();
        }
      } 
      // 2. 세그먼트 모드로 전환하는데 세그먼트가 없는 경우
      else if (!newIsFullMode && 
               (updatedText.segments == null || updatedText.segments!.isEmpty)) {
        debugPrint('세그먼트 모드로 전환했으나 세그먼트가 없어 문장별 처리 시작...');
        
        // 로딩 다이얼로그 표시
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );
        
        try {
          // 세그먼트 처리 (문장 분리 및 번역)
          // _processTextSegmentsInParallel은 private 메서드이므로 processText 사용
          final processedResult = await _ocrService.processText(
            updatedText.fullOriginalText, 
            "languageLearning"
          );
          
          // 세그먼트 결과 업데이트
          if (processedResult.segments != null && processedResult.segments!.isNotEmpty) {
            updatedText = updatedText.copyWith(segments: processedResult.segments);
            debugPrint('세그먼트 처리 완료: ${processedResult.segments!.length}개 세그먼트');
          } else {
            debugPrint('세그먼트 처리 시도했으나 결과가 없음');
          }
        } catch (e) {
          debugPrint('세그먼트 처리 중 오류 발생: $e');
        } finally {
          // 로딩 다이얼로그 닫기
          if (context.mounted) Navigator.of(context).pop();
        }
      }
      
      // 상태 업데이트
      setState(() {
        _processedText = updatedText;
      });
      
      // 업데이트된 ProcessedText 저장 (캐시 업데이트)
      if (widget.page.id != null) {
        _pageContentService.setProcessedText(widget.page.id!, updatedText);
        await _pageContentService.updatePageCache(
          widget.page.id!, 
          updatedText, 
          "languageLearning"
        );
      }
    } catch (e) {
      debugPrint('뷰 모드 전환 중 오류 발생: $e');
    }
  }
}
