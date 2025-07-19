import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../features/home/coordinators/home_ui_coordinator.dart';
import '../models/subscription_state.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import 'pika_button.dart';
import '../../../core/services/common/usage_limit_service.dart';
import '../constants/plan_constants.dart';
import '../../../core/widgets/upgrade_modal.dart';

/// 사용량 확인 다이얼로그
/// 현재 사용량과 플랜 정보를 표시합니다.
class UsageDialog extends StatelessWidget {
  final SubscriptionInfo subscriptionInfo;

  const UsageDialog({Key? key, required this.subscriptionInfo}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final String effectiveTitle = '현재까지의 사용량';
    final String effectiveMessage = '';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      title: Text(
        effectiveTitle,
        style: TypographyTokens.subtitle1.copyWith(fontWeight: FontWeight.bold),
      ),
      content: FutureBuilder<Map<String, dynamic>>(
        future: UsageLimitService().getUserUsageForSettings(),
        builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              width: 260,
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                '사용량 데이터를 불러올 수 없습니다: ${snapshot.error}',
                style: TypographyTokens.body2,
              ),
            );
          }

          final usage = snapshot.data?['usage'] as Map<String, dynamic>? ?? {};
          final limits = PlanConstants.getPlanLimits(subscriptionInfo.canUsePremiumFeatures ? PlanConstants.PLAN_PREMIUM : PlanConstants.PLAN_FREE);

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (effectiveMessage.isNotEmpty) ...[
                Text(effectiveMessage, style: TypographyTokens.body2),
                SizedBox(height: SpacingTokens.md),
              ],
              _buildUsageItem(
                '📱', 
                '이미지 노트 변환', 
                '이번 달 ${usage['ocrPages'] ?? 0}장 사용',
                '월 ${limits['ocrPages'] ?? 0}장'
              ),
              const SizedBox(height: 16),
              _buildUsageItem(
                '🔊', 
                '원어민 발음 듣기 (노트)', 
                '이번 달 ${usage['ttsRequestsNote'] ?? 0}회 사용',
                '월 ${limits['ttsRequests'] ?? 0}회'
              ),
              const SizedBox(height: 16),
              _buildUsageItem(
                '📚', 
                '원어민 발음 듣기 (플래시카드)', 
                '이번 달 ${usage['ttsRequestsFlashcard'] ?? 0}회 사용',
                '월 ${limits['ttsRequests'] ?? 0}회'
              ),
            ],
          );
        },
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        PikaButton(  
          text: '닫기',
          variant: PikaButtonVariant.primary,
          size: PikaButtonSize.small,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
  
  Widget _buildUsageItem(String icon, String title, String usage, String limit) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(icon, style: TypographyTokens.body1.copyWith(fontSize: 24)),
        const SizedBox(width: SpacingTokens.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TypographyTokens.body1),
              SizedBox(height: SpacingTokens.xsHalf),
              Text(usage, style: TypographyTokens.caption),
              SizedBox(height: SpacingTokens.xsHalf),
              Text(limit, style: TypographyTokens.caption),
            ],
          ),
        ),
      ],
    );
  }
} 