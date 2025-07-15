import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:convert';
import 'dart:async';
import '../../constants/plan_constants.dart';
import '../subscription/unified_subscription_manager.dart';
import '../../events/subscription_events.dart';
import '../../models/subscription_state.dart';

/// 🔄 사용량 제한 관리 서비스 (반응형 버전)
/// 
/// 🎯 **핵심 책임 (Reactive Architecture):**
/// - UnifiedSubscriptionManager 구독 이벤트 구독
/// - 구독 상태 변경에 반응하여 사용량 제한 자동 재계산
/// - 사용량 데이터 Firebase 관리
/// - 실시간 한도 상태 스트림 제공
/// 
/// 🚫 **더 이상 담당하지 않음:**
/// - ❌ 수동 구독 상태 조회 → UnifiedSubscriptionManager 이벤트 구독
/// - ❌ 수동 플랜 타입 확인 → 이벤트에서 자동 제공
/// 
/// 🔄 **이벤트 기반 흐름:**
/// ```
/// UnifiedSubscriptionManager → SubscriptionEvent → UsageLimitService 
///                                                ↓
///                               limitStatusStream → HomeViewModel
/// ```

class UsageLimitService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  
  // 싱글톤 패턴 구현
  static final UsageLimitService _instance = UsageLimitService._internal();
  factory UsageLimitService() => _instance;
  
  UsageLimitService._internal() {
    _initializeReactiveSubscription();
  }
  
  // 🎯 반응형 구독 관리
  final UnifiedSubscriptionManager _subscriptionManager = UnifiedSubscriptionManager();
  StreamSubscription<SubscriptionEvent>? _subscriptionEventSubscription;
  
  // 🎯 캐시 메커니즘 추가
  Map<String, int>? _cachedUsageData;
  Map<String, int>? _cachedLimitsData;
  DateTime? _lastUsageUpdate;
  DateTime? _lastLimitsUpdate;
  String? _lastUserId;
  
  // 캐시 유효 시간 (5분)
  static const Duration _cacheValidDuration = Duration(minutes: 5);
  
  // 사용자별 커스텀 제한 설정을 위한 Firestore 컬렉션
  static const String _CUSTOM_LIMITS_COLLECTION = 'user_limits';
  
  // 현재 사용자 ID 가져오기
  String? get _currentUserId => _auth.currentUser?.uid;
  
  /// 🎯 반응형 구독 이벤트 초기화
  void _initializeReactiveSubscription() {
    if (kDebugMode) {
      debugPrint('⚠️ [UsageLimitService] 반응형 구독 이벤트 기능 제거됨 - 단순화된 구조');
    }
    
    // 이벤트 스트림이 더 이상 존재하지 않으므로 구독 제거
    // UnifiedSubscriptionManager의 구독 이벤트 스트림이 제거됨
  }
  
  /// 🎯 구독 이벤트 처리 (반응형 핵심)
  Future<void> _handleSubscriptionEvent(SubscriptionEvent event) async {
    if (kDebugMode) {
      debugPrint('📡 [UsageLimitService] 구독 이벤트 수신: ${event.type}');
      debugPrint('   컨텍스트: ${event.context}');
      debugPrint('   권한: ${event.state.entitlement.value}');
    }
    
    try {
      // 🎯 구독 상태 변경시 사용량 제한 자동 재계산
      await _recalculateLimitsFromSubscriptionState(event.state);
      
      // 🎯 현재 사용량과 새로운 제한으로 한도 상태 체크
      final limitStatus = await _calculateCurrentLimitStatus();
      
      // 🎯 실시간 스트림으로 업데이트 발행
      _notifyLimitStatusChange(limitStatus);
      
      if (kDebugMode) {
        debugPrint('✅ [UsageLimitService] 구독 이벤트 처리 완료: $limitStatus');
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UsageLimitService] 구독 이벤트 처리 실패: $e');
      }
    }
  }
  
  /// 🎯 구독 상태로부터 사용량 제한 재계산
  Future<void> _recalculateLimitsFromSubscriptionState(SubscriptionState state) async {
    final planType = state.canUsePremiumFeatures 
        ? PlanConstants.PLAN_PREMIUM 
        : PlanConstants.PLAN_FREE;
    
    if (kDebugMode) {
      debugPrint('🔄 [UsageLimitService] 플랜 타입 결정: $planType (권한: ${state.entitlement.value})');
    }
    
    // 🎯 캐시 무효화 후 새 제한으로 업데이트
    _cachedLimitsData = null;
    _lastLimitsUpdate = null;
    
    // 새로운 제한 로드 (플랜 타입 직접 제공)
    await _loadLimitsFromPlanType(planType);
  }
  
  /// 🎯 플랜 타입으로부터 제한 로드 (이벤트 기반)
  Future<void> _loadLimitsFromPlanType(String planType) async {
    try {
      final limits = PlanConstants.PLAN_LIMITS[planType];
      if (limits != null) {
        _cachedLimitsData = Map<String, int>.from(limits);
        _lastLimitsUpdate = DateTime.now();
        
        if (kDebugMode) {
          debugPrint('✅ [UsageLimitService] 플랜 기반 제한 로드: $planType -> $_cachedLimitsData');
        }
      } else {
        _cachedLimitsData = _getDefaultLimits();
        _lastLimitsUpdate = DateTime.now();
        
        if (kDebugMode) {
          debugPrint('⚠️ [UsageLimitService] 플랜 정보 없음, 기본 제한 사용: $_cachedLimitsData');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UsageLimitService] 플랜 기반 제한 로드 실패: $e');
      }
      _cachedLimitsData = _getDefaultLimits();
      _lastLimitsUpdate = DateTime.now();
    }
  }
  
  /// 🎯 현재 사용량 상태로 한도 도달 여부 계산
  Future<Map<String, bool>> _calculateCurrentLimitStatus() async {
    try {
      final usage = await _loadUsageDataFromFirebase();
      final limits = _cachedLimitsData ?? _getDefaultLimits();
      
      final limitStatus = {
        'ocrLimitReached': (usage['ocrPages'] ?? 0) >= (limits['ocrPages'] ?? 0),
        'ttsLimitReached': (usage['ttsRequests'] ?? 0) >= (limits['ttsRequests'] ?? 0),
      };
      
      if (kDebugMode) {
        debugPrint('🔍 [UsageLimitService] 현재 한도 상태 계산:');
        debugPrint('   OCR: ${usage['ocrPages']}/${limits['ocrPages']} = ${limitStatus['ocrLimitReached']}');
        debugPrint('   TTS: ${usage['ttsRequests']}/${limits['ttsRequests']} = ${limitStatus['ttsLimitReached']}');
      }
      
      return limitStatus;
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UsageLimitService] 한도 상태 계산 실패: $e');
      }
      return {'ocrLimitReached': false, 'ttsLimitReached': false};
    }
  }

  /// 캐시 무효화 (사용자 변경 시 또는 명시적 호출)
  void _invalidateCache() {
    _cachedUsageData = null;
    _cachedLimitsData = null;
    _lastUsageUpdate = null;
    _lastLimitsUpdate = null;
    _lastUserId = null;
    if (kDebugMode) {
      debugPrint('🗑️ [UsageLimitService] 캐시 무효화됨');
    }
  }
  
  /// 사용자 변경 감지 및 캐시 무효화
  void _checkUserChange() {
    final currentUserId = _currentUserId;
    // null에서 실제 사용자로 변경되는 경우는 로그인이므로 캐시 무효화하지 않음
    if (currentUserId != _lastUserId && _lastUserId != null && currentUserId != null) {
      _invalidateCache();
      if (kDebugMode) {
        debugPrint('👤 [UsageLimitService] 사용자 변경 감지: $_lastUserId -> $currentUserId');
      }
    } else if (_lastUserId == null && currentUserId != null) {
      if (kDebugMode) {
        debugPrint('👤 [UsageLimitService] 로그인 감지: null -> $currentUserId (캐시 유지)');
      }
    }
    _lastUserId = currentUserId;
  }
  
  /// 캐시 유효성 검사
  bool _isUsageCacheValid() {
    _checkUserChange();
    return _cachedUsageData != null && 
           _lastUsageUpdate != null && 
           DateTime.now().difference(_lastUsageUpdate!).abs() < _cacheValidDuration;
  }
  
  bool _isLimitsCacheValid() {
    _checkUserChange();
    return _cachedLimitsData != null && 
           _lastLimitsUpdate != null && 
           DateTime.now().difference(_lastLimitsUpdate!).abs() < _cacheValidDuration;
  }
  
  /// 1. 앱 시작시 제한 확인 (캐시 사용으로 최적화)
  /// 🎯 더 이상 수동 구독 상태 조회하지 않음 - 이벤트 기반으로 자동 업데이트
  Future<Map<String, bool>> checkInitialLimitStatus({bool forceRefresh = false}) async {
    try {
      if (kDebugMode) {
        debugPrint('🔍 [UsageLimitService] checkInitialLimitStatus 시작 ${forceRefresh ? "(강제 새로고침)" : "(캐시 사용)"}');
      }
      
      final userId = _currentUserId;
      if (userId == null) {
        if (kDebugMode) {
          debugPrint('❌ [UsageLimitService] 사용자 ID가 없음 - 모든 제한 false 반환');
        }
        return {
          'ocrLimitReached': false,
          'ttsLimitReached': false,
        };
      }
      
      // 🎯 현재 상태로 한도 계산 (이벤트 기반으로 이미 최신 상태)
      return await _calculateCurrentLimitStatus();
      
    } catch (e) {
      debugPrint('❌ [UsageLimitService] checkInitialLimitStatus 오류: $e');
      return {
        'ocrLimitReached': false,
        'ttsLimitReached': false,
      };
    }
  }
  
  /// 2. 노트 생성 후 사용량 업데이트 및 제한 확인 (실시간 알림 포함)
  /// 사용량을 Firebase에 업데이트하고 제한 도달 여부를 반환
  Future<Map<String, bool>> updateUsageAfterNoteCreation({
    int ocrPages = 0,
    int ttsRequests = 0,
  }) async {
    try {
      debugPrint('노트 생성 후 사용량 업데이트 시작');
      
      final userId = _currentUserId;
      if (userId == null) {
        debugPrint('사용자 ID가 없음 - 업데이트 실패');
        return {
          'ocrLimitReached': false,
          'ttsLimitReached': false,
        };
      }
      
      // 현재 사용량 가져오기
      final currentUsage = await _loadUsageDataFromFirebase();
      
      // 새로운 사용량 계산
      final newUsage = {
        'ocrPages': (currentUsage['ocrPages'] ?? 0) + ocrPages,
        'ttsRequests': (currentUsage['ttsRequests'] ?? 0) + ttsRequests,
      };
      
      // Firebase에 업데이트
      await _firestore.collection('users').doc(userId).update({
        'usage.ocrPages': newUsage['ocrPages'],
        'usage.ttsRequests': newUsage['ttsRequests'],
        'usage.lastUpdated': FieldValue.serverTimestamp(),
      });
      
      // 캐시 무효화 (사용량이 변경되었으므로)
      _cachedUsageData = null;
      _lastUsageUpdate = null;
      
      debugPrint('사용량 업데이트 완료: $newUsage');
      
      // 제한 확인
      final limits = await _loadLimitsFromFirebase();
      final limitStatus = {
        'ocrLimitReached': (newUsage['ocrPages'] ?? 0) >= (limits['ocrPages'] ?? 0),
        'ttsLimitReached': (newUsage['ttsRequests'] ?? 0) >= (limits['ttsRequests'] ?? 0),
      };
      
      debugPrint('노트 생성 후 제한 확인 결과: $limitStatus');
      
      // 🎯 실시간 상태 변경 알림
      _notifyLimitStatusChange(limitStatus);
      
      return limitStatus;
      
    } catch (e) {
      debugPrint('노트 생성 후 사용량 업데이트 중 오류: $e');
      return {
        'ocrLimitReached': false,
        'ttsLimitReached': false,
      };
    }
  }
  
  /// 🎯 사용량 한도 상태 변경 알림
  void _notifyLimitStatusChange(Map<String, bool> limitStatus) {
    if (!_limitStatusController.isClosed) {
      _limitStatusController.add(limitStatus);
      if (kDebugMode) {
        debugPrint('🔔 [UsageLimitService] 실시간 한도 상태 변경 알림: $limitStatus');
      }
    }
  }
  
  /// 서비스 정리 (스트림 컨트롤러 닫기)
  void dispose() {
    _limitStatusController.close();
    _subscriptionEventSubscription?.cancel(); // 구독 이벤트 스트림 구독 취소
    if (kDebugMode) {
      debugPrint('🗑️ [UsageLimitService] 서비스 정리 완료');
    }
  }
  
  /// 3. 설정 화면에서 사용량 조회
  /// 사용자가 명시적으로 사용량을 확인할 때 사용
  Future<Map<String, dynamic>> getUserUsageForSettings() async {
    try {
      debugPrint('📊 [UsageLimitService] 설정 화면 사용량 조회 시작');
      
      final userId = _currentUserId;
      if (userId == null) {
        debugPrint('❌ [UsageLimitService] 사용자 ID가 없음 - 기본값 반환');
        return _getDefaultUsageInfo();
      }
      
      debugPrint('📊 [UsageLimitService] 사용자 ID: $userId');
      
      // Firebase에서 최신 데이터 가져오기 (설정 화면에서는 항상 최신 정보)
      final usage = await _loadUsageDataFromFirebase(forceRefresh: true);
      debugPrint('📊 [UsageLimitService] Firebase 사용량 데이터: $usage');
      
      final limits = await _loadLimitsFromFirebase(forceRefresh: true);
      debugPrint('📊 [UsageLimitService] Firebase 제한 데이터: $limits');
      
      // 제한 도달 여부
      final limitStatus = {
        'ocrLimitReached': (usage['ocrPages'] ?? 0) >= (limits['ocrPages'] ?? 0),
        'ttsLimitReached': (usage['ttsRequests'] ?? 0) >= (limits['ttsRequests'] ?? 0),
        'ocrLimit': limits['ocrPages'] ?? 0,
        'ttsLimit': limits['ttsRequests'] ?? 0,
      };
      
      // 사용량 퍼센트 계산
      final ocrPercentage = (limits['ocrPages'] ?? 0) > 0 ? 
        ((usage['ocrPages'] ?? 0).toDouble() / (limits['ocrPages'] ?? 1).toDouble() * 100.0).clamp(0.0, 100.0) : 0.0;
      final ttsPercentage = (limits['ttsRequests'] ?? 0) > 0 ? 
        ((usage['ttsRequests'] ?? 0).toDouble() / (limits['ttsRequests'] ?? 1).toDouble() * 100.0).clamp(0.0, 100.0) : 0.0;
        
      debugPrint('📊 [UsageLimitService] 계산된 퍼센트 - OCR: $ocrPercentage%, TTS: $ttsPercentage%');
      
      final result = {
        'usage': usage,
        'limits': limits,
        'usagePercentages': <String, double>{
          'ocr': ocrPercentage,
          'tts': ttsPercentage,
        },
        'limitStatus': limitStatus,
      };
      
      debugPrint('✅ [UsageLimitService] 설정 화면 사용량 조회 완료: $result');
      return result;
      
    } catch (e, stackTrace) {
      debugPrint('❌ [UsageLimitService] 설정 화면 사용량 조회 중 오류: $e');
      debugPrint('❌ [UsageLimitService] 스택 트레이스: $stackTrace');
      return _getDefaultUsageInfo();
    }
  }
  
  /// 4. TTS 재생 완료 후 사용량 증가 (실시간 알림 포함)
  /// TTS 재생이 성공적으로 완료된 후 호출하여 사용량을 1 증가시킴
  Future<bool> incrementTtsUsageAfterPlayback() async {
    try {
      debugPrint('TTS 재생 완료 후 사용량 증가 시작');
      
      final userId = _currentUserId;
      if (userId == null) {
        debugPrint('사용자 ID가 없음 - 사용량 증가 건너뜀');
        return true;
      }
      
      // 현재 사용량 가져오기
      final currentUsage = await _loadUsageDataFromFirebase();
      final newTtsUsage = (currentUsage['ttsRequests'] ?? 0) + 1;
      
      // Firebase에 업데이트
      await _firestore.collection('users').doc(userId).update({
        'usage.ttsRequests': newTtsUsage,
        'usage.lastUpdated': FieldValue.serverTimestamp(),
      });
      
      // 캐시 무효화 (사용량이 변경되었으므로)
      _cachedUsageData = null;
      _lastUsageUpdate = null;
      
      debugPrint('TTS 사용량 증가 완료: $newTtsUsage');
      
      // 🎯 제한 확인 및 실시간 알림
      final limits = await _loadLimitsFromFirebase();
      final limitStatus = {
        'ocrLimitReached': (currentUsage['ocrPages'] ?? 0) >= (limits['ocrPages'] ?? 0),
        'ttsLimitReached': newTtsUsage >= (limits['ttsRequests'] ?? 0),
      };
      
      // 실시간 상태 변경 알림
      _notifyLimitStatusChange(limitStatus);
      
      return true;
      
    } catch (e) {
      debugPrint('TTS 사용량 증가 중 오류: $e');
      return false;
    }
  }
  
  /// Firebase에서 사용량 데이터 로드 (캐시 적용)
  Future<Map<String, int>> _loadUsageDataFromFirebase({bool forceRefresh = false}) async {
    // 캐시 확인
    if (!forceRefresh && _isUsageCacheValid()) {
      if (kDebugMode) {
        debugPrint('📦 [UsageLimitService] 캐시된 사용량 데이터 사용: $_cachedUsageData');
      }
      return _cachedUsageData!;
    }
    
    try {
      final userId = _currentUserId;
      if (userId == null) {
        if (kDebugMode) {
          debugPrint('🔍 [UsageLimitService] _loadUsageDataFromFirebase: 사용자 ID 없음');
        }
        return _getDefaultUsageData();
      }
      
      final doc = await _firestore.collection('users').doc(userId).get();
      
      if (!doc.exists) {
        if (kDebugMode) {
          debugPrint('🔍 [UsageLimitService] _loadUsageDataFromFirebase: 사용자 문서가 존재하지 않음');
        }
        return _getDefaultUsageData();
      }
      
      final data = doc.data() as Map<String, dynamic>;
      
      // 'usage' 필드에서 데이터 추출
      Map<String, int> usageData = {};
      
      if (data.containsKey('usage') && data['usage'] is Map) {
        final usage = data['usage'] as Map<String, dynamic>;
        usageData = {
          'ocrPages': _parseIntSafely(usage['ocrPages']),
          'ttsRequests': _parseIntSafely(usage['ttsRequests']),
        };
      } else {
        // 최상위 필드에서 확인
        usageData = {
          'ocrPages': _parseIntSafely(data['ocrPages']),
          'ttsRequests': _parseIntSafely(data['ttsRequests']),
        };
      }
      
      // 캐시 업데이트
      _cachedUsageData = usageData;
      _lastUsageUpdate = DateTime.now();
      
      if (kDebugMode) {
        debugPrint('✅ [UsageLimitService] Firebase 사용량 데이터 로드 및 캐시 업데이트: $usageData');
      }
      return usageData;
    } catch (e, stackTrace) {
      // 네트워크 연결 오류 감지
      final isNetworkError = e.toString().contains('Unavailable') || 
                            e.toString().contains('Network') ||
                            e.toString().contains('connectivity');
      
      if (isNetworkError) {
        debugPrint('🌐 [UsageLimitService] 네트워크 연결 오류 - Firebase 사용량 데이터 로드 실패: $e');
      } else {
        debugPrint('❌ [UsageLimitService] Firebase에서 사용량 데이터 로드 중 오류: $e');
        if (kDebugMode) {
          debugPrint('❌ [UsageLimitService] 스택 트레이스: $stackTrace');
        }
      }
      return _getDefaultUsageData();
    }
  }
  
  /// Firebase에서 제한 데이터 로드 (캐시 적용)
  Future<Map<String, int>> _loadLimitsFromFirebase({bool forceRefresh = false}) async {
    // 캐시 확인
    if (!forceRefresh && _isLimitsCacheValid()) {
      if (kDebugMode) {
        debugPrint('📦 [UsageLimitService] 캐시된 제한 데이터 사용: $_cachedLimitsData');
      }
      return _cachedLimitsData!;
    }
    
    try {
      final userId = _currentUserId;
      if (userId == null) {
        if (kDebugMode) {
          debugPrint('🔍 [UsageLimitService] _loadLimitsFromFirebase: 사용자 ID 없음, 기본 제한 반환');
        }
        return _getDefaultLimits();
      }
      
      // 1. 사용자별 커스텀 제한 확인
      final customLimits = await _getUserCustomLimits(userId);
      if (customLimits.isNotEmpty) {
        // 캐시 업데이트
        _cachedLimitsData = customLimits;
        _lastLimitsUpdate = DateTime.now();
        
        if (kDebugMode) {
          debugPrint('✅ [UsageLimitService] _loadLimitsFromFirebase: 커스텀 제한 사용: $customLimits');
        }
        return customLimits;
      }
      
      // 2. 플랜 기반 제한 적용 (기본값 사용 - 이벤트 기반에서 자동 업데이트됨)
      final planType = PlanConstants.PLAN_FREE; // 이벤트 기반에서 자동으로 업데이트됨
      
      final limits = PlanConstants.PLAN_LIMITS[planType];
      if (limits != null) {
        final result = Map<String, int>.from(limits);
        
        // 캐시 업데이트
        _cachedLimitsData = result;
        _lastLimitsUpdate = DateTime.now();
        
        if (kDebugMode) {
          debugPrint('✅ [UsageLimitService] _loadLimitsFromFirebase: 플랜 기반 제한 사용: $planType -> $result');
        }
        return result;
      }
      
      // 3. 기본 제한 적용
      final defaultLimits = _getDefaultLimits();
      
      // 캐시 업데이트
      _cachedLimitsData = defaultLimits;
      _lastLimitsUpdate = DateTime.now();
      
      if (kDebugMode) {
        debugPrint('✅ [UsageLimitService] _loadLimitsFromFirebase: 기본 제한 사용: $defaultLimits');
      }
      return defaultLimits;
    } catch (e, stackTrace) {
      debugPrint('❌ [UsageLimitService] _loadLimitsFromFirebase 오류: $e');
      if (kDebugMode) {
        debugPrint('❌ [UsageLimitService] _loadLimitsFromFirebase 스택 트레이스: $stackTrace');
      }
      final defaultLimits = _getDefaultLimits();
      debugPrint('🔄 [UsageLimitService] _loadLimitsFromFirebase: 오류로 인한 기본 제한 사용: $defaultLimits');
      return defaultLimits;
    }
  }
  
  /// 사용자별 커스텀 제한 가져오기
  Future<Map<String, int>> _getUserCustomLimits(String userId) async {
    try {
      debugPrint('🔍 [UsageLimitService] _getUserCustomLimits: $userId로 user_limits 컬렉션 조회');
      
      final doc = await _firestore
          .collection(_CUSTOM_LIMITS_COLLECTION)
          .doc(userId)
          .get();
          
      if (!doc.exists) {
        debugPrint('🔍 [UsageLimitService] _getUserCustomLimits: user_limits 문서가 존재하지 않음');
        return {};
      }
      
      final data = doc.data() as Map<String, dynamic>;
      debugPrint('🔍 [UsageLimitService] _getUserCustomLimits: user_limits 문서 데이터: $data');
      
      final limits = <String, int>{};
      
      if (data.containsKey('ocrPages')) limits['ocrPages'] = _parseIntSafely(data['ocrPages']);
      if (data.containsKey('ttsRequests')) limits['ttsRequests'] = _parseIntSafely(data['ttsRequests']);
      
      debugPrint('✅ [UsageLimitService] _getUserCustomLimits: 파싱된 커스텀 제한: $limits');
      return limits;
    } catch (e, stackTrace) {
      debugPrint('❌ [UsageLimitService] _getUserCustomLimits 오류: $e');
      debugPrint('❌ [UsageLimitService] _getUserCustomLimits 스택 트레이스: $stackTrace');
      return {};
    }
  }
  
  /// 기본 사용량 데이터 (PlanService에서 가져오기)
  Map<String, int> _getDefaultUsageData() {
    return {
      'ocrPages': 0,
      'ttsRequests': 0,
    };
  }
  
  /// 기본 제한 값 (PlanConstants에서 가져오기)
  Map<String, int> _getDefaultLimits() {
    return Map<String, int>.from(PlanConstants.PLAN_LIMITS[PlanConstants.PLAN_FREE]!);
  }
  
  /// 기본 사용량 정보 (설정 화면용)
  Map<String, dynamic> _getDefaultUsageInfo() {
    final defaultLimits = _getDefaultLimits();
    return {
      'usage': _getDefaultUsageData(),
      'limits': defaultLimits,
      'usagePercentages': <String, double>{
        'ocr': 0.0,
        'tts': 0.0,
      },
      'limitStatus': {
        'ocrLimitReached': false,
        'ttsLimitReached': false,
        'ocrLimit': defaultLimits['ocrPages'] ?? 10,
        'ttsLimit': defaultLimits['ttsRequests'] ?? 30,
      },
    };
  }
  
  /// 안전한 정수 파싱
  int _parseIntSafely(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is double) return value.toInt();
    return 0;
  }
  
  // ========== PlanService 호환성을 위한 메서드들 ==========
  
  /// 사용량 비율 계산 (PlanService 호환성)
  Future<Map<String, double>> getUsagePercentages() async {
    final result = await getUserUsageForSettings();
    return Map<String, double>.from(result['usagePercentages'] as Map);
  }
  
  /// 제한 상태 확인 (PlanService 호환성)
  Future<Map<String, dynamic>> checkFreeLimits({bool withBuffer = false}) async {
    final result = await getUserUsageForSettings();
    return result['limitStatus'] as Map<String, dynamic>;
  }
  
  
  /// 사용량 한도 도달 여부 확인 (배너용)
  Future<bool> hasReachedAnyLimit() async {
    try {
      final limitStatus = await checkInitialLimitStatus();
      final ocrReached = limitStatus['ocrLimitReached'] ?? false;
      final ttsReached = limitStatus['ttsLimitReached'] ?? false;
      
      return ocrReached || ttsReached;
    } catch (e) {
      debugPrint('사용량 한도 확인 중 오류: $e');
      return false;
    }
  }

  /// 모든 사용량 초기화
  Future<void> resetAllUsage() async {
    try {
      final userId = _currentUserId;
      if (userId == null) return;
      
      await _firestore.collection('users').doc(userId).update({
        'usage.ocrPages': 0,
        'usage.ttsRequests': 0,
        'usage.translatedChars': 0,
        'usage.storageUsageBytes': 0,
        'usage.lastUpdated': FieldValue.serverTimestamp(),
      });
      
      debugPrint('모든 사용량 초기화 완료');
    } catch (e) {
      debugPrint('사용량 초기화 중 오류: $e');
    }
  }
  
  /// 월간 사용량 초기화 (Free 플랜)
  Future<void> resetMonthlyUsage() async {
    try {
      final unifiedManager = UnifiedSubscriptionManager();
      final entitlements = await unifiedManager.getSubscriptionEntitlements();
      final planType = entitlements['isPremium'] as bool? ?? false ? PlanConstants.PLAN_PREMIUM : PlanConstants.PLAN_FREE;
      
      if (planType != PlanConstants.PLAN_FREE) {
        debugPrint('Free 플랜이 아니므로 월간 초기화 건너뜀');
        return;
      }
      
      final prefs = await SharedPreferences.getInstance();
      final resetKey = 'monthly_reset_${_currentUserId ?? 'anonymous'}';
      final lastResetStr = prefs.getString(resetKey);
      
      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month, 1);
      
      if (lastResetStr == null) {
        await resetAllUsage();
        await prefs.setString(resetKey, currentMonth.toIso8601String());
        debugPrint('최초 월간 사용량 초기화 완료');
        return;
      }
      
      try {
        final lastReset = DateTime.parse(lastResetStr);
        
        if (lastReset.year != currentMonth.year || lastReset.month != currentMonth.month) {
          await resetAllUsage();
          await prefs.setString(resetKey, currentMonth.toIso8601String());
          debugPrint('월간 사용량 초기화 완료');
        }
      } catch (e) {
        await resetAllUsage();
        await prefs.setString(resetKey, currentMonth.toIso8601String());
        debugPrint('날짜 오류로 인한 월간 사용량 초기화');
      }
    } catch (e) {
      debugPrint('월간 사용량 초기화 중 오류: $e');
    }
  }
  
  /// 탈퇴 시 Firebase Storage 데이터 삭제
  Future<bool> deleteFirebaseStorageData(String userId) async {
    try {
      if (userId.isEmpty) {
        debugPrint('Firebase Storage 데이터 삭제 실패: 사용자 ID가 비어있음');
        return false;
      }
      
      final userFolderRef = _storage.ref().child('users/$userId');
      
      try {
        final result = await userFolderRef.listAll();
        debugPrint('탈퇴한 사용자의 Firebase Storage 파일 ${result.items.length}개, 폴더 ${result.prefixes.length}개 발견');
        
        for (final item in result.items) {
          await item.delete();
          debugPrint('파일 삭제됨: ${item.fullPath}');
        }
        
        for (final prefix in result.prefixes) {
          final subResult = await prefix.listAll();
          
          for (final subItem in subResult.items) {
            await subItem.delete();
            debugPrint('하위 폴더 파일 삭제됨: ${subItem.fullPath}');
          }
        }
        
        debugPrint('Firebase Storage 데이터 삭제 완료');
        return true;
      } catch (e) {
        debugPrint('Firebase Storage 데이터 삭제 중 오류: $e');
        return false;
      }
    } catch (e) {
      debugPrint('Firebase Storage 데이터 삭제 실패: $e');
      return false;
    }
  }
  
  // 🎯 실시간 상태 변경 스트림 추가
  final StreamController<Map<String, bool>> _limitStatusController = 
      StreamController<Map<String, bool>>.broadcast();
  
  /// 사용량 한도 상태 변경 스트림
  Stream<Map<String, bool>> get limitStatusStream => _limitStatusController.stream;
} 