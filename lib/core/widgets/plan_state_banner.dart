import 'package:flutter/material.dart';
import '../services/common/trial_completed_banner_service.dart';
import '../services/common/premium_expired_banner_service.dart';
import '../services/common/usage_limit_banner_service.dart';
import '../theme/tokens/color_tokens.dart';
import 'unified_banner.dart';
import 'upgrade_modal.dart';

/// 체험 완료 배너
class TrialCompletedBanner extends StatelessWidget {
  const TrialCompletedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final service = TrialCompletedBannerService();
    
    return FutureBuilder<bool>(
      future: service.shouldShowBanner(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data != true) {
          return const SizedBox.shrink();
        }

        return UnifiedBanner(
          icon: Icons.check_circle,
          iconColor: ColorTokens.primary,
          title: '7일 무료체험이 완료되었어요.',
          subtitle: '프리미엄(monthly)로 전환되었습니다. 언제든 구독 취소를 하실수 있어요.',
          onDismiss: () => service.dismissBanner(),
        );
      },
    );
  }
}

/// 프리미엄 만료 배너
class PremiumExpiredBanner extends StatelessWidget {
  const PremiumExpiredBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final service = PremiumExpiredBannerService();
    
    return FutureBuilder<bool>(
      future: service.shouldShowBanner(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data != true) {
          return const SizedBox.shrink();
        }

        return UnifiedBanner(
          icon: Icons.info,
          iconColor: ColorTokens.primary,
          title: '프리미엄 플랜이 무료 플랜으로 전환되었습니다.',
          subtitle: '자세한 내용은 settings > 플랜에서 확인하실수 있어요.',
          onDismiss: () => service.dismissBanner(),
        );
      },
    );
  }
}

/// 사용량 한도 배너
class UsageLimitBanner extends StatelessWidget {
  const UsageLimitBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final service = UsageLimitBannerService();
    
    return FutureBuilder<bool>(
      future: service.shouldShowBanner(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data != true) {
          return const SizedBox.shrink();
        }

        return UnifiedBanner(
          icon: Icons.warning,
          iconColor: ColorTokens.warning,
          title: '사용량 한도에 도달했어요.',
          subtitle: '추가로 사용하시려면 업그레이드 해주세요.',
          mainButtonText: '업그레이드',
          onMainButtonPressed: () => _showUpgradeModal(context),
          onDismiss: () => service.dismissBanner(),
        );
      },
    );
  }

  void _showUpgradeModal(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const UpgradeModal(),
    );
  }
} 