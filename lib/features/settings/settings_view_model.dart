import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/services/authentication/user_preferences_service.dart';
import '../../core/services/authentication/auth_service.dart';
import '../../core/services/common/plan_service.dart';
import '../../core/services/subscription/app_store_subscription_service.dart';
import '../../core/models/plan.dart';
import '../../core/utils/language_constants.dart';
import '../../core/services/text_processing/text_processing_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsViewModel extends ChangeNotifier {
  final UserPreferencesService _userPreferences = UserPreferencesService();
  final PlanService _planService = PlanService();

  final AuthService _authService = AuthService();

  // 로딩 상태
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  // 사용자 정보
  User? _currentUser;
  User? get currentUser => _currentUser;

  // 사용자 설정
  String _userName = '';
  String _noteSpaceName = '';
  String _sourceLanguage = SourceLanguage.DEFAULT;
  String _targetLanguage = TargetLanguage.DEFAULT;
  bool _useSegmentMode = false;

  String get userName => _userName;
  String get noteSpaceName => _noteSpaceName;
  String get sourceLanguage => _sourceLanguage;
  String get targetLanguage => _targetLanguage;
  bool get useSegmentMode => _useSegmentMode;

  // 플랜 정보 (App Store 기반)
  String? _planType;
  String? _planName;
  int _remainingDays = 0;
  Map<String, int> _planLimits = {};
  bool _isPlanLoaded = false;

  String get planType => _planType ?? 'free';
  String get planName => _planName ?? '로딩 중...';
  int get remainingDays => _remainingDays;
  Map<String, int> get planLimits => _planLimits;
  bool get isPlanLoaded => _isPlanLoaded;

  /// 초기 데이터 로드
  Future<void> initialize() async {
    await loadUserData();
    await loadUserPreferences();
    await loadPlanInfo();
  }

  /// 플랜 정보 새로고침 (설정 화면에서 수동 호출 가능)
  Future<void> refreshPlanInfo() async {
    if (kDebugMode) {
      print('🔄 [Settings] 플랜 정보 강제 새로고침 시작');
    }
    
    _isPlanLoaded = false;
    notifyListeners();
    
    // 강제 새로고침으로 서버에서 최신 데이터 가져오기
    await _loadPlanInfoWithForceRefresh();
  }
  
  /// 강제 새로고침으로 플랜 정보 로드
  Future<void> _loadPlanInfoWithForceRefresh() async {
    _setLoading(true);
    try {
      if (kDebugMode) {
        print('🔄 [Settings] App Store 기반 플랜 정보 강제 새로고침');
      }
      
      // App Store에서 강제 새로고침으로 최신 구독 상태 조회
      final appStoreService = AppStoreSubscriptionService();
      final appStoreStatus = await appStoreService.getCurrentSubscriptionStatus(forceRefresh: true);
      
      if (kDebugMode) {
        print('📥 [Settings] 강제 새로고침 결과:');
        print('   구독 상태: $appStoreStatus');
        print('   상태 메시지: ${appStoreStatus.displayName}');
        print('   프리미엄 여부: ${appStoreStatus.isPremium}');
        print('   체험 여부: ${appStoreStatus.isTrial}');
      }
      
      // UI에 표시할 정보 설정
      if (appStoreStatus.isPremium) {
        _planType = 'premium';
      } else if (appStoreStatus.isTrial) {
        _planType = 'premium'; // 체험도 프리미엄으로 분류
      } else {
        _planType = 'free';
      }
      
      _planName = appStoreStatus.displayName;
      _remainingDays = 0; // App Store에서 자동 관리
      
      // 플랜별 제한 설정 (간단화)
      if (appStoreStatus.isPremium || appStoreStatus.isTrial) {
        _planLimits = {
          'ocrPages': 300,
          'ttsRequests': 1000,
        };
      } else {
        _planLimits = {
          'ocrPages': 10,
          'ttsRequests': 30,
        };
      }
      
      _isPlanLoaded = true;
      notifyListeners();
      
      if (kDebugMode) {
        print('✅ [Settings] 강제 새로고침 완료');
        print('   UI 표시명: $_planName');
        print('   플랜 타입: $_planType');
        print('   제한: $_planLimits');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ [Settings] 강제 새로고침 오류: $e');
      }
      
      // 에러 발생 시 기본값 설정
      _planType = 'free';
      _planName = '새로고침 실패';
      _remainingDays = 0;
      _planLimits = {
        'ocrPages': 10,
        'ttsRequests': 30,
      };
      _isPlanLoaded = true;
      
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// 사용자 데이터 로드
  Future<void> loadUserData() async {
    _setLoading(true);
    try {
      _currentUser = FirebaseAuth.instance.currentUser;
    } catch (e) {
      if (kDebugMode) {
        print('사용자 정보 로드 오류: $e');
      }
    } finally {
      _setLoading(false);
    }
  }

  /// 사용자 설정 로드
  Future<void> loadUserPreferences() async {
    _setLoading(true);
    try {
      final preferences = await _userPreferences.getPreferences();
      
      _userName = preferences.userName ?? '사용자';
      _noteSpaceName = preferences.defaultNoteSpace;
      _sourceLanguage = preferences.sourceLanguage;
      _targetLanguage = preferences.targetLanguage;
      _useSegmentMode = preferences.useSegmentMode;
      
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('사용자 설정 로드 오류: $e');
      }
    } finally {
      _setLoading(false);
    }
  }

  /// 플랜 정보 로드 (App Store 기반)
  Future<void> loadPlanInfo() async {
    _setLoading(true);
    try {
      if (kDebugMode) {
        print('🔍 [Settings] App Store 기반 플랜 정보 로드 시작');
      }
      
      // App Store에서 캐시된 구독 상태 조회 (초기 로드는 캐시 우선)
      final appStoreService = AppStoreSubscriptionService();
      final appStoreStatus = await appStoreService.getCurrentSubscriptionStatus(forceRefresh: false);
      
      if (kDebugMode) {
          print('   구독 상태: $appStoreStatus');
          print('   상태 메시지: ${appStoreStatus.displayName}');
          print('   프리미엄 여부: ${appStoreStatus.isPremium}');
          print('   체험 여부: ${appStoreStatus.isTrial}');
      }
      
        // UI에 표시할 정보 설정
        if (appStoreStatus.isPremium) {
          _planType = 'premium';
        } else if (appStoreStatus.isTrial) {
          _planType = 'premium'; // 체험도 프리미엄으로 분류
        } else {
          _planType = 'free';
        }
        
        _planName = appStoreStatus.displayName;
        _remainingDays = 0; // App Store에서 자동 관리
        
        // 플랜별 제한 설정 (간단화)
        if (appStoreStatus.isPremium || appStoreStatus.isTrial) {
        _planLimits = {
          'ocrPages': 300,
          'ttsRequests': 1000,
        };
      } else {
        _planLimits = {
          'ocrPages': 10,
          'ttsRequests': 30,
        };
      }
      
      _isPlanLoaded = true;
      notifyListeners();
      
      if (kDebugMode) {
        print('✅ [Settings] App Store 기반 플랜 정보 로드 완료');
        print('   UI 표시명: $_planName');
        print('   플랜 타입: $_planType');
        print('   제한: $_planLimits');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ [Settings] App Store 기반 플랜 정보 로드 오류: $e');
      }
      
      // 에러 발생 시 기본값 설정
      _planType = 'free';
      _planName = 'App Store 연결 실패';
      _remainingDays = 0;
      _planLimits = {
        'ocrPages': 10,
        'ttsRequests': 30,
      };
      _isPlanLoaded = true;
      
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// 학습자 이름 업데이트
  Future<bool> updateUserName(String newName) async {
    if (newName.isEmpty) return false;
    
    try {
      final preferences = await _userPreferences.getPreferences();
      await _userPreferences.savePreferences(
        preferences.copyWith(
          userName: newName,
          defaultNoteSpace: "${newName}의 학습 노트"
        )
      );
      await loadUserPreferences();
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('학습자 이름 업데이트 오류: $e');
      }
      return false;
    }
  }

  /// 노트 스페이스 이름 업데이트
  Future<bool> updateNoteSpaceName(String newName) async {
    if (newName.isEmpty) return false;
    
    try {
      final preferences = await _userPreferences.getPreferences();
      final noteSpaces = List<String>.from(preferences.noteSpaces);
      
      // 노트 스페이스 이름 변경
      if (noteSpaces.contains(_noteSpaceName)) {
        final index = noteSpaces.indexOf(_noteSpaceName);
        noteSpaces[index] = newName;
      } else if (!noteSpaces.contains(newName)) {
        noteSpaces.add(newName);
      }
      
      await _userPreferences.savePreferences(
        preferences.copyWith(
          defaultNoteSpace: newName,
          noteSpaces: noteSpaces
        )
      );
      
      await loadUserPreferences();
      await _notifyNoteSpaceNameChanged(newName);
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('노트 스페이스 이름 업데이트 오류: $e');
      }
      return false;
    }
  }

  /// 원문 언어 업데이트
  Future<bool> updateSourceLanguage(String language) async {
    try {
      final preferences = await _userPreferences.getPreferences();
      await _userPreferences.savePreferences(
        preferences.copyWith(sourceLanguage: language)
      );
      await loadUserPreferences();
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('원문 언어 업데이트 오류: $e');
      }
      return false;
    }
  }

  /// 번역 언어 업데이트
  Future<bool> updateTargetLanguage(String language) async {
    try {
      final preferences = await _userPreferences.getPreferences();
      await _userPreferences.savePreferences(
        preferences.copyWith(targetLanguage: language)
      );
      await loadUserPreferences();
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('번역 언어 업데이트 오류: $e');
      }
      return false;
    }
  }

  /// 텍스트 처리 모드 업데이트
  Future<bool> updateTextProcessingMode(bool useSegmentMode) async {
    try {
      final preferences = await _userPreferences.getPreferences();
      await _userPreferences.savePreferences(
        preferences.copyWith(useSegmentMode: useSegmentMode)
      );
      
      // 텍스트 처리 모드 변경 시 모든 캐시된 텍스트 처리 결과 무효화
      final textProcessingService = TextProcessingService();
      await textProcessingService.invalidateAllProcessedTextCache();
      
      await loadUserPreferences();
      
      if (kDebugMode) {
        print('✅ 텍스트 처리 모드 변경 및 캐시 무효화 완료: useSegmentMode=$useSegmentMode');
      }
      
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('텍스트 처리 모드 업데이트 오류: $e');
      }
      return false;
    }
  }

  /// 재인증 필요 여부 확인
  Future<bool> isReauthenticationRequired() async {
    try {
      return await _authService.isReauthenticationRequired();
    } catch (e) {
      if (kDebugMode) {
        print('재인증 필요 여부 확인 오류: $e');
      }
      return false; // 에러 발생 시 재인증 불필요로 처리
    }
  }

  /// 계정 삭제
  Future<bool> deleteAccount() async {
    _setLoading(true);
    try {
      await _authService.deleteAccount();
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('계정 삭제 오류: $e');
      }
      // 에러를 다시 던져서 UI에서 구체적인 메시지를 표시할 수 있도록 함
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  /// 문의하기
  Future<bool> contactSupport() async {
    try {
      final planName = _planName;
      final subject = '[피카북] 사용량 문의';
      final body = '플랜: $planName\n'
                 '사용자 ID: ${_currentUser?.uid ?? '알 수 없음'}\n';
      
      await _planService.contactSupport(subject: subject, body: body);
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('문의하기 오류: $e');
      }
      return false;
    }
  }

  /// 노트스페이스 이름 변경 알림
  Future<void> _notifyNoteSpaceNameChanged(String newName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_notespace_change', DateTime.now().millisecondsSinceEpoch);
    await prefs.setString('last_changed_notespace_name', newName);
  }

  /// 로딩 상태 설정
  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }
} 