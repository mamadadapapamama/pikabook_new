import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/trial/trial_manager.dart';
import '../theme/tokens/color_tokens.dart';

/// 무료체험 상태 표시 위젯
class TrialStatusWidget extends StatelessWidget {
  final bool showProgress;
  final bool showSubscribeButton;
  
  const TrialStatusWidget({
    super.key,
    this.showProgress = false,
    this.showSubscribeButton = true,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<TrialManager>(
      builder: (context, trialManager, child) {
        // 프리미엄 사용자는 표시하지 않음
        if (trialManager.isPremiumUser && !trialManager.isSampleMode) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _getBackgroundColor(trialManager),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _getBorderColor(trialManager),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 상태 텍스트
              Row(
                children: [
                  Icon(
                    _getStatusIcon(trialManager),
                    color: _getIconColor(trialManager),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      trialManager.trialStatusText,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _getTextColor(trialManager),
                      ),
                    ),
                  ),
                  if (trialManager.isTrialActive && trialManager.remainingDays > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getAccentColor(trialManager),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${trialManager.remainingDays}일',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              
              // 진행률 바 (옵션)
              if (showProgress && trialManager.isTrialActive) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: trialManager.trialProgress,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _getAccentColor(trialManager),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(trialManager.trialProgress * 100).toStringAsFixed(0)}% 진행',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
              
              // 구독 버튼 (옵션)
              if (showSubscribeButton && 
                  (trialManager.isTrialExpired || 
                   trialManager.remainingDays <= 2 ||
                   trialManager.isSampleMode)) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _onSubscribePressed(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _getAccentColor(trialManager),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(
                      _getButtonText(trialManager),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Color _getBackgroundColor(TrialManager trialManager) {
    if (trialManager.isSampleMode) {
      return Colors.blue.shade50;
    }
    if (trialManager.isTrialExpired) {
      return Colors.red.shade50;
    }
    if (trialManager.remainingDays <= 2) {
      return Colors.orange.shade50;
    }
    return Colors.green.shade50;
  }

  Color _getBorderColor(TrialManager trialManager) {
    if (trialManager.isSampleMode) {
      return Colors.blue.shade200;
    }
    if (trialManager.isTrialExpired) {
      return Colors.red.shade200;
    }
    if (trialManager.remainingDays <= 2) {
      return Colors.orange.shade200;
    }
    return Colors.green.shade200;
  }

  Color _getTextColor(TrialManager trialManager) {
    if (trialManager.isSampleMode) {
      return Colors.blue.shade800;
    }
    if (trialManager.isTrialExpired) {
      return Colors.red.shade800;
    }
    if (trialManager.remainingDays <= 2) {
      return Colors.orange.shade800;
    }
    return Colors.green.shade800;
  }

  Color _getIconColor(TrialManager trialManager) {
    return _getTextColor(trialManager);
  }

  Color _getAccentColor(TrialManager trialManager) {
    if (trialManager.isSampleMode) {
      return Colors.blue;
    }
    if (trialManager.isTrialExpired) {
      return Colors.red;
    }
    if (trialManager.remainingDays <= 2) {
      return Colors.orange;
    }
    return Colors.green;
  }

  IconData _getStatusIcon(TrialManager trialManager) {
    if (trialManager.isSampleMode) {
      return Icons.preview;
    }
    if (trialManager.isTrialExpired) {
      return Icons.access_time_filled;
    }
    if (trialManager.remainingDays <= 2) {
      return Icons.warning;
    }
    return Icons.check_circle;
  }

  String _getButtonText(TrialManager trialManager) {
    if (trialManager.isSampleMode) {
      return '로그인하고 무료체험 시작하기';
    }
    if (trialManager.isTrialExpired) {
      return '프리미엄 구독하기';
    }
    return '프리미엄 구독하기';
  }

  void _onSubscribePressed(BuildContext context) {
    // TODO: 구독 화면으로 이동 또는 로그인 화면으로 이동
    final trialManager = context.read<TrialManager>();
    
    if (trialManager.isSampleMode) {
      // 로그인 화면으로 이동
      _navigateToLogin(context);
    } else {
      // 구독 화면으로 이동
      _navigateToSubscription(context);
    }
  }

  void _navigateToLogin(BuildContext context) {
    // TODO: 로그인 화면 네비게이션 구현
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('로그인 화면으로 이동'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _navigateToSubscription(BuildContext context) {
    // TODO: 구독 화면 네비게이션 구현
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('구독 화면으로 이동'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

/// 간단한 체험 상태 배지 위젯
class TrialStatusBadge extends StatelessWidget {
  const TrialStatusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TrialManager>(
      builder: (context, trialManager, child) {
        if (trialManager.isPremiumUser && !trialManager.isSampleMode) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _getBadgeColor(trialManager),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _getBadgeText(trialManager),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        );
      },
    );
  }

  Color _getBadgeColor(TrialManager trialManager) {
    if (trialManager.isSampleMode) return Colors.blue;
    if (trialManager.isTrialExpired) return Colors.red;
    if (trialManager.remainingDays <= 2) return Colors.orange;
    return Colors.green;
  }

  String _getBadgeText(TrialManager trialManager) {
    if (trialManager.isSampleMode) return '샘플';
    if (trialManager.isTrialExpired) return '만료';
    return '체험 ${trialManager.remainingDays}일';
  }
} 