import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'theme/app_theme.dart';
import 'views/screens/home_screen.dart';
import 'services/initialization_service.dart';
import 'services/user_preferences_service.dart';
import 'views/screens/onboarding_screen.dart';
import 'firebase_options.dart';
import 'views/screens/login_screen.dart';
import 'views/screens/settings_screen.dart';

class App extends StatefulWidget {
  final InitializationService initializationService;

  const App({Key? key, required this.initializationService}) : super(key: key);

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  bool _isFirebaseInitialized = false;
  bool _isUserAuthenticated = false;
  bool _isOnboardingCompleted = false;
  String? _error;
  final UserPreferencesService _preferencesService = UserPreferencesService();
  bool _isCheckingInitialization = false;
  
  // 앱 시작 시간 기록
  final DateTime _appStartTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    debugPrint('App initState 호출됨 (${DateTime.now().toString()})');
    // 초기화 상태 확인은 비동기로 시작하고 UI는 즉시 렌더링
    _startInitializationCheck();
  }

  // 초기화 상태 확인 시작 (비동기)
  void _startInitializationCheck() {
    if (_isCheckingInitialization) return;
    _isCheckingInitialization = true;
    
    debugPrint('앱 초기화 상태 확인 시작 (${DateTime.now().toString()})');

    // 초기화 즉시 진행
    // 온보딩 상태와 초기화 상태를 병렬로 확인
    Future.wait([
      _checkOnboardingStatus(),
      _checkInitializationStatus(),
    ]).then((results) {
      final elapsed = DateTime.now().difference(_appStartTime);
      debugPrint('앱 초기화 완료 (소요시간: ${elapsed.inMilliseconds}ms)');
      _isCheckingInitialization = false;
    }).catchError((e) {
      debugPrint('초기화 상태 확인 중 오류 발생: $e');
      _isCheckingInitialization = false;
    });
  }

  Future<void> _checkOnboardingStatus() async {
    try {
      final startTime = DateTime.now();
      debugPrint('온보딩 상태 확인 시작 (${startTime.toString()})');
      
      final isCompleted = await _preferencesService.isOnboardingCompleted();
      
      if (mounted) {
        setState(() {
          _isOnboardingCompleted = isCompleted;
        });
      }
      
      final duration = DateTime.now().difference(startTime);
      debugPrint('온보딩 상태 확인 완료: $_isOnboardingCompleted (소요시간: ${duration.inMilliseconds}ms)');
    } catch (e) {
      debugPrint('온보딩 상태 확인 중 오류 발생: $e');
    }
  }

  Future<void> _checkInitializationStatus() async {
    try {
      final startTime = DateTime.now();
      debugPrint('Firebase 초기화 상태 확인 시작 (${startTime.toString()})');
      
      // Firebase 초기화 상태 확인
      final firebaseInitialized =
          await widget.initializationService.isFirebaseInitialized;

      if (!firebaseInitialized) {
        setState(() {
          _error = widget.initializationService.firebaseError;
        });
        debugPrint('Firebase 초기화 실패: $_error');
        return;
      }

      setState(() {
        _isFirebaseInitialized = true;
      });
      
      final firebaseDuration = DateTime.now().difference(startTime);
      debugPrint('Firebase 초기화 상태 확인 완료 (소요시간: ${firebaseDuration.inMilliseconds}ms)');

      // 사용자 인증 상태 확인
      final authStartTime = DateTime.now();
      debugPrint('사용자 인증 상태 확인 시작 (${authStartTime.toString()})');
      
      final userAuthenticationChecked =
          await widget.initializationService.isUserAuthenticationChecked;

      if (!userAuthenticationChecked) {
        setState(() {
          _error = widget.initializationService.authError;
        });
        debugPrint('사용자 인증 상태 확인 실패: $_error');
        return;
      }

      // 사용자가 로그인되어 있는지 확인
      setState(() {
        _isUserAuthenticated = widget.initializationService.isUserAuthenticated;
      });
      
      final authDuration = DateTime.now().difference(authStartTime);
      debugPrint('사용자 인증 상태 확인 완료: $_isUserAuthenticated (소요시간: ${authDuration.inMilliseconds}ms)');
      
    } catch (e) {
      setState(() {
        _error = '앱 초기화 중 오류가 발생했습니다: $e';
      });
      debugPrint('초기화 상태 확인 중 예외 발생: $e');
    }
  }

  void _handleLoginSuccess() {
    setState(() {
      _isUserAuthenticated = true;
    });
    debugPrint('로그인 성공 처리됨: _isUserAuthenticated = $_isUserAuthenticated');
  }

  void _handleLogout() async {
    debugPrint('로그아웃 시작...');
    
    // 먼저 InitializationService를 통해 로그아웃 처리
    await widget.initializationService.signOut();
    
    // 그 다음 UI 상태 업데이트
    setState(() {
      _isUserAuthenticated = false;
      _isOnboardingCompleted = false; // 온보딩 상태도 초기화
    });
    
    debugPrint('로그아웃 처리 완료: _isUserAuthenticated = $_isUserAuthenticated, _isOnboardingCompleted = $_isOnboardingCompleted');
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('App build 호출됨 (${DateTime.now().toString()})');
    return MaterialApp(
      title: 'Pikabook',
      theme: AppTheme.lightTheme,
      home: _buildHomeScreen(),
      routes: {
        '/settings': (context) => SettingsScreen(
              initializationService: widget.initializationService,
              onLogout: _handleLogout,
            ),
      },
    );
  }

  Widget _buildHomeScreen() {
    // 앱 상태 디버깅 로그
    debugPrint('현재 앱 상태: Firebase initialized=$_isFirebaseInitialized, '
        'User authenticated=$_isUserAuthenticated, '
        'Onboarding completed=$_isOnboardingCompleted, '
        'Error=$_error');
        
    // 앱 초기화 중인 경우 로딩 화면 표시 (스플래시 역할)
    if (!_isFirebaseInitialized || _isCheckingInitialization) {
      return _buildLoadingScreen();
    }

    // 오류가 있는 경우
    if (_error != null) {
      return _buildErrorScreen();
    }

    // 사용자가 로그인되어 있는 경우
    if (_isUserAuthenticated) {
      // 온보딩 완료 여부에 따라 화면 결정
      if (_isOnboardingCompleted) {
        debugPrint('로그인 완료 및 온보딩 완료 - 홈 화면 표시');
        return const HomeScreen();
      } else {
        debugPrint('로그인 완료, 온보딩 필요 - 온보딩 화면 표시');
        return OnboardingScreen(
          onComplete: () {
            setState(() {
              _isOnboardingCompleted = true;
            });
          },
        );
      }
    } else {
      // 로그인 화면 표시
      debugPrint('로그인 필요 - 로그인 화면 표시');
      return LoginScreen(
        initializationService: widget.initializationService,
        onLoginSuccess: _handleLoginSuccess,
        onSkipLogin: () {
          setState(() {
            _isUserAuthenticated = true;
          });
        },
      );
    }
  }

  // 로딩 화면 (스플래시 화면 역할)
  Widget _buildLoadingScreen() {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/splash_background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 로고 이미지
                SizedBox(
                  width: 160,
                  height: 160,
                  child: Image.asset(
                    'assets/images/pikabook_logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 32),
                
                // 로딩 인디케이터
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF8F56)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error ?? '알 수 없는 오류가 발생했습니다.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _error = null;
                  _isFirebaseInitialized = false;
                  _isUserAuthenticated = false;
                });
                widget.initializationService.retryInitialization(
                  options: DefaultFirebaseOptions.currentPlatform,
                );
                _checkInitializationStatus();
              },
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}
