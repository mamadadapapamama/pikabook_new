import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/authentication/user_preferences_service.dart';
import '../../core/services/authentication/auth_service.dart';
import '../../core/services/authentication/user_account_service.dart';
import '../../core/services/common/support_service.dart';
import '../../core/services/subscription/unified_subscription_manager.dart';
import '../../core/models/subscription_state.dart';
import '../../core/utils/language_constants.dart';
import '../../core/services/text_processing/text_processing_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/widgets/pika_button.dart';
import '../../core/widgets/upgrade_modal.dart';
import '../../core/services/common/usage_limit_service.dart';
import '../../core/widgets/usage_dialog.dart';


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
  final UserAccountService _userAccountService = UserAccountService();
  final UnifiedSubscriptionManager _subscriptionManager = UnifiedSubscriptionManager();

  // --- 상태 변수 ---
  bool _isLoading = false;
  String? _lastUserId;

  // 사용자 정보
  User? _currentUser;

  // 사용자 설정
  String _userName = '';
  String _noteSpaceName = '';
  String _sourceLanguage = SourceLanguage.DEFAULT;
  String _targetLanguage = TargetLanguage.DEFAULT;
  bool _useSegmentMode = false;

  // 🎯 구독 정보 (읽기 전용 - 외부에서 주입받음)
  SubscriptionInfo? _subscriptionInfo;
  bool get isPlanLoaded => _subscriptionInfo != null && !_isLoading;

  // --- Getters ---
  bool get isLoading => _isLoading;
  User? get currentUser => _currentUser;
  String get userName => _userName;
  String get noteSpaceName => _noteSpaceName;
  String get sourceLanguage => _sourceLanguage;
  String get targetLanguage => _targetLanguage;
  bool get useSegmentMode => _useSegmentMode;

  // 🎯 읽기 전용으로 구독 정보 제공
  SubscriptionInfo? get subscriptionInfo => _subscriptionInfo;

  /// 초기 데이터 로드
  Future<void> initialize() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isUserChanged = _lastUserId != null && _lastUserId != currentUserId;
    
    if (isUserChanged) {
      if (kDebugMode) print('🔄 [Settings] 사용자 변경 감지. 데이터 초기화.');
      _resetAllData();
    }
    _lastUserId = currentUserId;
    
    await loadUserData();
    await loadUserPreferences();
    // refreshPlanInfo 제거 - 외부에서 주입받음
  }

  /// 🎯 외부에서 구독 상태 설정 (App.dart에서 호출)
  void setSubscriptionInfo(SubscriptionInfo subscriptionInfo) {
    if (kDebugMode) {
      print('📝 [Settings] 구독 정보 설정: ${subscriptionInfo.planTitle}');
    }
    _subscriptionInfo = subscriptionInfo;
    notifyListeners();
  }

  /// 플랜 정보 새로고침 (UI 호출용 - 강제 새로고침만)
  Future<void> refreshPlanInfo({bool force = false}) async {
    if (_isLoading && !force) {
      if (kDebugMode) print('⏭️ [Settings] 이미 로딩 중 - 중복 호출 방지');
      return;
    }
    
    if (kDebugMode) print('🔄 [Settings] 강제 새로고침 요청 - UnifiedSubscriptionManager 캐시 무효화');
    
    // 🎯 UI 피드백을 위한 로딩 상태 표시
    _setLoading(true);
    
    try {
      // 강제 새로고침은 UnifiedSubscriptionManager에 위임
      await _subscriptionManager.invalidateCache();
      // 상태는 App.dart를 통해 업데이트됨
      
      // 잠시 대기하여 사용자에게 새로고침이 진행되고 있음을 알림
      await Future.delayed(const Duration(milliseconds: 500));
      
    } catch (e) {
      if (kDebugMode) print('❌ [Settings] 강제 새로고침 실패: $e');
    } finally {
      _setLoading(false);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _resetAllData() {
    _currentUser = null;
    _userName = '';
    _noteSpaceName = '';
    _subscriptionInfo = null;
    notifyListeners();
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// 사용자 데이터 로드
  Future<void> loadUserData() async {
      _currentUser = FirebaseAuth.instance.currentUser;
    notifyListeners();
  }

  /// 사용자 설정 로드
  Future<void> loadUserPreferences() async {
    try {
      final preferences = await _userPreferences.getPreferences();
      _userName = preferences.userName ?? '사용자';
      _noteSpaceName = preferences.defaultNoteSpace;
      _sourceLanguage = preferences.sourceLanguage;
      _targetLanguage = preferences.targetLanguage;
      _useSegmentMode = preferences.useSegmentMode;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('사용자 설정 로드 오류: $e');
    }
  }

  /// CTA 버튼 클릭 처리
  void handleCTAAction(BuildContext context) {
    if (_subscriptionInfo == null) return;
    
    final ctaText = _subscriptionInfo!.ctaText;
      
    if (ctaText.contains('App Store') || ctaText.contains('갱신하기')) {
      _openAppStore();
    } else {
      _showUpgradeModal(context);
    }
  }

  /// 사용량 조회 다이얼로그 표시
  Future<void> showUsageDialog(BuildContext context) async {
    if (_subscriptionInfo == null) {
      if (kDebugMode) print('SubscriptionInfo가 null이므로 UsageDialog를 표시할 수 없습니다.');
      return;
    }
    
    try {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return UsageDialog(subscriptionInfo: _subscriptionInfo!);
        },
      );
    } catch (e) {
      if (kDebugMode) print('사용량 조회 다이얼로그 표시 오류: $e');
    }
  }

  /// 업그레이드 모달 표시
  void _showUpgradeModal(BuildContext context) {
    UpgradeModal.show(
      context,
      onUpgrade: () async {
        await refreshPlanInfo(force: true);
      },
    );
  }

  // --- 외부 서비스 호출 ---

  Future<void> signOut() async => await _authService.signOut();
  
  void _openAppStore() async {
    // TODO: 앱 ID를 상수로 관리하는 것이 좋음
    final url = Uri.parse('https://apps.apple.com/app/id6502381223');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  // --- 언어 및 학습 설정 ---
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
      if (kDebugMode) print('학습자 이름 업데이트 오류: $e');
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
      if (kDebugMode) print('노트 스페이스 이름 업데이트 오류: $e');
      return false;
    }
  }

  /// 원문 언어 업데이트
  Future<void> updateSourceLanguage(String language) async {
      final preferences = await _userPreferences.getPreferences();
    await _userPreferences.savePreferences(preferences.copyWith(sourceLanguage: language));
      await loadUserPreferences();
  }

  /// 번역 언어 업데이트
  Future<void> updateTargetLanguage(String language) async {
      final preferences = await _userPreferences.getPreferences();
    await _userPreferences.savePreferences(preferences.copyWith(targetLanguage: language));
      await loadUserPreferences();
  }

  /// 텍스트 처리 모드 업데이트
  Future<void> updateUseSegmentMode(bool value) async {
      final preferences = await _userPreferences.getPreferences();
    await _userPreferences.savePreferences(preferences.copyWith(useSegmentMode: value));
      await loadUserPreferences();
  }

  /// 재인증 필요 여부 확인
  Future<bool> isReauthenticationRequired() async {
    try {
      return await _userAccountService.isReauthenticationRequired();
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

  /// 노트스페이스 이름 변경 알림
  Future<void> _notifyNoteSpaceNameChanged(String newName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_notespace_change', DateTime.now().millisecondsSinceEpoch);
    await prefs.setString('last_changed_notespace_name', newName);
  }
} 