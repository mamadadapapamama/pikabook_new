import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'theme/app_theme.dart';
import 'views/screens/home_screen.dart';
import 'services/initialization_service.dart';
import 'services/user_preferences_service.dart';
import 'views/screens/splash_screen.dart';
import 'views/screens/onboarding_screen.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';

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
  bool _skipLogin = false;
  String? _error;
  final UserPreferencesService _preferencesService = UserPreferencesService();

  @override
  void initState() {
    super.initState();
    _checkInitializationStatus();
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    try {
      final isCompleted = await _preferencesService.isOnboardingCompleted();
      if (mounted) {
        setState(() {
          _isOnboardingCompleted = isCompleted;
        });
      }
    } catch (e) {
      debugPrint('온보딩 상태 확인 중 오류 발생: $e');
    }
  }

  Future<void> _checkInitializationStatus() async {
    try {
      // Firebase 초기화 상태 확인
      final firebaseInitialized =
          await widget.initializationService.isFirebaseInitialized;

      if (!firebaseInitialized) {
        setState(() {
          _error = widget.initializationService.firebaseError;
        });
        return;
      }

      setState(() {
        _isFirebaseInitialized = true;
      });

      // 사용자 인증 상태 확인
      final userAuthenticationChecked =
          await widget.initializationService.isUserAuthenticationChecked;

      if (!userAuthenticationChecked) {
        setState(() {
          _error = widget.initializationService.authError;
        });
        return;
      }

      // 사용자가 로그인되어 있는지 확인
      setState(() {
        _isUserAuthenticated = widget.initializationService.isUserAuthenticated;
      });
    } catch (e) {
      setState(() {
        _error = '앱 초기화 중 오류가 발생했습니다: $e';
      });
    }
  }

  void _handleLoginSuccess() {
    setState(() {
      _isUserAuthenticated = true;
    });
  }

  void _handleSkipLogin() {
    setState(() {
      _skipLogin = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pikabook',
      theme: AppTheme.lightTheme,
      home: _buildHomeScreen(),
    );
  }

  Widget _buildHomeScreen() {
    // 오류가 있는 경우
    if (_error != null) {
      return _buildErrorScreen();
    }

    // 디버그 모드에서 테스트 화면 표시
    if (kDebugMode) {
      // 온보딩 화면 테스트를 위해 주석 해제
      // return const OnboardingScreen();
    }

    // Firebase 초기화가 완료된 경우
    if (_isFirebaseInitialized) {
      // 사용자가 로그인되어 있거나 로그인을 건너뛴 경우
      if (_isUserAuthenticated || _skipLogin) {
        // 온보딩 완료 여부에 따라 화면 결정
        if (_isOnboardingCompleted) {
          return const HomeScreen();
        } else {
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
        return LoginScreen(
          initializationService: widget.initializationService,
          onLoginSuccess: _handleLoginSuccess,
          onSkipLogin: _handleSkipLogin,
        );
      }
    }

    // 초기화 중인 경우
    return const SplashScreen();
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
