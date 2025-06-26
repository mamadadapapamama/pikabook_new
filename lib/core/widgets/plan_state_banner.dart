import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/common/trial_completed_banner_service.dart';
import '../services/common/premium_expired_banner_service.dart';
import '../services/common/usage_limit_banner_service.dart';
import '../services/common/plan_service.dart';
import '../theme/tokens/color_tokens.dart';
import 'unified_banner.dart';
import 'upgrade_modal.dart';
import 'package:url_launcher/url_launcher.dart';

/// 체험 완료 배너
class TrialCompletedBanner extends StatefulWidget {
  const TrialCompletedBanner({super.key});

  @override
  State<TrialCompletedBanner> createState() => _TrialCompletedBannerState();
}

class _TrialCompletedBannerState extends State<TrialCompletedBanner> {
  final service = TrialCompletedBannerService();
  bool _shouldShow = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkShouldShow();
  }

  Future<void> _checkShouldShow() async {
    final shouldShow = await service.shouldShowBanner();
    if (mounted) {
      setState(() {
        _shouldShow = shouldShow;
        _isLoading = false;
      });
    }
  }

  Future<void> _dismiss() async {
    await service.dismissBanner();
    if (mounted) {
      setState(() {
        _shouldShow = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || !_shouldShow) {
      return const SizedBox.shrink();
    }

    return UnifiedBanner(
      icon: Icons.check_circle,
      iconColor: ColorTokens.primary,
      title: '7일 무료체험이 완료되었어요.',
      subtitle: '프리미엄(monthly)로 전환되었습니다. 언제든 구독 취소를 하실수 있어요.',
      onDismiss: _dismiss,
    );
  }
}

/// 프리미엄 만료 배너
class PremiumExpiredBanner extends StatefulWidget {
  const PremiumExpiredBanner({super.key});

  @override
  State<PremiumExpiredBanner> createState() => _PremiumExpiredBannerState();
}

class _PremiumExpiredBannerState extends State<PremiumExpiredBanner> {
  final service = PremiumExpiredBannerService();
  bool _shouldShow = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkShouldShow();
  }

  Future<void> _checkShouldShow() async {
    final shouldShow = await service.shouldShowBanner();
    if (mounted) {
      setState(() {
        _shouldShow = shouldShow;
        _isLoading = false;
      });
    }
  }

  Future<void> _dismiss() async {
    await service.dismissBanner();
    if (mounted) {
      setState(() {
        _shouldShow = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || !_shouldShow) {
      return const SizedBox.shrink();
    }

    return UnifiedBanner(
      icon: Icons.info,
      iconColor: ColorTokens.primary,
      title: '프리미엄 플랜이 무료 플랜으로 전환되었습니다.',
      subtitle: '자세한 내용은 settings > 플랜에서 확인하실수 있어요.',
      onDismiss: _dismiss,
    );
  }
}

/// 사용량 한도 배너
class UsageLimitBanner extends StatefulWidget {
  const UsageLimitBanner({super.key});

  @override
  State<UsageLimitBanner> createState() => _UsageLimitBannerState();
}

class _UsageLimitBannerState extends State<UsageLimitBanner> {
  final service = UsageLimitBannerService();
  bool _shouldShow = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkShouldShow();
  }

  Future<void> _checkShouldShow() async {
    final shouldShow = await service.shouldShowBanner();
    if (mounted) {
      setState(() {
        _shouldShow = shouldShow;
        _isLoading = false;
      });
    }
  }

  Future<void> _dismiss() async {
    await service.dismissBanner();
    if (mounted) {
      setState(() {
        _shouldShow = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || !_shouldShow) {
      return const SizedBox.shrink();
    }

    return UnifiedBanner(
      icon: Icons.warning,
      iconColor: ColorTokens.warning,
      title: '사용량 한도에 도달했어요.',
      subtitle: '추가로 사용하시려면 관리자에게 문의해주세요.',
      mainButtonText: '문의하기',
      onMainButtonPressed: () => _handleUsageLimitUpgrade(context),
      onDismiss: _dismiss,
    );
  }

  /// 사용량 한도 배너에서 업그레이드 처리 (플랜 상태에 따른 분기)
  Future<void> _handleUsageLimitUpgrade(BuildContext context) async {
    try {
      // 현재 플랜 상태 확인
      final planService = PlanService();
      final subscriptionDetails = await planService.getSubscriptionDetails();
      final currentPlan = subscriptionDetails['currentPlan'] as String?;
      final hasUsedFreeTrial = subscriptionDetails['hasUsedFreeTrial'] as bool? ?? false;
      final hasEverUsedTrial = subscriptionDetails['hasEverUsedTrial'] as bool? ?? false;
      
      if (currentPlan == PlanService.PLAN_FREE) {
        // 무료 플랜 사용자
        if (hasUsedFreeTrial || hasEverUsedTrial) {
          // 무료체험 사용한 적 있음 -> 프리미엄 모달
          UpgradeModal.show(
            context,
            reason: UpgradeReason.limitReached,
          );
        } else {
          // 무료체험 사용한 적 없음 -> 무료체험 모달
          UpgradeModal.show(
            context,
            reason: UpgradeReason.welcomeTrial,
          );
        }
      } else if (currentPlan == PlanService.PLAN_PREMIUM) {
        // 🎯 프리미엄 사용자 -> 문의하기 폼
        final formUrl = Uri.parse('https://docs.google.com/forms/d/e/1FAIpQLSfgVL4Bd5KcTh9nhfbVZ51yApPAmJAZJZgtM4V9hNhsBpKuaA/viewform?usp=dialog');
        try {
          if (await canLaunchUrl(formUrl)) {
            await launchUrl(formUrl, mode: LaunchMode.externalApplication);
          } else {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('문의 폼을 열 수 없습니다.'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('문의 폼을 여는 중 오류가 발생했습니다: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
      
      if (kDebugMode) {
        debugPrint('[UsageLimitBanner] 사용량 한도 업그레이드 처리: $currentPlan, 체험사용: $hasUsedFreeTrial');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[UsageLimitBanner] 사용량 한도 업그레이드 처리 실패: $e');
      }
      // 기본적으로 업그레이드 모달 표시
      UpgradeModal.show(
        context,
        reason: UpgradeReason.limitReached,
      );
    }
  }
} 