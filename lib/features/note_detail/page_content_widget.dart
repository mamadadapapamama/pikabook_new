import 'package:flutter/material.dart';
import 'dart:io';
import '../../core/models/page.dart' as page_model;
import '../../core/models/processed_text.dart';
import '../../core/models/flash_card.dart';
import '../../core/models/dictionary.dart';
import 'managers/page_content_manager.dart';
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
import '../../core/services/dictionary/dictionary_service.dart';
import '../../core/services/content/page_service.dart';
import 'dart:async';
import 'page_image_widget.dart'; // PageImageWidget 추가
import 'processed_text_widget.dart'; // ProcessedTextWidget 추가

/// PageContentWidget은 노트의 페이지 전체 컨텐츠를 관리하고 표시하는 위젯입니다.
///
/// ## 주요 기능
/// - 페이지 이미지 및 텍스트 로딩/처리 상태 관리
/// - 사전 검색 및 바텀시트 표시
/// - 플래시카드 관련 상태 관리
/// - 텍스트 모드 전환(세그먼트/전체) 처리
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
  final SegmentManager _segmentManager = SegmentManager();
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
      final cachedText = await _segmentManager.getProcessedText(widget.page.id!);
      
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
      _segmentManager.stopSpeaking();
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
    debugPrint('페이지 텍스트 처리 시작: \x1b[32m[32m${widget.page.id}\x1b[0m');
    try {
      final processedText = await _segmentManager.processPageText(
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

  // 세그먼트 삭제 핸들러: SegmentManager만 사용
  Future<void> _handleDeleteSegment(int index) async {
    if (widget.page.id == null) return;
    final updatedPage = await _segmentManager.deleteSegment(
      noteId: widget.noteId,
      page: widget.page,
      segmentIndex: index,
    );
    if (updatedPage != null) {
      final processedText = await _segmentManager.getProcessedText(widget.page.id!);
      if (mounted) {
        setState(() {
          _processedText = processedText;
        });
      }
    }
  }

  @override
  void dispose() {
    // 화면을 나갈 때 TTS 중지
    _segmentManager.stopSpeaking();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  // TTS 재생: SegmentManager만 사용
  void _playTts(String text, {int? segmentIndex}) async {
    await _segmentManager.playTts(text, segmentIndex: segmentIndex);
    // playingSegmentIndex 등 UI 상태는 필요시 SegmentManager 콜백으로만 처리
  }

  @override
  Widget build(BuildContext context) {
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
                  ProcessedTextWidget(
                    processedText: _processedText!,
                    onDictionaryLookup: _showDictionaryResult,
                    onCreateFlashCard: widget.onCreateFlashCard,
                    flashCards: widget.flashCards,
                    onDeleteSegment: _handleDeleteSegment,
                    onPlayTts: _playTts,
                    playingSegmentIndex: _playingSegmentIndex,
                    originalTextStyle: _originalTextStyle,
                    pinyinTextStyle: _pinyinTextStyle,
                    translatedTextStyle: _translatedTextStyle,
                  ),
                ]
                else if ((widget.page.originalText.isNotEmpty && widget.page.originalText != '___PROCESSING___') || widget.isLoadingImage) ...[
                  const Center(
                    child: DotLoadingIndicator(message: '텍스트 처리 중...'),
                  ),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 사전 결과 표시: SegmentManager만 사용
  void _showDictionaryResult(String word) async {
    // 플래시카드에 이미 있는 단어인지 확인
    FlashCard? existingCard;
    if (widget.flashCards != null) {
      for (final card in widget.flashCards!) {
        if (card.front == word) {
          existingCard = card;
          break;
        }
      }
    }
    try {
      if (existingCard != null) {
        if (!mounted) return;
        final customEntry = DictionaryEntry(
          word: existingCard.front,
          pinyin: existingCard.pinyin ?? '',
          meaning: existingCard.back,
          examples: [],
        );
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => Container(
            decoration: BoxDecoration(
              color: ColorTokens.surface,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(SpacingTokens.lg),
              ),
            ),
            child: DictionaryResultWidget(
              entry: customEntry,
              onCreateFlashCard: widget.onCreateFlashCard,
              isExistingFlashcard: true,
            ),
          ),
        );
        return;
      }
      final entry = await _segmentManager.lookupWord(word);
      if (entry != null) {
        if (mounted) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => Container(
              decoration: BoxDecoration(
                color: ColorTokens.surface,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(SpacingTokens.lg),
                ),
              ),
              child: DictionaryResultWidget(
                entry: entry,
                onCreateFlashCard: widget.onCreateFlashCard,
                isExistingFlashcard: false,
              ),
            ),
          );
        }
      } else {
        if (!mounted) return;
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

        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => Container(
            decoration: BoxDecoration(
              color: ColorTokens.surface,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(SpacingTokens.lg),
              ),
            ),
            child: DictionaryResultWidget(
              entry: customEntry,
              onCreateFlashCard: widget.onCreateFlashCard,
              isExistingFlashcard: true,
            ),
          ),
        );
        return;
      }

      debugPrint('사전 서비스에서 단어 검색 시작: $word');
      
      // 사전 서비스에서 단어 검색 
      final entry = await _segmentManager.lookupWord(word);

      if (entry != null) {
        debugPrint('단어 검색 성공: ${entry.word}, 의미: ${entry.meaning}');
        if (mounted) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => Container(
              decoration: BoxDecoration(
                color: ColorTokens.surface,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(SpacingTokens.lg),
                ),
              ),
              child: DictionaryResultWidget(
                entry: entry,
                onCreateFlashCard: widget.onCreateFlashCard,
                isExistingFlashcard: false,
              ),
            ),
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
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => Container(
                decoration: BoxDecoration(
                  color: ColorTokens.surface,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(SpacingTokens.lg),
                  ),
                ),
                child: DictionaryResultWidget(
                  entry: apiEntry,
                  onCreateFlashCard: widget.onCreateFlashCard,
                  isExistingFlashcard: false,
                ),
              ),
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

  
  // ProcessedText 저장 함수 추가 (비동기 처리를 FutureBuilder에서 분리)
  Future<void> _saveProcessedText(String pageId, ProcessedText processedText) async {
    try {
      if (!mounted) return; // 위젯이 이미 dispose된 경우 중단
      
      await _segmentManager.setProcessedText(pageId, processedText);
      
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
