import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../../../core/models/page.dart' as page_model;
import '../../../core/models/processed_text.dart';
import '../../../core/models/text_unit.dart';
import '../../../core/models/flash_card.dart';
import '../../../core/models/processing_status.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/utils/timeout_manager.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/widgets/error_display_widget.dart';
import '../../../core/widgets/inline_error_widget.dart';
import '../../../core/widgets/dot_loading_indicator.dart';
import '../../../core/widgets/pika_button.dart';
import '../../../core/services/media/image_service.dart';
import '../view_model/note_detail_viewmodel.dart';
import '../../flashcard/flashcard_view_model.dart';
import 'processed_text_widget.dart';
import '../../dictionary/dictionary_result_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
  bool _hasTimedOut = false;
  String _currentMessage = '텍스트를 번역하고 있어요.\n잠시만 기다려 주세요!';
  String get _errorId => 'page_${widget.page.id}';

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
      _hasTimedOut = false;
      _currentMessage = '텍스트를 번역하고 있어요.\n잠시만 기다려 주세요!';
      _disposeTimeoutManager();
      ErrorHandler.clearError(_errorId);
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
      timeoutSeconds: 30,
      identifier: 'OCR-${widget.page.id}',
      onProgress: (elapsedSeconds) {
        if (!mounted) return;
        // 진행 상황은 ErrorDisplayWidget에서 자동 처리
      },
      onTimeout: () {
        if (mounted) {
          // ErrorHandler를 통해 타임아웃 에러 등록
          ErrorHandler.registerTimeoutError(
            id: _errorId,
            onRetry: _retryOcrProcessing,
          );
          
          if (kDebugMode) {
            print('⏰ [NotePageWidget] 타임아웃 발생 - ErrorHandler 등록');
          }
        }
      },
    );
  }

  /// OCR 재시도 실행
  void _retryOcrProcessing() {
    if (mounted) {
      setState(() {
        _hasTimedOut = false;
        _currentMessage = '텍스트를 번역하고 있어요.\n잠시만 기다려 주세요!';
        
        // 타임아웃 매니저 정리
        _disposeTimeoutManager();
        
        // ViewModel의 에러 상태 초기화
        final viewModel = Provider.of<NoteDetailViewModel>(context, listen: false);
        viewModel.clearPageError(widget.page.id);
        
        if (kDebugMode) {
          print('🔄 [NotePageWidget] 재시도 시작 - 에러 상태 초기화: ${widget.page.id}');
        }
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _tryLoadTextIfNeeded();
        });
      });
    }
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
        final status = textViewModel['status'] as ProcessingStatus? ?? ProcessingStatus.created;
        
        if (kDebugMode) {
          print('🎭 [NotePageWidget] 데이터 상태 확인: ${widget.page.id}');
          print('   processedText: ${processedText != null ? "있음 (${processedText.units.length}개 유닛)" : "없음"}');
          print('   isLoading: $isLoading');
          print('   error: $error');
          print('   status: $status');
          if (processedText != null) {
            print('   번역 텍스트 길이: ${processedText.fullTranslatedText?.length ?? 0}');
            print('   스트리밍 상태: ${processedText.streamingStatus}');
          }
        }
        
        return _buildPageContent(context, viewModel, processedText, isLoading, error, status);
      },
    );
  }
  
  Widget _buildPageContent(BuildContext context, NoteDetailViewModel viewModel, 
      ProcessedText? processedText, bool isLoading, String? error, ProcessingStatus status) {
    
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
          _buildImageWidget(context, viewModel),
          
          SizedBox(height: SpacingTokens.md),
          
          // 텍스트 콘텐츠 위젯
          _buildTextContent(context, viewModel, processedText, isLoading, error, status),
        ],
      ),
    );
  }
  
  // 페이지 이미지 위젯
  Widget _buildImageWidget(BuildContext context, NoteDetailViewModel viewModel) {
    return Container(
      height: 200,
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: GestureDetector(
          onTap: () => _openFullScreenImage(context),
          child: Stack(
            alignment: Alignment.center,
            children: [
              _buildImageContent(),
              // 확대 아이콘
              Positioned(
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(128),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.zoom_in,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 이미지 콘텐츠 위젯
  Widget _buildImageContent() {
    // 1. 로컬 파일이 있는 경우 (새로 선택된 이미지)
    if (widget.imageFile != null) {
      return Image.file(
        widget.imageFile!,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildEmptyImageWidget();
        },
      );
    }
    
    // 2. URL이 있는 경우 (기존 저장된 이미지)
    if (widget.page.imageUrl != null && widget.page.imageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: widget.page.imageUrl!,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        placeholder: (context, url) => Center(
          child: DotLoadingIndicator(
            message: '이미지 로딩 중...',
            dotColor: ColorTokens.primary,
          ),
        ),
        errorWidget: (context, url, error) {
          if (kDebugMode) {
            debugPrint('🖼️ 이미지 로드 오류: $error');
          }
          return _buildEmptyImageWidget();
        },
      );
    }
    
    // 3. 이미지가 없는 경우
    return _buildEmptyImageWidget();
  }

  // 빈 이미지 위젯
  Widget _buildEmptyImageWidget() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[100],
      ),
      child: Image.asset(
        'assets/images/image_empty.png',
        fit: BoxFit.cover,
      ),
    );
  }

  // 전체 화면 이미지 뷰어 열기
  void _openFullScreenImage(BuildContext context) {
    File? imageFile;
    
    if (widget.imageFile != null) {
      imageFile = widget.imageFile;
    } else if (widget.page.imageUrl != null && widget.page.imageUrl!.isNotEmpty) {
      // URL에서 로컬 파일을 가져와야 하는 경우
      // ImageService를 통해 처리할 수 있지만, 여기서는 간단히 스킵
      if (kDebugMode) {
        debugPrint('🖼️ URL 이미지의 전체화면 보기는 현재 지원되지 않습니다: ${widget.page.imageUrl}');
      }
      return;
    }
    
    if (imageFile == null) return;
    
    // ImageService를 통한 전체화면 보기
    final imageService = ImageService();
    imageService.showFullImage(context, imageFile, '이미지 보기');
  }
  
  // 텍스트 콘텐츠 위젯 (상태에 따라 다른 위젯 반환)
  Widget _buildTextContent(BuildContext context, NoteDetailViewModel viewModel,
      ProcessedText? processedText, bool isLoading, String? error, ProcessingStatus status) {
    
    if (kDebugMode) {
      print('🎭 [NotePageWidget] _buildTextContent 호출: ${widget.page.id}');
      print('   processedText != null: ${processedText != null}');
      print('   isLoading: $isLoading');
      print('   error: $error');
      print('   status: $status');
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
      // OCR 처리 완료 - 타임아웃 매니저 정상 완료 처리
      if (_ocrTimeoutManager != null && _ocrTimeoutManager!.isActive) {
        if (kDebugMode) {
          print('✅ [NotePageWidget] OCR 완료 - 타임아웃 매니저 정상 완료: ${widget.page.id}');
        }
        _ocrTimeoutManager!.complete();
        _ocrTimeoutManager = null;
      }
      
      if (kDebugMode) {
        print('✅ [NotePageWidget] ProcessedText 위젯 반환: ${widget.page.id}');
      }
      return _buildProcessedTextWidget(context, processedText, viewModel);
    }
    
    // 기존 에러가 있는 경우 인라인 에러 위젯으로 표시
    if (error != null) {
      // 에러 발생 시 즉시 타임아웃 매니저 중단
      if (_ocrTimeoutManager != null && _ocrTimeoutManager!.isActive) {
        if (kDebugMode) {
          print('🛑 [NotePageWidget] 에러 발생으로 타임아웃 매니저 중단: ${widget.page.id}');
        }
        _ocrTimeoutManager!.stop();
        _ocrTimeoutManager = null;
      }
      
      final isChineseDetectionError = error.contains('중국어가 없습니다');
      
      if (isChineseDetectionError) {
        // 중국어 감지 실패 시 인라인 에러 위젯 표시
        return InlineErrorWidget.chineseDetectionFailed(
          onExit: () => Navigator.of(context).pop(),
        );
      } else {
        // 기타 에러 처리
        final errorType = ErrorHandler.analyzeError(error);
        final isTimeoutError = errorType == ErrorType.timeout;
        final isNetworkError = errorType == ErrorType.network;
        
        if (isTimeoutError) {
          return InlineErrorWidget.timeout(
            onRetry: _retryOcrProcessing,
          );
        } else if (isNetworkError) {
          return InlineErrorWidget.network(
            onRetry: _retryOcrProcessing,
          );
        } else {
          return InlineErrorWidget.general(
            message: ErrorHandler.getErrorMessage(errorType),
            onRetry: _retryOcrProcessing,
          );
        }
      }
    }
    
    // processedText가 null이고 error도 null인 경우
    // 1. 로딩 중이거나 처리가 아직 완료되지 않은 경우: 로딩 표시
    // 2. 처리가 완료되었지만 텍스트가 없는 경우: "텍스트가 없습니다" 에러 표시
    if (isLoading || !status.isCompleted) {
      // 로딩 중이거나 처리 중인 경우
      return InlineLoadingErrorWidget(
        loadingMessage: _currentMessage,
        error: null,
        onRetry: _retryOcrProcessing,
        loadingWidget: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32.0),
            child: DotLoadingIndicator(message: _currentMessage),
          ),
        ),
      );
    } else if (status.isCompleted) {
      // 처리가 완료되었지만 텍스트가 없는 경우 (실제로는 발생하지 않아야 함)
      return InlineErrorWidget.noText(
        onExit: () => Navigator.of(context).pop(),
      );
    } else {
      // 기타 상태 (failed 등)에서는 일반 에러 표시
      return InlineErrorWidget.general(
        message: '텍스트 처리 중 문제가 발생했습니다.',
        onRetry: _retryOcrProcessing,
      );
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
    // 타임아웃 발생한 경우 에러 상태로 표시
    if (_hasTimedOut) {
      return _buildDynamicStatusIndicator(
        message: _currentMessage,
        showLoading: false,
        messageColor: Colors.red[800],
        icon: Icons.error_outline,
        iconColor: Colors.red,
        onRetry: _retryOcrProcessing,
        retryButtonText: '다시 시도',
      );
    }
    
    // 일반 로딩 상태
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0),
        child: DotLoadingIndicator(message: _currentMessage),
      ),
    );
  }
  
  // 동적 로딩/에러 인디케이터
  Widget _buildDynamicStatusIndicator({
    required String message,
    bool showLoading = true,
    Color? messageColor,
    IconData? icon,
    Color? iconColor,
    VoidCallback? onRetry,
    String? retryButtonText,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0, horizontal: 16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showLoading) ...[
              const DotLoadingIndicator(message: ''),
              const SizedBox(height: 16),
            ] else if (icon != null) ...[
              Icon(
                icon,
                color: iconColor ?? Colors.grey,
                size: 48,
              ),
              const SizedBox(height: 16),
            ],
            Text(
              message,
              style: TypographyTokens.body2.copyWith(
                color: messageColor ?? Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              PikaButton(
                text: retryButtonText ?? '다시 시도',
                variant: PikaButtonVariant.text,
                onPressed: _isRetrying ? null : onRetry,
                isLoading: _isRetrying,
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  // 사전 검색 처리
  void _handleDictionaryLookup(BuildContext context, String word) {
    if (word.isEmpty) return;
    
    if (kDebugMode) {
      print('🔍 [사전검색] 시작: "$word"');
    }
    
    DictionaryResultWidget.searchAndShowDictionary(
      context: context,
      word: word,
      onCreateFlashCard: widget.onCreateFlashCard ?? (_, __, {pinyin}) {},
      onEntryFound: (entry) {
        if (kDebugMode) {
          print('✅ [사전검색] 성공: ${entry.word} - ${entry.meaning} (출처: ${entry.source})');
        }
      },
      onNotFound: () {
        if (kDebugMode) {
          print('❌ [사전검색] 실패: "$word" - 모든 소스에서 찾을 수 없음');
        }
      },
    );
  }
}
