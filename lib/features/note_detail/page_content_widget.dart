import 'package:flutter/material.dart';
import 'dart:io';
import '../../core/models/page.dart' as page_model;
import '../../core/models/processed_text.dart';
import '../../core/models/flash_card.dart';
import '../../core/models/dictionary.dart';
import 'processed_text_widget.dart';
import 'managers/content_manager.dart';
import '../../widgets/dictionary_result_widget.dart';
import 'package:flutter/foundation.dart'; // kDebugMode 사용하기 위한 import
import '../../core/widgets/dot_loading_indicator.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/theme/tokens/spacing_tokens.dart';
import '../../core/utils/segment_utils.dart';
import '../../core/services/text_processing/text_reader_service.dart'; // TTS 서비스 추가
import '../../core/services/common/usage_limit_service.dart';
import '../../core/widgets/usage_dialog.dart';
import '../../core/services/text_processing/translation_service.dart';
import '../../core/services/text_processing/enhanced_ocr_service.dart';
import '../../core/services/dictionary/dictionary_service.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import '../../core/services/content/page_service.dart';
import 'dart:async';
import 'page_image_widget.dart'; // PageImageWidget 추가

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
    this.imageFile,
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
  final ContentManager _contentManager = ContentManager();
  final DictionaryService _dictionaryService = DictionaryService();
  final TextReaderService _textReaderService = TextReaderService();
  final PageService _pageService = PageService();
  
  // 상태 변수들
  ProcessedText? _processedText;
  bool _isProcessingText = false;
  bool _showFullText = false;
  bool _showPinyin = true;
  bool _showTranslation = true;
  
  // 추가 상태 변수
  bool _hasProcessedText = false;
  bool _isProcessing = false;
  bool _isLoading = false;
  bool _isError = false;
  String _errorMessage = '';
  Timer? _backgroundCheckTimer;
  
  // 스타일 및 레이아웃 관련 변수
  late TextStyle _originalTextStyle;
  late TextStyle _translatedTextStyle;
  late TextStyle _pinyinTextStyle;

  Set<String> _flashcardWords = {};
  int? _playingSegmentIndex; // 현재 재생 중인 세그먼트 인덱스 추가

  // TTS 사용량 제한 확인 변수
  bool _isCheckingTtsLimit = false;
  Map<String, dynamic>? _ttsLimitStatus;
  Map<String, double>? _ttsUsagePercentages;

  // 번역 서비스 추가
  final TranslationService _translationService = TranslationService();
  // OCR 서비스 추가
  final EnhancedOcrService _ocrService = EnhancedOcrService();

  // timeout 안내 관련 변수 추가
  Timer? _timeoutTimer;
  bool _isTimeout = false;

  @override
  void initState() {
    super.initState();
    
    // 서비스 초기화
    _textReaderService.init();
    
    // 플래시카드 단어 목록 업데이트
    _updateFlashcardWords();
    
    // 스타일 초기화
    _initStyles();
    
    // 비동기 데이터 로드
    if (widget.page.id != null) {
      // 이미 처리된 텍스트가 있는지 확인
      _getProcessedTextFromCache();
    }

    // timeout 타이머 시작
    _startTimeoutTimer();
  }

  // 캐시에서 처리된 텍스트 가져오기
  Future<void> _getProcessedTextFromCache() async {
    if (widget.page.id == null) return;
    
    try {
      final cachedText = await _contentManager.getProcessedText(widget.page.id!);
      
      if (mounted) {
        setState(() {
          _processedText = cachedText;
          
          if (_processedText == null) {
            // 텍스트 처리 상태로 변경
            _isProcessingText = true;
            // 비동기로 페이지 처리
            _processPageText();
          }
        });
      }
    } catch (e) {
      debugPrint('캐시에서 처리된 텍스트 가져오기 오류: $e');
      if (mounted) {
        setState(() {
          _isProcessingText = true;
        });
        _processPageText();
      }
    }
  }

  @override
  void didUpdateWidget(PageContentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 페이지가 변경되면 TTS 중지
    if (oldWidget.page.id != widget.page.id) {
      _contentManager.stopSpeaking();
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
      _isTimeout = false;
    });
    _startTimeoutTimer();
    final startTime = DateTime.now();
    debugPrint('페이지 텍스트 처리 시작: [32m${widget.page.id}[0m');
    try {
      final processedText = await _contentManager.processPageText(
        page: widget.page,
        imageFile: widget.imageFile,
      );
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      if (kDebugMode) {
        debugPrint('페이지 텍스트 처리 소요시간: ${duration.inMilliseconds}ms');
      }
      if (mounted) {
        setState(() {
          _processedText = processedText;
          _isProcessingText = false;
          _isTimeout = false;
        });
        _timeoutTimer?.cancel();
      }
    } catch (e) {
      debugPrint('텍스트 처리 중 오류 발생: $e');
      if (mounted) {
        setState(() {
          _isProcessingText = false;
        });
        _timeoutTimer?.cancel();
      }
    }
  }

  @override
  void dispose() {
    // 화면을 나갈 때 TTS 중지
    _contentManager.stopSpeaking();
    _textReaderService.dispose(); // TTS 서비스 정리
    _timeoutTimer?.cancel();
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
    final pt = _processedText;
    final List<Widget> segmentWidgets = [];
    if (pt != null && pt.segments != null && pt.segments!.isNotEmpty) {
      for (final seg in pt.segments!) {
        segmentWidgets.add(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 중국어(원문)는 항상 바로 표시
            if (seg.original != null && seg.original!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 2.0),
                child: Text(seg.original!, style: _originalTextStyle),
              ),
            // 2. 병음은 준비되는 대로 표시
            if (seg.pinyin != null && seg.pinyin!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 2.0),
                child: Text(seg.pinyin!, style: _pinyinTextStyle),
              ),
            // 3. 번역도 준비되는 대로 표시
            if (seg.translatedText != null && seg.translatedText!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(seg.translatedText!, style: _translatedTextStyle),
              ),
          ],
        ));
      }
    }
    return SingleChildScrollView(
      key: ValueKey('page_${widget.page.id}'),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 페이지 이미지 표시 (이미지가 있는 경우)
          if (widget.imageFile != null || (widget.page.imageUrl != null && widget.page.imageUrl!.isNotEmpty))
            Padding(
              padding: const EdgeInsets.fromLTRB(24,0,24,16),
              child: PageImageWidget(
                imageFile: widget.imageFile,
                imageUrl: widget.page.imageUrl,
                page: widget.page,
                isLoading: widget.isLoadingImage,
                title: '',
                showTitle: false,
                style: ImageContainerStyle.noteDetail,
                height: 200,
                enableFullScreen: true,
              ),
            ),
          
          // 텍스트 처리 중 표시 및 나머지 콘텐츠는 좌우 패딩 적용
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // timeout 안내
                if (_isTimeout) ...[
                  Column(
                    children: [
                      const SizedBox(height: 16),
                      Text(
                        '⚠️ LLM 처리 시간이 오래 걸리고 있습니다.\n일시적인 네트워크 문제이거나, 서버가 혼잡할 수 있습니다.\n잠시 후 다시 시도해 주세요.',
                        style: TypographyTokens.body2.copyWith(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ]
                else if (_isProcessingText && !_isTimeout) ...[
                  const DotLoadingIndicator(message: '텍스트 처리 중이에요!'),
                ]
                else if (widget.page.originalText == '___PROCESSING___') ...[
                  const DotLoadingIndicator(message: '텍스트 처리 중이에요!'),
                ]
                else if (_processedText != null) ...[
                  ...segmentWidgets,
                ]
                else if ((widget.page.originalText.isNotEmpty && widget.page.originalText != '___PROCESSING___') || widget.isLoadingImage) ...[
                  const Center(
                    child: DotLoadingIndicator(message: '텍스트 처리 중...'),
                  ),
                ]
                else ...[
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
      final entry = await _contentManager.lookupWord(word);

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
    final Set<String> newFlashcardWords = {};
    
    if (widget.flashCards == null || widget.flashCards!.isEmpty) {
      setState(() {
        _flashcardWords = {};
      });
      return;
    }
    
    // 플래시카드 앞면(중국어 단어)만 추출
    for (var card in widget.flashCards!) {
      if (card.front.isNotEmpty) {
        newFlashcardWords.add(card.front);
      }
    }
    
    // 변경 사항이 있는 경우에만 setState 호출
    if (_flashcardWords.length != newFlashcardWords.length ||
        !_flashcardWords.containsAll(newFlashcardWords) ||
        !newFlashcardWords.containsAll(_flashcardWords)) {
      
      setState(() {
        _flashcardWords = newFlashcardWords;
      });
      
      if (kDebugMode) {
        print('플래시카드 단어 목록 업데이트: ${_flashcardWords.length}개');
        if (_flashcardWords.isNotEmpty) {
          print('첫 5개 단어: ${_flashcardWords.take(5).join(', ')}');
        }
      }
    }
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

      debugPrint('사전 서비스에서 단어 검색 시작: $word');
      
      // 사전 서비스에서 단어 검색 
      final entry = await _contentManager.lookupWord(word);

      if (entry != null) {
        debugPrint('단어 검색 성공: ${entry.word}, 의미: ${entry.meaning}');
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
        debugPrint('내부 사전에서 단어를 찾지 못해 외부 API 직접 사용을 시도합니다');
        final dictionaryService = DictionaryService();
        final result = await dictionaryService.lookupWord(word);
        
        debugPrint('외부 API 검색 결과: ${result['success']}, 메시지: ${result['message'] ?? "없음"}');
        
        if (result['success'] == true && result['entry'] != null) {
          final apiEntry = result['entry'] as DictionaryEntry;
          debugPrint('외부 API에서 단어 찾음: ${apiEntry.word}, 의미: ${apiEntry.meaning}');
          
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
          debugPrint('내부 및 외부 사전 모두에서 단어를 찾지 못했습니다: $word');
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
        _contentManager.setProcessedText(widget.page.id!, updatedText);
        await _contentManager.updatePageCache(
          widget.page.id!, 
          updatedText, 
          "languageLearning"
        );
      }
    } catch (e) {
      debugPrint('뷰 모드 전환 중 오류 발생: $e');
    }
  }

  // ProcessedText 저장 함수 추가 (비동기 처리를 FutureBuilder에서 분리)
  Future<void> _saveProcessedText(String pageId, ProcessedText processedText) async {
    try {
      if (!mounted) return; // 위젯이 이미 dispose된 경우 중단
      
      await _contentManager.setProcessedText(pageId, processedText);
      
      // 로깅
      debugPrint('processedText 저장 완료: pageId=$pageId');
    } catch (e) {
      debugPrint('processedText 저장 중 오류 발생: $e');
    }
  }

  void _startTimeoutTimer() {
    _timeoutTimer?.cancel();
    _isTimeout = false;
    _timeoutTimer = Timer(const Duration(seconds: 60), () {
      if (mounted && _isProcessingText) {
        setState(() {
          _isTimeout = true;
        });
      }
    });
  }
}
