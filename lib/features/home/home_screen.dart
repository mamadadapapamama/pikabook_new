import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
// 🎯 Core imports - 새로운 통합 구독 상태 관리 시스템
import '../../core/models/subscription_state.dart';                    // 통합 구독 상태 모델
import '../../core/services/subscription/subscription_status_service.dart'; // 🆕 새로운 통합 서비스 (기존 BannerManager 대체)
import '../../core/services/common/usage_limit_service.dart';          // 사용량 한도 실시간 스트림용
import '../../core/services/common/plan_service.dart';                // 플랜 변경 실시간 스트림용
import '../../core/services/trial/trial_manager.dart';                // 환영 메시지 콜백용 (기존 유지)

import '../../core/theme/tokens/color_tokens.dart';
import '../../core/theme/tokens/ui_tokens.dart';
import '../../core/widgets/pika_app_bar.dart';
import '../../core/widgets/pika_button.dart';
import '../../core/widgets/dot_loading_indicator.dart';
import '../../core/widgets/unified_banner.dart';                      // 통합 배너 위젯
import '../../core/widgets/upgrade_modal.dart';
import '../../core/widgets/image_picker_bottom_sheet.dart';

// Feature imports
import '../note/view/note_detail_screen.dart';                        // NoteDetailScreenMVVM 사용
import 'home_viewmodel.dart';                                         // HomeViewModel 사용
import 'note_list_item.dart';

/// 🏠 홈 스크린

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 🔧 서비스 인스턴스 (실시간 스트림 구독용)
  late final UsageLimitService _usageLimitService;  // 사용량 한도 실시간 감지
  late final PlanService _planService;              // 플랜 변경 실시간 감지

  // 🎯 통합 구독 상태 (단일 상태 관리)
  // ✨ 새로운: SubscriptionState 하나로 모든 상태 통합
  SubscriptionState _subscriptionState = SubscriptionState.defaultState();

  // 📡 실시간 스트림 구독 (상태 변경 감지)
  StreamSubscription<Map<String, dynamic>>? _limitStatusSubscription;  // 사용량 한도 변경
  StreamSubscription<Map<String, dynamic>>? _planChangeSubscription;   // 플랜 변경

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _initializeAsyncTasks();  // 🎯 핵심 변경: InitializationManager 호출 제거됨
  }

  @override
  void dispose() {
    // 📡 실시간 스트림 구독 해제 (메모리 누수 방지)
    _limitStatusSubscription?.cancel();
    _planChangeSubscription?.cancel();
    super.dispose();
  }

  /// 🔧 서비스 초기화 (실시간 스트림 구독용)
  void _initializeServices() {
    _usageLimitService = UsageLimitService();
    _planService = PlanService();
  }

  /// 🚀 비동기 초기화 작업 (대폭 단순화됨)
  /// - 통합 구독 상태 로드 (모든 정보 한 번에)
  /// - 환영 메시지 콜백 설정 (기존 기능 유지)
  /// - 실시간 스트림 구독 (상태 변경 감지)
  Future<void> _initializeAsyncTasks() async {
    try {
      // 🎯 구독 상태 로드 (모든 상태 정보 포함)
      // 이전: BannerManager + TrialManager + PlanService 개별 호출
      // 현재: SubscriptionStatusService 단일 호출로 모든 정보 획득
      await _loadSubscriptionStatus();
      
      // 🎉 TrialManager 환영 메시지 콜백 설정 (기존 기능 유지)
      _setupTrialWelcomeCallback();
      
      // 📡 실시간 상태 변경 스트림 구독 (새로운 기능)
      _setupRealtimeStreams();
      
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[HomeScreenRefactored] 비동기 초기화 중 오류 발생: $e');
        debugPrint('[HomeScreenRefactored] 스택 트레이스: $stackTrace');
      }
      // 🛡️ 비동기 초기화 실패는 앱 진행에 영향을 주지 않음 (Graceful degradation)
    }
  }

  /// 🎯 구독 상태 로드 (새로운 통합 서비스 사용)
  /// - SubscriptionStatusService.fetchStatus() 한 번 호출로 모든 정보 획득
  /// - 내부에서 모든 서비스를 통합 호출하여 일관성 보장
  /// 
  /// 💡 참고: 홈 화면 접근 = 이미 로그인 상태 (불필요한 로그인 체크 제거)
  Future<void> _loadSubscriptionStatus() async {
    try {
      
      if (kDebugMode) {
        debugPrint('[HomeScreenRefactored] 🎯 구독 상태 조회 시작');
      }
      
      // 🆕 SubscriptionStatusService에서 통합 상태 조회
      // forceRefresh: false → 캐시 활용하여 빠른 로딩
      final subscriptionState = await SubscriptionStatusService.fetchStatus(forceRefresh: false);
      
      // 🔄 결과 받아서 UI 업데이트 (mounted 체크로 메모리 누수 방지)
      if (mounted) {
        setState(() {
          _subscriptionState = subscriptionState;
        });
      }
      
      if (kDebugMode) {
        debugPrint('[HomeScreenRefactored] ✅ 구독 상태 로드 완료: $_subscriptionState');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[HomeScreenRefactored] ❌ 구독 상태 로드 실패: $e');
      }
      // 🛡️ 에러 발생 시에도 앱이 계속 동작하도록 함 (기본 상태 유지)
    }
  }

  /// 🎉 TrialManager 환영 메시지 콜백 설정 (기존 기능 유지)
  /// 
  /// 📝 환영 메시지만 설정:
  /// - 무료체험 시작 시 환영 메시지 표시
  /// 
  /// 🎯 변경점: TrialStatusChecker 제거 - 실시간 스트림으로 상태 변경 감지
  void _setupTrialWelcomeCallback() {
    final trialManager = TrialManager();
    
    // 🎉 환영 메시지 콜백 (TrialManager) - 기존과 동일
    trialManager.onWelcomeMessage = (title, message) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            backgroundColor: ColorTokens.snackbarBg,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.fixed,
          ),
        );
      }
    };
  }

  /// 📡 실시간 스트림 구독 설정 (새로운 기능)
  /// 🆕 새로 추가된 기능:
  /// - 사용량 한도 실시간 감지 → 즉시 배너 업데이트
  /// - 플랜 변경 실시간 감지 → 즉시 UI 상태 업데이트
  void _setupRealtimeStreams() {
    // 📊 사용량 한도 상태 변경 스트림 구독
    _limitStatusSubscription = _usageLimitService.limitStatusStream.listen(
      (limitStatus) async {
        if (mounted) {
                  if (kDebugMode) {
          debugPrint('🔔 [HomeScreen] 실시간 사용량 한도 상태 변경: $limitStatus');
        }
          
          // 🚨 사용량 한도 도달 시 상태 업데이트
          final shouldShowUsageLimit = limitStatus['ocrLimitReached'] == true || 
                                      limitStatus['ttsLimitReached'] == true;
          
          // 🔄 현재 상태와 다를 때만 업데이트 (불필요한 API 호출 방지)
          if (shouldShowUsageLimit != _subscriptionState.hasUsageLimitReached) {
            // 구독 상태 다시 로드 (통합 서비스 사용)
            await _loadSubscriptionStatus();
          }
        }
      },
      onError: (error) {
        if (kDebugMode) {
          debugPrint('❌ [HomeScreenRefactored] 사용량 한도 스트림 오류: $error');
        }
      },
    );
    
    // 💎 플랜 변경 스트림 구독
    _planChangeSubscription = _planService.planChangeStream.listen(
      (planChangeData) async {
        if (mounted) {
          if (kDebugMode) {
            debugPrint('🔔 [HomeScreenRefactored] 실시간 플랜 변경: $planChangeData');
          }
          
          // 🔄 플랜 변경 시 구독 상태 다시 로드 (통합 서비스 사용)
          await _loadSubscriptionStatus();
        }
      },
      onError: (error) {
        if (kDebugMode) {
          debugPrint('❌ [HomeScreenRefactored] 플랜 변경 스트림 오류: $error');
        }
      },
    );
    
    if (kDebugMode) {
      debugPrint('✅ [HomeScreenRefactored] 실시간 스트림 구독 설정 완료');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UITokens.screenBackground,
      appBar: PikaAppBar.home(),
      body: Consumer<HomeViewModel>(
        builder: (context, viewModel, _) {
          if (viewModel.isLoading && viewModel.notes.isEmpty) {
            return _buildLoadingState();
          }

          if (viewModel.notes.isEmpty) {
            return _buildZeroState(context);
          }

          return _buildNotesList(context, viewModel);
        },
      ),
      floatingActionButton: Consumer<HomeViewModel>(
        builder: (context, viewModel, _) {
          final isDisabled = _subscriptionState.hasUsageLimitReached;
          return Container(
            width: 200, // width 제한
            margin: const EdgeInsets.symmetric(horizontal: 24),
            child: isDisabled 
              ? Tooltip(
                  message: '사용량 한도 초과로 비활성화되었습니다',
                  child: PikaButton(
                    text: _getBottomButtonText(viewModel),
                    onPressed: null, // 비활성화
                    variant: PikaButtonVariant.primary,
                    isFullWidth: false, // width 제한으로 변경
                  ),
                )
              : PikaButton(
                  text: _getBottomButtonText(viewModel),
                  onPressed: () => _handleBottomButtonPressed(viewModel),
                  variant: PikaButtonVariant.primary,
                  isFullWidth: false, // width 제한으로 변경
                ),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  /// 로딩 상태 위젯
  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DotLoadingIndicator(),
          SizedBox(height: 16),
          Text(
            '노트를 불러오는 중...',
            style: TextStyle(
              fontSize: 16,
              color: ColorTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// 제로 상태 위젯 (배너 포함)
  Widget _buildZeroState(BuildContext context) {
    return Consumer<HomeViewModel>(
      builder: (context, viewModel, _) {
        return Column(
          children: [
            // 🎯 활성 배너들 표시
            ..._buildActiveBanners(),
            
            // 제로 스테이트 콘텐츠
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/zeronote.png',
                      width: 200,
                      height: 200,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '먼저, 번역이 필요한\n이미지를 올려주세요.',
                      style: GoogleFonts.notoSans(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: ColorTokens.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '이미지를 기반으로 학습 노트를 만들어드립니다. \n카메라 촬영도 가능합니다.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: const Color(0xFF969696), // #969696
                      ),
                    ),
                const SizedBox(height: 32), // 간격만 유지
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 노트 리스트 위젯 (배너 포함)
  Widget _buildNotesList(BuildContext context, HomeViewModel viewModel) {
    return Column(
      children: [
        // 🎯 활성 배너들 표시
        ..._buildActiveBanners(),
        
        // 노트 리스트
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await viewModel.refreshNotes();
              await _loadSubscriptionStatus(); // 구독 상태도 함께 새로고침
            },
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
              itemCount: viewModel.notes.length,
              itemBuilder: (context, index) {
                final note = viewModel.notes[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: NoteListItem(
                    note: note,
                    onDismissed: () => _deleteNote(viewModel, note),
                    onNoteTapped: (selectedNote) => _navigateToNoteDetail(selectedNote),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// 🎯 활성 배너들 표시 (통합 배너 시스템)
  /// - SubscriptionState.activeBanners에서 중앙 집중식 관리
  /// - 모든 배너가 동일한 상태 정보 기반으로 표시
  /// - UnifiedBanner 위젯으로 일관된 UI 제공
  List<Widget> _buildActiveBanners() {
    final banners = <Widget>[];
    
    // 🎯 통합 구독 상태에서 활성 배너 목록 가져오기
    for (final bannerType in _subscriptionState.activeBanners) {
      final bannerData = _getBannerData(bannerType);
      banners.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: UnifiedBanner(
            icon: bannerData['icon'],
            iconColor: bannerData['iconColor'],
            title: bannerData['title'],
            subtitle: bannerData['subtitle'],
            mainButtonText: bannerData['buttonText'],
            onMainButtonPressed: bannerData['buttonText'] != null 
                ? () => _showUpgradeModal(bannerType) 
                : null,
            onDismiss: () {
              // 🔄 배너 해제 로직 (필요시 구현)
              // 현재는 서버 상태 기반이므로 로컬에서 해제하지 않음
            },
          ),
        ),
      );
    }
    
    return banners;
  }

  /// 🎨 배너 타입별 데이터 반환 (UI 설정)
  /// 
  /// 📝 각 배너 타입에 따른 아이콘, 색상, 텍스트 설정
  /// BannerType enum과 1:1 매핑되어 일관성 보장
  Map<String, dynamic> _getBannerData(BannerType bannerType) {
    switch (bannerType) {
      case BannerType.usageLimit:
        return {
          'icon': Icons.warning_rounded,
          'iconColor': Colors.orange,
          'title': '사용량 한도 도달',
          'subtitle': '더 많은 기능을 사용하려면 프리미엄으로 업그레이드하세요',
          'buttonText': '업그레이드',
        };
      case BannerType.trialCompleted:
        return {
          'icon': Icons.star_rounded,
          'iconColor': Colors.blue,
          'title': '무료체험 완료',
          'subtitle': '계속 사용하려면 프리미엄으로 업그레이드하세요',
          'buttonText': '업그레이드',
        };
      case BannerType.premiumExpired:
        return {
          'icon': Icons.diamond_rounded,
          'iconColor': Colors.purple,
          'title': '프리미엄 만료',
          'subtitle': '프리미엄 기능을 계속 사용하려면 구독을 갱신하세요',
          'buttonText': '갱신하기',
        };
      default:
        return {
          'icon': Icons.info_rounded,
          'iconColor': Colors.grey,
          'title': '알림',
          'subtitle': '새로운 소식이 있습니다',
          'buttonText': null,
        };
    }
  }

  /// 💎 업그레이드 모달 표시
  /// 
  /// 🔄 BannerType을 UpgradeReason으로 변환하여 적절한 모달 표시
  /// 각 배너 타입에 따라 다른 업그레이드 이유와 메시지를 제공
  void _showUpgradeModal(BannerType bannerType) {
    // 🔄 BannerType을 UpgradeReason으로 변환
    UpgradeReason reason;
    switch (bannerType) {
      case BannerType.usageLimit:
        reason = UpgradeReason.limitReached;      // 사용량 한도 도달
        break;
      case BannerType.trialCompleted:
        reason = UpgradeReason.trialExpired;      // 무료체험 완료
        break;
      case BannerType.premiumExpired:
        reason = UpgradeReason.trialExpired;      // 프리미엄 만료 (체험 만료와 동일 처리)
        break;
      default:
        reason = UpgradeReason.general;           // 일반 업그레이드
    }

    // 🎯 업그레이드 모달 표시
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => UpgradeModal(reason: reason),
    );
  }

  /// 📝 하단 버튼 텍스트 결정 (수정됨)
  String _getBottomButtonText(HomeViewModel viewModel) {
    if (viewModel.notes.isEmpty) {
      return '이미지 올리기'; // 제로 상태일 때
    } else {
      return '스마트 노트 만들기'; // 노트가 있을 때
    }
  }

  /// 🎯 하단 버튼 눌림 처리 (기존과 동일)
  /// 
  /// 📝 노트 생성 프로세스:
  /// 1. 이미지 선택 바텀시트 표시
  /// 2. 사용자가 이미지 선택
  /// 3. OCR 처리 및 노트 생성
  void _handleBottomButtonPressed(HomeViewModel viewModel) {
    _showImagePickerBottomSheet();
  }

  /// 📷 이미지 선택 바텀시트 표시 (기존과 동일)
  void _showImagePickerBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const ImagePickerBottomSheet(),
    );
  }

  /// 📖 노트 상세 화면으로 이동 (기존과 동일)
  /// 
  /// 🎯 NoteDetailScreenMVVM.route() 사용으로 MVVM 패턴 유지
  void _navigateToNoteDetail(note) {
    Navigator.push(
      context,
      NoteDetailScreenMVVM.route(note: note),
    );
  }

  /// 🗑️ 노트 삭제 (기존과 동일)
  /// 
  /// 📝 HomeViewModel을 통해 노트 삭제 처리
  /// UI 업데이트는 Provider 패턴으로 자동 반영
  void _deleteNote(HomeViewModel viewModel, note) {
    viewModel.deleteNote(note.id);
  }
} 