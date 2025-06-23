import 'package:flutter/material.dart';
import '../../core/models/dictionary.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../../core/widgets/pika_button.dart';
import '../../../core/widgets/dot_loading_indicator.dart';
import '../../../core/utils/error_handler.dart';
import '../tts/tts_button.dart';
import 'dictionary_service.dart';

/// 사전 검색 결과를 표시하는 바텀 시트 위젯
class DictionaryResultWidget extends StatelessWidget {
  final DictionaryEntry entry;
  final Function(String, String, {String? pinyin}) onCreateFlashCard;
  final bool isExistingFlashcard;

  const DictionaryResultWidget({
    super.key,
    required this.entry,
    required this.onCreateFlashCard,
    this.isExistingFlashcard = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(SpacingTokens.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 단어와 TTS 버튼
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.word,
                  style: TypographyTokens.headline2Cn.copyWith(
                    color: ColorTokens.textPrimary,
                  ),
                ),
              ),
              // TtsButton 위젯 사용 - 모든 상태 관리가 내부에서 자동으로 처리됨
              TtsButton(
                text: entry.word,
                size: TtsButton.sizeMedium,
                iconColor: ColorTokens.secondary,
                activeBackgroundColor: ColorTokens.primary.withOpacity(0.2),
                tooltip: '단어 발음 듣기',
              ),
            ],
          ),
          
          // 핀인
          if (entry.pinyin.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: SpacingTokens.sm),
              child: Text(
                entry.pinyin,
                style: TypographyTokens.caption.copyWith(
                  color: ColorTokens.textGrey,
                  fontFamily: TypographyTokens.poppins,
                ),
              ),
            ),
          
          // 의미 (다국어 지원)
          if (entry.displayMeaning.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: SpacingTokens.sm),
              child: Text(
                entry.displayMeaning,
                style: TypographyTokens.body1.copyWith(
                  color: ColorTokens.secondary,
                ),
              ),
            ),
          
          SizedBox(height: SpacingTokens.lg),
          
          // 플래시카드 추가 버튼
          PikaButton(
            text: isExistingFlashcard ? '플래시카드로 설정됨' : '플래시카드 추가',
            variant: isExistingFlashcard ? PikaButtonVariant.primary : PikaButtonVariant.primary,
            leadingIcon: !isExistingFlashcard 
              ? Image.asset(
                  'assets/images/icon_flashcard_dic.png',
                  width: 24,
                  height: 24,
                )
              : null,
            onPressed: isExistingFlashcard
                ? null
                : () => _handleAddToFlashcard(context),
            isFullWidth: true,
          ),
        ],
      ),
    );
  }
  
  /// 플래시카드 추가 처리
  void _handleAddToFlashcard(BuildContext context) {
    onCreateFlashCard(
      entry.word,
      entry.displayMeaning,
      pinyin: entry.pinyin,
    );
    Navigator.pop(context);

    // 성공 메시지는 실제 플래시카드 생성을 담당하는 곳에서 표시
  }


  
  /// 단어 검색 및 결과 표시 메서드
  static Future<void> searchAndShowDictionary({
    required BuildContext context,
    required String word,
    required Function(String, String, {String? pinyin}) onCreateFlashCard,
    required Function(DictionaryEntry) onEntryFound,
    Function()? onNotFound,
  }) async {
    if (word.isEmpty) {
      ErrorHandler.showInfoSnackBar(context, '검색할 단어를 입력하세요');
      return;
    }
    
    // 바텀시트를 먼저 열고 그 안에서 로딩 표시
    if (context.mounted) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.transparent,
        isDismissible: true,
        builder: (bottomSheetContext) => _DictionaryBottomSheet(
          word: word,
          onCreateFlashCard: onCreateFlashCard,
          onEntryFound: onEntryFound,
          onNotFound: onNotFound,
        ),
      );
    }
  }
  
  /// 단어 검색 (사전 결과만 반환)
  static Future<DictionaryEntry?> searchWord(String word) async {
    if (word.isEmpty) {
      return null;
    }
    
    try {
      // Singleton 인스턴스 사용
      final dictionaryService = DictionaryService();
      
      // 사전 초기화 확인
      if (!dictionaryService.isInitialized) {
        await dictionaryService.initialize();
      }
      
      // 단어 검색
      return await dictionaryService.lookup(word);
    } catch (e) {
      return null;
    }
  }
  
}

/// 사전 검색 바텀시트 (로딩 + 결과 통합)
class _DictionaryBottomSheet extends StatefulWidget {
  final String word;
  final Function(String, String, {String? pinyin}) onCreateFlashCard;
  final Function(DictionaryEntry) onEntryFound;
  final Function()? onNotFound;

  const _DictionaryBottomSheet({
    required this.word,
    required this.onCreateFlashCard,
    required this.onEntryFound,
    this.onNotFound,
  });

  @override
  State<_DictionaryBottomSheet> createState() => _DictionaryBottomSheetState();
}

class _DictionaryBottomSheetState extends State<_DictionaryBottomSheet> {
  bool _isLoading = true;
  DictionaryEntry? _entry;
  String? _errorMessage;
  
  @override
  void initState() {
    super.initState();
    _searchWord();
  }

  Future<void> _searchWord() async {
    try {
      // Singleton 인스턴스 사용
      final dictionaryService = DictionaryService();
      
      // 단어 검색
      final entry = await dictionaryService.lookup(widget.word);
      
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (entry != null) {
            _entry = entry;
            widget.onEntryFound(_entry!);
          } else {
            _errorMessage = '단어를 찾을 수 없습니다: ${widget.word}';
            if (widget.onNotFound != null) {
              widget.onNotFound!();
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = ErrorHandler.getMessageFromError(e, ErrorContext.dictionary);
          if (widget.onNotFound != null) {
            widget.onNotFound!();
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ColorTokens.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(SpacingTokens.lg),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(SpacingTokens.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 핸들 바
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ColorTokens.textGrey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            SizedBox(height: SpacingTokens.lg),
            
            // 로딩 중이면 로딩 표시, 아니면 결과 표시
            if (_isLoading) ...[
              // 단어 영역 (로딩 중)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.word,
                      style: TypographyTokens.headline2Cn.copyWith(
                        color: ColorTokens.textPrimary,
                      ),
                    ),
                  ),
                  // TTS 버튼 자리 (로딩 중에는 비활성화)
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: ColorTokens.textGrey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ],
              ),
              SizedBox(height: SpacingTokens.sm),
              
              // 핀인 영역 (로딩 중)
              Container(
                height: 16,
                width: 80,
                decoration: BoxDecoration(
                  color: ColorTokens.textGrey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              SizedBox(height: SpacingTokens.sm),
              
              // 의미 영역 (로딩 중)
              Container(
                height: 20,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: ColorTokens.textGrey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              SizedBox(height: SpacingTokens.lg),
              
              // 로딩 애니메이션
              Center(
                child: DotLoadingIndicator(
                  dotColor: ColorTokens.primary,
                  dotSize: 8.0,
                  spacing: 6.0,
                ),
              ),
              SizedBox(height: SpacingTokens.lg),
              
              // 버튼 영역 (로딩 중)
              Container(
                height: 48,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: ColorTokens.textGrey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ] else if (_entry != null) ...[
              // 실제 사전 결과 표시
              _buildDictionaryContent(),
            ] else ...[
              // 오류 표시
              _buildErrorContent(),
            ],
          ],
        ),
      ),
    );
  }

  /// 사전 결과 콘텐츠
  Widget _buildDictionaryContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 단어와 TTS 버튼
        Row(
          children: [
            Expanded(
              child: Text(
                _entry!.word,
                style: TypographyTokens.headline2Cn.copyWith(
                  color: ColorTokens.textPrimary,
                ),
              ),
            ),
            // TtsButton 위젯 사용
            TtsButton(
              text: _entry!.word,
              size: TtsButton.sizeMedium,
              iconColor: ColorTokens.secondary,
              activeBackgroundColor: ColorTokens.primary.withOpacity(0.2),
              tooltip: '단어 발음 듣기',
            ),
          ],
        ),
        
        // 핀인
        if (_entry!.pinyin.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: SpacingTokens.sm),
            child: Text(
              _entry!.pinyin,
              style: TypographyTokens.caption.copyWith(
                color: ColorTokens.textGrey,
                fontFamily: TypographyTokens.poppins,
              ),
            ),
          ),
        
        // 의미 (다국어 지원)
        if (_entry!.displayMeaning.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: SpacingTokens.sm),
            child: Text(
              _entry!.displayMeaning,
              style: TypographyTokens.body1.copyWith(
                color: ColorTokens.secondary,
              ),
            ),
          ),
        
        SizedBox(height: SpacingTokens.lg),
        
        // 플래시카드 추가 버튼
        PikaButton(
          text: '플래시카드 추가',
          variant: PikaButtonVariant.primary,
          leadingIcon: Image.asset(
            'assets/images/icon_flashcard_dic.png',
            width: 24,
            height: 24,
          ),
          onPressed: () => _handleAddToFlashcard(),
          isFullWidth: true,
        ),
      ],
    );
  }

  /// 플래시카드 추가 처리
  void _handleAddToFlashcard() {
    if (_entry != null) {
      widget.onCreateFlashCard(
        _entry!.word,
        _entry!.displayMeaning,
        pinyin: _entry!.pinyin,
      );
      Navigator.pop(context);
    }
  }

  /// 오류 콘텐츠
  Widget _buildErrorContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 검색한 단어 표시
        Text(
          widget.word,
          style: TypographyTokens.headline2Cn.copyWith(
            color: ColorTokens.textPrimary,
          ),
        ),
        SizedBox(height: SpacingTokens.lg),
        
        // 오류 메시지
        Center(
          child: Column(
            children: [
              Icon(
                Icons.search_off,
                size: 32,
                color: ColorTokens.textGrey,
              ),
              SizedBox(height: SpacingTokens.sm),
              Text(
                _errorMessage ?? '검색 결과가 없습니다',
                style: TypographyTokens.body1.copyWith(
                  color: ColorTokens.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        SizedBox(height: SpacingTokens.lg),
      ],
    );
  }
}
