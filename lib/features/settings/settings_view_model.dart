import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/services/authentication/user_preferences_service.dart';
import '../../core/services/authentication/auth_service.dart';
import '../../core/services/common/support_service.dart';
import '../../core/services/subscription/unified_subscription_manager.dart';
import '../../core/models/plan_status.dart';
import '../../core/utils/language_constants.dart';
import '../../core/services/text_processing/text_processing_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/plan_constants.dart';
import '../../core/widgets/pika_button.dart';
import '../../core/widgets/upgrade_modal.dart';


/// CTA 버튼 상태 모델
class CTAButtonModel {
  final String text;
  final PikaButtonVariant variant;
  final bool isEnabled;
  final VoidCallback? action;

  CTAButtonModel({
    required this.text,
    this.variant = PikaButtonVariant.primary,
    this.isEnabled = true,
    this.action,
  });
}

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
  
  // 🎯 v4-simplified: 내 플랜 상세 정보
  String _planTitle = '';
  String _planSubtitle = '';
  String _planStatusText = '';
  String? _nextPaymentDateText;
  String? _freeTransitionDateText;

  String get planTitle => _planTitle;
  String get planSubtitle => _planSubtitle;
  String get planStatusText => _planStatusText;
  String? get nextPaymentDateText => _nextPaymentDateText;
  String? get freeTransitionDateText => _freeTransitionDateText;

  // 🎯 CTA 관련 getters
  CTAButtonModel get ctaButton {
    // 현재 상태에 따라 다른 버튼 모델 반환
    if (_ctaButtonText.contains('문의')) {
      return CTAButtonModel(text: _ctaButtonText, action: () => contactSupport());
    }
    if (_ctaButtonText.contains('업그레이드')) {
      return CTAButtonModel(text: _ctaButtonText, action: () => _showUpgradeModal(null));
    }
    if (_ctaButtonText.contains('App Store')) {
       return CTAButtonModel(text: _ctaButtonText, action: () => _openAppStore());
    }
    return CTAButtonModel(
      text: _ctaButtonText, 
      variant: _ctaButtonEnabled ? PikaButtonVariant.primary : PikaButtonVariant.outline,
      isEnabled: _ctaButtonEnabled,
    );
  }

  String get ctaSubtext => _ctaSubtext;
  bool get shouldUsePremiumQuota => _shouldUsePremiumQuota;

  // v4-simplified: 서버에서 직접 hasUsedTrial 제공
  bool _hasUsedTrial = false;

  // v4-simplified 체험 이력 getter들 (서버 기반)
  bool get hasUsedFreeTrial => _hasUsedTrial;
  bool get hasEverUsedTrial => _hasUsedTrial;

  /// 초기 데이터 로드
  Future<void> initialize() async {
    // 🔄 사용자 변경 감지
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isUserChanged = _lastUserId != null && _lastUserId != currentUserId;
    
    if (isUserChanged) {
      if (kDebugMode) {
        print('🔄 [Settings] 사용자 변경 감지');
      }
      // 사용자가 변경된 경우 모든 데이터 초기화
      _resetAllData();
      
      // 🎯 UnifiedSubscriptionManager 캐시도 무효화 (중요!)
      final subscriptionManager = UnifiedSubscriptionManager();
      subscriptionManager.invalidateCache();
    }
    
    _lastUserId = currentUserId;
    
    // 🔄 사용자 변경이 있었다면 강제 새로고침, 아니면 캐시 활용
    await loadUserData();
    await loadUserPreferences();
    
    if (isUserChanged) {
      // 🚨 사용자 변경 시 반드시 강제 새로고침 (이전 사용자 데이터 방지)
      await _loadPlanInfoWithForceRefresh();
    } else {
      // 동일 사용자면 캐시 활용
      await loadPlanInfo();
    }
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
    _hasUsedTrial = false;
    notifyListeners();
  }

  /// 플랜 정보 새로고침 (설정 화면에서 수동 호출 가능)
  Future<void> refreshPlanInfo() async {
    if (kDebugMode) {
      print('🔄 [Settings] 사용자 요청으로 플랜 정보 새로고침 (동적 캐시 적용)');
    }
    
    _isPlanLoaded = false;
    notifyListeners();
    
    // 🎯 새로운 동적 캐시 메서드 사용 (웹훅/수동 새로고침 전용)
    final subscriptionManager = UnifiedSubscriptionManager();
    await subscriptionManager.getSubscriptionState(forceRefresh: true);
    
    // 🎯 캐시가 이미 갱신되었으므로 일반 로드 메서드 사용
    await loadPlanInfo();
  }
  

  
  /// 강제 새로고침으로 플랜 정보 로드 (v4-simplified 직접 처리)
  Future<void> _loadPlanInfoWithForceRefresh() async {
    _setLoading(true);
    try {

      
      // 🎯 UnifiedSubscriptionManager에서 구독 상태 가져오기
      final subscriptionManager = UnifiedSubscriptionManager();
      final entitlements = await subscriptionManager.getSubscriptionEntitlements(forceRefresh: true);
      
      if (kDebugMode) {
        print('📥 [Settings] 구독 상태: ${entitlements['entitlement']} (${entitlements['subscriptionStatus']})');
      }
      
      // 구독 상태에서 필드 추출
      final entitlement = entitlements['entitlement'];
      final subscriptionStatus = entitlements['subscriptionStatus'];
      final hasUsedTrial = entitlements['hasUsedTrial'];
      final expirationDate = entitlements['expirationDate'] as String?;
      final subscriptionType = entitlements['subscriptionType'] as String?;
      
      if (kDebugMode) {
        print('🔍 [Settings] 체험 이력 디버그:');
        print('   entitlement: $entitlement');
        print('   subscriptionStatus: $subscriptionStatus');
        print('   hasUsedTrial (서버): $hasUsedTrial');
        print('   전체 서버 응답: $entitlements');
      }
      
      // 🎯 서버 응답 그대로 사용 (클라이언트 추론 없음)
      _hasUsedTrial = hasUsedTrial;
      
      if (kDebugMode) {
        print('✅ [Settings] 최종 hasUsedTrial: $_hasUsedTrial (서버 응답 그대로)');
      }
      
      // 🎯 기존 호환성을 위한 PlanStatus 설정 (레거시 UI용)
      _planStatus = _calculatePlanStatusFromServerResponse(entitlement, subscriptionStatus, _hasUsedTrial);
      
      // UI에 표시할 정보 설정
      if (entitlement == 'premium') {
        _planType = 'premium';
      } else if (entitlement == 'trial') {
        _planType = 'premium'; // 체험도 프리미엄으로 분류
      } else {
        _planType = 'free';
      }
      
      // 🎯 표시명과 CTA 설정 (v4-simplified 직접 처리 + 날짜 정보)
      _configureUIFromServerResponse(entitlement, subscriptionStatus, _hasUsedTrial, 
        expirationDate: expirationDate, subscriptionType: subscriptionType);
      
      _isPlanLoaded = true;
      notifyListeners();
      

    } catch (e) {
      if (kDebugMode) {
        print('❌ [Settings] 강제 새로고침 오류: $e');
      }
      
      // 에러 발생 시 기본값 설정 (v4-simplified 방식)
      _planType = 'free';
      _planName = '새로고침 실패';
      _remainingDays = 0;
      _planStatus = PlanStatus.free;
      _hasUsedTrial = false;
      _configureUIFromServerResponse('free', 'cancelled', false, expirationDate: null, subscriptionType: null); // v4-simplified 기본값
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

  /// 플랜 정보 로드 (v4-simplified 직접 처리)
  Future<void> loadPlanInfo() async {
    _setLoading(true);
    try {

      
      // 🎯 UnifiedSubscriptionManager에서 구독 상태 가져오기 (캐시 활용)
      final subscriptionManager = UnifiedSubscriptionManager();
      final entitlements = await subscriptionManager.getSubscriptionEntitlements(forceRefresh: false);
      
      if (kDebugMode) {
        print('📥 [Settings] 구독 상태 (캐시): ${entitlements['entitlement']} (${entitlements['subscriptionStatus']})');
      }
      
      // 구독 상태에서 필드 추출
      final entitlement = entitlements['entitlement'];
      final subscriptionStatus = entitlements['subscriptionStatus'];
      final hasUsedTrial = entitlements['hasUsedTrial'];
      final expirationDate = entitlements['expirationDate'] as String?;
      final subscriptionType = entitlements['subscriptionType'] as String?;
      
      if (kDebugMode) {
        print('🔍 [Settings] 체험 이력 디버그 (캐시):');
        print('   entitlement: $entitlement');
        print('   subscriptionStatus: $subscriptionStatus');
        print('   hasUsedTrial (서버): $hasUsedTrial');
        print('   전체 서버 응답: $entitlements');
      }
      
      // 🎯 서버 응답 그대로 사용 (클라이언트 추론 없음)
      _hasUsedTrial = hasUsedTrial;
      
      if (kDebugMode) {
        print('✅ [Settings] 최종 hasUsedTrial: $_hasUsedTrial (서버 응답 그대로)');
      }
      
      // 🎯 기존 호환성을 위한 PlanStatus 설정 (레거시 UI용)
      _planStatus = _calculatePlanStatusFromServerResponse(entitlement, subscriptionStatus, _hasUsedTrial);
      
      // UI에 표시할 정보 설정
      if (entitlement == 'premium') {
        _planType = 'premium';
      } else if (entitlement == 'trial') {
        _planType = 'premium'; // 체험도 프리미엄으로 분류
      } else {
        _planType = 'free';
      }
      
      // 🎯 표시명과 CTA 설정 (v4-simplified 직접 처리 + 날짜 정보)
      _configureUIFromServerResponse(entitlement, subscriptionStatus, _hasUsedTrial, 
        expirationDate: expirationDate, subscriptionType: subscriptionType);
      
      _isPlanLoaded = true;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('❌ [Settings] 플랜 정보 로드 오류: $e');
      }
      // 에러 발생 시 기본값 설정 (v4-simplified 방식)
      _planType = 'free';
      _planName = '플랜 정보 로드 실패';
      _remainingDays = 0;
      _planStatus = PlanStatus.free;
      _hasUsedTrial = false;
      _configureUIFromServerResponse('free', 'cancelled', false, expirationDate: null, subscriptionType: null); // v4-simplified 기본값
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

  /// 🎯 v4-simplified 서버 응답으로부터 PlanStatus 계산
  PlanStatus _calculatePlanStatusFromServerResponse(String entitlement, String subscriptionStatus, bool hasUsedTrial) {
    if (entitlement == 'premium') {
      switch (subscriptionStatus) {
        case 'active':
          return PlanStatus.premiumActive;
        case 'cancelling':
          return PlanStatus.premiumCancelled;
        case 'cancelled':
        case 'expired':
          return PlanStatus.premiumExpired;
        case 'refunded':
          return PlanStatus.premiumExpired; // 환불된 경우 만료로 처리
      }
    } else if (entitlement == 'trial') {
      switch (subscriptionStatus) {
        case 'active':
          return PlanStatus.trialActive;
        case 'cancelling':
          return PlanStatus.trialCancelled;
        case 'cancelled':
        case 'expired':
          return PlanStatus.trialCompleted;
        case 'refunded':
          return PlanStatus.trialCompleted; // 환불된 경우 완료로 처리
      }
    } else { // entitlement == 'free'
      if (hasUsedTrial) {
        return PlanStatus.trialCompleted; // 과거에 체험을 사용했던 무료 사용자
      } else {
        return PlanStatus.free; // 순수 무료 사용자
      }
    }
    
    return PlanStatus.free; // 기본값
  }

  /// 🎯 v4-simplified 서버 응답으로부터 UI 설정 (직접 처리)
  void _configureUIFromServerResponse(String entitlement, String subscriptionStatus, bool hasUsedTrial, {String? expirationDate, String? subscriptionType}) {

    
    // 🎯 만료일 계산 및 표시
    String? dateDisplay;
    int daysRemaining = 0;
    
    if (expirationDate != null && expirationDate.isNotEmpty) {
      try {
        DateTime expiration;
        
        // Unix timestamp (milliseconds) 또는 ISO 문자열 처리
        if (RegExp(r'^\d+$').hasMatch(expirationDate)) {
          // 숫자만 있는 경우: Unix timestamp (milliseconds)
          final timestamp = int.parse(expirationDate);
          expiration = DateTime.fromMillisecondsSinceEpoch(timestamp);
          
        } else {
          // ISO 문자열 형태
          expiration = DateTime.parse(expirationDate);
        }
        
        final now = DateTime.now();
        daysRemaining = expiration.difference(now).inDays;
        
        // 날짜 표시 형식 (년 월 일)
        dateDisplay = '${expiration.year}년 ${expiration.month}월 ${expiration.day}일';
        _nextPaymentDateText = '다음 결제일: $dateDisplay';
        _freeTransitionDateText = '$dateDisplay 부터 무료 전환';
        

      } catch (e) {
        if (kDebugMode) {
          print('⚠️ [Settings] 만료일 파싱 실패: $expirationDate');
        }
        _nextPaymentDateText = null;
        _freeTransitionDateText = null;
      }
    } else {
      _nextPaymentDateText = null;
      _freeTransitionDateText = null;
    }
    
    // 🎯 구독 타입 표시 (monthly/yearly)
    final subscriptionTypeDisplay = subscriptionType == 'yearly' ? '연간 구독' : '월간 구독';
    
    // 🎯 상태별 UI 텍스트 설정
    if (entitlement == 'trial') {
      _planTitle = 'Premium';
      _planSubtitle = '무료체험';
      if (subscriptionStatus == 'active') {
        _planStatusText = '활성';
        _ctaButtonText = 'App Store에서 관리';
        _ctaButtonEnabled = false;
        _ctaSubtext = '체험 기간 종료 시 자동으로 결제됩니다.';
        _planName = dateDisplay != null ? '무료체험 중 (${daysRemaining}일 남음)' : '무료체험 중';
      } else { // cancelling, expired, refunded
        _planStatusText = '종료됨';
        _ctaButtonText = '프리미엄으로 업그레이드';
        _ctaButtonEnabled = true;
        _ctaSubtext = '';
        _planName = '무료체험 완료';
      }
      _shouldUsePremiumQuota = true;

    } else if (entitlement == 'premium') {
      _planTitle = 'Premium';
      _planSubtitle = subscriptionTypeDisplay;
      if (subscriptionStatus == 'active') {
        _planStatusText = '활성';
        _ctaButtonText = 'App Store에서 관리';
        _ctaButtonEnabled = false;
        _ctaSubtext = '';
        _planName = '프리미엄 ($subscriptionTypeDisplay)';
      } else { // cancelling, expired, refunded
        _planStatusText = '만료됨';
        _ctaButtonText = '프리미엄으로 업그레이드';
        _ctaButtonEnabled = true;
        _ctaSubtext = '';
        _planName = '프리미엄 만료';
      }
      _shouldUsePremiumQuota = true;

    } else { // free
      _planTitle = 'Free';
      _planSubtitle = '무료 플랜';
      _planStatusText = '활성';
      _ctaButtonText = '프리미엄으로 업그레이드';
      _ctaButtonEnabled = true;
      _ctaSubtext = '';
      _planName = '무료 플랜';
      _shouldUsePremiumQuota = false;
    }
    
    // Grace Period 특별 처리
    if (entitlement == 'premium' && subscriptionStatus == 'active' && daysRemaining > 0 && daysRemaining <= 7) {
      _planStatusText = '결제 문제';
      _ctaButtonText = 'App Store에서 결제 정보 업데이트';
      _ctaButtonEnabled = true; // 사용자가 직접 해결하도록 유도
      _ctaSubtext = '구독을 유지하려면 결제 정보를 업데이트해주세요.';
    }
    
    _remainingDays = daysRemaining;
    
    // 플랜 제한 설정
    if (_shouldUsePremiumQuota) {
      _planLimits = Map<String, int>.from(PlanConstants.getPlanLimits(PlanConstants.PLAN_PREMIUM));
    } else {
      _planLimits = Map<String, int>.from(PlanConstants.getPlanLimits(PlanConstants.PLAN_FREE));
    }
    
    if (kDebugMode) {
      print('✅ [Settings] UI 설정 완료: $_planName');
    }
  }

  /// CTA 버튼 액션 처리
  void handleCTAAction(BuildContext context) {
    if (ctaButton.action != null) {
      ctaButton.action!();
    } else if (_ctaButtonText.contains('업그레이드')) {
       _showUpgradeModal(context);
    }
  }

  // 업그레이드 모달 표시
  void _showUpgradeModal(BuildContext? context) {
    if (context == null) return;
    UpgradeModal.show(
      context,
      reason: hasUsedFreeTrial ? UpgradeReason.general : UpgradeReason.welcomeTrial,
      onUpgrade: () {
        // 실제 구매 로직 연결
      },
    );
  }
  
  // App Store 열기
  void _openAppStore() {
    // URL Launcher 로직 추가
  }


} 