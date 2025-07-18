import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/tokens/color_tokens.dart';
import '../theme/tokens/typography_tokens.dart';
import '../theme/tokens/spacing_tokens.dart';
import '../services/payment/in_app_purchase_service.dart';

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

  /// 🚨 모달 중복 방지를 위한 정적 변수
  static bool _isShowing = false;
  static String _currentModalId = '';

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

  /// 모달 표시 정적 메서드 (중복 방지 로직 추가)
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
    // 🚨 중복 방지 체크
    final modalId = '${reason.name}_${DateTime.now().millisecondsSinceEpoch}';
    
    if (_isShowing) {
      if (kDebugMode) {
        debugPrint('⚠️ [UpgradeModal] 이미 모달이 표시 중입니다. 중복 호출 방지: $_currentModalId');
      }
      return Future.value(null);
    }

    if (kDebugMode) {
      debugPrint('🎯 [UpgradeModal] 모달 표시 시작: $modalId (reason: ${reason.name})');
    }

    // 모달 표시 상태 설정
    _isShowing = true;
    _currentModalId = modalId;

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
    ).then((result) {
      // 🚨 모달 닫힐 때 상태 초기화
      _isShowing = false;
      _currentModalId = '';
      
      if (kDebugMode) {
        debugPrint('✅ [UpgradeModal] 모달 닫힘: $modalId (result: $result)');
      }
      
      return result;
    });
  }

  /// 🚨 강제로 모달 상태 초기화 (에러 복구용)
  static void resetModalState() {
    _isShowing = false;
    _currentModalId = '';
    if (kDebugMode) {
      debugPrint('🔄 [UpgradeModal] 모달 상태 강제 초기화');
  }
  }

  /// 🚨 현재 모달 표시 상태 확인
  static bool get isShowing => _isShowing;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        padding: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCharacterHeader(),
            if (reason == UpgradeReason.welcomeTrial)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (customTitle != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          customTitle!,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    _buildMainMessage(),
                    const SizedBox(height: 16),
                    _buildFeatureList(),
                    const SizedBox(height: 24),
                    _buildButtons(context),
                  ],
                ),
              )
            else ...[
              const SizedBox(height: 16),
              if (reason == UpgradeReason.general && customMessage == null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Text(
                    '이미 무료체험을 사용하셨습니다',
                    style: const TextStyle(
                      color: Color(0xFFFA6400),
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (customTitle != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    customTitle!,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (customTitle != null) const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildMainMessage(),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildFeatureList(),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildButtons(context),
              ),
            ],
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
      '월 \$USD3.99로, \nPikabook을 마음껏 사용해 보세요!',
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
              _resetModalState();
              Navigator.of(context).pop(true);
              await launchUrl(Uri.parse('https://forms.gle/YaeznYjGLiMdHmBD9'));
              onUpgrade?.call();
            },
          ),
          
          const SizedBox(height: 16),
          
          _buildTextButton(
            '닫기',
            () {
              _resetModalState();
              Navigator.of(context).pop(false);
              onCancel?.call();
            },
          ),
        ],
      );
    }

    // 온보딩 후 환영 모달 (월간 구독 7일 무료체험 + 연간 구독 즉시 결제)
    if (reason == UpgradeReason.welcomeTrial) {
      return Column(
        children: [
          // 🎯 월간 구독 (7일 무료체험 포함)
          _buildPrimaryButton(
            '월 \$3.99 USD (7일 무료 체험)',
            '(언제든 구독 취소할수 있어요)',
            () async {
              if (kDebugMode) {
                debugPrint('🎯 [UpgradeModal] 월간 구독 (7일 무료 체험) 버튼 클릭됨');
              }
              
              _resetModalState();
              Navigator.of(context).pop(true);
              
              // 월간 구독은 7일 무료체험이 있는 offer
              await _handleWelcomeTrialPurchase(InAppPurchaseService.premiumMonthlyId);
              onUpgrade?.call();
            },
          ),
          
          const SizedBox(height: 12),
          
          // 🎯 연간 구독 (즉시 결제, 할인 강조)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFFF6B35), width: 1.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                // 할인 배지
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF6B35),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(6),
                      topRight: Radius.circular(6),
                    ),
                  ),
                  child: const Text(
                    '2개월 무료! 27% 할인',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                // 연간 구독 버튼
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () async {
                if (kDebugMode) {
                        debugPrint('🎯 [UpgradeModal] 연간 구독 (즉시 결제) 버튼 클릭됨');
                      }
                      
                      _resetModalState();
                      Navigator.of(context).pop(true);
                      
                      // 연간 구독은 즉시 결제 (무료체험 없음)
                      await _handleWelcomeYearlyPurchase();
                      onUpgrade?.call();
                    },
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(6),
                      bottomRight: Radius.circular(6),
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Column(
                        children: [
                          const Text(
                            '연간 \$34.99 USD',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFFF6B35),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            '(월 \$2.91 USD 상당)',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFFF6B35),
                              fontWeight: FontWeight.normal,
                            ),
                            textAlign: TextAlign.center,
                    ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 하단 링크 - 무료 플랜
          _buildTextButton(
            '무료 플랜으로 시작',
            () {
              _resetModalState();
              Navigator.of(context).pop(false);
              // 무료 플랜으로 시작 (인앱결제 없음)
              if (kDebugMode) {
                debugPrint('🎯 [UpgradeModal] 무료 플랜으로 시작');
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
                      _resetModalState();
                      Navigator.of(context).pop(true);
                      await _handlePurchase(InAppPurchaseService.premiumYearlyId);
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
              _resetModalState();
              Navigator.of(context).pop(true);
              await _handlePurchase(InAppPurchaseService.premiumMonthlyId);
              onUpgrade?.call();
            },
            isFullWidth: true,
            variant: PikaButtonVariant.outline,
          ),
          
          SizedBox(height: SpacingTokens.sm),
          
          // 취소 버튼
          TextButton(
            onPressed: () {
              _resetModalState();
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
                    _resetModalState();
                    Navigator.of(context).pop(true);
                    await _handlePurchase(InAppPurchaseService.premiumYearlyId);
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
            _resetModalState();
            Navigator.of(context).pop(true);
            await _handlePurchase(InAppPurchaseService.premiumMonthlyId);
            onUpgrade?.call();
          },
          isFullWidth: true,
          variant: PikaButtonVariant.outline,
        ),
        
        SizedBox(height: SpacingTokens.sm),
        
        // 취소 버튼
        TextButton(
          onPressed: () {
            _resetModalState();
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
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
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

  /// 구매 처리 헬퍼
  static Future<void> _handlePurchase(String productId) async {
    final purchaseService = InAppPurchaseService();
    await purchaseService.buyProduct(productId);
  }

  /// 🛠️ Pending Transaction 해결 가이드 다이얼로그
  static Future<void> _showPendingTransactionDialog(
    BuildContext context, 
    Map<String, dynamic> errorDetails
  ) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange[600], size: 24),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  errorDetails['title'] ?? '미완료 구매 감지',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                errorDetails['message'] ?? '이전 구매가 완료되지 않아 새 구매를 진행할 수 없습니다.',
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              ),
              SizedBox(height: 16),
              Text(
                '해결 방법:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              ...((errorDetails['solutions'] as List<Map<String, dynamic>>?) ?? [])
                  .map((solution) => Padding(
                        padding: EdgeInsets.only(bottom: 6),
                        child: Text(
                          '• ${solution['description']}',
                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                        ),
                      )),
            ],
          ),
          actions: [
            // 구매 복원 버튼
            TextButton.icon(
              icon: Icon(Icons.restore, size: 18),
              label: Text('구매 복원'),
              onPressed: () async {
                Navigator.of(context).pop();
                await _attemptRestorePurchases(context);
              },
            ),
            
            // 앱 재시작 안내 버튼
            TextButton.icon(
              icon: Icon(Icons.refresh, size: 18),
              label: Text('앱 재시작'),
              onPressed: () {
                Navigator.of(context).pop();
                _showAppRestartDialog(context);
              },
            ),
            
            // 닫기 버튼
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: ColorTokens.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text('확인'),
            ),
          ],
        );
      },
    );
  }

  /// 🔄 구매 복원 시도
  static Future<void> _attemptRestorePurchases(BuildContext context) async {
    // 로딩 표시
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('미완료 거래 정리 중...'),
            ],
          ),
        ),
      ),
    );

    try {
      final purchaseService = InAppPurchaseService();
      await purchaseService.restorePurchases();
      
      // 로딩 다이얼로그 닫기
      if (context.mounted) {
        Navigator.of(context).pop();
      }
      
      // 결과에 따른 메시지 표시
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('구매 복원이 완료되었습니다.'),
            backgroundColor: Colors.green[600],
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      
    } catch (e) {
      // 로딩 다이얼로그 닫기
      if (context.mounted) {
        Navigator.of(context).pop();
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('구매 복원 중 오류가 발생했습니다.'),
            backgroundColor: Colors.red[600],
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// 📱 앱 재시작 안내 다이얼로그
  static void _showAppRestartDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.restart_alt, color: Colors.blue[600], size: 24),
              SizedBox(width: 8),
              Text('앱 재시작 안내', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '앱을 완전히 종료하고 다시 실행하면 미완료 거래가 자동으로 정리됩니다.',
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              ),
              SizedBox(height: 12)
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: ColorTokens.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text('확인'),
            ),
          ],
        );
      },
    );
  }

  void _resetModalState() {
    resetModalState();
  }

  /// 환영 모달에서 월간 구독 구매 처리 (7일 무료 체험)
  static Future<void> _handleWelcomeTrialPurchase(String productId) async {
    final purchaseService = InAppPurchaseService();
    // 무료체험 구매 시도
    await purchaseService.buyProduct(productId);
  }

  /// 환영 모달에서 연간 구독 구매 처리 (즉시 결제)
  static Future<void> _handleWelcomeYearlyPurchase() async {
    final purchaseService = InAppPurchaseService();
    // 연간 구독 구매 시도
    await purchaseService.buyYearly();
  }
}

/// 업그레이드 유도 관련 유틸리티 클래스
class UpgradePromptHelper {
  /// 온보딩 완료 후 환영 모달 표시 (7일 무료체험 유도)
  static Future<void> showWelcomeTrialPrompt(
    BuildContext context, {
    required Function(bool userChoseTrial) onComplete,
  }) async {
    bool userChoseTrial = false;
    
    try {
      if (kDebugMode) {
        print('🎉 [UpgradeModal] 환영 모달 표시 시작 (7일 무료체험 유도)');
      }
      
      // InAppPurchaseService 구매 결과 콜백 설정
      final purchaseService = InAppPurchaseService();
      bool purchaseCompleted = false;
      
      purchaseService.setOnPurchaseResult((bool success, String? transactionId, String? error) {
        if (kDebugMode) {
          print('🛒 [UpgradeModal] 구매 결과 수신: success=$success, transactionId=$transactionId, error=$error');
        }
        
        if (success) {
          userChoseTrial = true;
          purchaseCompleted = true;
          if (kDebugMode) {
            print('✅ [UpgradeModal] 구매 성공 - 무료체험 선택됨');
          }
        } else {
          // 구매 실패 시 무료 플랜으로 처리
          userChoseTrial = false;
          purchaseCompleted = true;
          if (kDebugMode) {
            print('⚠️ [UpgradeModal] 구매 실패 - 무료 플랜으로 처리: $error');
          }
        }
      });
      
      final result = await UpgradeModal.show(
        context,
        reason: UpgradeReason.welcomeTrial,
        // onUpgrade는 버튼 내에서 직접 처리  
      );
      
      // 모달 결과에 따라 처리
      if (result == true) {
        // "7일간 무료로 프리미엄 시작하기" 선택
        if (kDebugMode) {
          print('🎯 [UpgradeModal] 사용자가 무료체험 버튼 선택 - 구매 결과 대기');
        }
        
        // 구매 완료까지 최대 1분 대기
        int waitCount = 0;
        while (!purchaseCompleted && waitCount < 600) { // 
          await Future.delayed(Duration(milliseconds: 600));
          waitCount++;
        }
        
        if (!purchaseCompleted) {
          if (kDebugMode) {
            print('⏰ [UpgradeModal] 구매 결과 대기 타임아웃 - 무료 플랜으로 처리');
          }
          userChoseTrial = false;
        }
      } else {
        // "나가기" 선택
        userChoseTrial = false;
        if (kDebugMode) {
          print('🎯 [UpgradeModal] 사용자가 나가기 선택 - 무료 플랜');
        }
      }
      
      if (kDebugMode) {
        print('✅ [UpgradeModal] 환영 모달 완료 - 최종 선택: ${userChoseTrial ? "무료체험" : "무료플랜"}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UpgradeModal] 환영 모달 표시 오류: $e');
      }
      userChoseTrial = false;
    } finally {
      // 구매 결과 콜백 해제
      final purchaseService = InAppPurchaseService();
      purchaseService.setOnPurchaseResult(null);
      
      onComplete(userChoseTrial);
    }
  }

  /// 탈퇴 후 재가입 시 구독 복원 스낵바 표시
  static void showSubscriptionRestoredSnackbar(
    BuildContext context, {
    required bool isFreeTrial,
  }) {
    final message = isFreeTrial
        ? '프리미엄 무료 체험이 복원되었습니다.\n전환하려면 App Store > 구독 관리에서 Pikabook 구독을 먼저 취소해주세요.'
        : '프리미엄 플랜이 복원되었습니다.\n무료 플랜으로 전환하려면 App Store > 구독 관리에서 Pikabook 구독을 먼저 취소해주세요.';

    if (kDebugMode) {
      print('📢 [UpgradeModal] 구독 복원 스낵바 표시');
      print('   무료체험: $isFreeTrial');
      print('   메시지: ${message.replaceAll('\n', ' ')}');
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: ColorTokens.snackbarBg,
        behavior: SnackBarBehavior.fixed,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  /// 무료체험 기록이 있는 사용자를 위한 프리미엄 업그레이드 모달
  static Future<void> showPremiumUpgradePrompt(
    BuildContext context, {
    required VoidCallback onComplete,
  }) async {
    try {
      if (kDebugMode) {
        print('💳 [UpgradeModal] 프리미엄 업그레이드 모달 표시 시작 (일반 구독)');
      }
      
      await UpgradeModal.show(
        context,
        reason: UpgradeReason.general, // 일반 구독 옵션 표시
      );
      
      if (kDebugMode) {
        print('✅ [UpgradeModal] 프리미엄 업그레이드 모달 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UpgradeModal] 프리미엄 업그레이드 모달 표시 오류: $e');
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
      onUpgrade: () => _handleUpgrade(),
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
      onUpgrade: () => _handleUpgrade(),
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
      onUpgrade: () => _handleUpgrade(),
      onCancel: onCancel,
    );
  }

  /// 업그레이드 처리 (인앱 구매 연동)
  static void _handleUpgrade() {
    // 기본적으로 월간 구독으로 연결
    UpgradeModal._handlePurchase(InAppPurchaseService.premiumMonthlyId);
  }
}