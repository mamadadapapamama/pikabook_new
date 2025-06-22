import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import '../services/payment/in_app_purchase_service.dart';
import '../services/common/plan_service.dart';
import 'pika_button.dart';
import 'package:url_launcher/url_launcher.dart';

/// 업그레이드 모달의 표시 상황
enum UpgradeReason {
  limitReached,     // 한도 도달
  trialExpired,     // 무료 체험 만료 (온보딩 후 무료체험 포함)
  freeTrialActive,  // 무료체험 중 (바로 구독 유도)
  settings,         // 설정에서 업그레이드
  general,          // 일반적인 업그레이드
  premiumUser,      // 이미 프리미엄 사용자
  welcomeTrial,     // 온보딩 후 환영 모달 (7일 무료체험 유도)
}

/// 프리미엄 업그레이드 모달
class UpgradeModal extends StatelessWidget {
  final String? customTitle;
  final String? customMessage;
  final String? upgradeButtonText;
  final String? cancelButtonText;
  final VoidCallback? onUpgrade;
  final VoidCallback? onCancel;
  final UpgradeReason reason;

  const UpgradeModal({
    Key? key,
    this.customTitle,
    this.customMessage,
    this.upgradeButtonText,
    this.cancelButtonText,
    this.onUpgrade,
    this.onCancel,
    this.reason = UpgradeReason.general,
  }) : super(key: key);

  /// 모달 표시 정적 메서드
  static Future<bool?> show(
    BuildContext context, {
    String? customTitle,
    String? customMessage,
    String? upgradeButtonText,
    String? cancelButtonText,
    VoidCallback? onUpgrade,
    VoidCallback? onCancel,
    UpgradeReason reason = UpgradeReason.general,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return UpgradeModal(
          customTitle: customTitle,
          customMessage: customMessage,
          upgradeButtonText: upgradeButtonText,
          cancelButtonText: cancelButtonText,
          onUpgrade: onUpgrade,
          onCancel: onCancel,
          reason: reason,
        );
      },
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
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
            // 상단 캐릭터 일러스트 영역
            _buildCharacterHeader(),
            
            // 콘텐츠 영역
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // 메인 메시지
                  _buildMainMessage(),
                  const SizedBox(height: 24),
                  
                  // 기능 리스트
                  _buildFeatureList(),
                  const SizedBox(height: 32),
                  
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

  /// 상단 캐릭터 일러스트 영역
  Widget _buildCharacterHeader() {
    return Container(
      width: double.infinity,
      height: 240,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        child: Image.asset(
          'assets/images/ill_premium.png',
          width: double.infinity,
          height: 240,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              height: 240,
              color: Colors.grey.shade200,
              child: const Icon(
                Icons.image_not_supported,
                size: 48,
                color: Colors.grey,
              ),
            );
          },
        ),
      ),
    );
  }
  
  /// 메인 메시지
  Widget _buildMainMessage() {
    return const Text(
      '월 \$3.99로, Pikabook을\n마음껏 사용해 보세요!',
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Colors.black,
        height: 1.3,
      ),
      textAlign: TextAlign.center,
    );
  }

  /// 기능 리스트
  Widget _buildFeatureList() {
    return Column(
      children: [
        _buildFeatureItem(
          '📱',
          '이미지를 스마트 노트로(번역, 병음 제공)',
          '무료 플랜: 월 10장 → **프리미엄: 월 300장**',
        ),
        const SizedBox(height: 16),
        _buildFeatureItem(
          '🔊',
          '원어민 발음 듣기',
          '무료 플랜: 월 100회 → **프리미엄: 월 1000회**',
        ),
        const SizedBox(height: 16),
        _buildFeatureItem(
          '📚',
          '플래시카드 단어 복습',
          '무료 플랜: 듣기 제한 → **프리미엄: 월 1000회**',
        ),
      ],
    );
  }

  /// 개별 기능 아이템
  Widget _buildFeatureItem(String emoji, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.only(right: 12),
          child: Text(
            emoji,
            style: const TextStyle(fontSize: 18),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 2),
              _buildRichDescription(description),
            ],
          ),
        ),
      ],
    );
  }

  /// 인라인 스타일링으로 프리미엄 정보 강조
  Widget _buildRichDescription(String description) {
    // ** 마크다운 스타일 볼드 처리
    final boldPattern = RegExp(r'\*\*(.*?)\*\*');
    final matches = boldPattern.allMatches(description);
    
    if (matches.isEmpty) {
      // 볼드 처리할 텍스트가 없는 경우
      return Text(
        description,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.black,
          height: 1.2,
        ),
      );
    }

    // 볼드 처리가 있는 경우 RichText로 처리
    List<TextSpan> spans = [];
    int lastEnd = 0;
    
    for (final match in matches) {
      // 볼드 이전 텍스트 추가
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: description.substring(lastEnd, match.start),
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black,
            height: 1.2,
          ),
        ));
      }
      
      // 볼드 텍스트 추가
      spans.add(TextSpan(
        text: match.group(1), // ** 안의 텍스트만
        style: const TextStyle(
          fontSize: 12,
          color: Colors.black,
          height: 1.2,
          fontWeight: FontWeight.bold,
        ),
      ));
      
      lastEnd = match.end;
    }
    
    // 마지막 남은 텍스트 추가
    if (lastEnd < description.length) {
      spans.add(TextSpan(
        text: description.substring(lastEnd),
        style: const TextStyle(
          fontSize: 12,
          color: Colors.black,
          height: 1.2,
        ),
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
    );
  }

  /// 버튼들
  Widget _buildButtons(BuildContext context) {
    // 프리미엄 사용자인 경우 문의하기 버튼만 표시
    if (reason == UpgradeReason.premiumUser) {
      return Column(
        children: [
          _buildPrimaryButton(
            '더 많은 기능이 필요해요',
            '',
            () async {
              Navigator.of(context).pop(true);
              await launchUrl(Uri.parse('https://forms.gle/YaeznYjGLiMdHmBD9'));
              onUpgrade?.call();
            },
          ),
          
          const SizedBox(height: 16),
          
          _buildTextButton(
            '닫기',
            () {
              Navigator.of(context).pop(false);
              onCancel?.call();
            },
          ),
        ],
      );
    }

    // 온보딩 후 환영 모달 (7일 무료체험 유도)
    if (reason == UpgradeReason.welcomeTrial) {
      return Column(
        children: [
          // 주황색 CTA 버튼 - 7일 무료체험
          _buildPrimaryButton(
            '프리미엄 무료체험 시작하기',
            '(월 \$3.99, 7일간 무료)',
            () async {
              Navigator.of(context).pop(true);
              try {
                final purchaseService = InAppPurchaseService();
                if (!purchaseService.isAvailable) {
                  await purchaseService.initialize();
                }
                if (kDebugMode) debugPrint('🎯 Starting monthly subscription with trial');
                await _handlePurchase(context, InAppPurchaseService.premiumMonthlyId);
              } catch (e) {
                if (kDebugMode) debugPrint('❌ Trial subscription error: $e');
              }
              onUpgrade?.call();
            },

          ),
          
          const SizedBox(height: 16),
          
          // 하단 링크 - 무료 플랜
          _buildTextButton(
            '무료 플랜으로 시작하기',
            () async {
              Navigator.of(context).pop(false);
              // 간단한 무료체험 시작
              try {
                final planService = PlanService();
                final user = FirebaseAuth.instance.currentUser;
                if (user != null) {
                  await planService.startFreeTrial(user.uid);
                }
              } catch (e) {
                if (kDebugMode) debugPrint('❌ Simple trial error: $e');
              }
              onCancel?.call();
            },
          ),
        ],
      );
    }

    // 프리미엄 무료체험 중 (바로 구독 유도)
    if (reason == UpgradeReason.freeTrialActive) {
      return Column(
        children: [
          // 연간 구독 버튼 (할인 강조)
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: ColorTokens.primary, width: 2),
              borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
            ),
            child: Column(
              children: [
                // 할인 배지
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: ColorTokens.primary,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(SpacingTokens.radiusSmall - 2),
                      topRight: Radius.circular(SpacingTokens.radiusSmall - 2),
                    ),
                  ),
                  child: Text(
                    '27% 할인',
                    style: TypographyTokens.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                // 연간 구독 버튼
                Padding(
                  padding: EdgeInsets.all(SpacingTokens.sm),
                  child: PikaButton(
                    text: '연간 구독 \$34.99 USD',
                    onPressed: () async {
                      Navigator.of(context).pop(true);
                      await _handlePurchase(context, InAppPurchaseService.premiumYearlyId);
                      onUpgrade?.call();
                    },
                    isFullWidth: true,
                    variant: PikaButtonVariant.primary,
                  ),
                ),
              ],
            ),
          ),
          
          SizedBox(height: SpacingTokens.md),
          
          // 월간 구독 버튼
          PikaButton(
            text: '월간 구독 \$3.99 USD',
            onPressed: () async {
              Navigator.of(context).pop(true);
              await _handlePurchase(context, InAppPurchaseService.premiumMonthlyId);
              onUpgrade?.call();
            },
            isFullWidth: true,
            variant: PikaButtonVariant.outline,
          ),
          
          SizedBox(height: SpacingTokens.sm),
          
          // 취소 버튼
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(false);
              onCancel?.call();
            },
            child: Text(
              '나중에',
              style: TypographyTokens.button.copyWith(
                color: ColorTokens.textTertiary,
              ),
            ),
          ),
        ],
      );
    }

    // 일반 사용자인 경우 구독 옵션 표시 (기존 디자인)
    return Column(
      children: [
        // 연간 구독 버튼 (할인 강조)
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: ColorTokens.primary, width: 2),
            borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
          ),
          child: Column(
            children: [
              // 할인 배지
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: ColorTokens.primary,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(SpacingTokens.radiusSmall - 2),
                    topRight: Radius.circular(SpacingTokens.radiusSmall - 2),
                  ),
                ),
                child: Text(
                  '27% 할인',
                  style: TypographyTokens.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              // 연간 구독 버튼
              Padding(
                padding: EdgeInsets.all(SpacingTokens.sm),
                child: PikaButton(
                  text: '연간 구독 \$34.99 USD',
                  onPressed: () async {
                    Navigator.of(context).pop(true);
                    await _handlePurchase(context, InAppPurchaseService.premiumYearlyId);
                    onUpgrade?.call();
                  },
                  isFullWidth: true,
                  variant: PikaButtonVariant.primary,
                ),
              ),
            ],
          ),
        ),
        
        SizedBox(height: SpacingTokens.md),
        
        // 월간 구독 버튼
        PikaButton(
          text: '월간 구독 \$3.99 USD',
          onPressed: () async {
            Navigator.of(context).pop(true);
            await _handlePurchase(context, InAppPurchaseService.premiumMonthlyId);
            onUpgrade?.call();
          },
          isFullWidth: true,
          variant: PikaButtonVariant.outline,
        ),
        
        SizedBox(height: SpacingTokens.sm),
        
        // 취소 버튼
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(false);
            onCancel?.call();
          },
          child: Text(
            cancelButtonText ?? '나가기',
            style: TypographyTokens.button.copyWith(
              color: ColorTokens.textTertiary,
            ),
          ),
        ),
      ],
    );
  }

  /// 주요 버튼 (주황색)
  Widget _buildPrimaryButton(String mainText, String subText, VoidCallback onPressed) {
    return Container(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF6B35),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              mainText,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (subText.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subText,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.normal,
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 텍스트 버튼
  Widget _buildTextButton(String text, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          color: Color(0xFF666666),
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  /// 인앱 구매 처리
  static Future<void> _handlePurchase(BuildContext context, String productId) async {
    try {
      if (kDebugMode) {
        debugPrint('🎯 [UpgradeModal] 인앱 구매 시작: $productId');
      }

      final purchaseService = InAppPurchaseService();
      
      // 인앱 구매 서비스가 초기화되지 않았으면 초기화
      if (!purchaseService.isAvailable) {
        await purchaseService.initialize();
      }

      // 구매 시작
      final success = await purchaseService.buyProduct(productId);
      
      if (success) {
        if (kDebugMode) {
          debugPrint('✅ [UpgradeModal] 구매 요청 성공');
        }
      } else {
        if (kDebugMode) {
          debugPrint('❌ [UpgradeModal] 구매 요청 실패');
        }
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('구매 요청 중 오류가 발생했습니다. 다시 시도해주세요.'),
              backgroundColor: Colors.red[600],
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UpgradeModal] 구매 처리 중 오류: $e');
      }
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('구매 처리 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red[600],
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

/// 업그레이드 유도 관련 유틸리티 클래스
class UpgradePromptHelper {
  /// 온보딩 완료 후 환영 모달 표시 (7일 무료체험 유도)
  static Future<void> showWelcomeTrialPrompt(
    BuildContext context, {
    required VoidCallback onComplete,
  }) async {
    try {
      await UpgradeModal.show(
        context,
        reason: UpgradeReason.welcomeTrial,
        // onUpgrade는 버튼 내에서 직접 처리  
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('welcoming modal display error: $e');
      }
    } finally {
      onComplete();
    }
  }

  /// 프리미엄 무료체험 중 업그레이드 모달 표시 (바로 구독 유도)
  static Future<bool?> showFreeTrialUpgradePrompt(
    BuildContext context, {
    VoidCallback? onCancel,
  }) {
    return UpgradeModal.show(
      context,
      reason: UpgradeReason.freeTrialActive,
      onUpgrade: () => _handleUpgrade(context),
      onCancel: onCancel,
    );
  }

  /// TTS 기능 제한 시 표시할 모달
  static Future<bool?> showTtsUpgradePrompt(
    BuildContext context, {
    VoidCallback? onCancel,
  }) {
    return UpgradeModal.show(
      context,
      reason: UpgradeReason.limitReached,
      onUpgrade: () => _handleUpgrade(context),
      onCancel: onCancel,
    );
  }

  /// 체험 만료 시 표시할 모달
  static Future<bool?> showTrialExpiredPrompt(
    BuildContext context, {
    VoidCallback? onCancel,
  }) {
    return UpgradeModal.show(
      context,
      reason: UpgradeReason.trialExpired,
      onUpgrade: () => _handleUpgrade(context),
      onCancel: onCancel,
    );
  }

  /// 업그레이드 처리 (인앱 구매 연동)
  static void _handleUpgrade(BuildContext context) {
    // 기본적으로 월간 구독으로 연결
    UpgradeModal._handlePurchase(context, InAppPurchaseService.premiumMonthlyId);
  }
}