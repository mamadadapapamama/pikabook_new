import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../authentication/user_preferences_service.dart';

import '../authentication/deleted_user_service.dart';
import '../media/image_service.dart';
import 'usage_limit_service.dart';



/// 앱 초기화 단계를 정의합니다.
enum InitializationStep {
  preparing,     // 준비 중
  firebase,      // Firebase 초기화
  auth,          // 인증 상태 확인
  userData,      // 사용자 데이터 로드
  usageCheck,    // 사용량 확인
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
  final UserPreferencesService _prefsService = UserPreferencesService();

  final DeletedUserService _deletedUserService = DeletedUserService();
  final UsageLimitService _usageLimitService = UsageLimitService();
  
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
  Completer<Map<String, dynamic>> _resultCompleter = Completer<Map<String, dynamic>>();
  
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
      // 이미 완료된 경우 저장된 결과 반환
      return result;
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
      
      // 현재 사용자 및 로그인 상태 확인 (Firebase Auth 초기화 대기)
      await FirebaseAuth.instance.authStateChanges().first;
      final currentUser = FirebaseAuth.instance.currentUser;
      bool isLoggedIn = currentUser != null;
      
      
      
      // 탈퇴된 사용자인지 확인 (로그인되어 있는 경우만)
      if (isLoggedIn && currentUser != null) {
        final isDeletedUser = await _checkIfUserDeleted(currentUser.uid);
        if (isDeletedUser) {
          debugPrint('탈퇴된 사용자 감지 - 자동 로그아웃 처리: ${currentUser.uid}');
          await FirebaseAuth.instance.signOut();
          final prefs = await SharedPreferences.getInstance();
          await prefs.clear(); // 모든 로컬 데이터 삭제
          isLoggedIn = false;
        }
      }
      
      final bool hasLoginHistory = await _prefsService.hasLoginHistory();
      
      // Firebase에서 온보딩 상태 직접 확인
      bool isOnboardingCompleted = false;
      if (isLoggedIn && currentUser != null) {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get();
          
          if (userDoc.exists) {
            final userData = userDoc.data() as Map<String, dynamic>;
            isOnboardingCompleted = userData['onboardingCompleted'] as bool? ?? false;
            
            if (kDebugMode) {
              debugPrint('🔍 [InitializationManager] Firebase에서 온보딩 상태: $isOnboardingCompleted');
            }
          }
        } catch (e) {
          debugPrint('Firebase 온보딩 상태 확인 실패: $e');
          isOnboardingCompleted = false;
        }
      }
      

      
      // 3. 사용량 확인 (로그인된 사용자이고 온보딩 완료된 경우만)
      Map<String, bool> usageLimitStatus = {};
      if (isLoggedIn && isOnboardingCompleted) {
        _updateProgress(
          InitializationStep.usageCheck,
          0.5,
          '사용량 확인 중...',
        );
        
        try {
          // 🎯 로그인 직후에는 강제 새로고침으로 정확한 상태 확인 (재시도 로직 포함)
          usageLimitStatus = await _retryFirebaseOperation(() async {
            final result = await _usageLimitService.checkInitialLimitStatus(forceRefresh: true);
            if (kDebugMode) {
              debugPrint('🔍 [InitializationManager] checkInitialLimitStatus 결과: $result');
            }
            return result;
          });
          debugPrint('초기화 중 사용량 확인 완료 (강제 새로고침): $usageLimitStatus');
        } catch (e) {
          debugPrint('초기화 중 사용량 확인 실패 (재시도 후): $e');
          // 사용량 확인 실패 시 기본값 설정
          usageLimitStatus = {
            'ocrLimitReached': false,
            'ttsLimitReached': false,
          };
        }
      } else {
        // 온보딩 미완료 사용자는 사용량 확인 건너뛰기
        if (isLoggedIn && !isOnboardingCompleted) {
          debugPrint('온보딩 미완료 사용자 - 사용량 확인 건너뛰기');
        }
        usageLimitStatus = {
          'ocrLimitReached': false,
          'ttsLimitReached': false,
        };
      }
      
      // 4. 사용자 데이터 로드 (필수 정보만)
      _updateProgress(
        InitializationStep.userData,
        0.6,
        '사용자 데이터 로드 중...',
      );
      
      // 5. 최종 처리
      _updateProgress(
        InitializationStep.finalizing,
        0.8,
        '초기화 마무리 중...',
      );
      
      // 기본 초기화 결과
      final initialResult = {
        'isLoggedIn': isLoggedIn,
        'hasLoginHistory': hasLoginHistory,
        'isOnboardingCompleted': isOnboardingCompleted,
        'error': null,
      };
      
      if (kDebugMode) {
        debugPrint('🎯 [InitializationManager] 최종 초기화 결과:');
        debugPrint('  - isLoggedIn: $isLoggedIn');
        debugPrint('  - isOnboardingCompleted: $isOnboardingCompleted');
      }
      
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
        'usageLimitStatus': {},
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
      // 5. 앱 설정 로드
      _updateProgress(
        InitializationStep.settings,
        0.7,
        '설정 로드 중...',
      );
      
      await _loadAppSettings();
      
      // 6. 마무리 작업 (정리, 최적화 등)
      _updateProgress(
        InitializationStep.finalizing,
        0.95,
        '마무리 중...',
      );
      
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
      // 일반 앱 설정 로드
      if (kDebugMode) {
        debugPrint('앱 설정 로드 중...');
      }
      
      // 사용자 설정 모드 디버깅 (세그먼트 모드 상태 확인) - 릴리즈 모드에서는 스킵
      if (kDebugMode) {
        try {
          final userPrefs = await _prefsService.getPreferences();
          debugPrint('🔍 초기화 중 사용자 설정 디버깅:');
          debugPrint('  세그먼트 모드: ${userPrefs.useSegmentMode}');
          debugPrint('  소스 언어: ${userPrefs.sourceLanguage}');
          debugPrint('  타겟 언어: ${userPrefs.targetLanguage}');
        } catch (e) {
          debugPrint('⚠️ 사용자 설정 디버깅 실패: $e');
        }
      }
      
      if (kDebugMode) {
        debugPrint('앱 설정 로드 완료');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('앱 설정 로드 중 오류: $e');
      }
    }
  }
  
  // 탈퇴된 사용자인지 확인
  Future<bool> _checkIfUserDeleted(String userId) async {
    try {
      return await _deletedUserService.isDeletedUser();
    } catch (e) {
      debugPrint('탈퇴된 사용자 확인 중 오류: $e');
      return false; // 오류 시 false 반환 (보수적 접근)
    }
  }

  /// Firebase 작업 재시도 로직
  /// 네트워크 연결 문제로 인한 일시적 오류에 대비
  Future<T> _retryFirebaseOperation<T>(Future<T> Function() operation, {int maxRetries = 3}) async {
    int attempts = 0;
    while (attempts < maxRetries) {
      try {
        return await operation();
      } catch (e) {
        attempts++;
        final isNetworkError = e.toString().contains('Unavailable') || 
                              e.toString().contains('Network') ||
                              e.toString().contains('connectivity');
        
        if (isNetworkError && attempts < maxRetries) {
          final delay = Duration(milliseconds: 1000 * attempts); // 1초, 2초, 3초
          if (kDebugMode) {
            debugPrint('🔄 Firebase 네트워크 오류 감지, ${delay.inSeconds}초 후 재시도 ($attempts/$maxRetries): $e');
          }
          await Future.delayed(delay);
          continue;
        }
        
        // 네트워크 오류가 아니거나 최대 재시도 횟수 도달
        rethrow;
      }
    }
    
    throw Exception('Firebase 작업 재시도 한계 초과');
  }



  // 초기화 상태 리셋 (재초기화용)
  void reset() {
    if (kDebugMode) {
      debugPrint('🔄 [InitializationManager] 초기화 상태 리셋');
    }
    
    _isInitializing = false;
    _isCompleted = false;
    _error = null;
    _currentStep = InitializationStep.preparing;
    _progress = 0.0;
    _message = '준비 중...';
    
    // 새로운 Completer 생성
    if (_resultCompleter.isCompleted) {
      _resultCompleter = Completer<Map<String, dynamic>>();
    }
  }
  
  /// 🧪 테스트용: 사용자 문서에 이전 플랜 이력 추가
  @pragma('vm:prefer-inline')
  Future<void> _addPlanHistoryToUser(String userId, String email) async {
    try {
      final firestore = FirebaseFirestore.instance;
      
      // 현재 사용자 문서 확인
      final userDoc = await firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        debugPrint('⚠️ [테스트] 사용자 문서가 존재하지 않음: $userId');
        return;
      }
      
      final userData = userDoc.data() as Map<String, dynamic>;
      final hasEverUsedTrial = userData['hasEverUsedTrial'] as bool? ?? false;
      final hasEverUsedPremium = userData['hasEverUsedPremium'] as bool? ?? false;
      
      // 이미 플랜 이력이 있으면 추가하지 않음
      if (hasEverUsedTrial && (email == 'expired@test.com' || hasEverUsedPremium)) {
        debugPrint('🧪 [테스트] $email 이미 플랜 이력 있음, 추가하지 않음');
        return;
      }
      
      // 플랜 이력 추가
      Map<String, dynamic> updateData = {
        'hasEverUsedTrial': true,
        'hasUsedFreeTrial': true,
      };
      
      // 프리미엄 이력이 필요한 계정들
      if (email == 'pexpired@test.com' || email == 'yearlyexpired@test.com') {
        updateData.addAll({
          'hasEverUsedPremium': true,
          'lastPremiumSubscriptionType': email == 'yearlyexpired@test.com' ? 'yearly' : 'monthly',
          'lastPremiumExpiredAt': FieldValue.serverTimestamp(),
        });
      }
      
      await firestore.collection('users').doc(userId).update(updateData);
      
      debugPrint('🧪 [테스트] $email 플랜 이력 추가 완료: $updateData');
    } catch (e) {
      debugPrint('❌ [테스트] 플랜 이력 추가 실패: $e');
      rethrow;
    }
  }
} 