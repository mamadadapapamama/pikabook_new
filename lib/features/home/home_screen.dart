import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:collection/collection.dart'; // 🎯 추가

// 🎯 Core imports
import '../../core/models/subscription_state.dart';
import '../../core/services/subscription/unified_subscription_manager.dart';
import '../../core/theme/tokens/ui_tokens.dart';
import '../../core/widgets/pika_app_bar.dart';
import '../../core/widgets/dot_loading_indicator.dart';
import '../../core/models/banner_type.dart';

// 🎯 Feature imports
import 'home_viewmodel.dart';
import 'coordinators/home_ui_coordinator.dart';
import 'widgets/home_zero_state.dart';
import 'widgets/home_notes_list.dart';
import 'widgets/home_floating_button.dart';

/// 🏠 홈 스크린 (단순화된 버전)
/// 
/// 책임:
/// - App.dart로부터 구독 상태를 전달받아 UI를 표시
/// - 환영 모달 표시 관리
class HomeScreen extends StatefulWidget {
  final SubscriptionState subscriptionState;

  const HomeScreen({
    super.key,
    required this.subscriptionState,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // 🔧 서비스 인스턴스
  final HomeUICoordinator _uiCoordinator = HomeUICoordinator();
  
  // 🎯 상태 관리
  bool _isLoading = true; // 뷰모델 로딩 상태
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
        debugPrint('🔄 [HomeScreen] 앱 포그라운드 복귀 - 상태 새로고침은 App.dart가 담당');
      }
      // App.dart에서 캐시 무효화를 담당하므로 HomeScreen에서는 별도 처리 안함
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
          _isLoading = false; // 뷰몸 로딩 완료
        });
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showWelcomeModal();
          }
        });
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [HomeScreen] 사용자 상태 결정 실패: $e');
      }
      _isNewUser = true;
      _setDefaultState();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showWelcomeModal();
        }
      });
    }
  }

  /// 🎯 기본 상태 설정
  void _setDefaultState() {
    if (mounted) {
      setState(() {
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
      }, SetOptions(merge: true));

      // 2. 온보딩 완료 상태는 이미 온보딩에서 저장됨 (중복 저장 방지)
      
      // 3. 무료 플랜 선택 시 Firestore 상태 설정
      if (!userChoseTrial) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .set({
          'subscriptionStatus': 'cancelled',
          'entitlement': 'free',
          'hasUsedTrial': false, // 🎯 명시적으로 false로 설정
        }, SetOptions(merge: true));
      }

      // 4. 🔥 중요: App.dart에서 이미 구독 중이므로, 여기서는 캐시 무효화만 요청
      await UnifiedSubscriptionManager().invalidateCache();
      
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

  /// 배너 닫기 (즉시 UI 업데이트 + 스트림 기반 새로고침)
  void _onDismissBanner(BannerType bannerType) async {
    if (kDebugMode) {
      debugPrint('🚫 [HomeScreen] 배너 닫기 시작: ${bannerType.name}');
    }
    
    // 💥 중요: 이제 HomeScreen은 상태를 직접 수정하지 않음
    // 올바른 방법은 UnifiedSubscriptionManager를 통해 상태를 업데이트하는 것이나,
    // 현재 구조에서는 HomeUICoordinator가 이를 처리하도록 위임.
    // setState(() {
    //   final updatedBanners = widget.subscriptionState.activeBanners.where((banner) => banner != bannerType.name).toList();
    //   _subscriptionState = _subscriptionState.copyWith(
    //     activeBanners: updatedBanners,
    //   );
    // });
      
    try {
      // 백그라운드에서 배너 상태 저장 -> 이로 인해 스트림이 업데이트되고 App.dart를 통해 HomeScreen에 전달됨
      await _uiCoordinator.dismissBanner(bannerType);
      
      if (kDebugMode) {
        debugPrint('✅ [HomeScreen] 배너 닫기 완료: ${bannerType.name}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [HomeScreen] 배너 닫기 실패: $e');
      }
    }
  }

  /// 수동 새로고침 (스트림 기반)
  void _onRefresh() {
    if (kDebugMode) {
      debugPrint('🔄 [HomeScreen] 수동 새로고침 요청');
    }
    // App.dart를 통해 상태가 관리되므로, 캐시 무효화만 트리거
    UnifiedSubscriptionManager().invalidateCache();
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
        body: Consumer<HomeViewModel>(
          builder: (context, viewModel, _) {
            final hasNotes = viewModel.notes.isNotEmpty;
            final activeBanners = _uiCoordinator.buildActiveBanners(
              context: context,
              activeBanners: widget.subscriptionState.activeBanners
                  .map((name) {
                    try {
                      return BannerType.values.firstWhere((e) => e.name == name);
                    } catch (e) {
                      return null;
                    }
                  })
                  .where((e) => e != null)
                  .cast<BannerType>()
                  .toList(),
              onShowUpgradeModal: _onShowUpgradeModal,
              onDismissBanner: _onDismissBanner,
            );

            if (hasNotes) {
              // 노트가 있는 경우 - 노트 리스트 표시
              return HomeNotesList(
                activeBanners: activeBanners,
                onRefresh: _onRefresh,
              );
            } else {
              // 노트가 없는 경우 - 제로 상태 표시
              return HomeZeroState(
                activeBanners: activeBanners,
              );
            }
          },
        ),
        floatingActionButton: const HomeFloatingButton(),
      ),
    );
  }
} 