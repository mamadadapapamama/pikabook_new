import 'package:flutter/material.dart';
import '../../core/models/dictionary.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import '../../../core/widgets/pika_button.dart';
import '../../../core/utils/error_handler.dart';
import '../tts/tts_button.dart';
import 'unified_dictionary_service.dart';

/// 사전 검색 결과를 표시하는 바텀 시트 위젯
class DictionaryResultWidget extends StatelessWidget {
  final DictionaryEntry entry;
  final Function(String, String, {String? pinyin}) onCreateFlashCard;
  final bool isExistingFlashcard;
  
  // 정적 UnifiedDictionaryService 인스턴스 (불필요한 재초기화 방지)
  static final UnifiedDictionaryService _dictionaryService = UnifiedDictionaryService();

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

  /// 사전 결과 바텀 시트 표시 헬퍼 메서드
  static void showDictionaryBottomSheet({
    required BuildContext context,
    required DictionaryEntry entry,
    required Function(String, String, {String? pinyin}) onCreateFlashCard,
    bool isExistingFlashcard = false,
  }) {
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
          onCreateFlashCard: onCreateFlashCard,
          isExistingFlashcard: isExistingFlashcard,
        ),
      ),
    );
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
    
    // 로딩 표시
    final loadingDialog = _showLoadingDialog(context);
    
    try {
      // 사전 초기화 확인 및 검색
      if (!_dictionaryService.isInitialized) {
        await _dictionaryService.initialize();
      }
      
      // 단어 검색
      final result = await _dictionaryService.lookupWord(word);
      
      // 로딩 다이얼로그 닫기
      if (context.mounted) {
        Navigator.of(context).pop(); // 로딩 다이얼로그 닫기
      }
      
      if (result['success'] == true && result['entry'] != null) {
        final entry = result['entry'] as DictionaryEntry;
        
        // 콜백 호출
        onEntryFound(entry);
        
        // 바텀 시트 표시
        if (context.mounted) {
          showDictionaryBottomSheet(
            context: context,
            entry: entry,
            onCreateFlashCard: onCreateFlashCard,
          );
        }
      } else {
        if (context.mounted) {
          // 사전 검색 결과 없음 메시지 표시
          final errorMessage = result['message'] ?? '단어를 찾을 수 없습니다: $word';
          ErrorHandler.showInfoSnackBar(context, errorMessage);
        }
        
        // 결과 없음 콜백
        if (onNotFound != null) {
          onNotFound();
        }
      }
    } catch (e) {
      // 오류 발생 시 로딩 다이얼로그 닫기
      if (context.mounted) {
        Navigator.of(context).pop(); // 로딩 다이얼로그 닫기
        ErrorHandler.showErrorSnackBar(context, e, ErrorContext.dictionary);
      }
      
      // 결과 없음 콜백
      if (onNotFound != null) {
        onNotFound();
      }
    }
  }
  
  /// 단어 검색 (사전 결과만 반환)
  static Future<Map<String, dynamic>> searchWord(String word) async {
    if (word.isEmpty) {
      return {'success': false, 'message': '검색할 단어를 입력하세요'};
    }
    
    try {
      // 사전 초기화 확인
      if (!_dictionaryService.isInitialized) {
        await _dictionaryService.initialize();
      }
      
      // 단어 검색
      return await _dictionaryService.lookupWord(word);
    } catch (e) {
      return {'success': false, 'message': ErrorHandler.getMessageFromError(e, ErrorContext.dictionary)};
    }
  }
  
  // 로딩 다이얼로그 표시
  static Future<void> _showLoadingDialog(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              const Text('단어 검색 중...'),
            ],
          ),
        );
      },
    );
  }
}
