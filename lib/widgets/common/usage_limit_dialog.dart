import 'package:flutter/material.dart';
import '../../theme/tokens/color_tokens.dart';
import '../../theme/tokens/typography_tokens.dart';
import '../../theme/tokens/spacing_tokens.dart';
import '../../services/usage_limit_service.dart';
import 'package:url_launcher/url_launcher.dart';

class UsageLimitDialog extends StatelessWidget {
  final Map<String, bool> limitStatus;
  final Map<String, double> usagePercentages;
  final VoidCallback? onContactSupport;
  
  // 프리미엄 문의 구글 폼 URL
  static const String _premiumRequestFormUrl = 'https://forms.gle/9EBEV1vaLpNbkhxD9';
  
  const UsageLimitDialog({
    Key? key,
    required this.limitStatus,
    required this.usagePercentages,
    this.onContactSupport,
  }) : super(key: key);
  
  // 구글 폼 열기
  Future<void> _openPremiumRequestForm() async {
    final Uri url = Uri.parse(_premiumRequestFormUrl);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw '지원팀에 문의하기를 열 수 없습니다';
      }
    } catch (e) {
      debugPrint('URL 열기 오류: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
      ),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: _buildDialogContent(context),
    );
  }
  
  Widget _buildDialogContent(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: SpacingTokens.md),
      decoration: BoxDecoration(
        color: ColorTokens.surface,
        shape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
        boxShadow: [
          BoxShadow(
            color: ColorTokens.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 경고 아이콘 상단
          Container(
            padding: EdgeInsets.all(SpacingTokens.md),
            decoration: BoxDecoration(
              color: ColorTokens.warningLight,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(SpacingTokens.radiusMedium),
                topRight: Radius.circular(SpacingTokens.radiusMedium),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: ColorTokens.warning,
                  size: SpacingTokens.iconSizeLarge,
                ),
                SizedBox(width: SpacingTokens.sm),
                Expanded(
                  child: Text(
                    '사용량이 월 한도를 초과했어요',
                    style: TypographyTokens.subtitle2.copyWith(
                      color: ColorTokens.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 메인 내용
          Padding(
            padding: EdgeInsets.all(SpacingTokens.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 사용량 현황
                Text(
                  '현재 사용량 현황',
                  style: TypographyTokens.body1Bold,
                ),
                SizedBox(height: SpacingTokens.sm),
                
                // 사용량 바 차트들
                _buildUsageBar('번역 사용량', usagePercentages['translationPercent'] ?? 0.0),
                SizedBox(height: SpacingTokens.xs),
                _buildUsageBar('노트 사용량', usagePercentages['notePercent'] ?? 0.0),
                SizedBox(height: SpacingTokens.xs),
                _buildUsageBar('OCR 사용량', usagePercentages['ocrPercent'] ?? 0.0),
                SizedBox(height: SpacingTokens.xs),
                _buildUsageBar('사전 조회량', usagePercentages['dictionaryPercent'] ?? 0.0),
                SizedBox(height: SpacingTokens.xs),
                _buildUsageBar('플래시카드', usagePercentages['flashcardPercent'] ?? 0.0),
                
                SizedBox(height: SpacingTokens.lg),
                
                // 안내 문구
                Container(
                  padding: EdgeInsets.all(SpacingTokens.md),
                  decoration: BoxDecoration(
                    color: ColorTokens.primaryverylight,
                    borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '현재는 일부 사용자에 한해\n기능 확장을 수동으로 제공하고 있습니다.',
                        style: TypographyTokens.body2,
                      ),
                      SizedBox(height: SpacingTokens.sm),
                      Text(
                        '관심 있으신 분은 아래 안내를 참고해 주세요.',
                        style: TypographyTokens.body2,
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: SpacingTokens.md),
                
                // 한도 초과 설명
                Text(
                  '한도 초과에 따른 영향:',
                  style: TypographyTokens.body1Bold,
                ),
                SizedBox(height: SpacingTokens.xs),
                
                // 제한되는 기능들 목록
                _buildLimitedFeatureItem(
                  limitStatus['noteLimitReached'] ?? false,
                  '노트 추가', 
                  '더 이상 새로운 노트를 추가할 수 없습니다'
                ),
                _buildLimitedFeatureItem(
                  limitStatus['ocrLimitReached'] ?? false,
                  'OCR 텍스트 인식', 
                  '더 이상 이미지에서 텍스트를 인식할 수 없습니다'
                ),
                _buildLimitedFeatureItem(
                  limitStatus['translationLimitReached'] ?? false,
                  '번역 기능', 
                  '더 이상 텍스트 번역을 수행할 수 없습니다'
                ),
                _buildLimitedFeatureItem(
                  limitStatus['dictionaryLimitReached'] ?? false,
                  '외부 사전 조회', 
                  '내장 사전은 계속 사용 가능'
                ),
                _buildLimitedFeatureItem(
                  limitStatus['flashcardLimitReached'] ?? false,
                  '플래시카드 추가', 
                  '더 이상 새로운 플래시카드를 추가할 수 없습니다'
                ),
              ],
            ),
          ),
          
          // 하단 버튼
          Padding(
            padding: EdgeInsets.only(
              left: SpacingTokens.md,
              right: SpacingTokens.md,
              bottom: SpacingTokens.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: ColorTokens.textTertiary,
                    ),
                    child: Text(
                      '닫기',
                      style: TypographyTokens.button,
                    ),
                  ),
                ),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onContactSupport ?? _openPremiumRequestForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ColorTokens.primary,
                      foregroundColor: ColorTokens.textLight,
                      padding: EdgeInsets.symmetric(vertical: SpacingTokens.sm),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
                      ),
                    ),
                    child: Text(
                      '문의하기',
                      style: TypographyTokens.button.copyWith(
                        color: ColorTokens.textLight,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // 사용량 바 위젯
  Widget _buildUsageBar(String label, double percentage) {
    final double clampedPercentage = percentage.clamp(0.0, 1.0);
    final bool isOverLimit = percentage >= 1.0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TypographyTokens.caption.copyWith(
                color: isOverLimit ? ColorTokens.error : ColorTokens.textSecondary,
              ),
            ),
            Text(
              '${(clampedPercentage * 100).toInt()}%',
              style: TypographyTokens.caption.copyWith(
                color: isOverLimit ? ColorTokens.error : ColorTokens.textSecondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(height: SpacingTokens.xs / 2),
        Stack(
          children: [
            // 배경 바
            Container(
              height: 6,
              width: double.infinity,
              decoration: BoxDecoration(
                color: ColorTokens.greyLight,
                borderRadius: BorderRadius.circular(SpacingTokens.radiusXs),
              ),
            ),
            // 진행 바
            LayoutBuilder(
              builder: (context, constraints) {
                return Container(
                  height: 6,
                  width: constraints.maxWidth * clampedPercentage,
                  decoration: BoxDecoration(
                    color: isOverLimit ? ColorTokens.error : ColorTokens.primary,
                    borderRadius: BorderRadius.circular(SpacingTokens.radiusXs),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
  
  // 제한되는 기능 아이템
  Widget _buildLimitedFeatureItem(bool isLimited, String feature, String description) {
    return Padding(
      padding: EdgeInsets.only(bottom: SpacingTokens.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isLimited ? Icons.cancel : Icons.check_circle_outline,
            color: isLimited ? ColorTokens.error : ColorTokens.success,
            size: SpacingTokens.iconSizeSmall,
          ),
          SizedBox(width: SpacingTokens.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature,
                  style: TypographyTokens.caption.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isLimited ? ColorTokens.error : ColorTokens.textPrimary,
                  ),
                ),
                if (isLimited)
                  Text(
                    description,
                    style: TypographyTokens.caption.copyWith(
                      color: ColorTokens.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // 다이얼로그 표시 유틸리티 함수
  static Future<void> show(
    BuildContext context, {
    required Map<String, bool> limitStatus,
    required Map<String, double> usagePercentages,
    VoidCallback? onContactSupport,
  }) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
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