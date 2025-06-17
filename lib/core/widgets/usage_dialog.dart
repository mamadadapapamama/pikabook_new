import 'package:flutter/material.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import 'pika_button.dart';
import '../../../core/services/common/usage_limit_service.dart';
import '../../../core/services/common/plan_service.dart';
import '../../../core/widgets/upgrade_modal.dart';

/// 사용량 확인 다이얼로그
/// 현재 사용량과 플랜 정보를 표시합니다.
class UsageDialog extends StatefulWidget {
  final String? title;
  final String? message;
  final Function? onContactSupport;

  const UsageDialog({
    Key? key,
    this.title,
    this.message,
    this.onContactSupport,
  }) : super(key: key);

  @override
  State<UsageDialog> createState() => _UsageDialogState();
  
  /// 다이얼로그 표시 정적 메서드
  static Future<void> show(
    BuildContext context, {
    String? title,
    String? message,
    Map<String, dynamic>? limitStatus, // 호환성을 위해 유지하지만 사용하지 않음
    Map<String, double>? usagePercentages, // 호환성을 위해 유지하지만 사용하지 않음
    Function? onContactSupport,
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return UsageDialog(
          title: title,
          message: message,
          onContactSupport: onContactSupport,
        );
      },
    );
  }
}

class _UsageDialogState extends State<UsageDialog> {
  final UsageLimitService _usageService = UsageLimitService();
  final PlanService _planService = PlanService();
  
  Map<String, dynamic> _limitStatus = {};
  Map<String, double> _usagePercentages = {};
  bool _isLoading = true;
  String _currentPlan = 'free';
  bool _isFreeTrial = false;

  @override
  void initState() {
    super.initState();
    _loadUsageData();
  }

  Future<void> _loadUsageData() async {
    setState(() => _isLoading = true);

    try {
      // 플랜 정보 가져오기
      final subscriptionDetails = await _planService.getSubscriptionDetails();
      _currentPlan = subscriptionDetails['currentPlan'] ?? 'free';
      _isFreeTrial = subscriptionDetails['isFreeTrial'] ?? false;
      
      // 사용량 정보 가져오기
      final usageInfo = await _usageService.getUserUsageForSettings();
      _limitStatus = usageInfo['limitStatus'] as Map<String, dynamic>;
      
      // 사용량 퍼센트 계산
      final percentagesMap = usageInfo['usagePercentages'] as Map<String, dynamic>;
      _usagePercentages = {};
      percentagesMap.forEach((key, value) {
        _usagePercentages[key] = (value is num) ? value.toDouble() : 0.0;
      });
      
    } catch (e) {
      // 기본값 설정
      _limitStatus = {
        'ocrLimitReached': false,
        'ttsLimitReached': false,
        'ocrLimit': 10,
        'ttsLimit': 30,
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
    final bool hasReachedLimit = _limitStatus['ocrLimitReached'] == true || 
                                _limitStatus['ttsLimitReached'] == true;
    
    final String effectiveTitle = widget.title ?? 
        (hasReachedLimit ? '학습 한도에 도달했어요.' : '현재까지의 사용량');
        
    final String effectiveMessage = widget.message ?? 
        (hasReachedLimit ? '무료 제공 한도에 도달했어요.\n프리미엄으로 업그레이드하여 더 많은 기능을 이용해보세요!' : '');

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
              height: 220,
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
      actionsPadding: EdgeInsets.all(SpacingTokens.md),
      actions: [
        if (widget.onContactSupport != null) _buildActionButton(),
        PikaButton(
          text: '닫기',
          variant: PikaButtonVariant.primary,
          size: PikaButtonSize.small,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
  
  /// 사용량 그래프 위젯
  Widget _buildUsageGraph() {
    final List<MapEntry<String, double>> entries = [
      MapEntry('ocr', _usagePercentages['ocr'] ?? 0.0),
      MapEntry('tts', _usagePercentages['tts'] ?? 0.0),
    ];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '사용량 현황',
          style: TypographyTokens.body2.copyWith(fontWeight: FontWeight.bold),
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
                    Text(label, style: TypographyTokens.caption),
                    Text(
                      '${percentage.toStringAsFixed(0)}%',
                      style: TypographyTokens.caption.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _getUsageColor(percentage),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: percentage / 100,
                  backgroundColor: ColorTokens.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(_getUsageColor(percentage)),
                ),
              ],
            ),
          );
        }).toList(),
      ],
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
    switch (key) {
      case 'ocr':
        return '업로드 이미지 수 (${_limitStatus['ocrLimit'] ?? 10}장)';
      case 'tts':
        return '듣기 기능 (${_limitStatus['ttsLimit'] ?? 30}회)';
      default:
        return key;
    }
  }

  /// 플랜 상태에 따른 액션 버튼
  Widget _buildActionButton() {
    final bool isPremiumPaid = _currentPlan == PlanService.PLAN_PREMIUM && !_isFreeTrial;
    
    return PikaButton(
      text: isPremiumPaid ? '문의하기' : '프리미엄으로 업그레이드',
      variant: PikaButtonVariant.outline,
      size: PikaButtonSize.small,
      onPressed: () async {
        Navigator.of(context).pop();
        
        if (isPremiumPaid) {
          // 유료 프리미엄 사용자 - 문의 모달
          if (mounted) {
            UpgradeModal.show(context, reason: UpgradeReason.premiumUser);
          }
        } else {
          // 무료/체험 사용자 - 업그레이드 모달
          if (mounted) {
            UpgradeModal.show(
              context,
              reason: _isFreeTrial ? UpgradeReason.trialExpired : UpgradeReason.limitReached,
            );
          }
        }
      },
    );
  }
} 