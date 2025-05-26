import 'package:flutter/material.dart';
import '../../../core/theme/tokens/color_tokens.dart';
import '../../../core/theme/tokens/typography_tokens.dart';
import '../../../core/theme/tokens/spacing_tokens.dart';
import 'pika_button.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/common/usage_limit_service.dart';

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
  Map<String, dynamic> _limitStatus = {};
  Map<String, double> _usagePercentages = {};
  bool _isLoading = true;

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
      // 외부에서 전달된 데이터가 있으면 사용, 없으면 서비스에서 직접 가져옴
      if (widget.limitStatus != null && widget.usagePercentages != null) {
        _limitStatus = Map<String, dynamic>.from(widget.limitStatus!);
        _usagePercentages = Map<String, double>.from(widget.usagePercentages!);
      } else {
        // UsageLimitService에서 최신 데이터를 가져옴
        final usageInfo = await _usageService.getUsageInfo();
        _limitStatus = usageInfo['limitStatus'];
        _usagePercentages = Map<String, double>.from(usageInfo['percentages'] as Map);
      }
      
      debugPrint('UsageDialog - 로드된 사용량 데이터: $_usagePercentages');
      debugPrint('UsageDialog - 로드된 제한 상태: $_limitStatus');
    } catch (e) {
      debugPrint('UsageDialog - 사용량 데이터 로드 중 오류: $e');
      // 기본값 설정
      _limitStatus = {
        'ocrLimitReached': false,
        'ttsLimitReached': false,
        'translationLimitReached': false,
        'storageLimitReached': false,
        'ocrLimit': 30,
        'ttsLimit': 100,
        'translationLimit': 3000,
        'storageLimit': 104857600, // 100MB
      };
      _usagePercentages = {
        'ocr': 0.0,
        'tts': 0.0,
        'translation': 0.0,
        'storage': 0.0,
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
        ? '사용량 제한에 도달했습니다' 
        : '현재까지의 사용량');
        
    final String effectiveMessage = widget.message ?? (hasReachedLimit 
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
    
    
        // 1:1 문의하기 버튼
        if (widget.onContactSupport != null)
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
    return _limitStatus['ocrLimitReached'] == true ||
           _limitStatus['ttsLimitReached'] == true ||
           _limitStatus['translationLimitReached'] == true ||
           _limitStatus['storageLimitReached'] == true ||
           _limitStatus['betaEnded'] == true;
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

    // 항상 4가지 주요 사용량을 표시 (ocr, tts, translation, storage)
    final List<MapEntry<String, double>> entries = [
      MapEntry('ocr', _usagePercentages['ocr'] ?? 0.0),
      MapEntry('tts', _usagePercentages['tts'] ?? 0.0),
      MapEntry('translation', _usagePercentages['translation'] ?? 0.0),
      MapEntry('storage', _usagePercentages['storage'] ?? 0.0),
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
        return '글자 추출 (${_limitStatus['ocrLimit'] ?? 30}장)';
      case 'tts':
        return '음성 읽기 (${_limitStatus['ttsLimit'] ?? 100}회)';
      case 'translation':
        return '번역 (${_limitStatus['translationLimit'] ?? 3000}자)';
      case 'storage':
        return '저장 공간 (${_formatStorageSize(_limitStatus['storageLimit'] ?? 104857600)})';
      default:
        return key;
    }
  }
  
  // 저장 공간 크기 포맷팅
  String _formatStorageSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)}MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)}KB';
    }
    return '${bytes}B';
  }
} 