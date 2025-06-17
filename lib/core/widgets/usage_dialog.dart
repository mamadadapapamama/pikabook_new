import 'package:flutter/material.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import 'pika_button.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/common/usage_limit_service.dart';
import '../../../core/services/common/plan_service.dart';
import '../../../core/widgets/upgrade_modal.dart';

/// 사용량 확인 다이얼로그
/// 사용량 정보 및 제한 상태를 확인할 수 있습니다.
class UsageDialog extends StatefulWidget {
  final String? title;
  final String? message;
  final Map<String, dynamic>? limitStatus;
  final Map<String, double>? usagePercentages;
  final Function? onContactSupport;

  const UsageDialog({
    Key? key,
    this.title,
    this.message,
    this.limitStatus,
    this.usagePercentages,
    this.onContactSupport,
  }) : super(key: key);

  @override
  State<UsageDialog> createState() => _UsageDialogState();
  
  /// 다이얼로그 표시 정적 메서드
  static Future<void> show(
    BuildContext context, {
    String? title,
    String? message,
    Map<String, dynamic>? limitStatus,
    Map<String, double>? usagePercentages,
    Function? onContactSupport,
  }) async {
    debugPrint('UsageDialog.show - limitStatus: $limitStatus');
    debugPrint('UsageDialog.show - usagePercentages: $usagePercentages');

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return UsageDialog(
          title: title,
          message: message,
          limitStatus: limitStatus,
          usagePercentages: usagePercentages,
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
  String _currentPlan = 'free'; // 현재 플랜 상태
  bool _isFreeTrial = false; // 무료 체험 여부

  @override
  void initState() {
    super.initState();
    _loadUsageData();
  }

  Future<void> _loadUsageData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 현재 플랜 정보 가져오기
      final subscriptionDetails = await _planService.getSubscriptionDetails();
      _currentPlan = subscriptionDetails['currentPlan'] ?? 'free';
      _isFreeTrial = subscriptionDetails['isFreeTrial'] ?? false;
      
      // 외부에서 전달된 데이터가 있으면 사용, 없으면 서비스에서 직접 가져옴
      if (widget.limitStatus != null && widget.usagePercentages != null) {
        _limitStatus = Map<String, dynamic>.from(widget.limitStatus!);
        
        // 안전한 타입 변환을 위해 각 값을 double로 변환
        _usagePercentages = {};
        widget.usagePercentages!.forEach((key, value) {
          if (value is num) {
            _usagePercentages[key] = value.toDouble();
          } else {
            _usagePercentages[key] = 0.0;
          }
        });
      } else {
        // UsageLimitService에서 최신 데이터를 가져옴
        final usageInfo = await _usageService.getUserUsageForSettings();
        _limitStatus = usageInfo['limitStatus'] as Map<String, dynamic>;
        
        // 안전한 타입 변환을 위해 각 값을 double로 변환
        final percentagesMap = usageInfo['usagePercentages'] as Map<String, dynamic>;
        _usagePercentages = {};
        percentagesMap.forEach((key, value) {
          if (value is num) {
            _usagePercentages[key] = value.toDouble();
          } else {
            _usagePercentages[key] = 0.0;
          }
        });
      }
      
      debugPrint('UsageDialog - 로드된 사용량 데이터: $_usagePercentages');
      debugPrint('UsageDialog - 로드된 제한 상태: $_limitStatus');
      debugPrint('UsageDialog - 현재 플랜: $_currentPlan');
      debugPrint('UsageDialog - 무료 체험 여부: $_isFreeTrial');
    } catch (e) {
      debugPrint('UsageDialog - 사용량 데이터 로드 중 오류: $e');
      // 기본값 설정
      _limitStatus = {
        'ocrLimitReached': false,
        'ttsLimitReached': false,
        'ocrLimit': 10,
        'ttsLimit': 30,
      };
      _usagePercentages = {
        'ocr': 0.0,
        'tts': 0.0,
      };
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 한도 초과 여부 확인
    final bool hasReachedLimit = _hasReachedAnyLimit();
    
    // 상태에 따른 제목과 메시지 설정
    final String effectiveTitle = widget.title ?? (hasReachedLimit 
        ? '학습 한도에 도달했어요.' 
        : '현재까지의 사용량');
        
    final String effectiveMessage = widget.message ?? (hasReachedLimit 
        ? '무료 제공 한도에 도달했어요.\n프리미엄으로 업그레이드하여 더 많은 기능을 이용해보세요!' 
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
      content: _isLoading
          ? SizedBox(
              width: 260, // 고정된 너비
              height: 220, // 로드된 콘텐츠와 비슷한 높이
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
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
        // 플랜 상태에 따른 버튼 표시
        if (widget.onContactSupport != null)
          _buildActionButton(),
          
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
    return _limitStatus['ocrLimitReached'] == true ||
           _limitStatus['ttsLimitReached'] == true;
  }
  
  // 베타 기간 정보를 표시할지 여부
  bool _showBetaPeriodInfo() {
    return _limitStatus.containsKey('remainingDays');
  }
  
  // 베타 기간 정보 위젯
  Widget _buildBetaPeriodInfo() {
    final int remainingDays = _limitStatus['remainingDays'] as int? ?? 0;
    
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
            ? '체험판 기간 잔여: $remainingDays일'
            : '체험판 기간 종료',
        style: TypographyTokens.caption.copyWith(
          color: remainingDays > 0 ? Colors.blue : Colors.red,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
  
  // 사용량 그래프 위젯
  Widget _buildUsageGraph() {
    debugPrint('UsageDialog - 표시할 사용량 데이터: $_usagePercentages');
    debugPrint('UsageDialog - 표시할 제한 상태: $_limitStatus');

    // 단순화된 2가지 주요 사용량만 표시 (ocr, tts)
    final List<MapEntry<String, double>> entries = [
      MapEntry('ocr', _usagePercentages['ocr'] ?? 0.0),
      MapEntry('tts', _usagePercentages['tts'] ?? 0.0),
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
          
          debugPrint('UsageDialog - ${entry.key} 사용량: $percentage%');
          
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
                        color: _getUsageColor(percentage),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                LinearProgressIndicator(
                  value: percentage / 100,
                  backgroundColor: ColorTokens.divider,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _getUsageColor(percentage),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
  
  // 사용량에 따른 색상 반환
  Color _getUsageColor(double percentage) {
    if (percentage > 90) return ColorTokens.error;
    if (percentage > 70) return Colors.orange;
    return ColorTokens.primary;
  }
  
  // 사용량 라벨 변환
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
  
  // 저장 공간 크기 포맷팅 (더 이상 사용하지 않지만 호환성을 위해 유지)
  String _formatStorageSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)}MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)}KB';
    }
    return '${bytes}B';
  }

  /// 플랜 상태에 따른 액션 버튼 빌드
  Widget _buildActionButton() {
    // 프리미엄 플랜이면서 체험판이 아닌 경우에만 "문의하기" 표시
    final bool isPremiumPaid = _currentPlan == PlanService.PLAN_PREMIUM && !_isFreeTrial;
    
    return PikaButton(
      text: isPremiumPaid ? '문의하기' : '프리미엄으로 업그레이드',
      variant: PikaButtonVariant.outline,
      size: PikaButtonSize.small,
      onPressed: () async {
        Navigator.of(context).pop(); // 다이얼로그 먼저 닫기
        
        if (isPremiumPaid) {
          // 유료 프리미엄 플랜 - 프리미엄 사용자용 모달 표시
          if (mounted) {
            UpgradeModal.show(
              context,
              reason: UpgradeReason.premiumUser,
            );
          }
        } else {
          // 무료 플랜 / 체험 플랜 - 프리미엄 모달 열기
          if (mounted) {
            UpgradeModal.show(
              context,
              reason: _isFreeTrial ? UpgradeReason.trialExpired : UpgradeReason.limitReached,
              onUpgrade: () {
                debugPrint('🎯 [UsageDialog] 프리미엄 업그레이드 선택');
                // TODO: 인앱 구매 처리
              },
            );
          }
        }
      },
    );
  }
} 