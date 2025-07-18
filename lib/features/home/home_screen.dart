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
  final HomeUICoordinator _uiCoordinator = HomeUICoordinator();
  
  // 🎯 상태 관리
  SubscriptionState _subscriptionState = SubscriptionState.defaultState();
  bool _isLoading = true;
  bool _isNewUser = false;
  HomeViewModel? _homeViewModel;
  SubscriptionState? _previousSubscriptionState; // 🎯 추가
  
  // 🆕 구독 상태 변경 스트림 구독
  StreamSubscription<SubscriptionState>? _subscriptionStateSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeScreen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscriptionStateSubscription?.cancel(); // 🆕 스트림 구독 취소
    super.dispose();
  }

  /// 앱 생명주기 변경 감지
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      if (kDebugMode) {
        debugPrint('🔄 [HomeScreen] 앱 포그라운드 복귀 - 구독 상태 새로고침 (스트림 기반)');
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
      
      // 🎯 기존 사용자인 경우 구독 상태 스트림 설정 + 초기 로드
      if (!_isNewUser) {
        _setupSubscriptionStateStream(); // 🔔 스트림 구독 먼저 설정
        await _loadSubscriptionState();  // 🔍 초기 상태 로드
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

  /// 🎯 구독 상태 스트림 설정 (실시간 배너 업데이트)
  void _setupSubscriptionStateStream() {
    if (kDebugMode) {
      debugPrint('🔔 [HomeScreen] 구독 상태 스트림 구독 시작');
    }
    
    _subscriptionStateSubscription = _subscriptionManager.subscriptionStateStream.listen(
      (newState) {
        final hasChanged = _hasSubscriptionStateChanged(newState);

        if (hasChanged) {
          if (kDebugMode) {
            debugPrint('🔔 [HomeScreen] 구독 상태 변경 감지됨 -> UI 업데이트');
            debugPrint('   이전: ${_previousSubscriptionState?.entitlement.value} / 새 상태: ${newState.entitlement.value}');
            debugPrint('   이전 배너: ${_previousSubscriptionState?.activeBanners.length}개 / 새 배너: ${newState.activeBanners.length}개');
          }

          if (mounted) {
            setState(() {
              _subscriptionState = newState;
              _isLoading = false;
            });
          }
        }
        _previousSubscriptionState = newState;
      },
      onError: (error) {
        if (kDebugMode) {
          debugPrint('❌ [HomeScreen] 구독 상태 스트림 오류: $error');
        }
        _setDefaultState();
      },
    );
    
    if (kDebugMode) {
      debugPrint('✅ [HomeScreen] 구독 상태 스트림 구독 완료');
    }
  }

  /// 🎯 새로운 상태와 이전 상태를 비교하여 UI 업데이트 여부를 결정
  bool _hasSubscriptionStateChanged(SubscriptionState newState) {
    if (_previousSubscriptionState == null) return true; // 첫 로드는 항상 업데이트

    final oldState = _previousSubscriptionState!;
    
    // 1. 주요 권한 변경 확인
    if (oldState.entitlement != newState.entitlement) return true;

    // 2. 배너 목록 변경 확인 (순서 무관)
    final bannerEquality = const DeepCollectionEquality.unordered();
    if (!bannerEquality.equals(oldState.activeBanners, newState.activeBanners)) return true;
    
    // 3. 로딩 상태 변경 확인
    if (_isLoading) return true;

    // 4. 구독 상태 메시지 변경 확인
    if (oldState.statusMessage != newState.statusMessage) return true;

    return false;
  }

  /// 🎯 구독 상태 로드 (최초 1회만 호출)
  Future<void> _loadSubscriptionState() async {
    try {
      if (kDebugMode) {
        debugPrint('🔍 [HomeScreen] 구독 상태 로드 시작');
      }
      
      // 🎯 최초 1회만 호출 - 이후는 스트림으로 자동 업데이트
      final subscriptionState = await _subscriptionManager.getSubscriptionState();
      
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

  /// 🎯 구독 상태 새로고침 (스트림 기반 업데이트)
  Future<void> _refreshSubscriptionState() async {
    if (_isNewUser) return; // 신규 사용자는 새로고침 안함
    
    if (kDebugMode) {
      debugPrint('🔄 [HomeScreen] 구독 상태 새로고침 요청');
    }
    
    try {
      // 서버에서 최신 상태 조회 - 스트림으로 자동 업데이트됨
      await _subscriptionManager.getSubscriptionState();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [HomeScreen] 구독 상태 새로고침 실패: $e');
      }
    }
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
      }, SetOptions(merge: true));

      // 2. 온보딩 완료 상태는 이미 온보딩에서 저장됨 (중복 저장 방지)
      // 🚨 제거: 불필요한 사용자 설정 저장으로 인한 캐시 이벤트 반복 방지
      
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

      // 4. 구독 상태 스트림 설정 + 초기 로드
      _setupSubscriptionStateStream(); // 🔔 스트림 구독 먼저 설정
      
      if (userChoseTrial) {
        // 구매 완료를 기다린 후 확인
        await Future.delayed(const Duration(milliseconds: 1500));
      }
      
      await _loadSubscriptionState(); // 🔍 초기 상태 로드
      
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
    
    try {
      // 즉시 UI에서 해당 배너 제거
      setState(() {
        final updatedBanners = _subscriptionState.activeBanners.where((banner) => banner != bannerType).toList();
        _subscriptionState = SubscriptionState(
          entitlement: _subscriptionState.entitlement,
          subscriptionStatus: _subscriptionState.subscriptionStatus,
          hasUsedTrial: _subscriptionState.hasUsedTrial,
          hasUsageLimitReached: _subscriptionState.hasUsageLimitReached,
          activeBanners: updatedBanners,
          statusMessage: _subscriptionState.statusMessage,
        );
      });
      
      // 백그라운드에서 배너 상태 저장
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
        final activeBanners = _uiCoordinator.buildActiveBanners(
          context: context,
          activeBanners: _subscriptionState.activeBanners,
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
    );
  }
} 