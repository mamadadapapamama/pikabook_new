import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'dart:async';

import 'views/screens/login_screen.dart';
import 'views/screens/home_screen.dart'; 
import 'views/screens/onboarding_screen.dart';
import 'views/screens/settings_screen.dart';
import 'services/initialization_manager.dart';
import 'services/user_preferences_service.dart';
import 'widgets/loading_screen.dart';
import 'theme/app_theme.dart';

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
  bool _isLoadingUserData = false; // 사용자 데이터 로딩 상태 추가
  String? _userId;
  User? _user;
  StreamSubscription<User?>? _authStateSubscription;
  late InitializationManager _initializationManager;
  late UserPreferencesService _preferencesService;
  String? _error;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
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
      
      // 공통 서비스 초기화
      await _initializationManager.initialize();
      
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
      
      if (mounted) {
        setState(() {
          _isLoadingUserData = false; // 데이터 로딩 완료
        });
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
  
  @override
  Widget build(BuildContext context) {
    // 앱 테마 정의
    return MaterialApp(
      title: 'Pikabook',
      theme: AppTheme.lightTheme,
      // 다크 테마 지원시 추가
      // darkTheme: AppTheme.darkTheme,
      // themeMode: ThemeMode.system,
      home: _buildHomeScreen(),
      debugShowCheckedModeBanner: false,
      // 성능 오버레이 비활성화
      showPerformanceOverlay: false,
    );
  }
  
  /// 로딩, 오류, 로그인 또는 홈 화면 중 적절한 화면을 반환
  Widget _buildHomeScreen() {
    // 1. 초기화 중이거나 로딩 중인 경우 로딩 화면 표시
    if (_isLoading) {
      return LoadingScreen(
        progress: 0.5,
        message: '앱을 초기화하는 중입니다...'
      );
    }
    
    // 1-2. 사용자 데이터 로딩 중인 경우 로딩 화면 표시
    if (_isLoadingUserData) {
      return LoadingScreen(
        progress: 0.8,
        message: '사용자 데이터를 불러오는 중입니다...'
      );
    }
    
    // 2. 초기화 실패시 오류 화면 표시
    if (_error != null || !_isInitialized) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  _error ?? '앱을 초기화할 수 없습니다.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _initializeApp(),
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }
    
    // 3. 사용자가 로그인되지 않은 경우 로그인 화면
    if (_user == null) {
      return LoginScreen(
        onLoginSuccess: (user) {
          // 사용자 로그인 성공 처리
          setState(() {
            _user = user;
            _userId = user.uid;
          });
          _loadUserPreferences();
        },
        isInitializing: false,
      );
    }
    
    // 사용자가 로그인된 경우
    // 4-1. 온보딩이 이미 완료된 경우 홈 화면
    if (_isOnboardingCompleted) {
      return HomeScreen(
        onSettingsPressed: (BuildContext context) async {
          // 설정 화면으로 이동 로직 구현
          // UI 스레드 처리를 위한 짧은 지연 추가
          await Future.delayed(const Duration(milliseconds: 10));
          
          if (!context.mounted) return;
          
          // 로그 추가
          debugPrint('App.dart에서 설정 화면으로 네비게이션 시작 (전달된 context 사용)');
          
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => SettingsScreen(
                onLogout: () async {
                  // 로그아웃 처리
                  await FirebaseAuth.instance.signOut();
                  // 앱 재시작 효과를 위한 페이지 전환
                  if (!context.mounted) return;
                  
                  Navigator.of(context).pushAndRemoveUntil(
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) => const App(),
                      transitionsBuilder: (context, animation, secondaryAnimation, child) {
                        const begin = 0.0;
                        const end = 1.0;
                        const curve = Curves.easeInOut;
                        
                        var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                        var fadeAnimation = animation.drive(tween);
                        
                        return FadeTransition(
                          opacity: fadeAnimation,
                          child: child,
                        );
                      },
                      transitionDuration: const Duration(milliseconds: 500),
                    ),
                    (route) => false,
                  );
                },
              ),
            ),
          );
        },
      );
    }
    // 4-2. 온보딩이 필요한 경우 온보딩 화면
    else {
      return OnboardingScreen(
        onComplete: () async {
          // 온보딩 완료 상태를 UserPreferencesService를 통해 저장
          await _preferencesService.setOnboardingCompleted(true);
          setState(() {
            _isOnboardingCompleted = true;
          });
        },
      );
    }
  }
}
