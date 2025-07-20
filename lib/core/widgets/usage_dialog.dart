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
import '../../../core/services/subscription/unified_subscription_manager.dart';

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
        future: _getUsageData(),
        builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              width: 280,
              height: 200,
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
          final limits = snapshot.data?['limits'] as Map<String, dynamic>? ?? {};
          final usagePercentages = snapshot.data?['usagePercentages'] as Map<String, double>? ?? {};

          return SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (effectiveMessage.isNotEmpty) ...[
                  Text(effectiveMessage, style: TypographyTokens.body2),
                  SizedBox(height: SpacingTokens.md),
                ],
                
                // 📱 이미지 노트 변환 그래프
                _buildUsageGraph(
                  '📖',
                  '이미지 변환',
                  usage['ocrPages'] ?? 0,
                  limits['ocrPages'] ?? 0,
                  usagePercentages['ocr'] ?? 0.0,
                ),
                
                const SizedBox(height: 20),
                
                // 🔊 원어민 발음 듣기 그래프 (통합)
                _buildUsageGraph(
                  '🔊',
                  '원어민 발음 듣기',
                  usage['ttsRequests'] ?? 0,
                  limits['ttsRequests'] ?? 0,
                  usagePercentages['tts'] ?? 0.0,
                ),
              ],
            ),
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
  
  /// 구독 상태를 가져와서 사용량 데이터 조회
  Future<Map<String, dynamic>> _getUsageData() async {
    try {
      final subscriptionState = await UnifiedSubscriptionManager().getSubscriptionState();
      return await UsageLimitService().getUserUsageForSettings(
        subscriptionState: subscriptionState,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ UsageDialog: 사용량 데이터 로드 실패: $e');
      }
      rethrow;
    }
  }
  
  /// 사용량 그래프 위젯 생성
  Widget _buildUsageGraph(String icon, String title, int current, int limit, double percentage) {
    // 퍼센티지를 0-100 범위로 제한
    final clampedPercentage = percentage.clamp(0.0, 100.0);
    final progressValue = clampedPercentage / 100.0;
    
    // 색상 결정 (80% 이상이면 주황색, 100%면 빨간색)
    Color progressColor;
    if (clampedPercentage >= 100.0) {
      progressColor = Colors.red;
    } else if (clampedPercentage >= 80.0) {
      progressColor = Colors.orange;
    } else {
      progressColor = ColorTokens.primary;
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 제목과 아이콘
        Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TypographyTokens.body1.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 8),
        
        // 진행률 바
        Container(
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: Colors.grey[200],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressValue,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
        ),
        
        const SizedBox(height: 6),
        
        // 사용량 텍스트
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$current / $limit',
              style: TypographyTokens.caption.copyWith(
                color: ColorTokens.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${clampedPercentage.toInt()}%',
              style: TypographyTokens.caption.copyWith(
                color: progressColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
} 