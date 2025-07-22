import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

// 🎯 Core imports
import '../../core/models/subscription_state.dart';
import '../../core/services/subscription/unified_subscription_manager.dart';
import '../../core/theme/tokens/ui_tokens.dart';
import '../../core/widgets/pika_app_bar.dart';
import '../../core/widgets/dot_loading_indicator.dart';
import '../../core/models/banner_type.dart';
import '../../core/widgets/welcome_modal.dart'; // 🎯 WelcomeModal 추가
import '../../core/constants/feature_flags.dart';

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
      
      // 로딩 상태 해제
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      
      if (kDebugMode) {
        debugPrint('✅ [HomeScreen] 화면 초기화 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [HomeScreen] 화면 초기화 실패: $e');
      }
      
      // 에러 발생 시에도 로딩 상태 해제
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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
      debugPrint('🎉 [HomeScreen] 환영 모달 표시 시도');
    }

    // 🎯 Feature Flag 체크
    if (!FeatureFlags.WELCOME_MODAL_ENABLED) {
      if (kDebugMode) {
        debugPrint('🚫 [HomeScreen] 환영 모달 비활성화됨 - 바로 완료 처리');
      }
      _completeWelcomeModal();
      return;
    }

    WelcomeModal.show(context).then((result) async {
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

  /// 🎯 환영 모달 완료 처리 (Feature Flag 비활성화 시 사용)
  void _completeWelcomeModal() async {
    if (kDebugMode) {
      debugPrint('✅ [HomeScreen] 환영 모달 완료 (Feature Flag로 스킵됨)');
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
          debugPrint('✅ [HomeScreen] 환영 모달 완료 기록 저장 완료 (스킵됨)');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [HomeScreen] 환영 모달 완료 기록 저장 실패: $e');
      }
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
    _uiCoordinator.showUpgradeModal(context, bannerType, subscriptionState: widget.subscriptionState);
  }

  /// 배너 닫기 (즉시 UI 업데이트)
  void _onDismissBanner(BannerType bannerType) async {
    if (kDebugMode) {
      debugPrint('🚫 [HomeScreen] 배너 닫기 시작: ${bannerType.name}');
    }
    
    try {
      // 배너 상태 저장
      await _uiCoordinator.dismissBanner(bannerType);
      
      // 🎯 배너 닫기 후 즉시 UI 업데이트 (FutureBuilder 강제 재빌드)
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
            
            // 🚨 FutureBuilder 전에 먼저 로그 출력
            if (kDebugMode) {
              debugPrint('🏠 [HomeScreen] 배너 상태 (FutureBuilder 전):');
              debugPrint('   - 구독 상태: ${widget.subscriptionState.toString()}');
              debugPrint('   - Plan: ${widget.subscriptionState.plan.id} (isPremium: ${widget.subscriptionState.plan.isPremium})');
              debugPrint('   - Status: ${widget.subscriptionState.status.name}');
              debugPrint('   - HasUsedTrial: ${widget.subscriptionState.hasUsedTrial}');
              debugPrint('   - 🎯 원본 배너 리스트: ${widget.subscriptionState.activeBanners}');
            }

            final convertedBanners = widget.subscriptionState.activeBanners
                .map((name) {
                  try {
                    final bannerType = BannerType.values.firstWhere((e) => e.name == name);
                    if (kDebugMode) {
                      debugPrint('   - ✅ 배너 변환 성공: "$name" → ${bannerType.name}');
                    }
                    return bannerType;
                  } catch (e) {
                    if (kDebugMode) {
                      debugPrint('   - ❌ 알 수 없는 배너 타입: "$name"');
                    }
                    return null;
                  }
                })
                .where((e) => e != null)
                .cast<BannerType>()
                .toList();

            if (kDebugMode) {
              debugPrint('   - 변환된 BannerType 목록: ${convertedBanners.map((e) => e.name).toList()}');
            }

            // 🎯 Feature Flag에 따라 배너 표시 여부 결정
            return FutureBuilder<List<Widget>>(
              future: FeatureFlags.SUBSCRIPTION_BANNERS_ENABLED 
                  ? _uiCoordinator.buildActiveBanners(
                      context: context,
                      activeBanners: convertedBanners,
                      onShowUpgradeModal: _onShowUpgradeModal,
                      onDismissBanner: _onDismissBanner,
                    )
                  : Future.value(<Widget>[]), // 빈 배너 리스트 반환
              builder: (context, bannerSnapshot) {
                if (kDebugMode) {
                  debugPrint('🏠 [HomeScreen] FutureBuilder 결과:');
                  debugPrint('   - connectionState: ${bannerSnapshot.connectionState}');
                  debugPrint('   - hasData: ${bannerSnapshot.hasData}');
                  debugPrint('   - 배너 위젯 수: ${bannerSnapshot.data?.length ?? 0}');
                  if (bannerSnapshot.hasError) {
                    debugPrint('   - 에러: ${bannerSnapshot.error}');
                  }
                }

                final bannerWidgets = bannerSnapshot.data ?? <Widget>[];

                // 🎯 Feature Flag에 따라 배너 필터링
                final filteredBanners = FeatureFlags.SUBSCRIPTION_BANNERS_ENABLED 
                    ? bannerWidgets 
                    : <Widget>[];

                if (hasNotes) {
                  // 노트가 있는 경우 - 노트 리스트 표시
                  return HomeNotesList(
                    activeBanners: filteredBanners,
                    onRefresh: _onRefresh,
                  );
                } else {
                  // 노트가 없는 경우 - 제로 상태 표시
                  return HomeZeroState(
                    activeBanners: filteredBanners,
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