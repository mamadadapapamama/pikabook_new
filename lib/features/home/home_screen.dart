import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// 🎯 Core imports
import '../../core/models/subscription_state.dart';
import '../../core/services/common/banner_manager.dart';
import '../../core/theme/tokens/ui_tokens.dart';
import '../../core/widgets/pika_app_bar.dart';
import '../../core/widgets/dot_loading_indicator.dart';

// 🎯 Feature imports
import 'home_viewmodel.dart';
import 'coordinators/home_lifecycle_coordinator.dart';
import 'coordinators/home_ui_coordinator.dart';
import 'widgets/home_zero_state.dart';
import 'widgets/home_notes_list.dart';
import 'widgets/home_floating_button.dart';

/// 🏠 홈 스크린 (리팩토링된 버전)
/// 
/// 책임:
/// - HomeViewModel과 coordinators를 조합하여 UI 렌더링
/// - 생명주기 관리는 HomeLifecycleCoordinator에 위임
/// - UI 상호작용은 HomeUICoordinator에 위임
class HomeScreen extends StatefulWidget {
  final bool shouldShowWelcomeModal;
  
  const HomeScreen({
    super.key,
    this.shouldShowWelcomeModal = false,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // 🔧 Coordinators
  late final HomeLifecycleCoordinator _lifecycleCoordinator;
  late final HomeUICoordinator _uiCoordinator;
  
  // 🎯 상태 관리
  SubscriptionState _subscriptionState = SubscriptionState.defaultState();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCoordinators();
  }

  @override
  void dispose() {
    _lifecycleCoordinator.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 앱 생명주기 변경 감지
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      if (kDebugMode) {
        debugPrint('🔄 [HomeScreen] 앱 포그라운드 복귀');
      }
      _lifecycleCoordinator.loadSubscriptionStatusAfterResume();
    }
  }

  /// Coordinators 초기화
  void _initializeCoordinators() {
    _lifecycleCoordinator = HomeLifecycleCoordinator();
    _uiCoordinator = HomeUICoordinator();
    
    // 생명주기 coordinator 초기화
    _lifecycleCoordinator.initialize(
      onSubscriptionStateChanged: _onSubscriptionStateChanged,
      onUserChanged: _onUserChanged,
    );
    
    // 신규 사용자 vs 기존 사용자 처리
    if (widget.shouldShowWelcomeModal) {
      if (kDebugMode) {
        debugPrint('[HomeScreen] 🆕 신규 사용자 - 환영 모달 표시');
      }
      _lifecycleCoordinator.initializeForNewUser();
      _showWelcomeModal();
    } else {
      if (kDebugMode) {
        debugPrint('[HomeScreen] 🔄 기존 사용자 - 기존 사용자 초기화');
      }
      _lifecycleCoordinator.initializeForExistingUser();
    }
  }

  /// 구독 상태 변경 콜백
  void _onSubscriptionStateChanged(SubscriptionState subscriptionState) {
    if (mounted) {
      setState(() {
        _subscriptionState = subscriptionState;
        _isLoading = false;
      });
      
      if (kDebugMode) {
        debugPrint('[HomeScreen] 구독 상태 업데이트: ${subscriptionState.statusMessage}');
      }
    }
  }

  /// 사용자 변경 콜백
  void _onUserChanged() {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
      
      if (kDebugMode) {
        debugPrint('[HomeScreen] 사용자 변경 감지 - 상태 초기화');
      }
    }
  }

  /// 환영 모달 표시
  void _showWelcomeModal() {
    _uiCoordinator.showWelcomeModalAfterDelay(
      context,
      onComplete: () {
        if (kDebugMode) {
          debugPrint('[HomeScreen] 환영 모달 완료 - 온보딩 완료 처리');
        }
        _lifecycleCoordinator.loadSubscriptionStatusAfterOnboarding();
      },
    );
  }

  /// 업그레이드 모달 표시
  void _onShowUpgradeModal(BannerType bannerType) {
    _uiCoordinator.showUpgradeModal(context, bannerType);
  }

  /// 배너 닫기
  void _onDismissBanner(BannerType bannerType) {
    _uiCoordinator.dismissBanner(
      bannerType,
      onBannersUpdated: (updatedBanners) {
        // 배너 닫기 후 구독 상태 새로고침
        _lifecycleCoordinator.refreshSubscriptionStatus();
      },
    );
  }

  /// 수동 새로고침
  void _onRefresh() {
    _lifecycleCoordinator.refreshSubscriptionStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UITokens.screenBackground,
      appBar: PikaAppBar.home(),
      body: _buildBody(),
      floatingActionButton: const HomeFloatingButton(),
    );
  }

  /// Body 구성
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: DotLoadingIndicator(message: '로딩 중...'),
      );
    }

    return Consumer<HomeViewModel>(
      builder: (context, viewModel, _) {
        final hasNotes = viewModel.notes.isNotEmpty;
        final activeBanners = _subscriptionState.activeBanners;

        if (hasNotes) {
          // 노트가 있는 경우 - 노트 리스트 표시
          return HomeNotesList(
            activeBanners: activeBanners,
            onShowUpgradeModal: _onShowUpgradeModal,
            onDismissBanner: _onDismissBanner,
            onRefresh: _onRefresh,
          );
        } else {
          // 노트가 없는 경우 - 제로 상태 표시
          return HomeZeroState(
            activeBanners: activeBanners,
            onShowUpgradeModal: _onShowUpgradeModal,
            onDismissBanner: _onDismissBanner,
          );
        }
      },
    );
  }
} 