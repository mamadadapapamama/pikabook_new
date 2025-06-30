import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'views/screens/login_screen.dart';
import 'features/home/home_screen.dart'; 
import 'views/screens/onboarding_screen.dart';
import 'core/services/authentication/user_preferences_service.dart';
import 'core/services/common/plan_service.dart';
import 'core/services/payment/in_app_purchase_service.dart';
import 'views/screens/loading_screen.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/tokens/color_tokens.dart';
import 'package:url_launcher/url_launcher.dart';
import 'features/sample/sample_home_screen.dart';
import 'features/home/home_viewmodel.dart';

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
  late UserPreferencesService _preferencesService;
  String? _error;
  final PlanService _planService = PlanService();
  final InAppPurchaseService _purchaseService = InAppPurchaseService();

  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  
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
    _initializeApp();
  }
  
  @override
  void dispose() {
    _authStateSubscription?.cancel();
    // InAppPurchaseService는 싱글톤이므로 앱 종료 시에만 dispose
    if (_purchaseService.isAvailable) {
      _purchaseService.dispose();
    }
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
  
  /// 앱 초기화 로직 (Firebase Auth만 확인)
  Future<void> _initializeApp() async {
    try {
      if (kDebugMode) {
        debugPrint('앱: 기본 초기화 시작 (Firebase Auth만)');
      }
      
      // Firebase Auth 상태만 확인
      await FirebaseAuth.instance.authStateChanges().first;
      final currentUser = FirebaseAuth.instance.currentUser;
      final isLoggedIn = currentUser != null;
      
      if (kDebugMode) {
        debugPrint('앱: Firebase Auth 상태 확인 완료 - 로그인: $isLoggedIn');
      }
      
      // 샘플 모드 상태 확인 (앱 특화 로직)
      _checkSampleMode();
      
      // 인증 상태 관찰 설정
      _setupAuthStateListener();
      
      // 로딩 스크린이 최소 1초는 보이도록 지연
      await Future.delayed(const Duration(milliseconds: 1000));
      
      // 초기화 상태 업데이트
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isLoading = !_isSampleMode; // 샘플 모드가 아니면 계속 로딩
        });
      }
      
      if (kDebugMode) {
        debugPrint('앱: 기본 초기화 완료 (로그인: $isLoggedIn, 샘플모드: $_isSampleMode)');
        if (isLoggedIn) {
          debugPrint('앱: 로그인 상태 - InitializationManager는 HomeScreen에서 호출됨');
        } else {
          debugPrint('앱: 로그아웃 상태 - InitializationManager 호출 안함');
        }
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
  
  /// 로그인 상태 확인 (샘플 모드 여부 결정)
  void _checkSampleMode() {
    // 로그인 상태에 따라 샘플 모드 결정
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;
    
    if (kDebugMode) {
      debugPrint('[checkSampleMode] 로그인 상태: $isLoggedIn, 현재 샘플모드: $_isSampleMode');
    }
    
    if (mounted) {
      setState(() {
        // 로그인된 경우에만 샘플 모드 비활성화
        // 로그아웃 상태라고 해서 자동으로 샘플 모드로 전환하지 않음
        if (isLoggedIn) {
          _isSampleMode = false;
          if (kDebugMode) {
            debugPrint('[checkSampleMode] 로그인 감지, 샘플 모드 비활성화');
          }
        } else {
          // 로그아웃 상태에서는 현재 샘플 모드 상태를 유지
          // 샘플 모드는 명시적으로 "로그인 없이 사용하기"를 선택했을 때만 활성화
          if (kDebugMode) {
            debugPrint('[checkSampleMode] 로그아웃 상태, 샘플 모드 상태 유지: $_isSampleMode');
          }
        }
        
        // 샘플 모드이면 로딩 상태 해제
        if (_isSampleMode) {
          if (kDebugMode) {
            debugPrint('[checkSampleMode] 샘플 모드 활성화됨, 로딩 상태 해제');
          }
          _isLoading = false;
          _isLoadingUserData = false;
        }
      });
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
            setState(() {
              _user = user;
              _userId = user.uid;
              _isLoading = false;
              _isLoadingUserData = true;
              _isSampleMode = false; // 로그인 시 샘플 모드 비활성화
            });
            
            // 사용자 데이터 로드
            await _loadUserPreferences();
          } else {
            // 로그아웃 처리
            if (kDebugMode) {
              debugPrint('앱: 로그아웃 처리, 샘플 모드 상태 유지: $_isSampleMode');
            }
            
            setState(() {
              _user = null;
              _userId = null;
              _isOnboardingCompleted = false;
              _isLoading = false;
              _isLoadingUserData = false;
              // 로그아웃 시 샘플 모드 상태를 유지 (자동으로 비활성화하지 않음)
              // _isSampleMode는 명시적으로 "로그인 없이 사용하기"를 선택했을 때만 true가 됨
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
      
      // 로그인 상태이므로 샘플 모드 비활성화
      _isSampleMode = false;
      
      // 사용자 데이터 로드
      await _preferencesService.setCurrentUserId(_userId!);
      
      // Firestore에서 사용자 문서 존재 여부 확인
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId!)
          .get();
      
      if (!userDoc.exists) {
        // 새로운 사용자이므로 사용자별 데이터만 초기화
        debugPrint('🔄 새로운 사용자 감지 - 사용자 데이터 초기화');
        await _preferencesService.clearUserData();
        // PlanService 캐시는 사용자별로 관리되므로 초기화하지 않음
        // (다른 사용자의 프리미엄 상태에 영향을 주지 않기 위해)
      }
      
      await _preferencesService.loadUserSettingsFromFirestore();
  
      // 온보딩 상태 확인 (노트 생성 시 자동으로 완료 처리됨)
      _isOnboardingCompleted = await _preferencesService.getOnboardingCompleted();
      
      // 상태 업데이트 (사용량 확인은 InitializationManager에서 처리됨)
      if (mounted) {
        setState(() {
          _isLoadingUserData = false;
          _isLoading = false;
        });
        
        // 플랜 변경은 InitializationManager에서 배너로 처리됨
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
  void _requestSampleModeScreen() {
    if (mounted) {
      if (kDebugMode) {
        debugPrint('[App] 샘플 모드 화면 요청: 샘플 모드 활성화');
      }
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
    
    // MaterialApp 반환
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
    if (kDebugMode) {
      debugPrint('_buildCurrentScreen 호출: user=${_user?.uid}, isSampleMode=$_isSampleMode, isLoading=$_isLoading, isLoadingUserData=$_isLoadingUserData');
    }
    
    // 상태에 따른 화면 표시
    if (!_isInitialized && _error != null) {
      return _buildErrorScreen(_error!); // Scaffold 반환
    } else if (_isLoading || (_isLoadingUserData && _user != null)) {
      return _buildLoadingScreen(); // LoadingScreen 위젯 반환
    } else if (_user == null) {
      if (kDebugMode) {
        debugPrint('사용자 로그아웃 상태: isSampleMode=$_isSampleMode -> ${_isSampleMode ? "SampleHomeScreen" : "LoginScreen"} 표시');
      }
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
             return ChangeNotifierProvider(
               create: (context) => HomeViewModel(),
               child: const HomeScreen(),
             );
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
    return const LoadingScreen(
      progress: 0.5, 
      message: '피카북을 준비하는 중이에요...',
      optimizeForAppReview: false, // 기본 로딩 화면 사용
    );
  }
    
  // 샘플 모드 화면 빌드
  Widget _buildSampleModeScreen() {
    if (kDebugMode) {
      debugPrint('App 샘플 모드 화면 표시 (로그인 안됨)');
    }
    // 샘플 모드에서는 전용 샘플 홈 화면을 사용
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


}
