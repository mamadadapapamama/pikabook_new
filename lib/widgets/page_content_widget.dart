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
import '../utils/segment_utils.dart';
import '../services/text_reader_service.dart'; // TTS 서비스 추가

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
  final PageContentService _pageContentService = PageContentService();
  final TextReaderService _textReaderService = TextReaderService(); // TTS 서비스 추가

  ProcessedText? _processedText;
  bool _isProcessingText = false;
  Set<String> _flashcardWords = {};
  int? _playingSegmentIndex; // 현재 재생 중인 세그먼트 인덱스 추가

  @override
  void initState() {
    super.initState();
    _processPageText();
    _updateFlashcardWords();
    _initTextReader(); // TTS 초기화 추가
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
      }
    });
    
    // TTS 재생 완료 콜백 설정
    _textReaderService.setOnPlayingCompleted(() {
      if (mounted) {
        setState(() {
          _playingSegmentIndex = null;
        });
      }
    });
  }

  // TTS 재생 메서드 추가
  void _playTts(String text, {int? segmentIndex}) {
    if (text.isEmpty) return;
    
    if (_playingSegmentIndex == segmentIndex) {
      // 이미 재생 중인 세그먼트를 다시 클릭한 경우 중지
      _textReaderService.stop();
    } else {
      // 새로운 세그먼트 재생
      if (segmentIndex != null) {
        _textReaderService.readSegment(text, segmentIndex);
      } else {
        _textReaderService.readText(text);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: ValueKey('page_${widget.page.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 텍스트 처리 중 표시
          if (_isProcessingText)
            const DotLoadingIndicator(message: '페이지 처리 중...')
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
                onPlayTts: _playTts, // TTS 콜백 추가
                playingSegmentIndex: _playingSegmentIndex, // 현재 재생 중인 세그먼트 인덱스 추가
              );
            }),
          ]
          // 처리된 텍스트가 없는 경우
          else if (widget.page.originalText.isNotEmpty || widget.isLoadingImage)
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
        if (mounted) {
          // 사전에서 찾지 못한 경우 오류 메시지
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('단어 "$word"를 사전에서 찾을 수 없습니다.')),
          );
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

  /// **세그먼트별 텍스트 표시 위젯**
  Widget _buildSegmentedView() {
    List<Widget> segmentWidgets = [];
    if (_processedText == null || _processedText!.segments == null) {
      return _buildFullTextView();
    }

    for (int i = 0; i < _processedText!.segments!.length; i++) {
      final segment = _processedText!.segments![i];

      // 디버깅 정보 출력
      if (kDebugMode) {
        debugPrint('세그먼트 $i 원본 텍스트: "${segment.originalText}"');
        debugPrint('세그먼트 $i 번역 텍스트: "${segment.translatedText}"');
        debugPrint('세그먼트 $i 핀인: "${segment.pinyin}"');
      }

      // 원본 텍스트가 비어있으면 건너뜀
      if (segment.originalText.isEmpty) {
        if (kDebugMode) {
          debugPrint('세그먼트 $i 원본 텍스트가 비어있어 건너뜁니다.');
        }
        continue;
      }

      // 세그먼트 위젯 생성 (Dismissible로 감싸기)
      segmentWidgets.add(
        SegmentUtils.buildDismissibleSegment(
          key: ValueKey('segment_$i'),
          direction: DismissDirection.startToEnd,
          onDelete: () {
            if (widget.onDeleteSegment != null) {
              widget.onDeleteSegment!(i);
            }
          },
          confirmDismiss: (direction) async {
            // 세그먼트 삭제 콜백이 없으면 삭제하지 않음
            if (widget.onDeleteSegment == null) return false;
            return true;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 첫번째 세그먼트 위에 여백 추가
              if (i == 0)
                const SizedBox(height: 8),
                
              // 원본 텍스트 표시 (항상 표시)
              _buildSelectableText(
                segment.originalText,
                TypographyTokens.subtitle2Cn.copyWith(
                  height: 1.5,
                  color: ColorTokens.textPrimary,
                ),
              ),

              // 핀인 표시 (showPinyin이 true일 때만)
              if (segment.pinyin != null && 
                  segment.pinyin!.isNotEmpty && 
                  _processedText!.showPinyin)
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Text(
                    segment.pinyin!,
                    style: TypographyTokens.body2En.copyWith(
                      color: ColorTokens.textGrey,
                    ),
                  ),
                ),

              // 번역 텍스트 표시 (showTranslation이 true일 때만)
              if (_processedText!.showTranslation && 
                  segment.translatedText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
                  child: _buildSelectableText(
                    segment.translatedText!,
                    TypographyTokens.body2.copyWith(
                      color: ColorTokens.textSecondary,
                    ),
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
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 원본 텍스트 표시
        _buildSelectableText(_processedText!.fullOriginalText),

        // 번역 텍스트 표시 (번역이 있고 showTranslation이 true인 경우)
        if (_processedText!.fullTranslatedText != null && 
            _processedText!.showTranslation)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child:
                _buildSelectableText(_processedText!.fullTranslatedText!),
          ),
      ],
    );
  }
  
  // 선택 가능한 텍스트 위젯 생성 - 메모이제이션 추가
  Widget _buildSelectableText(String text, [TextStyle? style]) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    
    final defaultStyle = TypographyTokens.subtitle2Cn.copyWith(
      height: 1.5,
      fontWeight: FontWeight.w600,
      color: ColorTokens.textPrimary,
    );
    final effectiveStyle = style ?? defaultStyle;
    
    // 짧은 텍스트의 경우 선택 가능하지만 간단한 Text 위젯 사용
    if (text.length < 100) {
      return SelectableText(
        text,
        style: effectiveStyle,
      );
    }
    
    // 긴 텍스트의 경우 선택 가능한 텍스트 위젯 사용
    return SelectableText(
      text,
      style: effectiveStyle,
    );
  }
}
