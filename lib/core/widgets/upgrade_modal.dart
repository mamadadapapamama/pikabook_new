import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import 'pika_button.dart';

/// 프리미엄 구독 업그레이드 유도 모달
class UpgradeModal extends StatelessWidget {
  final VoidCallback? onUpgrade;
  final VoidCallback? onCancel;
  final String? customMessage;

  const UpgradeModal({
    Key? key,
    this.onUpgrade,
    this.onCancel,
    this.customMessage,
  }) : super(key: key);

  /// 모달 표시 헬퍼 메서드
  static Future<bool?> show(
    BuildContext context, {
    VoidCallback? onUpgrade,
    VoidCallback? onCancel,
    String? customMessage,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false, // 배경 터치로 닫기 방지
      builder: (context) => UpgradeModal(
        onUpgrade: onUpgrade,
        onCancel: onCancel ?? () => Navigator.of(context).pop(false),
        customMessage: customMessage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: ColorTokens.surface,
          borderRadius: BorderRadius.circular(SpacingTokens.radiusMedium),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 상단 이미지 영역
            _buildHeaderImage(),
            
            // 콘텐츠 영역
            Padding(
              padding: EdgeInsets.all(SpacingTokens.lg),
              child: Column(
                children: [
                  // 제목
                  _buildTitle(),
                  SizedBox(height: SpacingTokens.md),
                  
                  // 메시지
                  _buildMessage(),
                  SizedBox(height: SpacingTokens.xl),
                  
                  // 버튼들
                  _buildButtons(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 상단 이미지 영역
  Widget _buildHeaderImage() {
    return Container(
      width: double.infinity,
      height: 120,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ColorTokens.primary.withOpacity(0.1),
            ColorTokens.secondary.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(SpacingTokens.radiusMedium),
          topRight: Radius.circular(SpacingTokens.radiusMedium),
        ),
      ),
      child: Center(
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: ColorTokens.primary,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.star,
            color: ColorTokens.textLight,
            size: 30,
          ),
        ),
      ),
    );
  }

  /// 제목
  Widget _buildTitle() {
    return Text(
      '프리미엄 구독이 필요합니다!',
      style: TypographyTokens.headline2.copyWith(
        color: ColorTokens.textPrimary,
        fontWeight: FontWeight.bold,
      ),
      textAlign: TextAlign.center,
    );
  }

  /// 메시지
  Widget _buildMessage() {
    final message = customMessage ?? 
        '무료체험 7일이 끝났어요.\n월 \$9.99에 프리미엄 기능을 사용해보세요.';
    
    return Text(
      message,
      style: TypographyTokens.body1.copyWith(
        color: ColorTokens.textSecondary,
        height: 1.5,
      ),
      textAlign: TextAlign.center,
    );
  }

  /// 버튼들
  Widget _buildButtons(BuildContext context) {
    return Column(
      children: [
        // 업그레이드 버튼
        PikaButton(
          text: '프리미엄 구독하기',
          onPressed: () {
            Navigator.of(context).pop(true);
            onUpgrade?.call();
          },
          isFullWidth: true,
          variant: PikaButtonVariant.primary,
        ),
        
        SizedBox(height: SpacingTokens.sm),
        
        // 취소 버튼
        TextButton(
          onPressed: () {
            if (kDebugMode) {
              debugPrint('🚪 [UpgradeModal] 나가기 버튼 클릭');
              debugPrint('📍 [UpgradeModal] 현재 라우트: ${ModalRoute.of(context)?.settings.name}');
            }
            
            // onCancel이 있는 경우에만 호출
            if (onCancel != null) {
              onCancel!();
            }
            
            if (kDebugMode) {
              debugPrint('🔙 [UpgradeModal] Navigator.pop 호출 (모달만 닫기)');
            }
            Navigator.of(context).pop(false);
          },
          child: Text(
            '나가기',
            style: TypographyTokens.button.copyWith(
              color: ColorTokens.textTertiary,
            ),
          ),
        ),
      ],
    );
  }
}

/// 업그레이드 유도 관련 유틸리티 클래스
class UpgradePromptHelper {
  /// TTS 기능 제한 시 표시할 모달
  static Future<bool?> showTtsUpgradePrompt(
    BuildContext context, {
    VoidCallback? onCancel,
  }) {
    return UpgradeModal.show(
      context,
      customMessage: 'TTS 기능은 프리미엄 전용입니다.\n월 \$9.99에 모든 기능을 사용해보세요.',
      onUpgrade: () => _handleUpgrade(context),
      onCancel: null,
    );
  }

  /// 체험 만료 시 표시할 모달
  static Future<bool?> showTrialExpiredPrompt(
    BuildContext context, {
    VoidCallback? onCancel,
  }) {
    return UpgradeModal.show(
      context,
      onUpgrade: () => _handleUpgrade(context),
      onCancel: null,
    );
  }

  /// 업그레이드 처리 (Apple App Store 연동)
  static void _handleUpgrade(BuildContext context) {
    // TODO: Apple App Store 인앱 구매 연동
    // 현재는 스낵바로 대체
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('곧 Apple App Store 결제 화면으로 이동합니다.'),
        backgroundColor: ColorTokens.primary,
      ),
    );
  }
} 