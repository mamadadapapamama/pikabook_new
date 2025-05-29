import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../core/services/payment/in_app_purchase_service.dart';
import '../../core/services/common/plan_service.dart';
import '../../core/theme/tokens/color_tokens.dart';
import '../../core/theme/tokens/typography_tokens.dart';
import '../../core/theme/tokens/spacing_tokens.dart';
import '../../core/widgets/pika_button.dart';
import '../../core/widgets/pika_app_bar.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({Key? key}) : super(key: key);

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final InAppPurchaseService _purchaseService = InAppPurchaseService();
  final PlanService _planService = PlanService();
  
  bool _isLoading = true;
  bool _isPurchasing = false;
  String? _selectedPlan;
  
  @override
  void initState() {
    super.initState();
    _initializePurchaseService();
  }

  Future<void> _initializePurchaseService() async {
    try {
      await _purchaseService.initialize();
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (kDebugMode) {
        print('❌ 구독 화면 초기화 오류: $e');
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorTokens.background,
      appBar: PikaAppBar.settings(
        onBackPressed: () => Navigator.of(context).pop(),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildSubscriptionContent(),
    );
  }

  Widget _buildSubscriptionContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          
          // 제목
          Text(
            'Pikabook Premium',
            style: TypographyTokens.headline2.copyWith(
              color: ColorTokens.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          
          const SizedBox(height: 8),
          
          Text(
            '원서 학습의 모든 기능을 무제한으로 이용하세요',
            style: TypographyTokens.body1.copyWith(
              color: ColorTokens.textSecondary,
            ),
          ),
          
          const SizedBox(height: 32),
          
          // 프리미엄 혜택
          _buildPremiumBenefits(),
          
          const SizedBox(height: 32),
          
          // 구독 플랜
          _buildSubscriptionPlans(),
          
          const SizedBox(height: 32),
          
          // 구매 버튼
          _buildPurchaseButton(),
          
          const SizedBox(height: 16),
          
          // 복원 버튼
          _buildRestoreButton(),
          
          const SizedBox(height: 32),
          
          // 약관 및 정책
          _buildTermsAndPolicy(),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildPremiumBenefits() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(SpacingTokens.lg),
      decoration: BoxDecoration(
        color: ColorTokens.primaryverylight,
        borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
        border: Border.all(
          color: ColorTokens.primarylight,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.star,
                color: ColorTokens.primary,
                size: 24,
              ),
              SizedBox(width: SpacingTokens.xs),
              Text(
                'Premium 혜택',
                style: TypographyTokens.subtitle1.copyWith(
                  color: ColorTokens.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: SpacingTokens.md),
          _buildBenefitItem('월 300페이지 OCR 인식', '무료: 30페이지'),
          _buildBenefitItem('월 10만자 번역', '무료: 1만자'),
          _buildBenefitItem('월 1,000회 TTS 음성', '무료: 0회'),
          _buildBenefitItem('1GB 저장 공간', '무료: 50MB'),
          _buildBenefitItem('광고 없는 환경', ''),
          _buildBenefitItem('우선 고객 지원', ''),
        ],
      ),
    );
  }

  Widget _buildBenefitItem(String title, String comparison) {
    return Padding(
      padding: EdgeInsets.only(bottom: SpacingTokens.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle,
            color: ColorTokens.success,
            size: 18,
          ),
          SizedBox(width: SpacingTokens.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TypographyTokens.body2.copyWith(
                    color: ColorTokens.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (comparison.isNotEmpty)
                  Text(
                    comparison,
                    style: TypographyTokens.caption.copyWith(
                      color: ColorTokens.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionPlans() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '구독 플랜 선택',
          style: TypographyTokens.subtitle1.copyWith(
            color: ColorTokens.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: SpacingTokens.md),
        
        // 월간 구독
        if (_purchaseService.monthlyProduct != null)
          _buildPlanOption(
            _purchaseService.monthlyProduct!,
            InAppPurchaseService.premiumMonthlyId,
            '가장 인기',
            false,
          ),
        
        SizedBox(height: SpacingTokens.sm),
        
        // 연간 구독
        if (_purchaseService.yearlyProduct != null)
          _buildPlanOption(
            _purchaseService.yearlyProduct!,
            InAppPurchaseService.premiumYearlyId,
            '최대 절약',
            true,
          ),
      ],
    );
  }

  Widget _buildPlanOption(
    ProductDetails product,
    String planId,
    String badge,
    bool isRecommended,
  ) {
    final bool isSelected = _selectedPlan == planId;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPlan = planId;
        });
      },
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(SpacingTokens.md),
        decoration: BoxDecoration(
          color: isSelected ? ColorTokens.primaryverylight : ColorTokens.surface,
          borderRadius: BorderRadius.circular(SpacingTokens.radiusSmall),
          border: Border.all(
            color: isSelected ? ColorTokens.primary : ColorTokens.primarylight,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.title,
                        style: TypographyTokens.subtitle2.copyWith(
                          color: ColorTokens.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: SpacingTokens.xs),
                      Text(
                        product.price,
                        style: TypographyTokens.headline3.copyWith(
                          color: ColorTokens.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                if (badge.isNotEmpty)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: SpacingTokens.sm,
                      vertical: SpacingTokens.xs,
                    ),
                    decoration: BoxDecoration(
                      color: isRecommended ? ColorTokens.success : ColorTokens.primary,
                      borderRadius: BorderRadius.circular(SpacingTokens.radiusXs),
                    ),
                    child: Text(
                      badge,
                      style: TypographyTokens.caption.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            if (planId == InAppPurchaseService.premiumYearlyId) ...[
              SizedBox(height: SpacingTokens.xs),
              Text(
                '월 평균 ${_calculateMonthlyPrice(product.price)}',
                style: TypographyTokens.caption.copyWith(
                  color: ColorTokens.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _calculateMonthlyPrice(String yearlyPrice) {
    // 연간 가격에서 월 평균 계산 (간단한 예시)
    final priceText = yearlyPrice.replaceAll(RegExp(r'[^\d.]'), '');
    final price = double.tryParse(priceText) ?? 0;
    final monthlyPrice = price / 12;
    return '₩${monthlyPrice.toStringAsFixed(0)}';
  }

  Widget _buildPurchaseButton() {
    return PikaButton(
      text: _isPurchasing ? '구매 중...' : '구독 시작하기',
      variant: PikaButtonVariant.primary,
      size: PikaButtonSize.large,
      onPressed: _selectedPlan != null && !_isPurchasing ? _purchaseSelectedPlan : null,
      isLoading: _isPurchasing,
      isFullWidth: true,
    );
  }

  Widget _buildRestoreButton() {
    return PikaButton(
      text: '구매 복원',
      variant: PikaButtonVariant.outline,
      size: PikaButtonSize.medium,
      onPressed: _isPurchasing ? null : _restorePurchases,
      isFullWidth: true,
    );
  }

  Widget _buildTermsAndPolicy() {
    return Column(
      children: [
        Text(
          '구독 시 자동 갱신됩니다. 언제든지 설정에서 취소할 수 있습니다.',
          style: TypographyTokens.caption.copyWith(
            color: ColorTokens.textTertiary,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: SpacingTokens.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: () {
                // 이용약관 페이지로 이동
              },
              child: Text(
                '이용약관',
                style: TypographyTokens.caption.copyWith(
                  color: ColorTokens.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            Text(
              ' • ',
              style: TypographyTokens.caption.copyWith(
                color: ColorTokens.textTertiary,
              ),
            ),
            TextButton(
              onPressed: () {
                // 개인정보처리방침 페이지로 이동
              },
              child: Text(
                '개인정보처리방침',
                style: TypographyTokens.caption.copyWith(
                  color: ColorTokens.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _purchaseSelectedPlan() async {
    if (_selectedPlan == null) return;

    setState(() {
      _isPurchasing = true;
    });

    try {
      final success = await _purchaseService.buyProduct(_selectedPlan!);
      
      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('구매를 시작할 수 없습니다.'),
              backgroundColor: ColorTokens.error,
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ 구매 중 오류: $e');
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('구매 중 오류가 발생했습니다: $e'),
            backgroundColor: ColorTokens.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPurchasing = false;
        });
      }
    }
  }

  Future<void> _restorePurchases() async {
    try {
      // 구매 복원은 InAppPurchaseService에서 자동으로 처리됨
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('구매 복원을 시도했습니다.'),
            backgroundColor: ColorTokens.success,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ 구매 복원 중 오류: $e');
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('구매 복원 중 오류가 발생했습니다: $e'),
            backgroundColor: ColorTokens.error,
          ),
        );
      }
    }
  }
} 