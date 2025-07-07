import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/services/authentication/user_preferences_service.dart';
import '../../core/services/authentication/auth_service.dart';
import '../../core/services/common/support_service.dart';
import '../../core/services/subscription/unified_subscription_manager.dart';
import '../../core/services/subscription/unified_subscription_manager.dart';
import '../../core/models/subscription_state.dart';
import '../../core/models/plan.dart';
import '../../core/models/plan_status.dart';
import '../../core/utils/language_constants.dart';
import '../../core/services/text_processing/text_processing_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsViewModel extends ChangeNotifier {
  final UserPreferencesService _userPreferences = UserPreferencesService();
  final SupportService _supportService = SupportService();

  final AuthService _authService = AuthService();

  // 로딩 상태
  bool _isLoading = false;
  bool get isLoading => _isLoading;
  
  // 🔄 현재 사용자 ID 추적 (사용자 변경 감지용)
  String? _lastUserId;

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
  
  // 🎯 구독 상태별 CTA 정보
  PlanStatus? _planStatus;
  String _ctaButtonText = '';
  bool _ctaButtonEnabled = true;
  String _ctaSubtext = '';
  bool _shouldUsePremiumQuota = false;

  String get planType => _planType ?? 'free';
  String get planName => _planName ?? '로딩 중...';
  int get remainingDays => _remainingDays;
  Map<String, int> get planLimits => _planLimits;
  bool get isPlanLoaded => _isPlanLoaded;
  
  // 🎯 CTA 관련 getters
  String get ctaButtonText => _ctaButtonText;
  bool get ctaButtonEnabled => _ctaButtonEnabled;
  String get ctaSubtext => _ctaSubtext;
  bool get shouldUsePremiumQuota => _shouldUsePremiumQuota;

  /// 초기 데이터 로드
  Future<void> initialize() async {
    // 🔄 사용자 변경 감지
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isUserChanged = _lastUserId != null && _lastUserId != currentUserId;
    
    if (isUserChanged) {
      if (kDebugMode) {
        print('🔄 [Settings] 사용자 변경 감지: $_lastUserId → $currentUserId');
      }
      // 사용자가 변경된 경우 모든 데이터 초기화
      _resetAllData();
    }
    
    _lastUserId = currentUserId;
    
    // 🔄 사용자 변경 감지를 위해 강제로 최신 데이터 로드
    await loadUserData();
    await loadUserPreferences();
    await loadPlanInfo();
  }
  
  /// 모든 데이터 초기화 (사용자 변경 시)
  void _resetAllData() {
    _currentUser = null;
    _userName = '';
    _noteSpaceName = '';
    _sourceLanguage = SourceLanguage.DEFAULT;
    _targetLanguage = TargetLanguage.DEFAULT;
    _useSegmentMode = false;
    _planType = null;
    _planName = null;
    _remainingDays = 0;
    _planLimits = {};
    _isPlanLoaded = false;
    notifyListeners();
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
      
      // 🎯 UnifiedSubscriptionManager에서 통합 구독 상태 가져오기
      final unifiedManager = UnifiedSubscriptionManager();
      final subscriptionState = await unifiedManager.getSubscriptionState(forceRefresh: true);
      
      if (kDebugMode) {
        print('📥 [Settings] 강제 새로고침 결과:');
        print('   구독 상태: $subscriptionState');
        print('   상태 메시지: ${subscriptionState.statusMessage}');
        print('   프리미엄 여부: ${subscriptionState.isPremium}');
        print('   체험 여부: ${subscriptionState.isTrial}');
        print('   남은 일수: ${subscriptionState.daysRemaining}');
      }
      
      // 🎯 구독 상태 저장
      _planStatus = subscriptionStatus.planStatus;
      
      // UI에 표시할 정보 설정
      if (subscriptionStatus.isPremium) {
        _planType = 'premium';
      } else if (subscriptionStatus.isTrial) {
        _planType = 'premium'; // 체험도 프리미엄으로 분류
      } else {
        _planType = 'free';
      }
      
      // 🎯 남은 일수 포함한 표시명 설정
      _planName = subscriptionStatus.displayName;
      _remainingDays = subscriptionStatus.daysUntilExpiration;
      
      // 🎯 구독 상태별 CTA 및 쿼터 설정
      _configureCTAAndQuota(subscriptionStatus);
      
      _isPlanLoaded = true;
      notifyListeners();
      
      if (kDebugMode) {
        print('✅ [Settings] 강제 새로고침 완료');
        print('   UI 표시명: $_planName');
        print('   플랜 타입: $_planType');
        print('   남은 일수: $_remainingDays');
        print('   CTA 버튼: $_ctaButtonText (활성화: $_ctaButtonEnabled)');
        print('   프리미엄 쿼터 사용: $_shouldUsePremiumQuota');
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
      _planStatus = PlanStatus.free;
      _configureCTAAndQuota(null); // 기본 무료 플랜 설정
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
      
      // 🎯 AppStoreSubscriptionService에서 직접 구독 상태 가져오기
      final appStoreService = AppStoreSubscriptionService();
      final subscriptionStatus = await appStoreService.getCurrentSubscriptionStatus(forceRefresh: true);
      
      if (kDebugMode) {
        print('📥 [Settings] App Store 구독 상태 조회 결과:');
        print('   구독 상태: $subscriptionStatus');
        print('   상태 메시지: ${subscriptionStatus.displayName}');
        print('   프리미엄 여부: ${subscriptionStatus.isPremium}');
        print('   체험 여부: ${subscriptionStatus.isTrial}');
        print('   남은 일수: ${subscriptionStatus.daysUntilExpiration}');
      }
      
      // 🎯 구독 상태 저장
      _planStatus = subscriptionStatus.planStatus;
      
      // UI에 표시할 정보 설정
      if (subscriptionStatus.isPremium) {
        _planType = 'premium';
      } else if (subscriptionStatus.isTrial) {
        _planType = 'premium'; // 체험도 프리미엄으로 분류
      } else {
        _planType = 'free';
      }
      
      // 🎯 남은 일수 포함한 표시명 설정
      _planName = subscriptionStatus.displayName;
      _remainingDays = subscriptionStatus.daysUntilExpiration;
      
      // 🎯 구독 상태별 CTA 및 쿼터 설정
      _configureCTAAndQuota(subscriptionStatus);
      
      _isPlanLoaded = true;
      notifyListeners();
      
      if (kDebugMode) {
        print('✅ [Settings] App Store 기반 플랜 정보 로드 완료');
        print('   UI 표시명: $_planName');
        print('   플랜 타입: $_planType');
        print('   남은 일수: $_remainingDays');
        print('   CTA 버튼: $_ctaButtonText (활성화: $_ctaButtonEnabled)');
        print('   프리미엄 쿼터 사용: $_shouldUsePremiumQuota');
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
      _planStatus = PlanStatus.free;
      _configureCTAAndQuota(null); // 기본 무료 플랜 설정
      _isPlanLoaded = true;
      
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  /// 🎯 구독 상태별 CTA 버튼과 사용량 쿼터 설정
  void _configureCTAAndQuota(SubscriptionStatus? subscriptionStatus) {
    if (subscriptionStatus == null) {
      // 에러 상황 - 기본 무료 플랜으로 설정
      _ctaButtonText = '프리미엄으로 업그레이드';
      _ctaButtonEnabled = true;
      _ctaSubtext = '';
      _shouldUsePremiumQuota = false;
      _planLimits = {
        'ocrPages': 10,
        'ttsRequests': 30,
      };
      return;
    }

    switch (subscriptionStatus.planStatus) {
      case PlanStatus.trialActive:
        // trial active 일 경우
        _ctaButtonText = '${_remainingDays}일 뒤에 프리미엄 전환';
        _ctaButtonEnabled = false; // disabled
        _ctaSubtext = '구독 취소는 App Store에서';
        _shouldUsePremiumQuota = true; // premium quota
        _planLimits = {
          'ocrPages': 300,
          'ttsRequests': 1000,
        };
        break;

      case PlanStatus.trialCancelled:
        // trial cancelled 일 경우 - 무료로 전환
        _ctaButtonText = '${_remainingDays}일 뒤에 무료 플랜 전환';
        _ctaButtonEnabled = false; // disabled
        _ctaSubtext = ''; // 구독 취소는 App Store에서 문구 제거
        _shouldUsePremiumQuota = true; // premium quota (아직 체험 기간 중)
        _planLimits = {
          'ocrPages': 300,
          'ttsRequests': 1000,
        };
        break;

      case PlanStatus.trialCompleted:
        // trial completed 일 경우
        _ctaButtonText = '사용량 추가 문의';
        _ctaButtonEnabled = true;
        _ctaSubtext = '';
        _shouldUsePremiumQuota = true; // premium quota (trial 기간 사용량 포함)
        _planLimits = {
          'ocrPages': 300,
          'ttsRequests': 1000,
        };
        break;

      case PlanStatus.premiumActive:
        // 프리미엄 일 경우
        _ctaButtonText = '사용량 추가 문의';
        _ctaButtonEnabled = true;
        _ctaSubtext = '';
        _shouldUsePremiumQuota = true; // premium quota (trial 기간 사용량 포함)
        _planLimits = {
          'ocrPages': 300,
          'ttsRequests': 1000,
        };
        break;

      case PlanStatus.premiumCancelled:
        // 프리미엄 cancelled의 경우
        _ctaButtonText = '${_remainingDays}일 뒤에 무료 플랜 전환';
        _ctaButtonEnabled = false; // disabled
        _ctaSubtext = '';
        _shouldUsePremiumQuota = true; // premium quota
        _planLimits = {
          'ocrPages': 300,
          'ttsRequests': 1000,
        };
        break;

      case PlanStatus.premiumGrace:
        // 프리미엄 grace period의 경우
        _ctaButtonText = '앱스토어 결제 확인 필요';
        _ctaButtonEnabled = false; // disabled
        _ctaSubtext = '';
        _shouldUsePremiumQuota = true; // premium quota
        _planLimits = {
          'ocrPages': 300,
          'ttsRequests': 1000,
        };
        break;

      case PlanStatus.premiumExpired:
        // 프리미엄 expired
        _ctaButtonText = '프리미엄으로 업그레이드';
        _ctaButtonEnabled = true;
        _ctaSubtext = '';
        _shouldUsePremiumQuota = false; // 무료 quota
        _planLimits = {
          'ocrPages': 10,
          'ttsRequests': 30,
        };
        break;

      case PlanStatus.free:
      default:
        // 무료 플랜 일경우
        _ctaButtonText = '프리미엄으로 업그레이드';
        _ctaButtonEnabled = true;
        _ctaSubtext = '';
        _shouldUsePremiumQuota = false; // 무료 플랜 quota
        _planLimits = {
          'ocrPages': 10,
          'ttsRequests': 30,
        };
        break;
    }

    if (kDebugMode) {
      print('🎯 [Settings] CTA 설정 완료: ${subscriptionStatus.planStatus.name}');
      print('   버튼 텍스트: $_ctaButtonText');
      print('   버튼 활성화: $_ctaButtonEnabled');
      print('   서브텍스트: $_ctaSubtext');
      print('   프리미엄 쿼터: $_shouldUsePremiumQuota');
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
      
      await _supportService.contactSupport(subject: subject, body: body);
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