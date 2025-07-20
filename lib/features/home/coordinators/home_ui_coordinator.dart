import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/banner_type.dart';
import '../../../core/services/authentication/user_preferences_service.dart';
import '../../../core/widgets/upgrade_modal.dart';
import '../../../core/widgets/unified_banner.dart';

/// 🎨 HomeScreen UI 관리 Coordinator
/// 
/// 책임:
/// - 환영 모달 관리
/// - 업그레이드 모달 표시
/// - 배너 닫기 처리
/// - 외부 링크 열기 (문의폼, App Store)
/// - 배너 위젯 생성
class HomeUICoordinator {
  final UserPreferencesService _userPreferencesService = UserPreferencesService();

  /// 활성 배너들을 UnifiedBanner 위젯 리스트로 변환
  Future<List<Widget>> buildActiveBanners({
    required BuildContext context,
    required List<BannerType> activeBanners,
    required Function(BannerType) onShowUpgradeModal,
    required Function(BannerType) onDismissBanner,
  }) async {
    final banners = <Widget>[];
    
    // 🎯 닫힌 배너 필터링
    final filteredBanners = await _filterDismissedBanners(activeBanners);
    
    for (final bannerType in filteredBanners) {
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

  /// 🎯 닫힌 배너 필터링
  Future<List<BannerType>> _filterDismissedBanners(List<BannerType> banners) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final filteredBanners = <BannerType>[];
      
      for (final bannerType in banners) {
        final key = 'banner_${bannerType.name}_dismissed';
        final isDismissed = prefs.getBool(key) ?? false;
        
        if (!isDismissed) {
          filteredBanners.add(bannerType);
        } else {
          if (kDebugMode) {
            debugPrint('🚫 [HomeUICoordinator] 닫힌 배너 필터링: ${bannerType.name}');
          }
        }
      }
      
      if (kDebugMode) {
        debugPrint('📋 [HomeUICoordinator] 배너 필터링 결과: ${banners.length} → ${filteredBanners.length}');
      }
      
      return filteredBanners;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [HomeUICoordinator] 배너 필터링 실패: $e');
      }
      return banners; // 실패 시 원본 반환
    }
  }

  /// 배너 타입별 버튼 텍스트 결정
  String? _getButtonTextForBannerType(BannerType bannerType) {
    switch (bannerType) {
      case BannerType.trialStarted:
      case BannerType.premiumStarted:
        return null; // 환영 메시지, 닫기만 가능
      
      case BannerType.free:
        return '모든 플랜 보기';
      
      case BannerType.usageLimitFree:
        return '모든 플랜 보기';
      
      case BannerType.trialCancelled:
        return '모든 플랜 보기';
      
      case BannerType.switchToPremium:
        return null; // 트라이얼 완료후 월구독 시작

      case BannerType.premiumCancelled:
        return null;
      
      case BannerType.usageLimitPremium:
        return '문의하기';
      
      case BannerType.premiumGrace:
        return null;
      
      default:
        return '업그레이드';
    }
  }

  /// 🎉 환영 모달 표시 (지연 후)
  void showWelcomeModalAfterDelay(
    BuildContext context, {
    required Function(bool userChoseTrial) onComplete,
  }) {
    if (kDebugMode) {
      debugPrint('🎉 [HomeUICoordinator] 환영 모달 표시 준비');
    }
    
    // 화면이 완전히 로드된 후 환영 모달 표시
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (context.mounted) {
          if (kDebugMode) {
            debugPrint('🎉 [HomeUICoordinator] 환영 모달 표시 시작');
          }
          
          UpgradePromptHelper.showWelcomeTrialPrompt(
            context,
            onComplete: (bool userChoseTrial) async {
              if (kDebugMode) {
                debugPrint('✅ [HomeUICoordinator] 환영 모달 완료 - 구매 선택: $userChoseTrial');
              }
              
              // 완료 콜백 호출 (구매 선택 여부 전달)
              onComplete(userChoseTrial);
            },
          );
        }
      });
    });
  }

  /// 💎 업그레이드 모달 표시
  /// 
  /// 🔄 BannerType을 UpgradeReason으로 변환하여 적절한 모달 표시
  /// 각 배너 타입에 따라 다른 업그레이드 이유와 메시지를 제공
  void showUpgradeModal(BuildContext context, BannerType bannerType) {
    // 🚨 이미 업그레이드 모달이 표시 중이면 중복 호출 방지
    if (UpgradeModal.isShowing) {
      if (kDebugMode) {
        debugPrint('⚠️ [HomeUICoordinator] 업그레이드 모달이 이미 표시 중입니다. 중복 호출 방지');
      }
      return;
    }

    // 🔄 BannerType별 처리
    switch (bannerType) {
      case BannerType.trialStarted:
      case BannerType.premiumStarted:
        // 트라이얼 시작 및 프리미엄 시작 배너는 버튼 없음 (닫기만 가능)
        return;

      case BannerType.free:
      case BannerType.usageLimitFree:
        _showUpgradeModalWithReason(context, UpgradeReason.limitReached);
        break;

      case BannerType.usageLimitPremium:
        // 프리미엄 플랜 사용량 한도 → 문의 폼으로 처리
        showContactForm(context);
        return;

      case BannerType.switchToPremium: // trialCompleted, premiumExpired 통합
      case BannerType.trialCancelled:
      case BannerType.premiumCancelled:
        _showUpgradeModalWithReason(context, UpgradeReason.trialExpired);
        break;

      case BannerType.premiumGrace:
        // Grace Period → App Store 열기
        openAppStore(context);
        return;

      default:
        _showUpgradeModalWithReason(context, UpgradeReason.general);
    }
  }

  /// 업그레이드 모달 표시 헬퍼
  void _showUpgradeModalWithReason(BuildContext context, UpgradeReason reason) {
    if (kDebugMode) {
      debugPrint('🎯 [HomeUICoordinator] 업그레이드 모달 표시: ${reason.name}');
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => UpgradeModal(reason: reason),
    );
  }

  /// 📧 문의 폼 표시 (프리미엄 사용자용)
  void showContactForm(BuildContext context) {
    launchUrl(Uri.parse('https://forms.gle/YaeznYjGLiMdHmBD9'));
  }
  
  /// 🛒 App Store 열기 (결제 정보 관리)
  void openAppStore(BuildContext context) {
    launchUrl(Uri.parse('https://apps.apple.com/account/subscriptions'));
  }

  /// 🚫 배너 닫기 처리
  Future<void> dismissBanner(BannerType bannerType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'banner_${bannerType.name}_dismissed';
      await prefs.setBool(key, true);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [HomeUICoordinator] 배너 닫기 실패: $e');
      }
    }
  }
} 

/// 💎 업그레이드 모달 표시 도우미
/// 
/// 책임:
/// - 온보딩 완료 후 환영 모달 표시
class UpgradePromptHelper {
  /// 온보딩 완료 후 환영 모달 표시
  static void showWelcomeTrialPrompt(
    BuildContext context, {
    required Function(bool userChoseTrial) onComplete,
  }) {
    if (kDebugMode) {
      debugPrint('🎉 [UpgradePromptHelper] 환영 모달 표시 준비');
    }
    
    // 화면이 완전히 로드된 후 환영 모달 표시
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 800), () {
        if (context.mounted) {
          if (kDebugMode) {
            debugPrint('🎉 [UpgradePromptHelper] 환영 모달 표시 시작');
          }
          
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => UpgradeModal(reason: UpgradeReason.welcomeTrial),
          ).then((_) {
            onComplete(false); // 환영 모달은 구매 선택 없이 닫힘
          });
        }
      });
    });
  }
} 