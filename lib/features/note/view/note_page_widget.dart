import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:async';
import '../../../core/models/processed_text.dart';
import '../../../core/models/processing_status.dart';
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tryLoadTextIfNeeded();
      });
    }
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
      viewModel.loadCurrentPageText();
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
    // FlashCardViewModel 생성 (기존 flashCards 리스트로 초기화)
    final flashCardViewModel = FlashCardViewModel(
      noteId: widget.noteId,
      initialFlashcards: widget.flashCards,
    );
    
    // 타이프라이터 효과 조건:
    // 1. 페이지에서 타이프라이터 효과가 활성화되어 있고
    // 2. 스트리밍 중이거나 번역이 아직 완료되지 않은 상태
    final shouldShowTypewriter = widget.page.showTypewriterEffect && 
                                (processedText.streamingStatus == StreamingStatus.streaming ||
                                 processedText.fullTranslatedText?.isEmpty == true);
    
    if (kDebugMode) {
      print('🎬 타이프라이터 효과 조건 확인:');
      print('   page.showTypewriterEffect: ${widget.page.showTypewriterEffect}');
      print('   streamingStatus: ${processedText.streamingStatus}');
      print('   fullTranslatedText.isEmpty: ${processedText.fullTranslatedText?.isEmpty}');
      print('   shouldShowTypewriter: $shouldShowTypewriter');
    }
    
    return ProcessedTextWidget(
      processedText: processedText,
      onDictionaryLookup: (word) => _handleDictionaryLookup(context, word),
      onCreateFlashCard: widget.onCreateFlashCard,
      flashCardViewModel: flashCardViewModel,
      onPlayTts: widget.onPlayTts,
      playingSegmentIndex: null, // TTS 재생 인덱스는 별도 관리 필요
      showTypewriterEffect: shouldShowTypewriter, // 새 노트 생성 시에만 타이프라이터 효과
    );
  }
  
  // 로딩 인디케이터 (처리 중 상태 공통 사용)
  Widget _buildLoadingIndicator() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 32.0),
        child: DotLoadingIndicator(message: '텍스트를 처리하고 있습니다'),
      ),
    );
  }
  
  // 오류 위젯
  Widget _buildErrorWidget(String? errorMessage) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              errorMessage ?? '텍스트 처리 중 오류가 발생했습니다.',
              style: TypographyTokens.body2.copyWith(color: Colors.red[800]),
              textAlign: TextAlign.center,
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
