import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'theme/app_theme.dart';
import 'views/screens/home_screen.dart';
import 'services/initialization_service.dart';
import 'services/user_preferences_service.dart';
import 'views/screens/onboarding_screen.dart';
import 'firebase_options.dart';
import 'views/screens/login_screen.dart';
import 'views/screens/settings_screen.dart';
import 'views/screens/note_detail_screen.dart';
import 'widgets/dot_loading_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  bool _hasLoginHistory = false;
  bool _isFirstEntry = true; // 첫 진입 여부 (툴팁 표시)
  String? _error;
  final UserPreferencesService _preferencesService = UserPreferencesService();
  bool _isCheckingInitialization = false;
  bool _isLoadingUserData = false;
  
  // 앱 시작 시간 기록
  final DateTime _appStartTime = DateTime.now();
  
  // 인증 상태 변경 구독 취소용 변수
  late final Stream<User?> _authStateStream;
  
  @override
  void initState() {
    super.initState();
    debugPrint('App initState 호출됨 (${DateTime.now().toString()})');
    // 초기화 상태 확인은 비동기로 시작하고 UI는 즉시 렌더링
    _startInitializationCheck();
    
    // 인증 상태 변경 리스너 설정
    _authStateStream = widget.initializationService.authStateChanges;
    _setupAuthStateListener();
  }

  // 인증 상태 변경 리스너 설정
  void _setupAuthStateListener() {
    _authStateStream.listen((User? user) {
      debugPrint('인증 상태 변경 감지: ${user != null ? '로그인' : '로그아웃'}');
      
      if (mounted) {
        if (user != null) {
          debugPrint('사용자 로그인됨: ${user.uid}');
          // 로그인 상태 처리
          _handleUserLogin(user);
        } else {
          debugPrint('사용자 로그아웃됨');
          // 로그아웃 상태 처리
          setState(() {
            _isUserAuthenticated = false;
            _isOnboardingCompleted = false;
            _hasLoginHistory = false;
          });
        }
      }
    }, onError: (error) {
      debugPrint('인증 상태 변경 리스너 오류: $error');
    });
  }

  // 로그인한 사용자 처리
  Future<void> _handleUserLogin(User user) async {
    try {
      setState(() {
        _isLoadingUserData = true;
        _isUserAuthenticated = true;
      });
      
      // 초기화 서비스를 통해 로그인 처리
      final result = await widget.initializationService.handleUserLogin(user);
      
      if (mounted) {
        setState(() {
          _isUserAuthenticated = true;
          _hasLoginHistory = result['hasLoginHistory'] ?? false;
          _isOnboardingCompleted = result['isOnboardingCompleted'] ?? false;
          _isFirstEntry = result['isFirstEntry'] ?? true;
          _isLoadingUserData = false;
        });
      }
      
      debugPrint('사용자 로그인 처리 완료: 로그인 기록=${result['hasLoginHistory']}, 온보딩 완료=${result['isOnboardingCompleted']}');
    } catch (e) {
      debugPrint('사용자 로그인 처리 중 오류 발생: $e');
      if (mounted) {
        setState(() {
          _isLoadingUserData = false;
        });
      }
    }
  }

  // 초기화 상태 확인 시작 (비동기)
  void _startInitializationCheck() {
    if (_isCheckingInitialization) return;
    _isCheckingInitialization = true;
    
    debugPrint('앱 초기화 상태 확인 시작 (${DateTime.now().toString()})');

    // 로그인 상태 확인
    widget.initializationService.checkLoginState().then((result) {
      if (mounted) {
        setState(() {
          _isUserAuthenticated = result['isLoggedIn'] ?? false;
          _hasLoginHistory = result['hasLoginHistory'] ?? false;
          _isOnboardingCompleted = result['isOnboardingCompleted'] ?? false;
          _isFirstEntry = result['isFirstEntry'] ?? true;
          _isFirebaseInitialized = true;
          _isCheckingInitialization = false;
        });
      }
      
      final elapsed = DateTime.now().difference(_appStartTime);
      debugPrint('앱 초기화 완료 (소요시간: ${elapsed.inMilliseconds}ms)');
      debugPrint('로그인 상태: $_isUserAuthenticated, 로그인 기록: $_hasLoginHistory, 온보딩 완료: $_isOnboardingCompleted');
    }).catchError((e) {
      debugPrint('초기화 상태 확인 중 오류 발생: $e');
      if (mounted) {
        setState(() {
          _error = '앱 초기화 중 오류가 발생했습니다: $e';
          _isCheckingInitialization = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pikabook',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.lightTheme, // 다크 모드 비활성화
      themeMode: ThemeMode.light,
      // 화면 방향 고정 (세로 모드만 지원)
      home: _buildHomeScreen(),
      routes: {
        '/settings': (context) => SettingsScreen(
              initializationService: widget.initializationService,
              onLogout: () async {
                await widget.initializationService.signOut();
                if (mounted) {
                  setState(() {
                    _isUserAuthenticated = false;
                    _isOnboardingCompleted = false;
                    _hasLoginHistory = false;
                  });
                }
              },
            ),
        // 추가 라우트 설정이 필요한 경우 여기에 추가
      },
    );
  }

  Widget _buildHomeScreen() {
    // 초기화 중이거나 사용자 데이터 로딩 중인 경우 로딩 화면 표시
    if (!_isFirebaseInitialized || _isLoadingUserData) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: Image.asset('assets/images/pikabook_bird.png'),
              ),
              const SizedBox(height: 24),
              const DotLoadingIndicator(),
              const SizedBox(height: 24),
              Text(
                _isLoadingUserData 
                    ? '사용자 데이터 로드 중...' 
                    : '앱 초기화 중...',
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    // 오류 발생 시 오류 화면 표시
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                '오류가 발생했습니다',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                  });
                  _startInitializationCheck();
                },
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }

    // 1. 로그인되지 않은 경우 로그인 화면으로 이동
    if (!_isUserAuthenticated) {
      return LoginScreen(
        initializationService: widget.initializationService,
        onLoginSuccess: (user) {
          _handleUserLogin(user);
        },
      );
    }

    // 2. 로그인 됐지만 로그인 기록이 없는 경우 온보딩 화면으로 이동
    if (!_hasLoginHistory) {
      return OnboardingScreen(
        onComplete: () {
          setState(() {
            _isOnboardingCompleted = true;
            _hasLoginHistory = true;
          });
        },
      );
    }

    // 3. 로그인 됐고 로그인 기록이 있지만 온보딩이 완료되지 않은 경우 온보딩 화면으로 이동
    if (!_isOnboardingCompleted) {
      return OnboardingScreen(
        onComplete: () {
          setState(() {
            _isOnboardingCompleted = true;
          });
        },
      );
    }

    // 4. 로그인 및 온보딩이 모두 완료된 경우 홈 화면으로 이동
    return HomeScreen(
      showTooltip: _isFirstEntry, // 첫 진입 시 툴팁 표시
      onCloseTooltip: () {
        // 툴팁 표시 여부 업데이트
        SharedPreferences.getInstance().then((prefs) {
          prefs.setBool('hasShownTooltip', true);
          setState(() {
            _isFirstEntry = false;
          });
        });
      },
      initializationService: widget.initializationService, // InitializationService 전달
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
