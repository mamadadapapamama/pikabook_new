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
        // 로그인 상태 변경
        setState(() {
          _isUserAuthenticated = user != null;
        });
        
        if (user != null) {
          debugPrint('사용자 로그인됨: ${user.uid}');
          
          // 로그인 시 노트 데이터에 따라 온보딩 상태 다시 확인
          _checkOnboardingForUser(user);
        } else {
          debugPrint('사용자 로그아웃됨');
          // 로그아웃 상태일 때 온보딩 초기화
          _preferencesService.setOnboardingCompleted(false);
          _preferencesService.setHasOnboarded(false);
          setState(() {
            _isOnboardingCompleted = false;
          });
        }
      }
    }, onError: (error) {
      debugPrint('인증 상태 변경 리스너 오류: $error');
    });
  }

  // 사용자가 로그인했을 때 노트 데이터에 따라 온보딩 상태 확인
  Future<void> _checkOnboardingForUser(User user) async {
    try {
      setState(() {
        _isLoadingUserData = true;
      });
      
      // InitializationService의 handleUserLogin을 호출하여 온보딩 상태 업데이트
      await widget.initializationService.handleUserLogin(user);
      
      // Firestore에서 사용자의 온보딩 상태 확인
      final firestore = FirebaseFirestore.instance;
      final userDoc = await firestore.collection('users').doc(user.uid).get();
      final hasCompletedOnboarding = userDoc.data()?['onboardingCompleted'] ?? false;
      
      // 로컬 저장소에도 온보딩 상태 저장
      await _preferencesService.setOnboardingCompleted(hasCompletedOnboarding);
      await _preferencesService.setHasOnboarded(hasCompletedOnboarding);
      
      if (mounted) {
        setState(() {
          _isOnboardingCompleted = hasCompletedOnboarding;
          _isLoadingUserData = false;
        });
      }
      
      debugPrint('사용자의 온보딩 상태 확인: $hasCompletedOnboarding');
    } catch (e) {
      debugPrint('사용자 온보딩 상태 확인 중 오류 발생: $e');
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
      
      // 현재 로그인된 사용자가 있는지 확인
      final user = widget.initializationService.getCurrentUser();
      if (user != null) {
        // Firestore에서 사용자의 온보딩 상태 확인
        final firestore = FirebaseFirestore.instance;
        final userDoc = await firestore.collection('users').doc(user.uid).get();
        final hasCompletedOnboarding = userDoc.data()?['onboardingCompleted'] ?? false;
        
        // 로컬 저장소에도 온보딩 상태 저장
        await _preferencesService.setOnboardingCompleted(hasCompletedOnboarding);
        await _preferencesService.setHasOnboarded(hasCompletedOnboarding);
        
        if (mounted) {
          setState(() {
            _isOnboardingCompleted = hasCompletedOnboarding;
          });
        }
      } else {
        // 로그인되지 않은 경우 기본값으로 온보딩 필요
        await _preferencesService.setOnboardingCompleted(false);
        await _preferencesService.setHasOnboarded(false);
        
        if (mounted) {
          setState(() {
            _isOnboardingCompleted = false;
          });
        }
        debugPrint('로그인되지 않음: 온보딩 필요로 설정');
      }
      
      final duration = DateTime.now().difference(startTime);
      debugPrint('온보딩 상태 확인 완료: $_isOnboardingCompleted (소요시간: ${duration.inMilliseconds}ms)');
    } catch (e) {
      debugPrint('온보딩 상태 확인 중 오류 발생: $e');
      // 오류 발생 시 기본값으로 온보딩 필요
      if (mounted) {
        setState(() {
          _isOnboardingCompleted = false;
        });
      }
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

      // 사용자 인증 상태 확인 (userAuthenticationChecked 확인 단계 건너뛰기)
      final authStartTime = DateTime.now();
      debugPrint('사용자 인증 상태 확인 시작 (${authStartTime.toString()})');
      
      // 사용자가 로그인되어 있는지 직접 확인
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
    debugPrint('로그인 성공 처리됨');
    
    // 로그인 상태 업데이트
    setState(() {
      _isUserAuthenticated = true;
      _isLoadingUserData = true; // 데이터 로딩 시작
    });
    
    // 현재 로그인한 사용자 정보 가져오기
    final user = widget.initializationService.getCurrentUser();
    if (user != null) {
      // 사용자 데이터 처리 및 온보딩 상태 확인
      _checkOnboardingForUser(user);
    } else {
      // 사용자 정보가 없는 경우 로딩 상태 해제
      setState(() {
        _isLoadingUserData = false;
      });
    }
  }

  void _handleLogout() async {
    debugPrint('로그아웃 시작...');
    
    try {
      // 캐시와 Firebase 로그아웃 처리
      await widget.initializationService.signOut();
      
      // 상태 변경을 통해 LoginScreen으로 전환
      if (mounted) {
        setState(() {
          _isUserAuthenticated = false;
          _isOnboardingCompleted = false;
        });
        
        // 앱 상태 디버깅
        debugPrint('로그아웃 후 상태: _isUserAuthenticated=$_isUserAuthenticated, _isOnboardingCompleted=$_isOnboardingCompleted');
      }
    } catch (e) {
      debugPrint('로그아웃 중 오류 발생: $e');
      // 오류 처리 - 사용자에게 알림 표시
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그아웃 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('App build 호출됨 (${DateTime.now().toString()})');
    return MaterialApp(
      title: 'Pikabook',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.lightTheme,
      themeMode: ThemeMode.light,
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
        'Loading user data=$_isLoadingUserData, '
        'Error=$_error');
        
    // 앱 초기화 중인 경우 로딩 화면 표시 (스플래시 역할)
    if (!_isFirebaseInitialized || _isCheckingInitialization) {
      return _buildLoadingScreen(message: '초기화 중...');
    }

    // 오류가 있는 경우
    if (_error != null) {
      return _buildErrorScreen();
    }

    // 사용자가 로그인되어 있는 경우
    if (_isUserAuthenticated) {
      // 사용자 데이터 로딩 중인 경우 로딩 화면 표시
      if (_isLoadingUserData) {
        return _buildLoadingScreen(message: '데이터 로드 중...');
      }
      
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
        onSkipLogin: null, // 익명 로그인 기능 제거
      );
    }
  }

  // 로딩 화면 (스플래시 화면 역할)
  Widget _buildLoadingScreen({String message = '로딩 중...'}) {
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
                
                // 로딩 메시지
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF3A3A3A),
                  ),
                ),
                
                const SizedBox(height: 16),
                
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

  @override
  void dispose() {
    super.dispose();
  }
}
