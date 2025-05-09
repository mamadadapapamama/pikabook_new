import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:io';
import '../../core/models/processed_text.dart';
import '../../core/models/flash_card.dart';
import '../../core/models/page.dart' as pika_page;
import '../../core/models/dictionary.dart';
import '../../core/models/note.dart';
import '../../core/services/dictionary/dictionary_service.dart';
import '../../core/services/content/page_service.dart';
import '../../core/services/media/tts_service.dart';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import '../../core/services/common/usage_limit_service.dart';
import '../../core/services/text_processing/enhanced_ocr_service.dart';
import '../../core/services/text_processing/translation_service.dart';
import '../../core/services/workflow/text_processing_workflow.dart';
import 'processed_text_widget.dart';
import 'managers/content_manager.dart';
import 'page_image_widget.dart'; // PageImageWidget 추가
import 'note_detail_state.dart'; // LoadingState Enum import 추가
import '../../core/theme/tokens/spacing_tokens.dart';
import '../../core/utils/segment_utils.dart';
import '../../core/services/text_processing/.text_reader_service.dart'; // TTS 서비스 추가
import '../../core/widgets/usage_dialog.dart';

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
  final pika_page.Page page;
  final File? imageFile;
  final bool isLoadingImage;
  final String noteId;
  final Function(String, String, {String? pinyin}) onCreateFlashCard;
  final List<FlashCard>? flashCards;
  final Function(int)? onDeleteSegment;
  final bool useSegmentMode;
  final LoadingState loadingState;
  final Function(LoadingState)? onLoadingStateChanged;
  final Function(ComponentState)? onContentReady;

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
    this.loadingState = LoadingState.contentReady,
    this.onLoadingStateChanged,
    this.onContentReady,
  });

  @override
  State<PageContentWidget> createState() => _PageContentWidgetState();
}

class _PageContentWidgetState extends State<PageContentWidget> {
  final ContentManager _contentManager = ContentManager();
  final DictionaryService _dictionaryService = DictionaryService();
  final TtsService _ttsService = TtsService();
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

  bool _isImageReady = false;
  bool _isTextReady = false;

  @override
  void initState() {
    super.initState();
    
    // 서비스 초기화
    _ttsService.init();
    
    // 플래시카드 단어 목록 업데이트
    _updateFlashcardWords();
    
    // 스타일 초기화
    _initStyles();
    
    // 초기 상태값 설정
    _isImageReady = false;
    _isTextReady = false;
    
    // 디버그 로깅
    if (kDebugMode) {
      debugPrint('PageContentWidget 초기화: pageId=${widget.page.id}, 이미지=${widget.imageFile != null ? "있음" : "없음"}, 텍스트=${widget.page.originalText.isNotEmpty ? "있음" : "없음"}');
    }
    
    // 비동기 데이터 로드
    if (widget.page.id != null) {
      // 이미 처리된 텍스트가 있는지 확인
      _getProcessedTextFromCache();
    }
    
    // 로딩 상태 변경 확인 및 콜백 호출
    if (widget.onLoadingStateChanged != null && _isProcessingText) {
      widget.onLoadingStateChanged!(LoadingState.pageProcessing);
    }

    // 이미지가 없는 경우 이미지는 이미 준비됨으로 처리
    if (widget.imageFile == null && (widget.page.imageUrl == null || widget.page.imageUrl!.isEmpty)) {
      _isImageReady = true;
      if (kDebugMode) {
        debugPrint('이미지 없음 - 이미지 준비 상태로 설정');
      }
      _checkAndUpdateReadyState();
    }
    
    // 텍스트가 없는 경우 텍스트는 이미 준비됨으로 처리
    if (widget.page.originalText.isEmpty) {
      _isTextReady = true;
      if (kDebugMode) {
        debugPrint('텍스트 없음 - 텍스트 준비 상태로 설정');
      }
      _checkAndUpdateReadyState();
    }
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
            
            // 로딩 상태 변경 콜백 호출
            if (widget.onLoadingStateChanged != null) {
              widget.onLoadingStateChanged!(LoadingState.pageProcessing);
            }
            
            // 비동기로 페이지 처리
            _processPageText();
          } else if (widget.onLoadingStateChanged != null) {
            // 콘텐츠가 준비된 상태로 콜백 호출
            widget.onLoadingStateChanged!(LoadingState.contentReady);
          }
        });
      }
    } catch (e) {
      debugPrint('캐시에서 처리된 텍스트 가져오기 오류: $e');
      if (mounted) {
        setState(() {
          _isProcessingText = true;
        });
        
        // 로딩 상태 변경 콜백 호출
        if (widget.onLoadingStateChanged != null) {
          widget.onLoadingStateChanged!(LoadingState.pageProcessing);
        }
        
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
    });
    
    // 로딩 상태 변경 콜백 호출
    if (widget.onLoadingStateChanged != null) {
      widget.onLoadingStateChanged!(LoadingState.pageProcessing);
    }

    final startTime = DateTime.now();
    debugPrint('페이지 텍스트 처리 시작: ${widget.page.id}');

    try {
      final processedText = await _contentManager.processPageText(
        page: widget.page,
        imageFile: widget.imageFile,
      );

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);
      
      if (mounted) {
        setState(() {
          _processedText = processedText;
          _isProcessingText = false;
          _isLoading = false;
          _isError = false;
        });
        
       // 로딩 상태 변경 콜백 호출
if (widget.onLoadingStateChanged != null) {
  widget.onLoadingStateChanged!(LoadingState.contentReady);
}

if (kDebugMode) {
  debugPrint('페이지 텍스트 처리 완료: 소요 시간 = ${duration.inMilliseconds}ms');
}
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessingText = false;
          _isLoading = false;
          _isError = true;
          _errorMessage = '텍스트 처리 중 오류가 발생했습니다: $e';
        });
        
        // 오류 상태 콜백 호출
        if (widget.onLoadingStateChanged != null) {
          widget.onLoadingStateChanged!(LoadingState.error);
        }
        
        debugPrint('페이지 텍스트 처리 중 오류 발생: $e');
      }
    }
  }

  @override
  void dispose() {
    // 화면을 나갈 때 TTS 중지
    _contentManager.stopSpeaking();
    _ttsService.dispose(); // TTS 서비스 정리
    super.dispose();
  }

  // TTS 초기화 메서드 추가
  void _initTextReader() async {
    await _ttsService.init();
    
    // TTS 상태 변경 콜백 설정
    _ttsService.setOnPlayingStateChanged((segmentIndex) {
      if (mounted) {
        setState(() {
          _playingSegmentIndex = segmentIndex;
        });
        debugPrint('페이지 콘텐츠 TTS 상태 변경: segmentIndex=$segmentIndex');
      }
    });
    
    // TTS 재생 완료 콜백 설정
    _ttsService.setOnPlayingCompleted(() {
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
      _ttsService.stop();
      
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
          await _ttsService.speakSegment(text, segmentIndex);
        } else {
          await _ttsService.speak(text);
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
                onStateChanged: _handleImageStateChanged,
                showLoadingUI: false, // 로딩 UI 비활성화
              ),
            ),
          
          // 텍스트 처리 중 표시 및 나머지 콘텐츠는 좌우 패딩 적용
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 텍스트 처리 중인 경우 - 로딩 인디케이터 없이 상태만 보고
                if (_isProcessingText || widget.page.originalText == '___PROCESSING___') 
                  Builder(builder: (context) {
                    // 콘텐츠 준비 콜백 호출
                    if (widget.onContentReady != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        widget.onContentReady!(ComponentState.loading);
                      });
                    }
                    
                    // 빈 컨테이너 반환
                    return const SizedBox();
                  })
                // 처리된 텍스트가 있는 경우
                else if (_processedText != null) ...[
                  Builder(builder: (context) {
                    // ProcessedText 처리 로직을 FutureBuilder로 감싸기
                    return FutureBuilder<ProcessedText?>(
                      future: widget.page.id != null 
                          ? _contentManager.getProcessedText(widget.page.id!)
                          : Future.value(_processedText),
                      builder: (context, snapshot) {
                        // 위젯이 dispose 되었는지 확인
                        if (!mounted) {
                          return const SizedBox.shrink();
                        }
                        
                        // 로딩 중이거나 데이터가 없는 경우
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          // 로딩 상태 콜백 호출
                          if (widget.onContentReady != null) {
                            widget.onContentReady!(ComponentState.loading);
                          }
                          // 로딩 UI 없이 빈 컨테이너 반환
                          return const SizedBox();
                        }
                        
                        if (!snapshot.hasData || snapshot.data == null) {
                          // 에러 상태 콜백 호출
                          if (widget.onContentReady != null) {
                            widget.onContentReady!(ComponentState.error);
                          }
                          // 에러 UI 없이 빈 컨테이너 반환
                          return const SizedBox();
                        }
                        
                        // 데이터가 있는 경우
                        final displayedText = snapshot.data!;
                        
                        // 상태 디버깅
                        debugPrint('표시할 ProcessedText: hashCode=${displayedText.hashCode}, '
                            'showFullText=${displayedText.showFullText}, '
                            'showPinyin=${displayedText.showPinyin}, '
                            'showTranslation=${displayedText.showTranslation}');
                      
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
                          // 비동기 호출은 별도 함수로 분리하여 FutureBuilder 내에서 관리하지 않음
                          _saveProcessedText(widget.page.id!, updatedText);
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
                          onStateChanged: _handleTextStateChanged,
                          showLoadingUI: false, // 로딩 UI 비활성화
                        );
                      },
                    );
                  }),
                ]
                // 빈 페이지인 경우 - 상태만 보고하고 최소한의 UI 유지
                else
                  Builder(builder: (context) {
                    // 콘텐츠 준비 콜백 호출 - 빈 페이지도 준비된 상태로 간주
                    if (widget.onContentReady != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        widget.onContentReady!(ComponentState.ready);
                      });
                    }
                    
                    // 텍스트 준비 완료 상태로 설정
                    _isTextReady = true;
                    _checkAndUpdateReadyState();
                    
                    return const SizedBox();
                  })
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
    setState(() {
      _flashcardWords =
          _contentManager.extractFlashcardWords(widget.flashCards);
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
          // 세그먼트 처리 (문장 분리 및 번역) - TextProcessingWorkflow 사용
          final textProcessingWorkflow = TextProcessingWorkflow();
          // Note 객체에 extractedText 필드를 설정합니다
          final note = Note(
            id: null, 
            userId: '', 
            originalText: updatedText.fullOriginalText,
            translatedText: updatedText.fullTranslatedText ?? '',
            sourceLanguage: 'zh-CN',
            targetLanguage: 'ko',
            extractedText: updatedText.fullOriginalText, // extractedText 필드에 원본 텍스트 설정
          );
          
          final processedResult = await textProcessingWorkflow.processText(
            text: updatedText.fullOriginalText,
            note: note,
            pageId: widget.page.id ?? 'temp',
            // 외부 extractedText 매개변수는 제거 (Note 객체 내부에 이미 설정됨)
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

  // 이미지 상태 업데이트 받는 메서드
  void _handleImageStateChanged(ComponentState state) {
    debugPrint('이미지 상태 변경: $state');
    setState(() {
      _isImageReady = state == ComponentState.ready;
    });
    _checkAndUpdateReadyState();
  }

  // 텍스트 상태 업데이트 받는 메서드
  void _handleTextStateChanged(ComponentState state) {
    debugPrint('텍스트 상태 변경: $state');
    setState(() {
      _isTextReady = state == ComponentState.ready;
    });
    _checkAndUpdateReadyState();
  }

  // 통합 상태 체크 및 부모에게 알림
  void _checkAndUpdateReadyState() {
    debugPrint('상태 체크: 이미지=$_isImageReady, 텍스트=$_isTextReady');
    
    if (_isImageReady && _isTextReady) {
      debugPrint('모든 컴포넌트 준비 완료, 상위 컴포넌트에 알림');
      if (widget.onContentReady != null) {
        widget.onContentReady!(ComponentState.ready);
      }
    } else {
      debugPrint('일부 컴포넌트 아직 로딩 중');
      if (widget.onContentReady != null) {
        widget.onContentReady!(ComponentState.loading);
      }
    }
  }
}

// 임시 사전 결과 위젯 클래스 추가
class DictionaryResultWidget {
  static Future<void> showDictionaryBottomSheet({
    required BuildContext context,
    required DictionaryEntry entry,
    required Function(String, String, {String? pinyin}) onCreateFlashCard,
    required bool isExistingFlashcard,
  }) async {
    // 간소화된 형태로 구현
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('단어: ${entry.word}', style: const TextStyle(fontWeight: FontWeight.bold)),
            if (entry.pinyin.isNotEmpty)
              Text('병음: ${entry.pinyin}'),
            Text('의미: ${entry.meaning}'),
            if (!isExistingFlashcard)
              ElevatedButton(
                onPressed: () {
                  onCreateFlashCard(entry.word, entry.meaning, pinyin: entry.pinyin);
                  Navigator.pop(context);
                },
                child: const Text('플래시카드 추가'),
              ),
          ],
        ),
      ),
    );
  }
}
