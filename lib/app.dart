import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'views/screens/home_screen.dart';
import 'services/initialization_manager.dart';
import 'services/user_preferences_service.dart';
import 'views/screens/onboarding_screen.dart';
import 'views/screens/login_screen.dart';
import 'views/screens/settings_screen.dart';
import 'widgets/loading_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'viewmodels/home_viewmodel.dart';

class App extends StatefulWidget {
  const App({Key? key}) : super(key: key);

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  bool _isUserAuthenticated = false;
  bool _isOnboardingCompleted = false;
  bool _hasLoginHistory = false;
  bool _isFirstEntry = true; // 첫 진입 여부 (툴팁 표시)
  String? _error;
  final UserPreferencesService _preferencesService = UserPreferencesService();
  
  // 초기화 관리자 인스턴스
  late final InitializationManager _initializationManager;
  
  // 초기화 상태 관리
  bool _isInitialized = false;
  InitializationStep _currentStep = InitializationStep.preparing;
  double _progress = 0.0;
  String _message = '준비 중...';
  String? _subMessage;
  
  // 앱 시작 시간 기록
  final DateTime _appStartTime = DateTime.now();
  
  // 인증 상태 변경 구독 취소용 변수
  late final Stream<User?> _authStateStream;
  
  @override
  void initState() {
    super.initState();
    debugPrint('App initState 호출됨 (${DateTime.now().toString()})');
    
    // 초기화 관리자 생성
    _initializationManager = InitializationManager();
    
    // 초기화 관리자 리스너 등록 - 무명 함수 사용
    _initializationManager.addListener((step, progress, message, subMessage) {
      _handleInitProgress(step, progress, message, subMessage);
      // 콘솔에 초기화 상태 출력
      debugPrint('초기화 상태: $step ($progress%) - $message ${subMessage ?? ""}');
    });
    
    // 인증 상태 변경 리스너 설정
    _authStateStream = FirebaseAuth.instance.authStateChanges();
    _setupAuthStateListener();
    
    // Firestore 오프라인 지원 설정
    _setupFirestore();
    
    // 초기화 시작
    _startInitialization();
  }
  
  // Firestore 설정
  Future<void> _setupFirestore() async {
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      debugPrint('💾 Firestore 설정 완료 (오프라인 지원 활성화)');
    } catch (e) {
      debugPrint('⚠️ Firestore 설정 중 오류: $e');
    }
  }

  // 초기화 진행 상황 처리
  void _handleInitProgress(
    InitializationStep step, 
    double progress, 
    String message, 
    String? subMessage
  ) {
    if (mounted) {
      setState(() {
        _currentStep = step;
        _progress = progress;
        _message = message;
        _subMessage = subMessage;
        
        // 사용자 데이터 단계까지 완료되면 앱 표시 시작
        if (step == InitializationStep.userData && progress >= 0.6) {
          _isInitialized = true;
        }
      });
    }
  }

  // 초기화 시작
  void _startInitialization() async {
    try {
      // 초기화 시작
      final result = await _initializationManager.initialize();
      
      if (mounted) {
        setState(() {
          _isUserAuthenticated = result['isLoggedIn'] ?? false;
          _hasLoginHistory = result['hasLoginHistory'] ?? false;
          _isOnboardingCompleted = result['isOnboardingCompleted'] ?? false;
          _isFirstEntry = result['isFirstEntry'] ?? true;
          _error = result['error'];
        });
      }
      
      final elapsed = DateTime.now().difference(_appStartTime);
      debugPrint('앱 초기화 완료 (소요시간: ${elapsed.inMilliseconds}ms)');
      debugPrint('로그인 상태: $_isUserAuthenticated, 로그인 기록: $_hasLoginHistory, 온보딩 완료: $_isOnboardingCompleted');
    } catch (e) {
      debugPrint('초기화 중 오류 발생: $e');
      if (mounted) {
        setState(() {
          _error = '앱 초기화 중 오류가 발생했습니다: $e';
        });
      }
    }
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
        _isUserAuthenticated = true;
      });
      
      // 사용자 정보 확인 - 기본 정보만 빠르게 로드
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
          
      if (userDoc.exists) {
        final userData = userDoc.data();
        if (userData != null) {
          // 사용자 기본 설정 로드 (필수적인 정보만)
          if (userData['userName'] != null) {
            await _preferencesService.setUserName(userData['userName']);
          }
          
          if (userData['defaultNoteSpace'] != null) {
            await _preferencesService.setDefaultNoteSpace(userData['defaultNoteSpace']);
          }
          
          // 로그인 기록 저장
          await _preferencesService.saveLoginHistory();
          
          // 온보딩 완료 여부 확인
          final isOnboardingCompleted = await _preferencesService.getOnboardingCompleted();
          
          if (mounted) {
            setState(() {
              _isOnboardingCompleted = isOnboardingCompleted;
              _hasLoginHistory = true;
            });
          }
          
          // 나머지 설정 정보는 백그라운드에서 로드
          _loadRemainingUserPreferences(userData);
        }
      }
      
      debugPrint('사용자 로그인 처리 완료: 온보딩 완료=$_isOnboardingCompleted');
    } catch (e) {
      debugPrint('사용자 로그인 처리 중 오류 발생: $e');
    }
  }
  
  // 나머지 사용자 설정 정보 백그라운드에서 로드
  Future<void> _loadRemainingUserPreferences(Map<String, dynamic> userData) async {
    try {
      // 우선순위가 낮은 설정 정보 로드
      if (userData['learningPurpose'] != null) {
        await _preferencesService.setLearningPurpose(userData['learningPurpose']);
      }
      
      final useSegmentMode = userData['translationMode'] == 'segment';
      await _preferencesService.setUseSegmentMode(useSegmentMode);
      
      debugPrint('사용자 추가 설정 로드 완료');
    } catch (e) {
      debugPrint('사용자 추가 설정 로드 중 오류: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<HomeViewModel>(create: (_) => HomeViewModel()),
      ],
      child: MaterialApp(
        title: 'Pikabook',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.lightTheme, // 다크 모드 비활성화
        themeMode: ThemeMode.light,
        // 화면 방향 고정 (세로 모드만 지원)
        home: _buildHomeScreen(),
      ),
    );
  }

  Widget _buildHomeScreen() {
    // 에러 발생한 경우
    if (_error != null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 로고
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: Image.asset('assets/images/pikabook_bird.png'),
                  ),
                  const SizedBox(height: 24),
                  // 오류 메시지
                  const Text(
                    '오류가 발생했습니다',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 재시도 버튼
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _error = null;
                      });
                      _startInitialization();
                    },
                    child: const Text('다시 시도'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 초기화 중인 경우 로딩 화면 표시
    if (!_isInitialized) {
      return LoadingScreen(
        progress: _progress,
        message: _message,
        subMessage: _subMessage,
        onSkip: () {
          if (mounted) {
            setState(() {
              _isInitialized = true;
            });
          }
        },
      );
    }

    // 로그인 되지 않은 경우
    if (!_isUserAuthenticated) {
      return LoginScreen(
        onLoginSuccess: (user) {
          _handleUserLogin(user);
        },
        isInitializing: false,
      );
    }

    // 온보딩이 필요한 경우
    if (!_isOnboardingCompleted) {
      return OnboardingScreen(
        onComplete: () {
          setState(() {
            _isOnboardingCompleted = true;
          });
        },
      );
    }

    // 모든 조건 통과 - 홈 화면 표시
    return HomeScreen(
      showTooltip: _isFirstEntry,
      onCloseTooltip: () async {
        // 툴팁 표시 여부 업데이트
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('hasShownTooltip', true);
        setState(() {
          _isFirstEntry = false;
        });
      },
      initializationService: null, // 이전 방식에서 필요했던 객체는 null로 설정
    );
  }
}
