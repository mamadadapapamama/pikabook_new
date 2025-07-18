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
class UsageDialog extends StatefulWidget {
  final String? title;
  final String? message;
  final Function? onContactSupport;
  final SubscriptionInfo? subscriptionInfo;

  const UsageDialog({
    Key? key,
    this.title,
    this.message,
    this.onContactSupport,
    this.subscriptionInfo,
  }) : super(key: key);

  @override
  State<UsageDialog> createState() => _UsageDialogState();
  
  /// 다이얼로그 표시 정적 메서드
  static Future<void> show(
    BuildContext context, {
    String? title,
    String? message,
    SubscriptionInfo? subscriptionInfo,
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return UsageDialog(
          title: title,
          message: message,
          subscriptionInfo: subscriptionInfo,
        );
      },
    );
  }
}

class _UsageDialogState extends State<UsageDialog> {
  final UsageLimitService _usageService = UsageLimitService();
  final HomeUICoordinator _uiCoordinator = HomeUICoordinator();
  
  Map<String, dynamic> _limitStatus = {};
  Map<String, double> _usagePercentages = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsageData();
  }

  Future<void> _loadUsageData() async {
    setState(() => _isLoading = true);

    try {
      if (kDebugMode) {
        debugPrint('📊 [UsageDialog] 사용량 데이터 로드 시작');
      }
      
      final usageInfo = await _usageService.getUserUsageForSettings();
      
      final isPremium = widget.subscriptionInfo?.canUsePremiumFeatures ?? false;
      final planLimits = isPremium 
        ? PlanConstants.getPlanLimits(PlanConstants.PLAN_PREMIUM) 
        : PlanConstants.getPlanLimits(PlanConstants.PLAN_FREE);

      _limitStatus = {
        'ocrLimitReached': usageInfo['limitStatus']?['ocrLimitReached'] ?? false,
        'ttsLimitReached': usageInfo['limitStatus']?['ttsLimitReached'] ?? false,
        'ocrLimit': planLimits['ocrPages'] ?? 10,
        'ttsLimit': planLimits['ttsRequests'] ?? 30,
      };
      
      final percentagesMap = usageInfo['usagePercentages'] as Map<String, dynamic>? ?? {};
      _usagePercentages = {};
      percentagesMap.forEach((key, value) {
        _usagePercentages[key] = (value is num) ? value.toDouble() : 0.0;
      });
      
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ [UsageDialog] 사용량 데이터 로드 실패: $e');
        debugPrint('❌ [UsageDialog] 스택 트레이스: $stackTrace');
      }
      
      final isPremium = widget.subscriptionInfo?.canUsePremiumFeatures ?? false;
      final planLimits = isPremium 
          ? PlanConstants.getPlanLimits(PlanConstants.PLAN_PREMIUM) 
          : PlanConstants.getPlanLimits(PlanConstants.PLAN_FREE);
      _limitStatus = {
        'ocrLimitReached': false,
        'ttsLimitReached': false,
        'ocrLimit': planLimits['ocrPages'] ?? 10,
        'ttsLimit': planLimits['ttsRequests'] ?? 30,
      };
      _usagePercentages = {'ocr': 0.0, 'tts': 0.0};
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String effectiveTitle = widget.title ?? '현재까지의 사용량';
    final String effectiveMessage = widget.message ?? '';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      title: Text(
        effectiveTitle,
        style: TypographyTokens.subtitle1.copyWith(fontWeight: FontWeight.bold),
      ),
      content: _isLoading
          ? const SizedBox(
              width: 260,
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (effectiveMessage.isNotEmpty) ...[
                    Text(effectiveMessage, style: TypographyTokens.body2),
                    SizedBox(height: SpacingTokens.md),
                  ],
                  _buildUsageGraph(),
                ],
              ),
            ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        _buildActionButton(context),
      ],
    );
  }
  
  /// 사용량 그래프 위젯
  Widget _buildUsageGraph() {
    return Column(
      children: _usagePercentages.entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: SpacingTokens.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_getUsageLabel(entry.key), style: TypographyTokens.caption),
              const SizedBox(height: SpacingTokens.xsHalf),
              LinearProgressIndicator(
                value: entry.value / 100,
                backgroundColor: ColorTokens.greyLight,
                valueColor: AlwaysStoppedAnimation<Color>(_getUsageColor(entry.value)),
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
  
  /// 사용량에 따른 색상 반환
  Color _getUsageColor(double percentage) {
    if (percentage > 90) return ColorTokens.error;
    if (percentage > 70) return Colors.orange;
    return ColorTokens.primary;
  }
  
  /// 사용량 라벨 변환
  String _getUsageLabel(String key) {
    final bool isPremium = widget.subscriptionInfo?.canUsePremiumFeatures ?? false;
    final String period = isPremium ? '/월' : '';
    
    switch (key) {
      case 'ocr':
        return '업로드 이미지 수 (${_limitStatus['ocrLimit'] ?? 10}장$period)';
      case 'tts':
        return '듣기 기능 (${_limitStatus['ttsLimit'] ?? 30}회$period)';
      default:
        return key;
    }
  }

  /// 플랜 상태에 따른 액션 버튼
  Widget _buildActionButton(BuildContext context) {
    return PikaButton(  
      text: '닫기',
      variant: PikaButtonVariant.primary,
      size: PikaButtonSize.small,
      onPressed: () => Navigator.of(context).pop(),
    );
  }
} 