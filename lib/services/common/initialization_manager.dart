import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/storage/unified_cache_service.dart';
import '../../services/authentication/user_preferences_service.dart';
import '../../services/authentication/auth_service.dart';
import '../../services/text_processing/internal_cn_segmenter_service.dart';
import '../../services/media/image_service.dart';

/// 앱 초기화 단계를 정의합니다.
enum InitializationStep {
  preparing,     // 준비 중
  firebase,      // Firebase 초기화
  auth,          // 인증 상태 확인
  userData,      // 사용자 데이터 로드
  settings,      // 설정 로드
  cache,         // 캐시 준비
  finalizing,    // 마무리
  completed,     // 완료
}

/// 초기화 과정의 상태를 업데이트하는 리스너 정의
typedef InitializationProgressListener = void Function(
  InitializationStep step,
  double progress,
  String message,
);

/// 앱 초기화를 단계별로 관리하는 클래스
///
/// 각 초기화 단계의 진행 상황을 추적하고 UI에 진행률을 보고합니다.
/// 초기화 과정을 효율적으로 분산하여 앱 시작 시간을 최적화합니다.
class InitializationManager {
  // 싱글톤 패턴 구현
  static final InitializationManager _instance = InitializationManager._internal();
  factory InitializationManager() => _instance;
  
  // 서비스 참조
  final UnifiedCacheService _cacheService = UnifiedCacheService();
  final UserPreferencesService _prefsService = UserPreferencesService();
  final AuthService _authService = AuthService();
  
  // 초기화 상태 관리
  InitializationStep _currentStep = InitializationStep.preparing;
  double _progress = 0.0;
  String _message = '준비 중...';
  bool _isInitializing = false;
  bool _isCompleted = false;
  
  // 오류 정보
  String? _error;
  
  // 리스너 목록
  final List<InitializationProgressListener> _listeners = [];
  
  // 초기화 결과 컨트롤러
  final Completer<Map<String, dynamic>> _resultCompleter = Completer<Map<String, dynamic>>();
  
  // 생성자
  InitializationManager._internal();
  
  // 게터
  InitializationStep get currentStep => _currentStep;
  double get progress => _progress;
  String get message => _message;
  bool get isInitializing => _isInitializing;
  bool get isCompleted => _isCompleted;
  String? get error => _error;
  
  // 초기화 결과 Future
  Future<Map<String, dynamic>> get result => _resultCompleter.future;
  
  // 리스너 추가
  void addListener(InitializationProgressListener listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
      
      // 즉시 현재 상태를 리스너에게 알림
      listener(_currentStep, _progress, _message);
    }
  }
  
  // 리스너 제거
  void removeListener(InitializationProgressListener listener) {
    _listeners.remove(listener);
  }
  
  // 진행 상태 업데이트
  void _updateProgress(
    InitializationStep step,
    double progress,
    String message,
  ) {
    _currentStep = step;
    _progress = progress.clamp(0.0, 1.0);
    _message = message;
    
    // 모든 리스너에게 알림
    for (final listener in _listeners) {
      listener(_currentStep, _progress, _message);
    }
    
    // 디버그 로그
    debugPrint('초기화 진행: ${(progress * 100).toStringAsFixed(1)}% - $message');
  }
  
  // 초기화 시작
  Future<Map<String, dynamic>> initialize() async {
    if (_isInitializing) {
      return result; // 이미 초기화 중인 경우 결과 반환
    }
    
    if (_isCompleted) {
      return {
        'isLoggedIn': FirebaseAuth.instance.currentUser != null,
        'hasLoginHistory': await _prefsService.hasLoginHistory(),
        'isOnboardingCompleted': await _prefsService.getOnboardingCompleted(),
        'error': null,
      };
    }
    
    _isInitializing = true;
    _error = null;
    
    try {
      // 1. 준비 단계: 초기화 시작
      _updateProgress(
        InitializationStep.preparing,
        0.1,
        '준비 중...',
      );
      
      // 2. 인증 상태 확인 (가장 중요한 단계)
      _updateProgress(
        InitializationStep.auth,
        0.3,
        '인증 상태 확인 중...',
      );
      
      // 현재 사용자 및 로그인 상태 확인
      final currentUser = FirebaseAuth.instance.currentUser;
      final bool isLoggedIn = currentUser != null;
      final bool hasLoginHistory = await _prefsService.hasLoginHistory();
      final bool isOnboardingCompleted = isLoggedIn ? await _prefsService.getOnboardingCompleted() : false;
      
      // 툴팁 표시 여부 확인 - SharedPreferences에서 직접 가져옴
      final prefs = await SharedPreferences.getInstance();
      final bool hasShownTooltip = prefs.getBool('hasShownTooltip') ?? false;
      final bool isFirstEntry = !hasShownTooltip;
      
      // 3. 사용자 데이터 로드 (필수 정보만)
      _updateProgress(
        InitializationStep.userData,
        0.6,
        '사용자 데이터 로드 중...',
      );
      
      // 기본 초기화 결과
      final initialResult = {
        'isLoggedIn': isLoggedIn,
        'hasLoginHistory': hasLoginHistory,
        'isOnboardingCompleted': isOnboardingCompleted,
        'isFirstEntry': isFirstEntry,
        'error': null,
      };
      
      // 백그라운드에서 나머지 작업 계속 진행
      _continueInitializationInBackground(isLoggedIn, currentUser);
      
      // 완료 상태 및 결과 업데이트
      if (!_resultCompleter.isCompleted) {
        _resultCompleter.complete(initialResult);
      }
      
      _isInitializing = false;
      _isCompleted = true;
      
      return initialResult;
      
    } catch (e) {
      _error = '초기화 중 오류가 발생했습니다: $e';
      debugPrint('초기화 오류: $_error');
      
      // 오류 상태 업데이트
      _isInitializing = false;
      
      final result = {
        'isLoggedIn': false,
        'hasLoginHistory': false,
        'isOnboardingCompleted': false,
        'isFirstEntry': true,
        'error': _error,
      };
      
      if (!_resultCompleter.isCompleted) {
        _resultCompleter.complete(result);
      }
      
      // 현재 단계를 오류 메시지로 업데이트
      _updateProgress(
        _currentStep, 
        _progress, 
        '오류가 발생했습니다',
      );
      
      return result;
    }
  }
  
  // 백그라운드에서 추가 초기화 작업 수행
  Future<void> _continueInitializationInBackground(bool isLoggedIn, User? currentUser) async {
    try {
      // 4. 앱 설정 로드
      _updateProgress(
        InitializationStep.settings,
        0.7,
        '설정 로드 중...',
      );
      
      await _loadAppSettings();
      
      // 5. 캐시 준비 (우선순위 낮음)
      _updateProgress(
        InitializationStep.cache,
        0.9,
        '캐시 준비 중...',
      );
      
      await _cacheService.initialize();
      
      // 6. 마무리 작업 (정리, 최적화 등)
      _updateProgress(
        InitializationStep.finalizing,
        0.95,
        '마무리 중...',
      );
      
      // 오래된 캐시 정리
      await _cleanupOldCache();
      
      // 임시 파일 정리
      final imageService = ImageService();
      await imageService.cleanupTempFiles();
      
      // 7. 완료
      _updateProgress(
        InitializationStep.completed,
        1.0,
        '초기화 완료',
      );
      
      debugPrint('백그라운드 초기화 작업 완료');
    } catch (e) {
      debugPrint('백그라운드 초기화 작업 중 오류: $e');
      // 백그라운드 오류는 앱 실행에 영향을 주지 않음
    }
  }
  
  // 앱 설정 로드
  Future<void> _loadAppSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // 중국어 분할 설정 로드
      InternalCnSegmenterService.isSegmentationEnabled =
          prefs.getBool('segmentation_enabled') ?? false;
      
      // 언어 설정 로드 - 기본값 설정
      final sourceLanguage = await _cacheService.getSourceLanguage();
      final targetLanguage = await _cacheService.getTargetLanguage();
      
      debugPrint('언어 설정 로드 완료 - 소스: $sourceLanguage, 타겟: $targetLanguage');
    } catch (e) {
      debugPrint('앱 설정 로드 중 오류: $e');
      // 기본값 설정
      InternalCnSegmenterService.isSegmentationEnabled = false;
    }
  }
  
  // 오래된 캐시 정리
  Future<void> _cleanupOldCache() async {
    try {
      await _cacheService.cleanupOldCache();
      debugPrint('오래된 캐시 정리 완료');
    } catch (e) {
      debugPrint('캐시 정리 중 오류: $e');
    }
  }
  
  // 초기화 리셋 (테스트용)
  void reset() {
    _isInitializing = false;
    _isCompleted = false;
    _currentStep = InitializationStep.preparing;
    _progress = 0.0;
    _message = '준비 중...';
    _error = null;
  }
} 