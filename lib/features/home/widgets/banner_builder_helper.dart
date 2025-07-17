import 'package:flutter/material.dart';

import '../../../core/services/common/banner_manager.dart';
import '../../../core/widgets/unified_banner.dart';

/// 🎯 배너 빌더 헬퍼
/// 
/// 책임:
/// - 활성 배너들의 UI 생성 로직 통합
/// - 배너 타입별 버튼 텍스트 결정 로직 중앙화
/// - HomeZeroState와 HomeNotesList 간의 중복 제거
class BannerBuilderHelper {
  /// 활성 배너들을 UnifiedBanner 위젯 리스트로 변환
  static List<Widget> buildActiveBanners({
    required List<BannerType> activeBanners,
    required Function(BannerType) onShowUpgradeModal,
    required Function(BannerType) onDismissBanner,
  }) {
    final banners = <Widget>[];
    
    for (final bannerType in activeBanners) {
      final buttonText = _getButtonTextForBannerType(bannerType);
      
      banners.add(
        UnifiedBanner(
          title: bannerType.title,
          subtitle: bannerType.subtitle,
          mainButtonText: buttonText,
          onMainButtonPressed: buttonText != null 
              ? () => onShowUpgradeModal(bannerType)
              : null,
          onDismiss: () => onDismissBanner(bannerType),
        ),
      );
    }
    
    return banners;
  }

  /// 배너 타입별 버튼 텍스트 결정
  static String? _getButtonTextForBannerType(BannerType bannerType) {
    switch (bannerType) {
      case BannerType.trialStarted:
      case BannerType.premiumStarted:
        return null; // 환영 메시지, 닫기만 가능
      
      case BannerType.free:
        return '풀팩 보기';
      
      case BannerType.usageLimitFree:
        return '풀팩보기';
      
      case BannerType.trialCancelled:
        return '풀팩 보기';
      
      case BannerType.switchToPremium:
        return '단기'; // 트라이얼 완료후 월구독 시작
      
      case BannerType.premiumCancelled:
        return '단기';
      
      case BannerType.usageLimitPremium:
        return '문의하기';
      
      case BannerType.premiumGrace:
        return '앱 스토어 바로가기';
      
      default:
        return '업그레이드';
    }
  }
} 