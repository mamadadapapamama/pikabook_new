import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';
import 'firebase_options.dart';
import 'dart:async';
import 'views/screens/login_screen.dart';
import 'features/home/home_screen_mvvm.dart'; 
import 'views/screens/onboarding_screen.dart';
import 'core/services/common/initialization_manager.dart';
import 'core/services/authentication/user_preferences_service.dart';
import 'core/services/common/plan_service.dart';
import 'core/services/common/usage_limit_service.dart';
import 'core/widgets/usage_dialog.dart';
import 'widgets/loading_screen.dart';
import 'core/services/marketing/marketing_campaign_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/tokens/color_tokens.dart';
import 'package:url_launcher/url_launcher.dart';
import 'features/sample/sample_mode_service.dart';
import 'features/sample/sample_home_screen.dart';

/// 오버스크롤 색상을 지정하는 커스텀 스크롤 비헤이비어
class CustomScrollBehavior extends ScrollBehavior {
  const CustomScrollBehavior();
  
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return GlowingOverscrollIndicator(
      axisDirection: details.direction,
      color: ColorTokens.primaryverylight, // 오버스크롤 색상을 primaryverylight로 변경
      child: child,
    );
  }
}

/// 앱의 시작 지점 및 초기 화면 결정 로직
/// - 로그인 확인
/// - 온보딩 확인
/// - Firebase 초기화

class App extends StatefulWidget {
  const App({Key? key}) : super(key: key);

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  bool _isInitialized = false;
  bool _isLoading = true;
  bool _isOnboardingCompleted = false;
  bool _isLoadingUserData = false;
  bool _isSampleMode = false;
  String? _userId;
  User? _user;
  StreamSubscription<User?>? _authStateSubscription;
  late InitializationManager _initializationManager;
  late UserPreferencesService _preferencesService;
  final UsageLimitService _usageLimitService = UsageLimitService();
  final SampleModeService _sampleModeService = SampleModeService();
  String? _error;
  final MarketingCampaignService _marketingService = MarketingCampaignService();
  final PlanService _planService = PlanService();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  
  bool _ttsExceed = false;
  bool _noteExceed = false;
  
  // 사용량 한도 다이얼로그 표시 여부 추적
  bool _hasShownUsageLimitDialog = false;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // 디버그 타이머 비활성화 (디버그 모드에서만)
    if (kDebugMode) {
      timeDilation = 1.0;
    }
    
    // 시스템 UI 조정
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    
    // 상태표시줄 설정
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      );
    });
    
    // 초기화 로직 시작
    _preferencesService = UserPreferencesService();
    _initializationManager = InitializationManager();
    _initializeApp();
  }
  
  @override
  void dispose() {
    _authStateSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 테마나 로케일 같은 의존성이 변경되었을 때 호출됩니다
    if (_isInitialized && mounted) {
      // 필요한 리소스 다시 로드
    }
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 앱 라이프사이클 상태 관리
    if (state == AppLifecycleState.resumed) {
      // 앱이 포그라운드로 돌아왔을 때
      _checkSampleMode();
    } else if (state == AppLifecycleState.paused) {
      // 앱이 백그라운드로 갔을 때
    }
  }
  
  /// 앱 초기화 로직
  Future<void> _initializeApp() async {
    try {
      // Firebase 초기화는 InitializationManager에서 처리하도록 변경
      if (kDebugMode) {
        debugPrint('앱: 초기화 시작');
      }
      
      // 공통 서비스 초기화 (Firebase 포함)
      final initResult = await _initializationManager.initialize();
      
      // 마케팅 캠페인 서비스 초기화 (필요 시에만)
      await _marketingService.initialize();
      
      // 초기화 결과에서 로그인 정보 가져오기
      final isLoggedIn = initResult['isLoggedIn'] as bool;
      final isOnboardingCompleted = initResult['isOnboardingCompleted'] as bool;
      
      // 샘플 모드 상태 확인 (앱 특화 로직)
      await _checkSampleMode();
      
      // 인증 상태 관찰 설정
      _setupAuthStateListener();
      
      // 초기화 상태 업데이트
      setState(() {
        _isInitialized = true;
        _isLoading = !_isSampleMode; // 샘플 모드가 아니면 계속 로딩
      });
      
      if (kDebugMode) {
        debugPrint('앱: 초기화 완료 (로그인: $isLoggedIn, 온보딩 완료: $isOnboardingCompleted)');
      }
    } catch (e) {
      // 초기화 실패 처리
      if (kDebugMode) {
        debugPrint('앱: 초기화 실패 - $e');
      }
      setState(() {
        _error = '앱 초기화 중 오류가 발생했습니다: $e';
        _isInitialized = false;
        _isLoading = false;
      });
    }
  }
  
  /// 샘플 모드 확인
  Future<void> _checkSampleMode() async {
    try {
      // 로그인한 사용자가 있으면 샘플 모드 강제 비활성화
      if (_user != null) {
        if (kDebugMode) {
          debugPrint('[checkSampleMode] 로그인 사용자 감지, 샘플 모드 강제 비활성화');
        }
        await _sampleModeService.disableSampleMode();
        if (mounted) {
          setState(() {
            _isSampleMode = false;
          });
        }
        return;
      }
      
      final isSampleMode = await _sampleModeService.isSampleModeEnabled();
      if (kDebugMode) {
        debugPrint('[checkSampleMode] 샘플 모드 상태: $isSampleMode');
      }
      
      if (mounted) {
        setState(() {
          _isSampleMode = isSampleMode;
          // 샘플 모드이면 로딩 상태 해제
          if (isSampleMode) {
            if (kDebugMode) {
              debugPrint('[checkSampleMode] 샘플 모드 활성화 확인, 로딩 상태 해제');
            }
            _isLoading = false;
            _isLoadingUserData = false;
          }
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[checkSampleMode] 샘플 모드 확인 중 오류: $e');
      }
      // 오류 발생 시 샘플 모드 비활성화 상태로 설정
      if (mounted) {
        setState(() {
          _isSampleMode = false;
        });
      }
    }
  }
  
  /// 사용자 인증 상태 관찰 설정
  void _setupAuthStateListener() {
    if (kDebugMode) {
      debugPrint('앱: 인증 상태 변경 리스너 설정');
    }
    
    try {
      // Firebase Auth 상태 변경 감지
      _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen(
        (User? user) async {
          if (!mounted) return;
          
          if (kDebugMode) {
            debugPrint('앱: 인증 상태 변경 감지: ${user != null ? "로그인" : "로그아웃"}');
          }
          
          // 사용자 로그인/로그아웃 처리
          if (user != null) {
            // 로그인 처리
            if (_isSampleMode) {
              await _sampleModeService.disableSampleMode();
              _isSampleMode = false;
            }
            
            setState(() {
              _user = user;
              _userId = user.uid;
              _isLoading = false;
              _isLoadingUserData = true;
            });
            
            // 사용자 데이터 로드
            await _loadUserPreferences();
          } else {
            // 로그아웃 처리
            await _checkSampleMode();
            
            setState(() {
              _user = null;
              _userId = null;
              _isOnboardingCompleted = false;
              _isLoading = false;
              _isLoadingUserData = false;
            });
          }
        },
        onError: (error, stackTrace) {
          if (kDebugMode) {
            debugPrint('앱: 인증 상태 감지 오류: $error');
          }
          
          if (mounted) {
            setState(() {
              _isLoading = false;
              _isLoadingUserData = false;
              _error = '인증 상태 확인 중 오류 발생: $error';
            });
          }
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('앱: 인증 리스너 설정 오류: $e');
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = '인증 상태 변경 리스너 설정 중 오류 발생: $e';
          });
        }
      }
  }
  
  /// 사용자 로그인 후 처리 로직
  Future<void> _loadUserPreferences() async {
    if (!mounted) return;
    
    if (kDebugMode) {
      debugPrint('[loadUserPreferences] 시작');
    }
    
    try {
      if (_userId == null) {
        setState(() {
          _isLoadingUserData = false;
          _isLoading = false;
        });
        return;
      }
      
      // 샘플 모드 비활성화 확인
      if (_isSampleMode) {
        await _sampleModeService.disableSampleMode();
        _isSampleMode = false;
      }
      
      // 사용자 데이터 로드
      await _preferencesService.setCurrentUserId(_userId!);
      await _preferencesService.loadUserSettingsFromFirestore();
  
      // 노트 존재 여부 확인 및 온보딩 상태 설정
      bool hasNotes = await _checkUserHasNotes();
      if (hasNotes) {
        await _preferencesService.setOnboardingCompleted(true);
        _isOnboardingCompleted = true;
      } else {
        _isOnboardingCompleted = await _preferencesService.getOnboardingCompleted();
      }
      
      // 사용량 제한 확인
      await _checkUsageLimits();
      
      // 상태 업데이트
      if (mounted) {
        setState(() {
          _isLoadingUserData = false;
          _isLoading = false;
        });
        
        // 플랜 변경 체크
        await _checkPlanChange();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[loadUserPreferences] 오류: $e');
      }
      if (mounted) {
        setState(() {
          _error = '사용자 데이터 로드 중 오류: $e';
          _isLoadingUserData = false;
          _isLoading = false;
        });
      }
    }
  }
  
  /// 사용자가 노트를 가지고 있는지 확인
  Future<bool> _checkUserHasNotes() async {
    try {
      if (_userId == null) return false;
      
      // Firestore에서 사용자의 노트 수 확인
      final notesSnapshot = await FirebaseFirestore.instance
          .collection('notes')
          .where('userId', isEqualTo: _userId)
          .limit(1) // 하나만 확인해도 충분
          .get();
      
      // 노트가 하나라도 있으면 true
      return notesSnapshot.docs.isNotEmpty;
    } catch (e) {
      if (kDebugMode) {
      debugPrint('노트 존재 여부 확인 중 오류: $e');
      }
      return false; // 오류 발생 시 기본값으로 false 반환
    }
  }
  
  /// 사용량 제한 확인
  Future<void> _checkUsageLimits() async {
    try {
      // 사용량 제한 플래그 확인 (버퍼 추가)
      final limitFlags = await _usageLimitService.checkUsageLimitFlags(withBuffer: true);
      final ttsExceed = limitFlags['ttsExceed'] ?? false;
      final noteExceed = limitFlags['noteExceed'] ?? false;
      
      setState(() {
        _ttsExceed = ttsExceed;
        _noteExceed = noteExceed;
      });
      
      if (kDebugMode) {
        debugPrint('사용자 사용량 제한 확인 (버퍼 적용): TTS 제한=$ttsExceed, 노트 제한=$noteExceed');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('사용량 제한 확인 중 오류: $e');
      }
    }
  }
  
  /// 플랜 변경 체크
  Future<void> _checkPlanChange() async {
    if (_userId != null) {
      final hasChangedToFree = await _planService.hasPlanChangedToFree();
      if (hasChangedToFree && mounted) {
        // 스낵바 표시
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: const Text(
              'Free plan으로 전환 되었습니다. 자세한 설명은 설정 -> 내 플랜 을 참고하세요.',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: ColorTokens.secondary,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: '확인',
              textColor: Colors.white,
              onPressed: () {
                _scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
              },
            ),
          ),
        );
      }
    }
  }
  
  /// 샘플 모드에서 로그인 화면으로 전환 요청
  void _requestLoginScreen() {
    if (mounted) {
      if (kDebugMode) {
        debugPrint('[App] 로그인 화면 요청: 샘플 모드 비활성화');
      }
      // 샘플 모드를 비활성화하여 App 위젯이 LoginScreen을 빌드하도록 유도
      setState(() {
        _isSampleMode = false;
      });
    }
  }
  
  /// 샘플 모드 화면으로 전환 요청 (LoginScreen에서 호출)
  void _requestSampleModeScreen() async {
    if (mounted) {
      if (kDebugMode) {
        debugPrint('[App] 샘플 모드 화면 요청: 샘플 모드 활성화');
      }
      // 샘플 모드 활성화 (서비스 호출)
      await _sampleModeService.enableSampleMode();
      // 상태 업데이트하여 App 위젯이 SampleHomeScreen을 빌드하도록 유도
      setState(() {
        _isSampleMode = true;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      debugPrint('App build 호출: isInitialized=$_isInitialized, isLoading=$_isLoading, isLoadingUserData=$_isLoadingUserData, user=${_user?.uid}, isOnboardingCompleted=$_isOnboardingCompleted, isSampleMode=$_isSampleMode');
    }
    
    // 단일 MaterialApp 반환
      return MaterialApp(
        debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
        scrollBehavior: const CustomScrollBehavior(),
      scaffoldMessengerKey: _scaffoldMessengerKey, // ScaffoldMessenger 키 설정
      home: _buildCurrentScreen(), // 상태에 따라 적절한 화면 위젯 반환
    );
  }
  
  // 현재 상태에 맞는 화면 위젯을 반환하는 헬퍼 메서드
  Widget _buildCurrentScreen() {
    // 상태에 따른 화면 표시
    if (!_isInitialized && _error != null) {
      return _buildErrorScreen(_error!); // Scaffold 반환
    } else if (_isLoading || (_isLoadingUserData && _user != null)) {
      return _buildLoadingScreen(); // LoadingScreen 위젯 반환
    } else if (_user == null) {
      return _isSampleMode ? _buildSampleModeScreen() : _buildLoginScreen(); // SampleHomeScreen 또는 LoginScreen 위젯 반환
    } else if (!_isOnboardingCompleted) {
      return _buildOnboardingScreen(); // OnboardingScreen 위젯 반환
    } else {
      // return _buildHomeScreen(); // HomeScreen 위젯 반환 (기존)
      // HomeScreen에서 사용량 다이얼로그를 표시해야 하므로 Builder 사용 고려
      // 또는 HomeScreen initState에서 다이얼로그 표시 로직 실행
      return Builder(
        builder: (context) {
           // 사용량 제한 다이얼로그 표시 로직 (HomeScreen으로 이동 권장)
           // WidgetsBinding.instance?.addPostFrameCallback((_) {
           //   if ((_ttsExceed || _noteExceed) && !_hasShownUsageLimitDialog && mounted) {
           //     _showUsageLimitDialog(context); 
           //   }
           // });
           try {
             return const HomeScreen();
           } catch (e, stackTrace) {
             if (kDebugMode) {
                debugPrint('⚠️ HomeScreen 인스턴스 생성 중 오류 발생: $e');
                debugPrint('스택 트레이스: $stackTrace');
             }
             // 여기서 context는 MaterialApp 하위의 context이므로 ScaffoldMessenger 사용 가능
             return _buildHomeScreenErrorFallback(e, context);
           }
        });
    }
  }

  // 에러 화면 빌드
  Widget _buildErrorScreen(String errorMessage) {
    if (kDebugMode) {
      debugPrint('App 초기화 실패 화면 표시: $errorMessage');
    }
    // MaterialApp 제거, Scaffold 반환
    return Scaffold(
          body: Center(
        child: Text(errorMessage),
        ),
      );
    }
    
  // 로딩 화면 빌드
  Widget _buildLoadingScreen() {
    if (kDebugMode) {
      debugPrint('App 로딩 화면 표시: _isLoading=$_isLoading, _isLoadingUserData=$_isLoadingUserData');
    }
    // MaterialApp 제거, LoadingScreen 직접 반환
    return const LoadingScreen(progress: 0.5, message: '앱을 초기화하는 중입니다...');
    }
    
  // 샘플 모드 화면 빌드
  Widget _buildSampleModeScreen() {
    if (kDebugMode) {
      debugPrint('App 샘플 모드 화면 표시 (로그인 안됨)');
    }
    // MaterialApp 제거, SampleHomeScreen 직접 반환
    return SampleHomeScreen(
      onRequestLogin: _requestLoginScreen, 
    );
  }
  
  // 로그인 화면 빌드
  Widget _buildLoginScreen() {
    if (kDebugMode) {
      debugPrint('App 로그인 화면 표시');
    }
    // MaterialApp 제거, LoginScreen 직접 반환
    return LoginScreen(
          onLoginSuccess: (user) {
        if (kDebugMode) {
          debugPrint('로그인 성공 콜백 실행 (상태 변경은 리스너가 처리): 사용자 ID=${user.uid}');
        }
      },
      // 샘플 모드 전환 콜백 전달
      onSkipLogin: _requestSampleModeScreen, 
          isInitializing: false,
      );
    }
    
  // 온보딩 화면 빌드
  Widget _buildOnboardingScreen() {
    if (kDebugMode) {
      debugPrint('App 온보딩 화면 표시');
    }
    // MaterialApp 제거, OnboardingScreen 직접 반환
    return OnboardingScreen(
          onComplete: () async {
            await _preferencesService.setOnboardingCompleted(true);
            if (mounted) {
              setState(() {
                _isOnboardingCompleted = true;
              });
            }
          },
    );
  }
  
  // 홈 화면 렌더링 실패 시 표시할 대체 UI
  Widget _buildHomeScreenErrorFallback(Object error, BuildContext context) {
    // MaterialApp 제거, Scaffold 반환
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pikabook'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // TODO: 새로고침 로직 개선 (setState만으론 부족할 수 있음)
              setState(() {
                _isLoading = true; // 로딩 상태로 만들어 재시도 유도?
              });
            },
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('화면을 불러오는 중 문제가 발생했습니다'),
            const SizedBox(height: 16),
            Text('$error'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                FirebaseAuth.instance.signOut(); // 로그아웃하여 로그인 화면으로 이동
              },
              child: const Text('로그아웃'),
            ),
          ],
        ),
        ),
      );
    }
    
  // 글로벌 에러 시 표시할 대체 UI
  Widget _buildGlobalErrorFallback(Object error) {
    // MaterialApp 제거, Scaffold 반환
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pikabook'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
            await FirebaseAuth.instance.signOut();
          },
        ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('화면 로딩 중 문제가 발생했습니다.'),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                // 앱 재시작 또는 초기화 로직 필요
                // TODO: 앱 재시작 로직 구현
                await _initializeApp(); // 임시로 초기화 재시도
              },
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void setState(VoidCallback fn) {
    if (kDebugMode) {
      debugPrint('[App] setState 호출 전 상태: _isLoading=$_isLoading, _isLoadingUserData=$_isLoadingUserData, _user=${_user?.uid}, _isOnboardingCompleted=$_isOnboardingCompleted, _isSampleMode=$_isSampleMode');
    }
    super.setState(fn);
    if (kDebugMode) {
      debugPrint('[App] setState 호출 후 상태: _isLoading=$_isLoading, _isLoadingUserData=$_isLoadingUserData, _user=${_user?.uid}, _isOnboardingCompleted=$_isOnboardingCompleted, _isSampleMode=$_isSampleMode');
    }
  }

  // 사용량 제한 다이얼로그 표시 (HomeScreen 내부 등으로 이동 필요)
  void _showUsageLimitDialog(BuildContext context) async {
    if (kDebugMode) {
      debugPrint('[_showUsageLimitDialog] 호출됨 (HomeScreen 내부로 이동 권장)');
    }
    // 사용량 정보 가져오기 (버퍼 적용)
    final usageInfo = await _usageLimitService.getUsageInfo(withBuffer: true);
    final limitStatus = usageInfo['limitStatus'] as Map<String, dynamic>;
    final usagePercentages = usageInfo['percentages'] as Map<String, double>;
    
    // 다이얼로그 표시
    if (mounted && !_hasShownUsageLimitDialog) {
      UsageDialog.show(
        context,
        title: _noteExceed ? '사용량 제한에 도달했습니다' : null,
        message: _noteExceed 
            ? '노트 생성 관련 기능이 제한되었습니다. 더 많은 기능이 필요하시다면 문의하기를 눌러 요청해 주세요.'
            : null,
        limitStatus: limitStatus,
        usagePercentages: usagePercentages,
        onContactSupport: _handleContactSupport,
      );
      // setState 호출을 여기서 하는 것은 적절하지 않음
      // _hasShownUsageLimitDialog = true; 
    }
  }
  
  // 지원팀 문의하기 처리 (HomeScreen 내부 등으로 이동 필요)
  void _handleContactSupport() async {
    if (kDebugMode) {
      debugPrint('[_handleContactSupport] 호출됨 (HomeScreen 내부로 이동 권장)');
    }
    // 프리미엄 문의 구글 폼 URL
    const String formUrl = 'https://forms.gle/9EBEV1vaLpNbkhxD9';
    final Uri url = Uri.parse(formUrl);
    
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        // URL을 열 수 없는 경우 스낵바로 알림
        // ScaffoldMessenger.of(context) 사용 필요 (키 또는 Builder context 사용)
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('문의 폼을 열 수 없습니다. 직접 브라우저에서 다음 주소를 입력해 주세요: $formUrl'),
            duration: const Duration(seconds: 10),
          ),
        );
      }
    } catch (e) {
      // 오류 발생 시 스낵바로 알림
      _scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('문의 폼을 여는 중 오류가 발생했습니다. 이메일로 문의해 주세요: hello.pikabook@gmail.com'),
          duration: const Duration(seconds: 10),
        ),
      );
    }
  }
}
