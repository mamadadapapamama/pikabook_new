import 'package:flutter/material.dart';
import '../../theme/tokens/color_tokens.dart';
import '../../theme/tokens/typography_tokens.dart';
import '../../theme/tokens/spacing_tokens.dart';
import 'pika_button.dart';

/// 사용량 제한 다이얼로그
/// 베타 기간 동안 기능 제한에 도달했을 때 표시됩니다.
class UsageLimitDialog extends StatelessWidget {
  final String? title;
  final String? message;
  final Map<String, bool> limitStatus;
  final Map<String, double> usagePercentages;
  final Function? onContactSupport;

  const UsageLimitDialog({
    Key? key,
    this.title,
    this.message,
    required this.limitStatus,
    required this.usagePercentages,
    this.onContactSupport,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 실제 제한 도달 정보 기반으로 제목과 메시지 설정
    final String effectiveTitle = title ?? _getLimitTitle();
    final String effectiveMessage = message ?? _getLimitMessage();

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            effectiveTitle,
            style: TypographyTokens.subtitle1.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_showBetaPeriodInfo()) ...[
            SizedBox(height: SpacingTokens.sm),
            _buildBetaPeriodInfo(),
          ],
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              effectiveMessage,
              style: TypographyTokens.body2,
            ),
            SizedBox(height: SpacingTokens.md),
            
            // 사용량 현황 그래프 (필요한 경우)
            if (_shouldShowUsageGraph()) _buildUsageGraph(),
          ],
        ),
      ),
      actions: [
        // 1:1 문의하기 버튼
        if (onContactSupport != null)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onContactSupport!();
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: Text(
              '1:1 문의하기',
              style: TypographyTokens.button.copyWith(
                color: ColorTokens.primary,
              ),
            ),
          ),
          
        // 확인 버튼
        PikaButton(
          text: '확인',
          variant: PikaButtonVariant.primary,
          size: PikaButtonSize.small,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
      actionsPadding: EdgeInsets.all(SpacingTokens.md),
    );
  }

  // 어떤 제한에 도달했는지 기반으로 제목 생성
  String _getLimitTitle() {
    if (limitStatus['betaEnded'] == true) {
      return '베타 기간이 종료되었습니다';
    }
    
    if (limitStatus['storageLimitReached'] == true) {
      return '저장 공간 제한에 도달했습니다';
    }
    
    if (limitStatus['ocrLimitReached'] == true) {
      return 'OCR 사용량 제한에 도달했습니다';
    }
    
    if (limitStatus['ttsLimitReached'] == true) {
      return '음성 읽기 사용량 제한에 도달했습니다';
    }
    
    return '사용량 제한에 도달했습니다';
  }
  
  // 제한 종류에 맞는 메시지 생성
  String _getLimitMessage() {
    // 베타 종료
    if (limitStatus['betaEnded'] == true) {
      return '피카북 베타 테스트 기간이 종료되었습니다. 정식 서비스 출시를 기다려주세요.';
    }
    
    // 저장 공간 제한
    if (limitStatus['storageLimitReached'] == true) {
      return '베타 기간 동안 사용할 수 있는 저장 공간 한도에 도달했습니다. 불필요한 이미지나 노트를 삭제하여 공간을 확보하세요.';
    }
    
    // OCR 제한
    if (limitStatus['ocrLimitReached'] == true) {
      return '베타 기간 동안 사용할 수 있는 OCR 인식 횟수 한도에 도달했습니다. 기능 테스트에 도움을 주셔서 감사합니다.';
    }
    
    // TTS 제한
    if (limitStatus['ttsLimitReached'] == true) {
      return '베타 기간 동안 사용할 수 있는 음성 읽기 횟수 한도에 도달했습니다. 기능 테스트에 도움을 주셔서 감사합니다.';
    }
    
    // 노트 개수 제한
    if (limitStatus['noteLimitReached'] == true) {
      return '베타 기간 동안 생성할 수 있는 노트 개수 한도에 도달했습니다. 불필요한 노트를 삭제하여 공간을 확보하세요.';
    }
    
    // 일반 메시지
    return '베타 기간 동안 무료로 사용할 수 있는 한도에 도달했습니다. 더 많은 기능을 이용하시려면 정식 서비스 출시를 기다려주세요.';
  }
  
  // 베타 기간 정보를 표시할지 여부
  bool _showBetaPeriodInfo() {
    return limitStatus.containsKey('remainingDays');
  }
  
  // 베타 기간 정보 위젯
  Widget _buildBetaPeriodInfo() {
    final int remainingDays = limitStatus['remainingDays'] as int? ?? 0;
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: SpacingTokens.sm,
        vertical: SpacingTokens.xs,
      ),
      decoration: BoxDecoration(
        color: remainingDays > 0 ? Colors.blue.withOpacity(0.1) : Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        remainingDays > 0
            ? '베타 기간 잔여: $remainingDays일'
            : '베타 기간 종료',
        style: TypographyTokens.caption.copyWith(
          color: remainingDays > 0 ? Colors.blue : Colors.red,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
  
  // 사용량 그래프를 표시할지 여부
  bool _shouldShowUsageGraph() {
    return usagePercentages.isNotEmpty;
  }
  
  // 사용량 그래프 위젯
  Widget _buildUsageGraph() {
    // 사용량이 가장 많은 항목 3개만 표시
    final sortedEntries = usagePercentages.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    final topEntries = sortedEntries.take(3).toList();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '사용량 현황',
          style: TypographyTokens.body2.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: SpacingTokens.sm),
        ...topEntries.map((entry) {
          final String label = _getUsageLabel(entry.key);
          final double percentage = entry.value.clamp(0, 100);
          
          return Padding(
            padding: EdgeInsets.only(bottom: SpacingTokens.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      label,
                      style: TypographyTokens.caption,
                    ),
                    Text(
                      '${percentage.toStringAsFixed(0)}%',
                      style: TypographyTokens.caption.copyWith(
                        fontWeight: FontWeight.bold,
                        color: percentage > 90 
                            ? ColorTokens.error
                            : percentage > 70
                                ? Colors.orange
                                : ColorTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                LinearProgressIndicator(
                  value: percentage / 100,
                  backgroundColor: ColorTokens.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    percentage > 90
                        ? ColorTokens.error
                        : percentage > 70
                            ? Colors.orange
                            : ColorTokens.primary,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
  
  // 사용량 라벨 변환
  String _getUsageLabel(String key) {
    switch (key) {
      case 'ocr':
        return 'OCR 인식';
      case 'tts':
        return '음성 읽기';
      case 'translation':
        return '번역';
      case 'storage':
        return '저장 공간';
      case 'dictionary':
        return '사전 검색';
      case 'page':
        return '페이지 수';
      case 'flashcard':
        return '플래시카드';
      case 'note':
        return '노트 수';
      default:
        return key;
    }
  }
  
  /// 다이얼로그 표시 정적 메서드
  static Future<void> show(
    BuildContext context, {
    required Map<String, bool> limitStatus,
    required Map<String, double> usagePercentages,
    Function? onContactSupport,
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return UsageLimitDialog(
          limitStatus: limitStatus,
          usagePercentages: usagePercentages,
          onContactSupport: onContactSupport,
        );
      },
    );
  }
} 