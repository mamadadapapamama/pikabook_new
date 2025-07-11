import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/common/banner_manager.dart';
import '../../../core/services/authentication/user_preferences_service.dart';
import '../../../core/widgets/upgrade_modal.dart';

/// 🎨 HomeScreen UI 관리 Coordinator
/// 
/// 책임:
/// - 환영 모달 관리
/// - 업그레이드 모달 표시
/// - 배너 닫기 처리
/// - 외부 링크 열기 (문의폼, App Store)
class HomeUICoordinator {
  final UserPreferencesService _userPreferencesService = UserPreferencesService();
  final BannerManager _bannerManager = BannerManager();

  /// 🎉 환영 모달 표시 (지연 후)
  void showWelcomeModalAfterDelay(
    BuildContext context, {
    required Function() onComplete,
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
            onComplete: () async {
              if (kDebugMode) {
                debugPrint('✅ [HomeUICoordinator] 환영 모달 완료 - 온보딩 완료 처리 시작');
              }
              
              try {
                // 온보딩 완료 상태 업데이트
                final preferences = await _userPreferencesService.getPreferences();
                await _userPreferencesService.savePreferences(
                  preferences.copyWith(onboardingCompleted: true),
                );
                
                if (kDebugMode) {
                  debugPrint('✅ [HomeUICoordinator] 온보딩 완료 상태 저장됨');
                }
                
                // 완료 콜백 호출
                onComplete();
                
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('❌ [HomeUICoordinator] 온보딩 완료 처리 실패: $e');
                }
              }
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

      case BannerType.usageLimitFree:
        _showUpgradeModalWithReason(context, UpgradeReason.limitReached);
        break;

      case BannerType.usageLimitPremium:
        // 프리미엄 플랜 사용량 한도 → 문의 폼으로 처리
        showContactForm(context);
        return;

      case BannerType.trialCompleted:
      case BannerType.trialCancelled:
      case BannerType.premiumExpired:
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
  Future<void> showContactForm(BuildContext context) async {
    const formUrl = 'https://docs.google.com/forms/d/e/1FAIpQLSfgVL4Bd5KcTh9nhfbVZ51yApPAmJAZJZgtM4V9hNhsBpKuaA/viewform?usp=dialog';
    
    try {
      final Uri uri = Uri.parse(formUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        
        if (kDebugMode) {
          debugPrint('✅ [HomeUICoordinator] 문의 폼 열기 성공');
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('문의 폼을 열 수 없습니다.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('문의 폼을 여는 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      
      if (kDebugMode) {
        debugPrint('❌ [HomeUICoordinator] 문의 폼 열기 실패: $e');
      }
    }
  }

  /// 📱 App Store 열기 (Grace Period 사용자용)
  Future<void> openAppStore(BuildContext context) async {
    const appStoreUrl = 'https://apps.apple.com/account/subscriptions';
    
    try {
      final Uri uri = Uri.parse(appStoreUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        
        if (kDebugMode) {
          debugPrint('✅ [HomeUICoordinator] App Store 열기 성공');
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('App Store를 열 수 없습니다.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('App Store를 여는 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      
      if (kDebugMode) {
        debugPrint('❌ [HomeUICoordinator] App Store 열기 실패: $e');
      }
    }
  }

  /// 🚫 배너 닫기 처리
  Future<void> dismissBanner(BannerType bannerType, {
    required Function(List<BannerType>) onBannersUpdated,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🚫 [HomeUICoordinator] 배너 닫기 시작: ${bannerType.name}');
      }
      
      await _bannerManager.dismissBanner(bannerType);
      
      if (kDebugMode) {
        debugPrint('✅ [HomeUICoordinator] 배너 닫기 완료: ${bannerType.name}');
      }
      
      // 🎯 현재 활성 배너 목록을 다시 가져와서 콜백 호출
      // BannerManager에서 최신 상태를 가져오는 것이 더 안전
      // 하지만 여기서는 간단히 빈 리스트나 업데이트된 리스트를 전달
      // 실제로는 HomeScreen에서 전체 구독 상태를 다시 로드하는 것이 좋음
      
      if (kDebugMode) {
        debugPrint('🔄 [HomeUICoordinator] 배너 닫기 후 상태 업데이트 요청');
      }
      
      // 빈 리스트를 전달하여 UI에서 해당 배너를 제거하도록 함
      // 실제 배너 상태는 다음 구독 상태 로드 시 정확히 반영됨
      onBannersUpdated([]);
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [HomeUICoordinator] 배너 닫기 실패: $e');
      }
    }
  }
} 