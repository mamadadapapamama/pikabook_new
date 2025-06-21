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
  trialExpired,     // 체험 만료
  settings,         // 설정에서 업그레이드
  general,          // 일반적인 업그레이드
  premiumUser,      // 이미 프리미엄 사용자
  welcomeTrial,     // 온보딩 후 무료체험
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
      height: 160,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(SpacingTokens.radiusMedium),
          topRight: Radius.circular(SpacingTokens.radiusMedium),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(SpacingTokens.radiusMedium),
          topRight: Radius.circular(SpacingTokens.radiusMedium),
        ),
        child: Image.asset(
          'assets/images/ill_premium.png',
          width: double.infinity,
          height: 160,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  /// 제목
  Widget _buildTitle() {
    String title;
    if (customTitle != null) {
      title = customTitle!;
    } else {
      switch (reason) {
        case UpgradeReason.limitReached:
        case UpgradeReason.trialExpired:
        case UpgradeReason.settings:
        case UpgradeReason.general:
        case UpgradeReason.welcomeTrial:
          title = '피카북 프리미엄';
          break;
        case UpgradeReason.premiumUser:
          title = '추가 기능 문의';
          break;
      }
    }

    return Text(
      title,
      style: TypographyTokens.headline2.copyWith(
        color: ColorTokens.textPrimary,
        fontWeight: FontWeight.bold,
      ),
      textAlign: TextAlign.center,
    );
  }

  /// 메시지
  Widget _buildMessage() {
    if (customMessage != null) {
      return Text(
        customMessage!,
        style: TypographyTokens.body1.copyWith(
          color: ColorTokens.textSecondary,
          height: 1.5,
        ),
        textAlign: TextAlign.center,
      );
    }

    switch (reason) {
      case UpgradeReason.premiumUser:
        return Text(
          '더 많은 기능이 필요하시다면 관리자에게 문의해주세요.',
          style: TypographyTokens.body1.copyWith(
            color: ColorTokens.textSecondary,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        );
      
      case UpgradeReason.limitReached:
      case UpgradeReason.trialExpired:
      case UpgradeReason.settings:
      case UpgradeReason.general:
      case UpgradeReason.welcomeTrial:
      default:
        return Column(
          children: [
            Text(
              '필요한 만큼 충분히 번역하고, 원어민의 발음을 마음껏 들어보세요.',
              style: TypographyTokens.body1.copyWith(
                color: ColorTokens.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: SpacingTokens.lg),
            _buildComparisonTable(),
            SizedBox(height: SpacingTokens.md),
            _buildFootnotes(),
          ],
        );
    }
  }

  /// 비교 테이블
  Widget _buildComparisonTable() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: ColorTokens.divider),
        borderRadius: BorderRadius.circular(SpacingTokens.radiusXs),
      ),
      child: Column(
        children: [
          // 헤더
          Container(
            padding: EdgeInsets.symmetric(
              vertical: SpacingTokens.sm,
              horizontal: SpacingTokens.md,
            ),
            decoration: BoxDecoration(
              color: ColorTokens.primaryverylight,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(SpacingTokens.radiusXs),
                topRight: Radius.circular(SpacingTokens.radiusXs),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    '항목',
                    style: TypographyTokens.caption.copyWith(
                      fontWeight: FontWeight.bold,
                      color: ColorTokens.textPrimary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '무료 플랜',
                    style: TypographyTokens.caption.copyWith(
                      fontWeight: FontWeight.bold,
                      color: ColorTokens.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Text(
                    '프리미엄 플랜',
                    style: TypographyTokens.caption.copyWith(
                      fontWeight: FontWeight.bold,
                      color: ColorTokens.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          // 스마트 노트 작성량
          _buildTableRow(
            '스마트 노트\n작성량*¹',
            '월 10페이지',
            '월 300페이지',
            true,
          ),
          // 듣기 기능 사용량
          _buildTableRow(
            '듣기 기능\n사용량*²',
            '월 30회',
            '월 1,000회',
            false,
          ),
        ],
      ),
    );
  }

  /// 테이블 행
  Widget _buildTableRow(String title, String freeValue, String premiumValue, bool isFirst) {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: SpacingTokens.sm,
        horizontal: SpacingTokens.md,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: isFirst ? BorderSide.none : BorderSide(color: ColorTokens.divider),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              title,
              style: TypographyTokens.caption.copyWith(
                color: ColorTokens.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              freeValue,
              style: TypographyTokens.caption.copyWith(
                color: ColorTokens.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              premiumValue,
              style: TypographyTokens.caption.copyWith(
                color: ColorTokens.primary,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// 각주
  Widget _buildFootnotes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '*¹ 스마트 노트 1페이지에는 원문, 번역, 병음이 포함됩니다',
          style: TypographyTokens.caption.copyWith(
            color: ColorTokens.textTertiary,
            fontSize: 10,
          ),
        ),
        SizedBox(height: 2),
        Text(
          '*² 새로운 문장을 들을 때만 횟수가 차감됩니다',
          style: TypographyTokens.caption.copyWith(
            color: ColorTokens.textTertiary,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  /// 버튼들
  Widget _buildButtons(BuildContext context) {
    // 프리미엄 사용자인 경우 문의하기 버튼만 표시
    if (reason == UpgradeReason.premiumUser) {
      return Column(
        children: [
          PikaButton(
            text: '문의하기',
            onPressed: () async {
              Navigator.of(context).pop(true);
              await launchUrl(Uri.parse('https://forms.gle/YaeznYjGLiMdHmBD9'));
              onUpgrade?.call();
            },
            isFullWidth: true,
            variant: PikaButtonVariant.primary,
          ),
          
          SizedBox(height: SpacingTokens.sm),
          
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(false);
              onCancel?.call();
            },
            child: Text(
              '닫기',
              style: TypographyTokens.button.copyWith(
                color: ColorTokens.textTertiary,
              ),
            ),
          ),
        ],
      );
    }

    // 온보딩 환영 모달의 경우
    if (reason == UpgradeReason.welcomeTrial) {
      return Column(
        children: [
          PikaButton(
            text: upgradeButtonText ?? '프리미엄 무료체험 시작',
            onPressed: () async {
              Navigator.of(context).pop(true);
              // 직접 무료체험 인앱 구매 호출
              try {
                final purchaseService = InAppPurchaseService();
                if (!purchaseService.isAvailable) {
                  await purchaseService.initialize();
                }
                if (kDebugMode) debugPrint('🎯 Starting premium trial with in-app purchase');
                await purchaseService.buyMonthlyTrial();
              } catch (e) {
                if (kDebugMode) debugPrint('❌ Trial purchase error: $e');
              }
              onUpgrade?.call();
            },
            isFullWidth: true,
            variant: PikaButtonVariant.primary,
          ),
          SizedBox(height: SpacingTokens.sm),
          TextButton(
            onPressed: () async {
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
            child: Text(
              cancelButtonText ?? '무료 플랜으로 시작',
              style: TypographyTokens.button.copyWith(
                color: ColorTokens.textTertiary,
              ),
            ),
          ),
        ],
      );
    }

    // 일반 사용자인 경우 구독 옵션 표시
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
            if (kDebugMode) {
              debugPrint('🚪 [UpgradeModal] 나가기 버튼 클릭');
              debugPrint('📍 [UpgradeModal] 현재 라우트: ${ModalRoute.of(context)?.settings.name}');
            }
            
            // 모달 닫기
            Navigator.of(context).pop(false);
            
            // onCancel 콜백 호출 (모달이 닫힌 후)
            if (onCancel != null) {
              if (kDebugMode) {
                debugPrint('🔄 [UpgradeModal] onCancel 콜백 호출');
              }
              onCancel!();
            }
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
  /// 온보딩 완료 후 환영 모달 표시
  static Future<void> showWelcomeTrialPrompt(
    BuildContext context, {
    required VoidCallback onComplete,
  }) async {
    try {
      await UpgradeModal.show(
        context,
        reason: UpgradeReason.welcomeTrial,
        customTitle: 'Pikabook에 오신 것을 환영합니다! 🎉',
        customMessage: '7일 무료 체험으로 모든 프리미엄 기능을 경험해보세요.\n\n• 월 300페이지 OCR 인식\n• 월 10만자 번역\n• 월 1,000회 TTS 음성\n• 1GB 저장 공간',
        // onUpgrade는 버튼 내에서 직접 처리
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint(' welcoming modal display error: $e');
      }
    } finally {
      onComplete();
    }
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