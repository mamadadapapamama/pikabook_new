import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/banner_type.dart';
import '../../../core/services/authentication/user_preferences_service.dart';
import '../../../core/widgets/simple_upgrade_modal.dart';
import '../../../core/widgets/unified_banner.dart';
import '../../../core/models/subscription_state.dart';

/// 🎨 HomeScreen UI 관리 Coordinator
/// 
/// 책임:
/// - 환영 모달 관리
/// - 업그레이드 모달 표시
/// - 배너 닫기 처리
/// - 외부 링크 열기 (문의폼, App Store)
/// - 배너 위젯 생성
/// - 구독 상태 변경 시 배너 상태 자동 리셋
class HomeUICoordinator {
  final UserPreferencesService _userPreferencesService = UserPreferencesService();

  /// 활성 배너들을 UnifiedBanner 위젯 리스트로 변환
  Future<List<Widget>> buildActiveBanners({
    required BuildContext context,
    required List<BannerType> activeBanners,
    required Function(BannerType) onShowUpgradeModal,
    required Function(BannerType) onDismissBanner,
  }) async {
    
    if (kDebugMode) {
      debugPrint('🎨 [HomeUICoordinator] buildActiveBanners 시작:');
      debugPrint('   - 입력 배너 수: ${activeBanners.length}');
      debugPrint('   - 입력 배너 타입들: ${activeBanners.map((e) => e.name).toList()}');
    }
    
    // 🎯 구독 상태 변경 시 관련 없는 배너 상태 리셋
    await _resetIrrelevantBannerStates(activeBanners);
    
    final banners = <Widget>[];
    
    // 🎯 닫힌 배너 필터링
    final filteredBanners = await _filterDismissedBanners(activeBanners);
    
    if (kDebugMode) {
      debugPrint('   - 필터링 후 배너 수: ${filteredBanners.length}');
      debugPrint('   - 필터링 후 배너 타입들: ${filteredBanners.map((e) => e.name).toList()}');
    }
    
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
    
    if (kDebugMode) {
      debugPrint('   - 최종 생성된 배너 위젯 수: ${banners.length}');
      debugPrint('🎨 [HomeUICoordinator] buildActiveBanners 완료');
    }
    
    return banners;
  }

  /// 🔄 구독 상태 변경 시 관련 없는 배너 상태 리셋
  Future<void> _resetIrrelevantBannerStates(List<BannerType> activeBanners) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final activeNames = activeBanners.map((e) => e.name).toSet();
      
      // 모든 배너 타입 중에서 현재 활성화되지 않은 것들의 닫힌 상태 리셋
      final allBannerTypes = BannerType.values;
      final resetCount = <String>[];
      
      for (final bannerType in allBannerTypes) {
        if (!activeNames.contains(bannerType.name)) {
          final key = 'banner_${bannerType.name}_dismissed';
          final wasDismissed = prefs.getBool(key) ?? false;
          
          if (wasDismissed) {
            await prefs.remove(key);
            resetCount.add(bannerType.name);
            
            if (kDebugMode) {
              debugPrint('🔄 [HomeUICoordinator] 배너 상태 리셋: ${bannerType.name}');
            }
          }
        }
      }
      
      if (resetCount.isNotEmpty && kDebugMode) {
        debugPrint('✅ [HomeUICoordinator] 총 ${resetCount.length}개 배너 상태 리셋: ${resetCount.join(', ')}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [HomeUICoordinator] 배너 상태 리셋 실패: $e');
      }
    }
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

  /// 🎉 환영 모달 표시 (온보딩 후)
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
          
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => SimpleUpgradeModal(
              type: UpgradeModalType.trialOffer,
              onClose: () {
                if (kDebugMode) {
                  debugPrint('✅ [HomeUICoordinator] 환영 모달 완료');
                }
                onComplete(false); // 환영 모달은 구매 선택 없이 닫힘
              },
            ),
          );
        }
      });
    });
  }

  /// 💎 업그레이드 모달 표시 (단순화됨)
  void showUpgradeModal(BuildContext context, BannerType bannerType, {SubscriptionState? subscriptionState}) {
    if (kDebugMode) {
      debugPrint('🎯 [HomeUICoordinator] 업그레이드 모달 표시: ${bannerType.name}');
    }

    // 🔄 BannerType별 처리
    switch (bannerType) {
      case BannerType.trialStarted:
      case BannerType.premiumStarted:
        // 트라이얼 시작 및 프리미엄 시작 배너는 버튼 없음 (닫기만 가능)
        return;

      case BannerType.usageLimitPremium:
        // 프리미엄 플랜 사용량 한도 → 문의 폼으로 처리
        showContactForm(context);
        return;

      case BannerType.premiumGrace:
        // Grace Period → App Store 열기
        openAppStore(context);
        return;

      default:
        // 🎯 구독 상태에 따라 모달 타입 결정
        final modalType = _determineModalType(subscriptionState);
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => SimpleUpgradeModal(type: modalType),
        );
    }
  }

  /// 🎯 구독 상태에 따라 모달 타입 결정
  UpgradeModalType _determineModalType(SubscriptionState? subscriptionState) {
    if (subscriptionState == null) {
      return UpgradeModalType.trialOffer;
    }
    
    // 무료체험을 사용한 적이 있으면 프리미엄 구독 유도
    if (subscriptionState.hasUsedTrial) {
      return UpgradeModalType.premiumOffer;
    }
    
    // 그렇지 않으면 무료체험 유도
    return UpgradeModalType.trialOffer;
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