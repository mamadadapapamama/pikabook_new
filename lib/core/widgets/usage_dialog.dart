import 'package:flutter/material.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import 'pika_button.dart';
import 'package:url_launcher/url_launcher.dart';

/// 사용량 확인 다이얼로그
/// 사용량 정보 및 제한 상태를 확인할 수 있습니다.
class UsageDialog extends StatelessWidget {
  final String? title;
  final String? message;
  final Map<String, dynamic> limitStatus;
  final Map<String, double> usagePercentages;
  final Function? onContactSupport;

  const UsageDialog({
    Key? key,
    this.title,
    this.message,
    required this.limitStatus,
    required this.usagePercentages,
    this.onContactSupport,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 한도 초과 여부 확인
    final bool hasReachedLimit = _hasReachedAnyLimit();
    
    // 상태에 따른 제목과 메시지 설정
    final String effectiveTitle = title ?? (hasReachedLimit 
        ? '사용량 제한에 도달했습니다' 
        : '현재까지의 사용량');
        
    final String effectiveMessage = message ?? (hasReachedLimit 
        ? '사용하시는 기능이 한도에 도달했습니다. \n더 많은 기능이 필요하시다면 문의하기를 눌러 요청해 주세요.' 
        : '');

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      backgroundColor: Colors.white,
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
            if (effectiveMessage.isNotEmpty) ...[
              Text(
                effectiveMessage,
                style: TypographyTokens.body2,
              ),
              SizedBox(height: SpacingTokens.md),
            ],
            
            // 사용량 현황 그래프
            _buildUsageGraph(),
          ],
        ),
      ),
      actionsPadding: EdgeInsets.all(SpacingTokens.md),
      actions: [
        // 1:1 문의하기 버튼
        if (onContactSupport != null)
          PikaButton(
            text: '문의하기',
            variant: PikaButtonVariant.outline,
            size: PikaButtonSize.small,
            onPressed: () {
              Navigator.of(context).pop();
              launchUrl(Uri.parse('https://forms.gle/YaeznYjGLiMdHmBD9'));
            },
          ),
          
        // 확인 버튼
        PikaButton(
          text: '닫기',
          variant: PikaButtonVariant.primary,
          size: PikaButtonSize.small,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  // 어떤 한도든 초과했는지 확인
  bool _hasReachedAnyLimit() {
    return limitStatus['ocrLimitReached'] == true ||
           limitStatus['ttsLimitReached'] == true ||
           limitStatus['translationLimitReached'] == true ||
           limitStatus['storageLimitReached'] == true ||
           limitStatus['betaEnded'] == true;
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
    // 항상 4가지 주요 사용량을 표시 (ocr, tts, translation, storage)
    final List<MapEntry<String, double>> entries = [
      MapEntry('ocr', usagePercentages['ocr'] ?? 0.0),
      MapEntry('tts', usagePercentages['tts'] ?? 0.0),
      MapEntry('translation', usagePercentages['translation'] ?? 0.0),
      MapEntry('storage', usagePercentages['storage'] ?? 0.0),
    ];
    
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
        ...entries.map((entry) {
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
        return 'OCR 페이지';
      case 'tts':
        return '음성 읽기';
      case 'translation':
        return '번역';
      case 'storage':
        return '저장 공간 (100MB)';
      default:
        return key;
    }
  }
  
  /// 다이얼로그 표시 정적 메서드
  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> limitStatus,
    required Map<String, double> usagePercentages,
    Function? onContactSupport,
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return UsageDialog(
          limitStatus: limitStatus,
          usagePercentages: usagePercentages,
          onContactSupport: onContactSupport,
        );
      },
    );
  }
} 