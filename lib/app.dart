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
import 'package:flutter/rendering.dart';

class App extends StatefulWidget {
  const App({Key? key}) : super(key: key);

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  // 앱 상태 변수
  bool _isInitialized = false;
  bool _isUserAuthenticated = false;
  bool _isOnboardingCompleted = false;
  bool _isFirstEntry = false;
  bool _hasLoginHistory = false;
  double _progress = 0.0;
  String? _error;
  
  // 로딩 단계 추적을 위한 상태 메시지 (UI에는 표시되지 않음)
  String _message = '앱 준비 중...';
  
  // 서비스들
  final InitializationManager _initManager = InitializationManager();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserPreferencesService _preferencesService = UserPreferencesService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 인증 상태 변경 구독 취소용 변수
  StreamSubscription<User?>? _authStateSubscription;
  
  // 앱 시작 시간 기록
  final DateTime _appStartTime = DateTime.now();
  
  @override
  void initState() {
    super.initState();
    debugPrint('App initState 호출됨 (${DateTime.now().toString()})');
    
    // iOS 앱 스토어 리뷰를 위한 최적화: 앱 실행 우선순위 높이기
    SystemChannels.platform.invokeMethod<void>('SystemChrome.setSystemUIOverlayStyle', <String, dynamic>{
      'key': 'enableFastApp',
      'value': true,
    }).catchError((e) => debugPrint('UI 우선순위 설정 실패: $e'));
    
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
    
    // iOS 앱 스토어 리뷰를 위한 최적화: 타임아웃 시간을 8초로 단축
    Future.delayed(const Duration(seconds: 8), () {
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
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      // 인증 상태 변경 감지
      _setupAuthStateListener();
      
      // 초기화 로직 실행
      await _initializeApp();
    } catch (e) {
      debugPrint('❌ Firebase 초기화 오류: $e');
      setState(() {
        _error = 'Firebase 초기화 중 오류 발생: $e';
        _progress = 0.0;
      });
    }
  }
  
  // 앱 초기화 로직
  Future<void> _initializeApp() async {
    try {
      // Firestore 설정
      await _setupFirestore();
      
      // 앱 데이터 초기화
      await _loadAppData();
      
      setState(() {
        _progress = 1.0;
        _message = '앱 준비 완료';
        _isInitialized = true;
      });
    } catch (e) {
      debugPrint('❌ 앱 초기화 오류: $e');
      setState(() {
        _error = '앱 초기화 중 오류 발생: $e';
        _progress = 0.0;
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
    // 초기화 상태에 따라 다른 화면 표시
    if (!_isInitialized) {
      // iOS 앱 스토어 리뷰를 위한 최적화: 로딩 화면 성능 개선
      return LoadingScreen(
        progress: _progress,
        message: _message,
        error: _error,
        optimizeForAppReview: true, // 앱 스토어 심사를 위한 최적화 플래그
      );
    }
    
    // 에러 발생 시
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                '오류가 발생했습니다',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                    _isInitialized = false;
                    _progress = 0.0;
                  });
                  _initializeFirebase();
                },
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
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
