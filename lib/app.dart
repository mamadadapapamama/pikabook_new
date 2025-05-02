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
import 'views/screens/settings_screen.dart';
import 'core/services/common/initialization_manager.dart';
import 'core/services/authentication/user_preferences_service.dart';
import 'core/services/common/plan_service.dart';
import 'core/services/common/usage_limit_service.dart';
import 'core/widgets/usage_dialog.dart';
import 'widgets/loading_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/services/marketing/marketing_campaign_service.dart';
import 'core/theme/app_theme.dart';
import 'dart:io';
import 'core/theme/tokens/ui_tokens.dart';
import 'core/theme/tokens/color_tokens.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'features/auth/sample_mode_service.dart';
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
      // Firebase 초기화
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      
      // 마케팅 캠페인 서비스 초기화
      await _marketingService.initialize();
      
      // 공통 서비스 초기화
      await _initializationManager.initialize();
      
      // 샘플 모드 상태 확인
      await _checkSampleMode();
      
      // 인증 상태 관찰
      _setupAuthStateListener();
      
      // 성공적으로 초기화 완료
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      // 초기화 실패 처리
      setState(() {
        _error = '앱 초기화 중 오류가 발생했습니다: $e';
        _isInitialized = false;
        _isLoading = false;
      });
    }
  }
  
  /// 샘플 모드 확인
  Future<void> _checkSampleMode() async {
    final isSampleMode = await _sampleModeService.isSampleModeEnabled();
    if (mounted) {
      setState(() {
        _isSampleMode = isSampleMode;
        if (isSampleMode) {
          _isLoading = false;
        }
      });
    }
  }
  
  /// 사용자 인증 상태 관찰 설정
  void _setupAuthStateListener() {
    _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen((User? user) async {
      if (mounted) {
        setState(() {
          _user = user;
          _userId = user?.uid;
          _isLoading = false;
        });
        
        if (user != null) {
          // 사용자가 로그인됨
          _isLoadingUserData = true;
          _loadUserPreferences();
        } else {
          // 사용자가 로그아웃됨
          setState(() {
            _isOnboardingCompleted = false;
          });
        }
      }
    });
  }
  
  /// 사용자 로그인 후 처리 로직
  Future<void> _loadUserPreferences() async {
    try {
      if (_userId == null) {
        setState(() {
          _isLoadingUserData = false;
        });
        return;
      }
      
      // 현재 사용자 ID를 UserPreferencesService에 설정
      await _preferencesService.setCurrentUserId(_userId!);

      // Firestore에서 사용자 설정 로드
      await _preferencesService.loadUserSettingsFromFirestore();
  
      // 1. 먼저 사용자가 노트를 가지고 있는지 확인
      bool hasNotes = await _checkUserHasNotes();
      
      // 2. 노트가 있는 경우 온보딩 완료 상태로 설정하고 홈화면으로 이동
      if (hasNotes) {
        debugPrint('사용자($_userId)의 노트가 존재합니다. 온보딩 완료 상태로 설정합니다.');
        await _preferencesService.setOnboardingCompleted(true);
        _isOnboardingCompleted = true;
      } 
      // 3. 노트가 없는 경우 기존 온보딩 완료 여부 확인
      else {
        debugPrint('사용자($_userId)의 노트가 없습니다. 온보딩 완료 여부를 확인합니다.');
        _isOnboardingCompleted = await _preferencesService.getOnboardingCompleted();
      }
      
      // 4. 사용량 제한 확인
      await _checkUsageLimits();
      
      if (mounted) {
        setState(() {
          _isLoadingUserData = false; // 데이터 로딩 완료
          _isLoading = false; // 추가: 모든 로딩 완료
        });
        // 사용자 데이터 로드 후 플랜 변경 체크
        await _checkPlanChange();
      }
    } catch (e) {
      // 사용자 설정 로드 실패 처리
      if (mounted) {
        setState(() {
          _error = '사용자 설정을 로드하는 중 오류가 발생했습니다: $e';
          _isLoadingUserData = false; // 오류 발생 시에도 로딩 상태 해제
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
      debugPrint('노트 존재 여부 확인 중 오류: $e');
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
      
      debugPrint('사용자 사용량 제한 확인 (버퍼 적용): TTS 제한=$ttsExceed, 노트 제한=$noteExceed');
    } catch (e) {
      debugPrint('사용량 제한 확인 중 오류: $e');
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
  
  @override
  Widget build(BuildContext context) {
    // 앱 자체가 초기화되지 않았거나 오류가 있는 경우
    if (!_isInitialized && _error != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: Text(_error ?? '오류가 발생했습니다'),
          ),
        ),
      );
    }
    
    // 앱이 로딩 중인 경우
    if (_isLoading || (_isLoadingUserData && _user != null)) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const LoadingScreen(progress: 0.5, message: '앱을 초기화하는 중입니다...'),
      );
    }
    
    // 샘플 모드인 경우
    if (_isSampleMode) {
      return MaterialApp(
        scrollBehavior: const CustomScrollBehavior(),
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: SampleHomeScreen(),
      );
    }
    
    // 사용자가 로그인하지 않은 경우 (인증 화면 표시)
    if (_user == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        scrollBehavior: const CustomScrollBehavior(),
        home: LoginScreen(
          onLoginSuccess: (user) async {
            // 샘플 모드 비활성화
            await _sampleModeService.disableSampleMode();
            
            // 사용자 로그인 성공 처리
            setState(() {
              _user = user;
              _userId = user.uid;
              _isSampleMode = false;
            });
            _loadUserPreferences();
          },
          isInitializing: false,
        ),
      );
    }
    
    // 사용자가 로그인했지만 온보딩을 완료하지 않은 경우
    if (!_isOnboardingCompleted) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        scrollBehavior: const CustomScrollBehavior(),
        home: OnboardingScreen(
          onComplete: () async {
            await _preferencesService.setOnboardingCompleted(true);
            if (mounted) {
              setState(() {
                _isOnboardingCompleted = true;
              });
            }
          },
        ),
      );
    }
    
    // 모든 조건을 만족한 경우 앱의 메인 화면 표시
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      scrollBehavior: const CustomScrollBehavior(),
      scaffoldMessengerKey: _scaffoldMessengerKey,
      title: 'Pikabook',
      home: Builder(
        builder: (context) {
          // 사용량 제한에 도달한 경우 다이얼로그 표시 (딜레이 적용)
          if ((_ttsExceed || _noteExceed) && !_hasShownUsageLimitDialog) {
            // 약간의 지연을 두고 다이얼로그 표시 (화면 전환 후)
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!_hasShownUsageLimitDialog) {
                _showUsageLimitDialog(context);
              }
            });
          }
          
          return const HomeScreen();
        },
      ),
      routes: {
        '/settings': (context) => SettingsScreen(
          onLogout: () async {
            // 로그아웃 처리
            await FirebaseAuth.instance.signOut();
          },
        ),
      },
    );
  }
  
  // 사용량 제한 다이얼로그 표시
  void _showUsageLimitDialog(BuildContext context) async {
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
      setState(() {
        _hasShownUsageLimitDialog = true;
      });
    }
  }
  
  // 지원팀 문의하기 처리
  void _handleContactSupport() async {
    // 프리미엄 문의 구글 폼 URL
    const String formUrl = 'https://forms.gle/9EBEV1vaLpNbkhxD9';
    final Uri url = Uri.parse(formUrl);
    
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        // URL을 열 수 없는 경우 스낵바로 알림
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
