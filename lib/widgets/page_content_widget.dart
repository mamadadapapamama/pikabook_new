import 'package:flutter/material.dart';
import 'dart:io';
import '../models/page.dart' as page_model;
import '../models/processed_text.dart';
import '../models/flash_card.dart';
import '../models/dictionary_entry.dart';
import 'text_section_widget.dart';
import 'processed_text_widget.dart';
import '../services/page_content_service.dart';
import 'dictionary_result_widget.dart';
import 'package:flutter/foundation.dart'; // kDebugMode 사용하기 위한 import
import 'pikabook_loader.dart';
import 'package:flutter/services.dart';
import '../services/dictionary_service.dart';
import '../services/text_reader_service.dart';
import '../utils/text_display_mode.dart';
import 'dot_loading_indicator.dart';

/// 페이지 내의 이미지, 텍스트 처리상태, 처리된 텍스트 등을 표시
/// 텍스트 모드전환, 사전 검색 등 처리
/// 텍스트 처리중 상태, 플래시카드 단어 목록 등 관리 (counter와 하이라이터를 위해)

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
    super.dispose();
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
              );
            }),
          ]
          // 처리된 텍스트가 없는 경우
          else if (widget.page.originalText.isNotEmpty || widget.isLoadingImage)
            const Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('텍스트 처리 중...'),
                ],
              ),
            )
          // 빈 페이지인 경우
          else
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.text_snippet_outlined, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('아직 텍스트가 없습니다.'),
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
        // 사전에서 찾을 수 없는 경우, 바로 플래시카드 추가 다이얼로그 표시
        if (!mounted) return;

        // 커스텀 다이얼로그 표시
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('단어 찾기 결과'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('단어: $word'),
                const SizedBox(height: 16),
                const Text('사전에서 찾을 수 없습니다. 플래시카드에 추가하시겠습니까?'),
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
    // 디버그 로그 추가
    debugPrint('_buildSegmentedView 호출 - 세그먼트 모드 렌더링');
    
    // _processedText 체크
    if (_processedText == null) {
      return const SizedBox.shrink();
    }
    
    // 세그먼트가 없으면 빈 컨테이너 반환
    if (_processedText!.segments == null ||
        _processedText!.segments!.isEmpty) {
      if (kDebugMode) {
        debugPrint('세그먼트가 없습니다.');
      }

      // 세그먼트가 없으면 전체 텍스트 표시
      return _buildFullTextView();
    }

    if (kDebugMode) {
      debugPrint('세그먼트 수: ${_processedText!.segments!.length}');
      debugPrint('표시 설정: 원문=${true}, 병음=${_processedText!.showPinyin}, 번역=${_processedText!.showTranslation}');
    }

    // 세그먼트 목록을 위젯 목록으로 변환
    List<Widget> segmentWidgets = [];

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
        Dismissible(
          key: ValueKey('segment_$i'),
          direction: DismissDirection.startToEnd, // 왼쪽에서 오른쪽으로 스와이프
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 20.0),
            color: Colors.red,
            child: const Icon(
              Icons.delete,
              color: Colors.white,
            ),
          ),
          confirmDismiss: (direction) async {
            // 세그먼트 삭제 콜백이 없으면 삭제하지 않음
            if (widget.onDeleteSegment == null) return false;
            
            // 세그먼트 삭제 콜백 호출
            widget.onDeleteSegment!(i);
            return true;
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // TTS 버튼 추가
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(
                      _playingSegmentIndex == i
                          ? Icons.stop_circle
                          : Icons.play_circle,
                      color:
                          _playingSegmentIndex == i ? Colors.red : Colors.blue,
                    ),
                    onPressed: () {
                      _playTts(segment.originalText, segmentIndex: i);
                    },
                    tooltip: _playingSegmentIndex == i ? '중지' : '읽기',
                    iconSize: 24,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),

              const SizedBox(height: 4.0),

              // 원본 텍스트 표시 (항상 표시)
              _buildSelectableText(segment.originalText),

              // 핀인 표시 (showPinyin이 true일 때만)
              if (segment.pinyin != null && 
                  segment.pinyin!.isNotEmpty && 
                  _processedText!.showPinyin)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, bottom: 4.0),
                  child: Text(
                    segment.pinyin!,
                    style: const TextStyle(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey,
                    ),
                  ),
                ),

              // 번역 텍스트 표시 (showTranslation이 true일 때만)
              if (_processedText!.showTranslation && 
                  segment.translatedText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                  child: _buildSelectableText(segment.translatedText!),
                ),
                
              // 구분선 추가 (마지막 세그먼트가 아닌 경우)
              if (i < _processedText!.segments!.length - 1)
                const Divider(height: 24, thickness: 1),
              
              // 마지막 세그먼트에는 여백 추가
              if (i == _processedText!.segments!.length - 1)
                const SizedBox(height: 16),
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
            padding: const EdgeInsets.only(top: 8.0),
            child:
                _buildSelectableText(_processedText!.fullTranslatedText!),
          ),
      ],
    );
  }
  
  // TTS 재생용 임시 변수 및 메서드
  int? _playingSegmentIndex;
  
  void _playTts(String text, {int? segmentIndex}) {
    if (text.isEmpty) return;
    
    setState(() {
      if (_playingSegmentIndex == segmentIndex) {
        // 이미 재생 중이면 중지
        _playingSegmentIndex = null;
        _pageContentService.stopSpeaking();
      } else {
        // 새로 재생
        _playingSegmentIndex = segmentIndex;
        _pageContentService.speakText(text);
      }
    });
  }
  
  // 선택 가능한 텍스트 위젯 생성 - 메모이제이션 추가
  Widget _buildSelectableText(String text) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // 짧은 텍스트의 경우 선택 가능하지만 간단한 Text 위젯 사용
    if (text.length < 100) {
      return SelectableText(
        text,
        style: const TextStyle(fontSize: 16),
      );
    }
    
    // 긴 텍스트의 경우 선택 가능한 텍스트 위젯 사용
    return SelectableText(
      text,
      style: const TextStyle(fontSize: 16),
    );
  }
}
