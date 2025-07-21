import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/tokens/color_tokens.dart';
import '../services/payment/in_app_purchase_service.dart';
import '../utils/snackbar_helper.dart';
import 'pika_button.dart';
import 'dot_loading_indicator.dart';

/// 🎯 업그레이드 모달 타입 (단순화됨)
enum UpgradeModalType {
  trialOffer,       // 무료체험 유도 (온보딩 후, 구매이력 없는 유저)
  premiumOffer,     // 프리미엄 구독 유도 (무료체험 사용한 유저)
}

/// 🎯 단순화된 업그레이드 모달 (로딩 상태 추가)
class SimpleUpgradeModal extends StatefulWidget {
  final UpgradeModalType type;
  final VoidCallback? onClose;

  const SimpleUpgradeModal({
    Key? key,
    required this.type,
    this.onClose,
  }) : super(key: key);

  @override
  State<SimpleUpgradeModal> createState() => _SimpleUpgradeModalState();
}

class _SimpleUpgradeModalState extends State<SimpleUpgradeModal> {
  bool _isLoading = false;
  String? _loadingMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            if (_isLoading) 
              _buildLoadingState()
            else 
              _buildContent(),
            if (!_isLoading) _buildButtons(context),
            SizedBox(height: 16.0),
          ],
        ),
      ),
    );
  }

  /// 헤더 (닫기 버튼)
  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          SizedBox(width: 24), // 균형 맞추기
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          GestureDetector(
            onTap: () {
              Navigator.of(context).pop();
              widget.onClose?.call();
            },
            child: Icon(
              Icons.close,
              size: 24,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// 콘텐츠 (제목, 설명, 일러스트)
  Widget _buildContent() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        children: [
          // 일러스트
          SvgPicture.asset(
            'assets/images/pikabook_textlogo_primary.svg',
            height: 80,
          ),
          SizedBox(height: 24.0),
          
          // 제목
          Text(
            _getTitle(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 16.0),
          
          // 설명
          Text(
            _getDescription(),
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 24.0),
        ],
      ),
    );
  }

  /// 버튼들
  Widget _buildButtons(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        children: [
          // 주요 버튼 (월간/연간)
          if (widget.type == UpgradeModalType.trialOffer) ...[
            // 무료체험 유도 - 7일 무료체험 후 월간
            PikaButton(
              text: '7일 무료체험 후 \$3.99 USD/월',
              variant: PikaButtonVariant.primary,
              onPressed: () => _handlePurchase(context, 'monthly'),
              isFullWidth: true,
            ),
            SizedBox(height: 8.0),
            
            // 연간 구독
            PikaButton(
              text: '연간 구독 \$34.99 USD/년 (2개월 무료!)',
              variant: PikaButtonVariant.outline,
              onPressed: () => _handlePurchase(context, 'yearly'),
              isFullWidth: true,
            ),
          ] else ...[
            // 프리미엄 구독 유도 - 월간
            PikaButton(
              text: '월간 구독 \$3.99 USD/월',
              variant: PikaButtonVariant.primary,
              onPressed: () => _handlePurchase(context, 'monthly'),
              isFullWidth: true,
            ),
            SizedBox(height: 8.0),
            
            // 연간 구독
            PikaButton(
              text: '연간 구독 \$34.99 USD/년 (2개월 무료!)',
              variant: PikaButtonVariant.outline,
              onPressed: () => _handlePurchase(context, 'yearly'),
              isFullWidth: true,
            ),
          ],
          
          SizedBox(height: 16.0),
          
          // 나중에 하기 버튼
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onClose?.call();
            },
            child: Text(
              '나중에 하기',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 로딩 상태 UI
  Widget _buildLoadingState() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 60.0, horizontal: 24.0),
      child: Column(
        children: [
          DotLoadingIndicator(
            message: _loadingMessage ?? '구매 처리 중...',
          ),
          SizedBox(height: 16.0),
          Text(
            '잠시만 기다려 주세요',
            style: TextStyle(
              fontSize: 16.0,
              color: ColorTokens.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 타입별 제목
  String _getTitle() {
    switch (widget.type) {
      case UpgradeModalType.trialOffer:
        return '7일 무료체험으로 시작하세요!';
      case UpgradeModalType.premiumOffer:
        return '무료 체험을 사용하셨습니다';
    }
  }

  /// 타입별 설명
  String _getDescription() {
    switch (widget.type) {
      case UpgradeModalType.trialOffer:
        return '모든 프리미엄 기능을 7일간 무료로 체험해보세요.\n언제든지 취소할 수 있습니다.';
      case UpgradeModalType.premiumOffer:
        return '계속해서 모든 프리미엄 기능을 사용하려면\n구독을 시작하세요.';
    }
  }

  /// 구매 처리
  Future<void> _handlePurchase(BuildContext context, String planType) async {
    setState(() {
      _isLoading = true;
      _loadingMessage = '구매 처리 중...';
    });

    try {
      final purchaseService = InAppPurchaseService();
      
      if (kDebugMode) {
        debugPrint('🛒 [SimpleUpgradeModal] 구매 시작: $planType');
      }
      
      PurchaseResult result;
      if (planType == 'monthly') {
        result = await purchaseService.buyMonthly();
      } else {
        result = await purchaseService.buyYearly();
      }
      
      if (kDebugMode) {
        debugPrint('🛒 [SimpleUpgradeModal] 구매 결과: ${result.success}');
      }
      
      if (result.success) {
        // 성공 시 모달 닫기 (Snackbar는 InAppPurchaseService에서 표시됨)
        if (context.mounted) {
          Navigator.of(context).pop();
          widget.onClose?.call();
        }
      } else if (result.errorMessage != null) {
        // 에러 시 에러 메시지 표시
        SnackbarHelper.showError(result.errorMessage!);
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SimpleUpgradeModal] 구매 처리 오류: $e');
      }
      SnackbarHelper.showError('구매 처리 중 오류가 발생했습니다.');
    } finally {
      setState(() {
        _isLoading = false;
        _loadingMessage = null;
      });
    }
  }

  /// 🎯 정적 메서드 - 모달 표시
  static Future<T?> show<T>(
    BuildContext context, {
    required UpgradeModalType type,
    VoidCallback? onClose,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SimpleUpgradeModal(
        type: type,
        onClose: onClose,
      ),
    );
  }
} 