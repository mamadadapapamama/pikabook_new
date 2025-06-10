import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:async';
import '../../../core/models/processed_text.dart';
import '../../../core/models/processing_status.dart';
import '../../../core/utils/timeout_manager.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/widgets/pika_button.dart';
import '../view_model/note_detail_viewmodel.dart';
import '../../../core/models/page.dart' as page_model;
import '../../../core/models/flash_card.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/widgets/dot_loading_indicator.dart';
import '../../flashcard/flashcard_view_model.dart';
import 'page_image_widget.dart';
import 'processed_text_widget.dart';
import '../../dictionary/dictionary_result_widget.dart';

/// 노트 페이지 위젯: 이미지와 처리된 텍스트를 함께 표시
class NotePageWidget extends StatefulWidget {
  final page_model.Page page;
  final File? imageFile;
  final String noteId;
  final List<FlashCard> flashCards;
  final Function(String, String, {String? pinyin})? onCreateFlashCard;
  final Function(String, {int? segmentIndex})? onPlayTts;
  
  const NotePageWidget({
    Key? key,
    required this.page,
    this.imageFile,
    required this.noteId,
    this.flashCards = const [],
    this.onCreateFlashCard,
    this.onPlayTts,
  }) : super(key: key);

  @override
  State<NotePageWidget> createState() => _NotePageWidgetState();
}

class _NotePageWidgetState extends State<NotePageWidget> {
  bool _hasTriedLoading = false;
  TimeoutManager? _ocrTimeoutManager;
  bool _isRetrying = false;

  @override
  void initState() {
    super.initState();
    // 초기 로딩 시도
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryLoadTextIfNeeded();
    });
  }

  @override
  void didUpdateWidget(NotePageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 페이지가 변경되면 로딩 상태 리셋
    if (oldWidget.page.id != widget.page.id) {
      _hasTriedLoading = false;
      _isRetrying = false;
      _disposeTimeoutManager();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tryLoadTextIfNeeded();
      });
    }
  }

  @override
  void dispose() {
    _disposeTimeoutManager();
    super.dispose();
  }

  void _disposeTimeoutManager() {
    _ocrTimeoutManager?.dispose();
    _ocrTimeoutManager = null;
  }

  void _tryLoadTextIfNeeded() {
    if (!mounted || _hasTriedLoading) return;
    
    final viewModel = Provider.of<NoteDetailViewModel>(context, listen: false);
    final textViewModel = viewModel.getTextViewModel(widget.page.id);
    final processedText = textViewModel['processedText'] as ProcessedText?;
    final isLoading = textViewModel['isLoading'] as bool? ?? false;
    
    // ProcessedText가 없고 로딩 중이 아닐 때만 로드 시도
    if (processedText == null && !isLoading && !viewModel.isLoading) {
      _hasTriedLoading = true;
      _startOcrTimeout();
      viewModel.loadCurrentPageText();
    }
  }

  /// OCR 처리 타임아웃 시작
  void _startOcrTimeout() {
    _disposeTimeoutManager();
    _ocrTimeoutManager = TimeoutManager();
    
    _ocrTimeoutManager!.start(
      timeoutSeconds: 5, // 테스트용: 30 -> 5초로 변경
      onProgress: (elapsedSeconds) {
        if (!mounted) return;
        // 진행 메시지는 loading indicator에서 자동 처리됨
      },
      onTimeout: () {
        if (mounted) {
          setState(() {
            // 타임아웃 상태로 변경하여 재시도 버튼 표시
          });
        }
      },
    );
  }

  /// OCR 재시도 실행
  void _retryOcrProcessing() {
    if (!mounted || _isRetrying) return;
    
    setState(() {
      _isRetrying = true;
      _hasTriedLoading = false;
    });
    
    final viewModel = Provider.of<NoteDetailViewModel>(context, listen: false);
    
    // 재시도 실행
    _tryLoadTextIfNeeded();
    
    setState(() {
      _isRetrying = false;
    });
  }

  /// 디버그 테스트 버튼들 (디버그 모드에서만 표시)
  Widget _buildDebugTestButtons(BuildContext context, NoteDetailViewModel viewModel) {
    return Container(
      padding: EdgeInsets.all(SpacingTokens.md),
      margin: EdgeInsets.symmetric(horizontal: SpacingTokens.md),
      decoration: BoxDecoration(
        color: Colors.yellow[50],
        border: Border.all(color: Colors.orange),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '🧪 테스트 버튼들 (디버그 모드)',
            style: TypographyTokens.body2.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.orange[800],
            ),
          ),
          SizedBox(height: SpacingTokens.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // OCR 타임아웃 강제 발생
              Expanded(
                child: PikaButton(
                  text: 'OCR 타임아웃',
                  variant: PikaButtonVariant.outline,
                  size: PikaButtonSize.small,
                  onPressed: () {
                    _simulateOcrTimeout();
                  },
                ),
              ),
              SizedBox(width: SpacingTokens.sm),
              // 네트워크 에러 강제 발생  
              Expanded(
                child: PikaButton(
                  text: '네트워크 에러',
                  variant: PikaButtonVariant.outline,
                  size: PikaButtonSize.small,
                  onPressed: () {
                    _simulateNetworkError();
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: SpacingTokens.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // LLM 타임아웃 강제 발생
              Expanded(
                child: PikaButton(
                  text: 'LLM 타임아웃',
                  variant: PikaButtonVariant.outline,
                  size: PikaButtonSize.small,
                  onPressed: () {
                    _simulateLlmTimeout(viewModel);
                  },
                ),
              ),
              SizedBox(width: SpacingTokens.sm),
              // 모든 테스트 상태 리셋
              Expanded(
                child: PikaButton(
                  text: '상태 리셋',
                  variant: PikaButtonVariant.text,
                  size: PikaButtonSize.small,
                  onPressed: () {
                    _resetTestStates(viewModel);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// OCR 타임아웃 시뮬레이션
  void _simulateOcrTimeout() {
    if (kDebugMode) {
      print('🧪 [테스트] OCR 타임아웃 시뮬레이션');
    }
    _ocrTimeoutManager?.dispose();
    setState(() {
      // 타임아웃 상태로 즉시 변경
    });
  }

  /// 네트워크 에러 시뮬레이션
  void _simulateNetworkError() {
    if (kDebugMode) {
      print('🧪 [테스트] 네트워크 에러 시뮬레이션');
    }
    final viewModel = Provider.of<NoteDetailViewModel>(context, listen: false);
    // 강제로 네트워크 에러 상태로 설정
    // viewModel에서 이 페이지의 에러를 설정하는 방법이 있다면 사용
  }

  /// LLM 타임아웃 시뮬레이션
  void _simulateLlmTimeout(NoteDetailViewModel viewModel) {
    if (kDebugMode) {
      print('🧪 [테스트] LLM 타임아웃 시뮬레이션');
    }
    // LLM 타임아웃 상태 강제 설정
    viewModel.updateLlmTimeoutStatus(true, true);
  }

  /// 테스트 상태들 리셋
  void _resetTestStates(NoteDetailViewModel viewModel) {
    if (kDebugMode) {
      print('🧪 [테스트] 모든 테스트 상태 리셋');
    }
    
    // OCR 타임아웃 매니저 리셋
    _disposeTimeoutManager();
    
    // LLM 타임아웃 상태 리셋
    viewModel.updateLlmTimeoutStatus(false, false);
    
    // 로딩 상태 리셋
    setState(() {
      _hasTriedLoading = false;
      _isRetrying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      print('🎭 [NotePageWidget] build() 호출: ${widget.page.id}');
    }
    
    // Consumer를 사용하여 ViewModel에 직접 접근
    return Consumer<NoteDetailViewModel>(
      builder: (context, viewModel, child) {
        if (kDebugMode) {
          print('🎭 [NotePageWidget] Consumer builder 호출: ${widget.page.id}');
        }
        
        // 현재 페이지의 텍스트 데이터 미리 가져오기
        final textViewModel = viewModel.getTextViewModel(widget.page.id);
        final processedText = textViewModel['processedText'] as ProcessedText?;
        final isLoading = textViewModel['isLoading'] as bool? ?? false;
        final error = textViewModel['error'] as String?;
        
        if (kDebugMode) {
          print('🎭 [NotePageWidget] 데이터 상태 확인: ${widget.page.id}');
          print('   processedText: ${processedText != null ? "있음 (${processedText.units.length}개 유닛)" : "없음"}');
          print('   isLoading: $isLoading');
          print('   error: $error');
          if (processedText != null) {
            print('   번역 텍스트 길이: ${processedText.fullTranslatedText?.length ?? 0}');
            print('   스트리밍 상태: ${processedText.streamingStatus}');
          }
        }
        
        return _buildPageContent(context, viewModel, processedText, isLoading, error);
      },
    );
  }
  
  Widget _buildPageContent(BuildContext context, NoteDetailViewModel viewModel, 
      ProcessedText? processedText, bool isLoading, String? error) {
    
    // 스크롤 가능한 컨테이너
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: SpacingTokens.lg,
        vertical: SpacingTokens.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 페이지 이미지 위젯
          PageImageWidget(
            imageFile: widget.imageFile,
            imageUrl: widget.page.imageUrl,
            page: widget.page,
            isLoading: viewModel.isLoading,
            enableFullScreen: true,
          ),
          
          SizedBox(height: SpacingTokens.md),
          
          // 텍스트 콘텐츠 위젯
          _buildTextContent(context, viewModel, processedText, isLoading, error),
          
          // 디버그 모드에서만 표시되는 테스트 버튼들
          if (kDebugMode) ...[
            SizedBox(height: SpacingTokens.lg),
            _buildDebugTestButtons(context, viewModel),
          ],
        ],
      ),
    );
  }
  
  // 텍스트 콘텐츠 위젯 (상태에 따라 다른 위젯 반환)
  Widget _buildTextContent(BuildContext context, NoteDetailViewModel viewModel,
      ProcessedText? processedText, bool isLoading, String? error) {
    
    if (kDebugMode) {
      print('🎭 [NotePageWidget] _buildTextContent 호출: ${widget.page.id}');
      print('   processedText != null: ${processedText != null}');
      print('   isLoading: $isLoading');
      print('   error: $error');
      print('   page.showTypewriterEffect: ${widget.page.showTypewriterEffect}');
      if (processedText != null) {
        print('   processedText.streamingStatus: ${processedText.streamingStatus}');
        print('   processedText.fullTranslatedText.length: ${processedText.fullTranslatedText?.length ?? 0}');
        print('   processedText.units.length: ${processedText.units.length}');
        // 첫 번째 유닛 샘플 출력
        if (processedText.units.isNotEmpty) {
          final firstUnit = processedText.units[0];
          print('   첫 번째 유닛 예시:');
          print('     원문: "${firstUnit.originalText}"');
          print('     번역: "${firstUnit.translatedText ?? ''}"');
          print('     병음: "${firstUnit.pinyin ?? ''}"');
        }
      }
    }
    
    // ProcessedText가 있으면 바로 표시 (타이프라이터 효과 제거)
    if (processedText != null) {
      if (kDebugMode) {
        print('✅ [NotePageWidget] ProcessedText 위젯 반환: ${widget.page.id}');
      }
      return _buildProcessedTextWidget(context, processedText, viewModel);
    }
    
    // 로딩 중이거나 오류가 있는 경우
    if (isLoading) {
      if (kDebugMode) {
        print('⏳ [NotePageWidget] 로딩 인디케이터 반환: ${widget.page.id}');
      }
      return _buildLoadingIndicator();
    } else if (error != null) {
      if (kDebugMode) {
        print('❌ [NotePageWidget] 에러 위젯 반환: ${widget.page.id} - $error');
      }
      return _buildErrorWidget(error);
    } else {
      if (kDebugMode) {
        print('⏳ [NotePageWidget] 기본 로딩 인디케이터 반환: ${widget.page.id}');
      }
      return _buildLoadingIndicator(); // 빈 상태도 로딩 인디케이터로 통일
    }
  }
  
  // 처리된 텍스트 위젯 (번역 완료된 상태)
  Widget _buildProcessedTextWidget(BuildContext context, ProcessedText processedText, NoteDetailViewModel viewModel) {
    // FlashCardViewModel 생성 (플래시카드가 없으면 노트 생성 중으로 간주)
    final isNoteCreation = widget.flashCards.isEmpty;
    final flashCardViewModel = FlashCardViewModel(
      noteId: widget.noteId,
      initialFlashcards: widget.flashCards,
      isNoteCreation: isNoteCreation, // 노트 생성 중 플래그 전달
    );
    
    // 타이프라이터 효과 완전 비활성화
    final shouldShowTypewriter = false;
    
    if (kDebugMode) {
      print('🎬 타이프라이터 효과 비활성화됨');
      print('   shouldShowTypewriter: $shouldShowTypewriter');
    }
    
    return ProcessedTextWidget(
      processedText: processedText,
      onDictionaryLookup: (word) => _handleDictionaryLookup(context, word),
      onCreateFlashCard: widget.onCreateFlashCard,
      flashCardViewModel: flashCardViewModel,
      onPlayTts: widget.onPlayTts,
      playingSegmentIndex: null, // TTS 재생 인덱스는 별도 관리 필요
      showTypewriterEffect: shouldShowTypewriter, // 타이프라이터 효과 완전 비활성화
    );
  }
  
  // 로딩 인디케이터 (텍스트 처리 중 상태)
  Widget _buildLoadingIndicator() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 32.0),
        child: DotLoadingIndicator(message: '텍스트를 번역하고 있어요.\n잠시만 기다려 주세요!'),
      ),
    );
  }
  
  // 오류 위젯
  Widget _buildErrorWidget(String? errorMessage) {
    final errorType = ErrorHandler.analyzeError(errorMessage ?? '');
    final userFriendlyMessage = ErrorHandler.getErrorMessage(errorType);
    final isTimeoutError = errorType == ErrorType.timeout;
    final isNetworkError = errorType == ErrorType.network;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isNetworkError ? Icons.wifi_off : Icons.error_outline,
              color: Colors.red,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              userFriendlyMessage,
              style: TypographyTokens.body2.copyWith(color: Colors.red[800]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // 타임아웃이나 네트워크 에러시 재시도 버튼 표시
            if (isTimeoutError || isNetworkError)
              PikaButton(
                text: '다시 시도',
                variant: PikaButtonVariant.text,
                onPressed: _isRetrying ? null : _retryOcrProcessing,
                isLoading: _isRetrying,
              ),
          ],
        ),
      ),
    );
  }
  
  // 사전 검색 처리
  void _handleDictionaryLookup(BuildContext context, String word) {
    if (word.isEmpty) return;
    
    if (kDebugMode) {
      print('사전 검색: $word');
    }
    
    DictionaryResultWidget.searchAndShowDictionary(
      context: context,
      word: word,
      onCreateFlashCard: widget.onCreateFlashCard ?? (_, __, {pinyin}) {},
      onEntryFound: (entry) {
        if (kDebugMode) {
          print('사전 검색 결과: ${entry.word} - ${entry.meaning}');
        }
      },
      onNotFound: () {
        if (kDebugMode) {
          print('사전 검색 결과 없음: $word');
        }
      },
    );
  }
}
