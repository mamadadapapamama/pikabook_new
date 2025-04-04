import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'dart:async'; // Timer 클래스를 위한 import
import 'package:flutter/services.dart'; // SystemChrome 사용을 위한 import
import 'theme/app_theme.dart';
import 'views/screens/home_screen.dart';
import 'services/initialization_manager.dart';
import 'services/user_preferences_service.dart';
import 'views/screens/onboarding_screen.dart';
import 'views/screens/login_screen.dart';
import 'widgets/loading_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'viewmodels/home_viewmodel.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

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
  
  // 초기화 상태 관리
  bool _isInitialized = false;
  InitializationStep _currentStep = InitializationStep.preparing;
  double _progress = 0.0;
  String _message = '앱 준비 중...';
  String? _subMessage;
  
  // 앱 시작 시간 기록
  final DateTime _appStartTime = DateTime.now();
  
  // 인증 상태 변경 구독 취소용 변수
  StreamSubscription<User?>? _authStateSubscription;
  
  @override
  void initState() {
    super.initState();
    debugPrint('App initState 호출됨 (${DateTime.now().toString()})');
    
    // 시스템 UI 스타일 설정
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.dark,
      ),
    );
    
    // Firebase 초기화 시작
    _initializeFirebase();
    
    // 타이머 추가 - 10초 후 강제로 진행 (최대 로딩 시간 제한)
    // 이 타임아웃 기능은 Firebase 초기화가 완료되지 않더라도 사용자가 앱을 사용할 수 있도록 합니다.
    // 초기화가 완료되지 않은 상태에서 다음 화면으로 넘어갈 경우:
    // 1. 백그라운드에서 초기화가 계속 진행됩니다.
    // 2. Firebase 관련 기능은 초기화가 완료될 때까지 사용할 수 없습니다.
    // 3. 로그인 화면 등 초기화가 필요한 화면에서는 각 서비스가 초기화 상태를 확인하고 적절히 처리합니다.
    Future.delayed(const Duration(seconds: 10), () {
      if (!_isInitialized && mounted) {
        debugPrint('타임아웃: 초기화 강제 진행');
        setState(() {
          _isInitialized = true;
          _message = '초기화 완료 (타임아웃)';
        });
      }
    });
  }
  
  @override
  void dispose() {
    // 인증 상태 리스너 해제
    _authStateSubscription?.cancel();
    super.dispose();
  }
  
  // Firebase 초기화 함수
  Future<void> _initializeFirebase() async {
    try {
      setState(() {
        _message = 'Firebase 초기화 중...';
        _progress = 0.1;
      });
      
      debugPrint('🔄 Firebase 초기화 시작...');
      
      // Firebase Auth 인증 지속성 설정 - 웹에서만 작동하는 기능이므로 모바일에서는 제거
      // 대신 앱 설치 여부 확인으로 처리
      
      // Firebase가 이미 초기화되었는지 확인
      if (Firebase.apps.isNotEmpty) {
        debugPrint('✅ Firebase 이미 초기화됨');
        setState(() {
          _progress = 0.3;
          _message = 'Firebase 서비스 설정 중...';
        });
        _setupFirebaseServices();
        return;
      }
      
      // Firebase가 초기화되지 않은 경우에만 초기화 시도 (main.dart에서 이미 초기화했을 가능성 높음)
      debugPrint('🔄 Firebase 새로 초기화 중...');
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        debugPrint('✅ Firebase 초기화 완료');
      } catch (e) {
        // 이미 초기화된 경우 발생하는 오류는 무시 (main.dart에서 이미 초기화했을 경우)
        if (e.toString().contains('duplicate-app')) {
          debugPrint('✅ Firebase가 이미 초기화되어 있습니다 (main.dart에서 초기화됨)');
        } else {
          // 다른 종류의 오류는 다시 던짐
          throw e;
        }
      }
      
      // 초기화 성공 표시
      setState(() {
        _progress = 0.3;
        _message = 'Firebase 서비스 설정 중...';
      });
      
      // Firebase 서비스 설정 시작
      _setupFirebaseServices();
    } catch (e) {
      debugPrint('❌ Firebase 초기화 오류: $e');
      setState(() {
        _error = 'Firebase 초기화 중 오류 발생: $e';
        _progress = 0.0;
      });
      
      // 3초 후 재시도
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          _initializeFirebase();
        }
      });
    }
  }
  
  // Firebase 서비스 설정
  void _setupFirebaseServices() {
    try {
      // Firestore 오프라인 지원 설정
      _setupFirestore();
      
      // 인증 상태 변경 리스너 설정
      _setupAuthStateListener();
      
      // 앱 데이터 초기화
      _loadAppData();
      
      setState(() {
        _progress = 0.5;
        _message = 'Firebase 서비스 초기화 완료';
      });
    } catch (e) {
      debugPrint('Firebase 서비스 설정 중 오류: $e');
      
      // 오류 발생 시 1초 후에 재시도
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _setupFirebaseServices();
        }
      });
    }
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
  
  // 인증 상태 변경 리스너 설정
  void _setupAuthStateListener() {
    try {
      // 기존 구독 취소
      _authStateSubscription?.cancel();
      
      // 새 구독 설정
      _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen((User? user) async {
        debugPrint('인증 상태 변경 감지: ${user != null ? '로그인' : '로그아웃'}');
        
        if (mounted) {
          if (user != null) {
            debugPrint('사용자 로그인됨: ${user.uid}');
            // 로그인 상태 처리
            _handleUserLogin(user);
          } else {
            debugPrint('사용자 로그아웃됨');
            
            // 로그아웃 시 사용자 설정 초기화
            try {
              // 사용자 데이터 초기화
              await _preferencesService.clearUserData();
              
              // 현재 사용자 ID도 초기화 (다음 로그인을 위해)
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('current_user_id');
              
              debugPrint('🔒 로그아웃 - 사용자 데이터 초기화 완료');
            } catch (e) {
              debugPrint('⚠️ 로그아웃 시 데이터 초기화 오류: $e');
            }
            
            // 로그아웃 상태 처리
            setState(() {
              _isUserAuthenticated = false;
              _isOnboardingCompleted = false;
              _hasLoginHistory = false;
              _isFirstEntry = false; // 툴팁 표시 상태도 초기화
            });
          }
        }
      }, onError: (error) {
        debugPrint('인증 상태 변경 리스너 오류: $error');
      });
    } catch (e) {
      debugPrint('인증 상태 변경 리스너 설정 실패: $e');
    }
  }
  
  // 앱 데이터 초기화
  Future<void> _loadAppData() async {
    try {
      // 기본 설정 로드
      final prefs = await SharedPreferences.getInstance();
      
      // 설치 첫 실행 확인 키
      const String appInstallKey = 'pikabook_installed';
      final bool isAppAlreadyInstalled = prefs.getBool(appInstallKey) ?? false;
      
      // 앱이 새로 설치된 경우(이전에 설치된 적이 없는 경우) 로그아웃 처리
      if (!isAppAlreadyInstalled) {
        debugPrint('새로운 앱 설치 감지: 로그아웃 처리 수행');
        // 설치 표시 설정
        await prefs.setBool(appInstallKey, true);
        
        // Firebase 로그아웃 수행
        if (FirebaseAuth.instance.currentUser != null) {
          debugPrint('기존 자동 로그인 방지: 로그아웃 실행');
          try {
            await FirebaseAuth.instance.signOut();
          } catch (e) {
            debugPrint('로그아웃 중 오류: $e');
          }
        }
        
        // 새 설치 시 모든 기존 설정 초기화
        await _preferencesService.clearAllUserPreferences();
      }
      
      // 1. 현재 사용자 로그인 상태 확인 (가장 우선)
      final isUserAuthenticated = FirebaseAuth.instance.currentUser != null;
      
      // 2. 로그인된 경우 노트 존재 확인 및 온보딩 상태 체크
      bool isOnboardingCompleted = false;
      bool hasNotes = false;
      
      if (isUserAuthenticated) {
        debugPrint('로그인된 사용자 감지: ${FirebaseAuth.instance.currentUser!.uid}');
        
        // 2.1 사용자의 노트 확인 - 노트가 있으면 온보딩 완료로 간주
        try {
          final notesSnapshot = await FirebaseFirestore.instance
              .collection('notes')
              .where('userId', isEqualTo: FirebaseAuth.instance.currentUser!.uid)
              .limit(1)
              .get();
              
          hasNotes = notesSnapshot.docs.isNotEmpty;
          
          if (hasNotes) {
            debugPrint('🔍 노트가 있는 사용자 감지 (${notesSnapshot.docs.length}개)');
            
            // 노트가 있으면 온보딩 완료로 간주하고 설정 업데이트
            isOnboardingCompleted = true;
            await _preferencesService.setOnboardingCompleted(true);
            
            // Firestore에도 온보딩 완료 상태 업데이트
            try {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(FirebaseAuth.instance.currentUser!.uid)
                  .update({'onboardingCompleted': true});
              debugPrint('✅ Firestore 사용자 문서에 온보딩 완료 상태 업데이트됨');
            } catch (e) {
              debugPrint('⚠️ Firestore 사용자 온보딩 상태 업데이트 실패: $e');
            }
          } else {
            debugPrint('🔍 노트가 없는 사용자');
            // 노트가 없으면 온보딩 완료 여부 확인
            isOnboardingCompleted = await _preferencesService.getOnboardingCompleted();
          }
        } catch (e) {
          debugPrint('⚠️ 노트 확인 중 오류: $e');
          // 오류 발생 시 기본 온보딩 상태 사용
          isOnboardingCompleted = await _preferencesService.getOnboardingCompleted();
        }
        
        // 로그인 기록 확인 및 저장
        await _preferencesService.saveLoginHistory();
      }
      
      // 3. 로그인 기록 확인 (UI에 표시 목적)
      final hasLoginHistory = prefs.getBool('login_history') ?? false;
      
      // 4. 툴팁 표시 여부 확인 - 온보딩 완료된 사용자만 관련 있음
      final hasShownTooltip = isOnboardingCompleted ? (prefs.getBool('hasShownTooltip') ?? false) : false;
      
      if (mounted) {
        setState(() {
          _hasLoginHistory = hasLoginHistory;
          _isOnboardingCompleted = isOnboardingCompleted;
          _isFirstEntry = isOnboardingCompleted && !hasShownTooltip; // 온보딩 완료된 사용자만 툴팁 관련
          _isUserAuthenticated = isUserAuthenticated;
          
          // 초기화 완료
          _isInitialized = true;
          _progress = 1.0;
          _message = '앱 준비 완료';
        });
      }
      
      debugPrint('앱 데이터 초기화 완료 - 로그인: $_isUserAuthenticated, 노트 있음: $hasNotes, 온보딩: $_isOnboardingCompleted, 툴팁 표시: $_isFirstEntry');
      
      final elapsed = DateTime.now().difference(_appStartTime);
      debugPrint('앱 초기화 완료 (소요시간: ${elapsed.inMilliseconds}ms)');
    } catch (e) {
      debugPrint('앱 데이터 초기화 중 오류: $e');
      
      // 오류가 있어도 앱은 계속 실행
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _progress = 1.0;
          _message = '앱 준비 완료 (일부 데이터 로드 실패)';
        });
      }
    }
  }

  // 로그인한 사용자 처리
  Future<void> _handleUserLogin(User user) async {
    try {
      setState(() {
        _isUserAuthenticated = true;
      });
      
      debugPrint('🔐 사용자 로그인 처리 시작: ${user.uid}');
      
      // 사용자 ID 설정 (사용자 변경 감지 및 데이터 초기화)
      await _preferencesService.setCurrentUserId(user.uid);
      
      // 1. 사용자 노트 존재 여부 확인 (가장 중요)
      bool hasNotes = false;
      bool isOnboardingCompleted = false;
      
      try {
        // 사용자의 노트 확인
        final notesSnapshot = await FirebaseFirestore.instance
            .collection('notes')
            .where('userId', isEqualTo: user.uid)
            .limit(1)
            .get();
            
        hasNotes = notesSnapshot.docs.isNotEmpty;
        
        if (hasNotes) {
          debugPrint('🔍 노트가 있는 사용자 감지 (${notesSnapshot.docs.length}개)');
          // 노트가 있으면 온보딩을 자동으로 완료 처리
          isOnboardingCompleted = true;
        }
      } catch (e) {
        debugPrint('⚠️ 노트 확인 중 오류: $e');
      }
      
      // 2. 사용자 정보 확인 - 기본 정보 로드
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
          
          // 노트 스페이스 명확하게 초기화
          if (userData['defaultNoteSpace'] != null) {
            // 노트 스페이스 설정
            await _preferencesService.setDefaultNoteSpace(userData['defaultNoteSpace']);
            debugPrint('사용자 노트 스페이스 설정: ${userData['defaultNoteSpace']}');
          } else {
            // 기본값으로 설정 (사용자 이름 기반)
            final userName = userData['userName'] ?? '사용자';
            final defaultNoteSpace = "${userName}의 학습노트";
            await _preferencesService.setDefaultNoteSpace(defaultNoteSpace);
            debugPrint('기본 노트 스페이스 생성: $defaultNoteSpace');
            
            // Firestore에 기본 노트 스페이스 저장
            await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
              'defaultNoteSpace': defaultNoteSpace
            });
          }
          
          // 3. 온보딩 상태 확인 및 업데이트
          if (!hasNotes) {
            // 노트가 없는 경우에만 기존 온보딩 상태 확인
            isOnboardingCompleted = userData['onboardingCompleted'] ?? await _preferencesService.getOnboardingCompleted();
            debugPrint('노트 없음 - 저장된 온보딩 상태: $isOnboardingCompleted');
          }
          
          // 4. 온보딩 상태 업데이트 (노트가 있는데 온보딩 완료 표시가 안 된 경우)
          if (hasNotes && !(userData['onboardingCompleted'] ?? false)) {
            // Firestore와 로컬 둘 다 온보딩 완료 상태 저장
            try {
              await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                'onboardingCompleted': true
              });
              debugPrint('✅ Firestore 사용자 문서에 온보딩 완료 상태 업데이트됨');
            } catch (e) {
              debugPrint('⚠️ Firestore 온보딩 상태 업데이트 실패: $e');
            }
          }
          
          // 로컬에 온보딩 상태 저장
          await _preferencesService.setOnboardingCompleted(isOnboardingCompleted);
          
          // 로그인 기록 저장
          await _preferencesService.saveLoginHistory();
          
          if (mounted) {
            setState(() {
              _isOnboardingCompleted = isOnboardingCompleted;
              _hasLoginHistory = true;
              
              // 온보딩 완료된 사용자만 툴팁 관련 설정
              if (isOnboardingCompleted) {
                final prefs = SharedPreferences.getInstance();
                prefs.then((p) {
                  _isFirstEntry = !(p.getBool('hasShownTooltip') ?? false);
                });
              } else {
                _isFirstEntry = false;
              }
            });
          }
          
          // 나머지 설정 정보는 백그라운드에서 로드
          _loadRemainingUserPreferences(userData);
        }
      }
      
      debugPrint('사용자 로그인 처리 완료: 노트 있음=$hasNotes, 온보딩 완료=$_isOnboardingCompleted');
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
        theme: AppTheme.lightTheme.copyWith(
          pageTransitionsTheme: PageTransitionsTheme(
            builders: {
              TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
              TargetPlatform.android: const ZoomPageTransitionsBuilder(),
              TargetPlatform.macOS: const CupertinoPageTransitionsBuilder(),
            },
          ),
          appBarTheme: AppBarTheme(
            systemOverlayStyle: const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark, // 안드로이드용
              statusBarBrightness: Brightness.light, // iOS용
            ),
          ),
        ),
        themeMode: ThemeMode.light, // 항상 라이트 모드 사용
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
                      _initializeFirebase();
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

    // 로그인된 경우 홈 화면 표시
    // 1. 온보딩이 이미 완료된 것으로 확인된 경우 홈 화면으로 이동
    if (_isOnboardingCompleted) {
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
      );
    }
    // 2. 온보딩이 필요한 경우 온보딩 화면으로 이동
    else {
      return OnboardingScreen(
        onComplete: () {
          setState(() {
            _isOnboardingCompleted = true;
          });
        },
      );
    }
  }
}
