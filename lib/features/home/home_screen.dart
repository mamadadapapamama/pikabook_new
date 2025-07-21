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
import '../../core/widgets/upgrade_modal.dart'; // 🎯 UpgradeModal 추가

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
  // 🗑️ 제거: 더 이상 필요 없는 중복 호출 방지 플래그
  // bool _hasSetupUsageLimitStream = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kDebugMode) {
      debugPrint('🔄 [HomeScreen] 화면 초기화 시작');
    }
    
    _initializeScreen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 위젯 업데이트 감지 (구독 상태 변경 시)
  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // ✅ Equatable 덕분에 이제 이 비교는 내용 기반으로 정확하게 이루어집니다.
    if (oldWidget.subscriptionState != widget.subscriptionState && 
        _homeViewModel != null && 
        !_isNewUser) {
      
      if (kDebugMode) {
        debugPrint('🔄 [HomeScreen] 구독 상태 변경 감지 - HomeViewModel에 알림');
        debugPrint('   이전: ${oldWidget.subscriptionState}');
        debugPrint('   현재: ${widget.subscriptionState}');
      }
      
      // HomeViewModel에 구독 상태 전달
      _homeViewModel!.setupUsageLimitStreamWithSubscriptionState(widget.subscriptionState);
    }
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
      // 사용자 상태 확인
      final userStatus = await _determineUserStatus();
      
      if (kDebugMode) {
        debugPrint('🔍 [HomeScreen] 사용자 상태 결정: $userStatus');
      }
      
      // HomeViewModel 초기화
      _homeViewModel = HomeViewModel(isNewUser: userStatus == '신규');
      
      if (kDebugMode) {
        debugPrint('✅ [HomeScreen] 화면 초기화 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [HomeScreen] 화면 초기화 실패: $e');
      }
    }
  }

  /// 🎯 사용자 상태 결정 - 환영 모달 본 적 있는지 확인
  Future<String> _determineUserStatus() async {
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
        // 🎉 신규 사용자 환영 모달 표시
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) {
              _showWelcomeModal();
            }
          });
        });
        return '신규';
      } else {
        return '기존';
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [HomeScreen] 사용자 상태 결정 실패: $e');
      }
      _isNewUser = true;
      return '신규';
    }
  }

  /// 🎉 환영 모달 표시
  void _showWelcomeModal() {
    if (kDebugMode) {
      debugPrint('🎉 [HomeScreen] 환영 모달 표시');
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false, // 온보딩 후에는 반드시 선택하도록
      builder: (context) => UpgradeModal(reason: UpgradeReason.welcomeTrial),
    ).then((result) async {
      if (kDebugMode) {
        debugPrint('✅ [HomeScreen] 환영 모달 완료');
      }
      
      // 🎯 환영 모달 완료 기록을 Firestore에 저장
      try {
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .set({
            'hasSeenWelcomeModal': true,
          }, SetOptions(merge: true));
          
          if (kDebugMode) {
            debugPrint('✅ [HomeScreen] 환영 모달 완료 기록 저장 완료');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ [HomeScreen] 환영 모달 완료 기록 저장 실패: $e');
        }
      }
    });
  }

  /// 🎯 기본 상태 설정
  void _setDefaultState() {
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
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
      // 백그라운드에서 배너 상태 저장 -> 이로 인해 스트림이 업데이트되고 App.dart를 통해 HomeScreen에 전달됨
      await _uiCoordinator.dismissBanner(bannerType);
      
      // 🎯 배너 닫기 후 즉시 UI 업데이트
      if (mounted) {
        setState(() {
          // FutureBuilder가 재실행되어 필터링된 배너 목록을 다시 빌드함
        });
      }
      
      if (kDebugMode) {
        debugPrint('✅ [HomeScreen] 배너 닫기 완료: ${bannerType.name}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [HomeScreen] 배너 닫기 실패: $e');
      }
    }
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
            
            return FutureBuilder<List<Widget>>(
              future: _uiCoordinator.buildActiveBanners(
                context: context,
                activeBanners: widget.subscriptionState.activeBanners
                    .map((name) {
                      try {
                        return BannerType.values.firstWhere((e) => e.name == name);
                      } catch (e) {
                        if (kDebugMode) {
                          debugPrint('⚠️ [HomeScreen] 알 수 없는 배너 타입: $name');
                        }
                        return null;
                      }
                    })
                    .where((e) => e != null)
                    .cast<BannerType>()
                    .toList(),
                onShowUpgradeModal: _onShowUpgradeModal,
                onDismissBanner: _onDismissBanner,
              ),
              builder: (context, snapshot) {
                final activeBanners = snapshot.data ?? [];
                
                if (kDebugMode) {
                  debugPrint('🏠 [HomeScreen] 배너 상태:');
                  debugPrint('   - 구독 상태 배너: ${widget.subscriptionState.activeBanners}');
                  debugPrint('   - 변환된 BannerType: ${widget.subscriptionState.activeBanners.map((name) => BannerType.values.where((e) => e.name == name).toList()).toList()}');
                  debugPrint('   - 최종 표시될 배너 위젯 수: ${activeBanners.length}');
                }

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
          },
        ),
        floatingActionButton: const HomeFloatingButton(),
      ),
    );
  }
} 