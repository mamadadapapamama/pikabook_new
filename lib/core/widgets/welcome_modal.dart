import 'package:flutter/material.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import 'pika_button.dart';

/// 신규 가입 유저를 위한 환영 모달
class WelcomeModal extends StatelessWidget {
  final VoidCallback onClose;

  const WelcomeModal({
    Key? key,
    required this.onClose,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: SpacingTokens.lg),
        padding: const EdgeInsets.all(SpacingTokens.xl),
        decoration: BoxDecoration(
          color: ColorTokens.surface,
          borderRadius: BorderRadius.circular(16),
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
            // 제목
            Text(
              '💪 중국어 교재 학습,\n피카북이 도와드릴게요!',
              style: TypographyTokens.headline3.copyWith(
                fontWeight: FontWeight.w700,
                color: ColorTokens.textPrimary,
                height: 1.3,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: SpacingTokens.xl),
            
            // 본문
            Text(
              '교재 사진을 업로드하면\n번역·병음은 최대 30페이지,\n원어민 발음은 50회까지 무료로 제공됩니다.',
              style: TypographyTokens.body1.copyWith(
                color: ColorTokens.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: SpacingTokens.xl),
            
            // 확인 버튼
            SizedBox(
              width: double.infinity,
              child: PikaButton(
                text: '시작하기',
                onPressed: onClose,
                isFullWidth: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 환영 모달 표시
  static Future<void> show(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => WelcomeModal(
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }
} 