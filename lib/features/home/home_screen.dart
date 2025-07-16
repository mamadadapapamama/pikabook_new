import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// 🎯 Core imports
import '../../core/models/subscription_state.dart';
import '../../core/services/common/banner_manager.dart';
import '../../core/services/subscription/unified_subscription_manager.dart';
import '../../core/services/authentication/user_preferences_service.dart';
import '../../core/theme/tokens/ui_tokens.dart';
import '../../core/widgets/pika_app_bar.dart';
import '../../core/widgets/dot_loading_indicator.dart';
import '../../core/widgets/upgrade_modal.dart';

// 🎯 Feature imports
import 'home_viewmodel.dart';
import 'coordinators/home_ui_coordinator.dart';
import 'widgets/home_zero_state.dart';
import 'widgets/home_notes_list.dart';
import 'widgets/home_floating_button.dart';

/// 🏠 홈 스크린 (단순화된 버전)
/// 
/// 책임:
/// - UnifiedSubscriptionManager 직접 사용
/// - 환영 모달 표시 관리
/// - 구독 상태 및 배너 관리
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // 🔧 서비스 인스턴스
  final UnifiedSubscriptionManager _subscriptionManager = UnifiedSubscriptionManager();
  final UserPreferencesService _userPreferencesService = UserPreferencesService();
  final HomeUICoordinator _uiCoordinator = HomeUICoordinator();
  
  // 🎯 상태 관리
  SubscriptionState _subscriptionState = SubscriptionState.defaultState();
  bool _isLoading = true;
  bool _isNewUser = false;
  HomeViewModel? _homeViewModel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeScreen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 앱 생명주기 변경 감지
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      if (kDebugMode) {
        debugPrint('🔄 [HomeScreen] 앱 포그라운드 복귀 - 구독 상태 새로고침');
      }
      _refreshSubscriptionState();
    }
  }

  /// 화면 초기화
  Future<void> _initializeScreen() async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 [HomeScreen] 화면 초기화 시작');
      }
      
      // 🎯 신규/기존 사용자 확인
      await _determineUserStatus();
      
      // 🎯 사용자 상태가 확인되면 HomeViewModel 생성
      if (mounted) {
        _homeViewModel = HomeViewModel(isNewUser: _isNewUser);
        setState(() {
          // UI 업데이트
        });
      }
      
      // 🎯 기존 사용자인 경우 구독 상태 로드
      if (!_isNewUser) {
        await _loadSubscriptionState();
      }
      
      if (kDebugMode) {
        debugPrint('✅ [HomeScreen] 화면 초기화 완료');
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [HomeScreen] 화면 초기화 실패: $e');
      }
      _setDefaultState();
    }
  }

  /// 🎯 사용자 상태 결정 - 환영 모달 본 적 있는지 확인
  Future<void> _determineUserStatus() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser!;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      
      bool hasSeenWelcomeModal = false;
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        hasSeenWelcomeModal = userData['hasSeenWelcomeModal'] as bool? ?? false;
      }
      
      _isNewUser = !hasSeenWelcomeModal;
      
      if (kDebugMode) {
        debugPrint('🔍 [HomeScreen] 사용자 상태 결정: ${_isNewUser ? "신규" : "기존"}');
      }
      
      // 신규 사용자인 경우 환영 모달 표시
      if (_isNewUser) {
        _setDefaultState();
        _showWelcomeModal();
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [HomeScreen] 사용자 상태 결정 실패: $e');
      }
      _isNewUser = true;
      _setDefaultState();
      _showWelcomeModal();
    }
  }

  /// 🎯 구독 상태 로드
  Future<void> _loadSubscriptionState() async {
    try {
      if (kDebugMode) {
        debugPrint('🔍 [HomeScreen] 구독 상태 로드 시작');
      }
      
      final subscriptionState = await _subscriptionManager.getSubscriptionStateWithBanners();
      
    if (mounted) {
      setState(() {
        _subscriptionState = subscriptionState;
        _isLoading = false;
      });
      }
      
      if (kDebugMode) {
        debugPrint('✅ [HomeScreen] 구독 상태 로드 완료');
        debugPrint('   권한: ${subscriptionState.entitlement.value}');
        debugPrint('   활성 배너: ${subscriptionState.activeBanners.length}개');
        debugPrint('   배너 타입: ${subscriptionState.activeBanners.map((e) => e.name).toList()}');
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [HomeScreen] 구독 상태 로드 실패: $e');
      }
      _setDefaultState();
    }
  }

  /// 🎯 구독 상태 새로고침
  Future<void> _refreshSubscriptionState() async {
    if (_isNewUser) return; // 신규 사용자는 새로고침 안함
    
    await _loadSubscriptionState();
  }

  /// 🎯 기본 상태 설정
  void _setDefaultState() {
    if (mounted) {
      setState(() {
        _subscriptionState = SubscriptionState.defaultState();
        _isLoading = false;
      });
    }
  }

  /// 환영 모달 표시
  void _showWelcomeModal() {
    _uiCoordinator.showWelcomeModalAfterDelay(
      context,
      onComplete: (bool userChoseTrial) async {
        if (kDebugMode) {
          debugPrint('[HomeScreen] 환영 모달 완료 - 구매 선택: $userChoseTrial');
        }
        
        // 🚨 HomeViewModel의 신규 사용자 플래그 해제
        _homeViewModel?.setNewUser(false);
        
        // 🎯 환영 모달 완료 처리
        await _handleWelcomeModalCompleted(userChoseTrial: userChoseTrial);
      },
    );
  }

  /// 🎯 환영 모달 완료 후 처리
  Future<void> _handleWelcomeModalCompleted({required bool userChoseTrial}) async {
    try {
      if (kDebugMode) {
        debugPrint('🎉 [HomeScreen] 환영 모달 완료 처리');
        debugPrint('   무료체험 선택: $userChoseTrial');
      }

      // 1. 환영 모달 본 것으로 표시
      final currentUser = FirebaseAuth.instance.currentUser!;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .set({
        'hasSeenWelcomeModal': true,
        'welcomeModalSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2. 온보딩 완료 상태 저장
      final preferences = await _userPreferencesService.getPreferences();
      await _userPreferencesService.savePreferences(
        preferences.copyWith(onboardingCompleted: true),
      );

      // 3. 무료 플랜 선택 시 Firestore 상태 설정
      if (!userChoseTrial) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .set({
          'planStatus': 'free',
          'subscriptionStatus': 'cancelled',
          'entitlement': 'free',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // 4. 구독 상태 확인 (배너 표시용)
      if (userChoseTrial) {
        // 구매 완료를 기다린 후 확인
        await Future.delayed(const Duration(milliseconds: 1500));
      }
      
      await _loadSubscriptionState();
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [HomeScreen] 환영 모달 완료 처리 실패: $e');
      }
      _setDefaultState();
    }
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
        // 배너 상태 새로고침
        _refreshSubscriptionState();
      },
    );
  }

  /// 수동 새로고침
  void _onRefresh() {
    _refreshSubscriptionState();
  }

  @override
  Widget build(BuildContext context) {
    // HomeViewModel이 아직 생성되지 않은 경우 로딩 표시
    if (_homeViewModel == null) {
      return Scaffold(
        backgroundColor: UITokens.screenBackground,
        appBar: PikaAppBar.home(),
        body: const Center(
          child: DotLoadingIndicator(message: '초기화 중...'),
        ),
      );
    }

    return ChangeNotifierProvider<HomeViewModel>.value(
      value: _homeViewModel!,
      child: Scaffold(
        backgroundColor: UITokens.screenBackground,
        appBar: PikaAppBar.home(),
        body: _buildBody(),
        floatingActionButton: const HomeFloatingButton(),
      ),
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