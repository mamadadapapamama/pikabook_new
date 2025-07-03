import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/utils/subscription_debug_helper.dart';
// 🎯 Core imports - 새로운 통합 구독 상태 관리 시스템
import '../../core/models/subscription_state.dart';                    // 통합 구독 상태 모델
import '../../core/services/subscription/app_store_subscription_service.dart'; // 🆕 App Store 기반 구독 서비스
import '../../core/services/common/usage_limit_service.dart';          // 사용량 한도 실시간 스트림용



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
import '../../core/services/common/banner_manager.dart';

/// 🏠 홈 스크린

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // 🔧 서비스 인스턴스 (실시간 스트림 구독용)
  late final UsageLimitService _usageLimitService;  // 사용량 한도 실시간 감지

  // 🎯 통합 구독 상태 (단일 상태 관리)
  SubscriptionState _subscriptionState = SubscriptionState.defaultState();
  
  // 초기 로드 완료 여부 추적
  bool _hasInitialLoad = false;

  // 📡 실시간 스트림 구독 (상태 변경 감지)
  StreamSubscription<Map<String, dynamic>>? _limitStatusSubscription;  // 사용량 한도 변경

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // 앱 생명주기 관찰
    _initializeServices();
    _initializeAsyncTasks();
  }

  @override
  void dispose() {
    // 📡 실시간 스트림 구독 해제 (메모리 누수 방지)
    _limitStatusSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this); // 앱 생명주기 관찰 해제
    super.dispose();
  }

  /// 앱 생명주기 변경 감지 (백그라운드 → 포그라운드 복귀 시 구독 상태 확인)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      // 앱이 포그라운드로 복귀했을 때 구독 상태 새로고침
      if (kDebugMode) {
        debugPrint('🔄 [HomeScreen] 앱 포그라운드 복귀 - 구독 상태 새로고침');
      }
      _loadSubscriptionStatus(forceRefresh: true);
    }
  }

  /// 🔧 서비스 초기화 (실시간 스트림 구독용)
  void _initializeServices() {
    _usageLimitService = UsageLimitService();
  }

  /// 🚀 비동기 초기화 작업 (간소화)
  Future<void> _initializeAsyncTasks() async {
    try {
      // 🎯 구독 상태 로드 (백그라운드에서 실행)
      _loadSubscriptionStatus();
      
      // 📡 실시간 스트림 구독
      _setupRealtimeStreams();
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[HomeScreen] 초기화 오류: $e');
      }
    }
  }

  /// 🎯 구독 상태 로드 (App Store 기반) - 캐시 우선 최적화
  Future<void> _loadSubscriptionStatus({bool forceRefresh = false}) async {
    try {
      // 🎯 초기 로드 시에는 캐시만 사용 (App.dart에서 이미 조회했음)
      // 포그라운드 복귀나 명시적 새로고침 요청시에만 API 호출
      final shouldUseCache = !forceRefresh && !_hasInitialLoad;
      
      if (kDebugMode) {
        debugPrint('[HomeScreen] 구독 상태 조회 (캐시우선: $shouldUseCache, forceRefresh: $forceRefresh)');
      }
      
      final appStoreService = AppStoreSubscriptionService();
      final subscriptionState = await appStoreService.getUnifiedSubscriptionState(
        forceRefresh: forceRefresh,  // 명시적 새로고침 요청시에만 API 호출
      );
      
      // 초기 로드 완료 표시
      if (!_hasInitialLoad) {
        _hasInitialLoad = true;
        if (kDebugMode) {
          debugPrint('✅ [HomeScreen] 초기 로드 완료 - 캐시에서 로드됨');
        }
      }
      
      // 🔄 결과 받아서 UI 업데이트 (mounted 체크로 메모리 누수 방지)
      if (mounted) {
        setState(() {
          _subscriptionState = subscriptionState;
        });
      }
      
      if (kDebugMode) {
        debugPrint('[HomeScreen] ✅ 구독 상태 로드 완료: $_subscriptionState');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[HomeScreen] ❌ 구독 상태 로드 실패: $e');
      }
    }
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
    
          if (kDebugMode) {
      debugPrint('✅ [HomeScreen] 실시간 스트림 구독 설정 완료 (사용량 한도만)');
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
    return Stack(
      children: [
        // 📝 노트 리스트 (전체 화면)
        RefreshIndicator(
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
        
        // 🎯 플로팅 배너들 (노트 리스트 위에 겹쳐서 표시)
        if (_subscriptionState.activeBanners.isNotEmpty)
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Column(
              children: _buildActiveBanners(),
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
    
    if (kDebugMode) {
      debugPrint('🎯 [HomeScreen] _buildActiveBanners 호출');
      debugPrint('   전체 활성 배너 수: ${_subscriptionState.activeBanners.length}');
      debugPrint('   배너 목록: ${_subscriptionState.activeBanners.map((e) => e.name).toList()}');
    }
    
    // 🎯 통합 구독 상태에서 활성 배너 목록 가져오기
    for (final bannerType in _subscriptionState.activeBanners) {
      final bannerData = _getBannerData(bannerType);
      
      if (kDebugMode) {
        debugPrint('🎯 [HomeScreen] 배너 위젯 생성: ${bannerType.name}');
        debugPrint('   제목: ${bannerData['title']}');
        debugPrint('   부제목: ${bannerData['subtitle']}');
        debugPrint('   버튼 텍스트: ${bannerData['buttonText']}');
      }
      
      banners.add(
        UnifiedBanner(
          title: bannerData['title'],
          subtitle: bannerData['subtitle'],
          mainButtonText: bannerData['buttonText'],
          onMainButtonPressed: bannerData['buttonText'] != null 
              ? () => _showUpgradeModal(bannerType) 
              : null,
          onDismiss: () {
            if (kDebugMode) {
              debugPrint('🚫 [HomeScreen] 배너 닫기 버튼 클릭: ${bannerType.name}');
            }
            _dismissBanner(bannerType);
          },
        ),
      );
    }
    
    if (kDebugMode) {
      debugPrint('🎯 [HomeScreen] 생성된 배너 위젯 수: ${banners.length}');
    }
    
    return banners;
  }

  /// 🎨 배너 타입별 데이터 반환 (BannerManager extension 사용)
  Map<String, dynamic> _getBannerData(BannerType bannerType) {
    // 🎯 BannerManager의 BannerTypeExtension 사용
    String? buttonText;
    switch (bannerType) {
      case BannerType.usageLimitFree:
      case BannerType.trialCancelled:
      case BannerType.premiumExpired:
        buttonText = '업그레이드';
        break;
      case BannerType.usageLimitPremium:
        buttonText = '문의하기';
        break;
      case BannerType.trialCompleted:
        buttonText = null; // 닫기만 가능
        break;
    }

    return {
      'title': bannerType.title,
      'subtitle': bannerType.subtitle,
      'buttonText': buttonText,
    };
  }

  /// 💎 업그레이드 모달 표시
  /// 
  /// 🔄 BannerType을 UpgradeReason으로 변환하여 적절한 모달 표시
  /// 각 배너 타입에 따라 다른 업그레이드 이유와 메시지를 제공
  void _showUpgradeModal(BannerType bannerType) {
    // 🚨 이미 업그레이드 모달이 표시 중이면 중복 호출 방지
    if (UpgradeModal.isShowing) {
      if (kDebugMode) {
        debugPrint('⚠️ [HomeScreen] 업그레이드 모달이 이미 표시 중입니다. 중복 호출 방지');
      }
      return;
    }

    // 🔄 BannerType을 UpgradeReason으로 변환
    UpgradeReason reason;
    switch (bannerType) {
      case BannerType.usageLimitFree:
        reason = UpgradeReason.limitReached;      // 무료 플랜 사용량 한도 도달
        break;
      case BannerType.usageLimitPremium:
        // 프리미엄 플랜 사용량 한도 → 문의 폼으로 처리
        _showContactForm();
        return;
      case BannerType.trialCompleted:
        reason = UpgradeReason.trialExpired;      // 무료체험 완료
        break;
      case BannerType.trialCancelled:
        reason = UpgradeReason.trialExpired;      // 프리미엄 체험 만료
        break;
      case BannerType.premiumExpired:
        reason = UpgradeReason.trialExpired;      // 프리미엄 만료 (체험 만료와 동일 처리)
        break;
      default:
        reason = UpgradeReason.general;           // 일반 업그레이드
    }

    if (kDebugMode) {
      debugPrint('🎯 [HomeScreen] 업그레이드 모달 표시: ${reason.name} (bannerType: ${bannerType.name})');
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

  /// 📧 문의 폼 표시 (프리미엄 사용자용)
  Future<void> _showContactForm() async {
    const formUrl = 'https://docs.google.com/forms/d/e/1FAIpQLSfgVL4Bd5KcTh9nhfbVZ51yApPAmJAZJZgtM4V9hNhsBpKuaA/viewform?usp=dialog';
    
    try {
      final Uri uri = Uri.parse(formUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('문의 폼을 열 수 없습니다.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('문의 폼을 여는 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 🚫 배너 닫기 처리
  Future<void> _dismissBanner(BannerType bannerType) async {
    try {
      if (kDebugMode) {
        debugPrint('🚫 [HomeScreen] 배너 닫기 시작: ${bannerType.name}');
      }
      
      final bannerManager = BannerManager();
      await bannerManager.dismissBanner(bannerType);
      
      if (kDebugMode) {
        debugPrint('✅ [HomeScreen] 배너 닫기 완료: ${bannerType.name}');
      }
      
      // 🎯 현재 상태에서 해당 배너만 제거하여 UI 업데이트
      // _loadSubscriptionStatus() 호출하지 않음 (BannerManager.getActiveBanners() 재호출 방지)
      if (mounted) {
        setState(() {
          _subscriptionState = SubscriptionState(
            isTrial: _subscriptionState.isTrial,
            isTrialExpiringSoon: _subscriptionState.isTrialExpiringSoon,
            isPremium: _subscriptionState.isPremium,
            isExpired: _subscriptionState.isExpired,
            hasUsageLimitReached: _subscriptionState.hasUsageLimitReached,
            daysRemaining: _subscriptionState.daysRemaining,
            activeBanners: _subscriptionState.activeBanners.where((banner) => banner != bannerType).toList(),
            statusMessage: _subscriptionState.statusMessage,
          );
        });
      }
      
      if (kDebugMode) {
        debugPrint('🔄 [HomeScreen] 배너 닫기 후 UI 업데이트 완료');
        debugPrint('   남은 배너: ${_subscriptionState.activeBanners.map((e) => e.name).toList()}');
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [HomeScreen] 배너 닫기 실패: $e');
      }
    }
  }

} 