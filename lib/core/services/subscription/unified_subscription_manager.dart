import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../common/banner_manager.dart';
import '../../models/subscription_state.dart';

/// 🎯 구독 상태 관리 저장소 (Apple 2025 Best Practice)
/// 
/// **최적화된 성능:**
/// - 5분 캐시로 빠른 응답
/// - 서버 측 10분 캐시 + App Store Server API 조합
/// - 웹훅 기반 실시간 업데이트
/// 
/// **핵심 기능:**
/// - 서버에서 구독 상태 조회 (캐시 우선)
/// - 권한 확인 헬퍼 (즉시 응답)
/// - 스마트 캐시 관리
/// - 🆕 활성 배너 포함 완전한 SubscriptionState 반환
class SubscriptionRepository {
  static final SubscriptionRepository _instance = SubscriptionRepository._internal();
  factory SubscriptionRepository() => _instance;
  SubscriptionRepository._internal();

  // 🎯 캐시 관리
  Map<String, dynamic>? _cachedEntitlements;
  DateTime? _lastEntitlementCheck;
  static const Duration _cacheValidDuration = Duration(minutes: 5);
  
  // 🎯 중복 요청 방지
  Future<Map<String, dynamic>>? _ongoingRequest;
  String? _lastUserId;
  
  // 🎯 BannerManager 인스턴스
  final BannerManager _bannerManager = BannerManager();

  /// 🎯 구독 권한 조회 (최적화된 캐시 + API 조합)
  /// 
  /// **Apple 2025 Best Practice:**
  /// - 캐시가 유효하면 즉시 반환 (빠른 응답)
  /// - 캐시 만료 시 서버 API 호출 (정확한 상태)
  /// - 서버에서 App Store Server API + 캐시 시스템 활용
  /// 
  /// **사용법:**
  /// ```dart
  /// final entitlements = await SubscriptionRepository().getSubscriptionEntitlements();
  /// bool isPremium = entitlements['isPremium']; 
  /// bool isTrial = entitlements['isTrial'];
  /// String entitlement = entitlements['entitlement']; // 'free', 'trial', 'premium'
  /// ```
  Future<Map<String, dynamic>> getSubscriptionEntitlements({bool forceRefresh = false}) async {
    if (kDebugMode) {
      debugPrint('🎯 [SubscriptionRepository] 구독 권한 조회 (forceRefresh: $forceRefresh)');
    }
    
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (kDebugMode) {
        debugPrint('⚠️ [SubscriptionRepository] 로그아웃 상태 - 기본 권한 반환');
      }
      return _getDefaultEntitlements();
    }
    
    final currentUserId = currentUser.uid;
    
    // 🎯 사용자 변경 감지 (캐시 무효화)
    if (_lastUserId != currentUserId) {
      if (kDebugMode) {
        debugPrint('🔄 [SubscriptionRepository] 사용자 변경 감지: $currentUserId');
      }
      invalidateCache();
      forceRefresh = true;
      _lastUserId = currentUserId;
    }
    
    // 🎯 캐시 우선 사용
    if (!forceRefresh && _cachedEntitlements != null && _lastEntitlementCheck != null) {
      final cacheAge = DateTime.now().difference(_lastEntitlementCheck!);
      if (cacheAge < _cacheValidDuration) {
        if (kDebugMode) {
          debugPrint('📦 [SubscriptionRepository] 캐시된 권한 반환 (${cacheAge.inSeconds}초 전)');
        }
        return _cachedEntitlements!;
      }
    }
    
    // 🎯 중복 요청 방지
    if (_ongoingRequest != null) {
      return await _ongoingRequest!;
    }

    if (kDebugMode) {
      debugPrint('🔍 [SubscriptionRepository] 서버 권한 조회 ${forceRefresh ? '(강제 갱신)' : ''}');
    }

    _ongoingRequest = _fetchFromServer(currentUserId);
    
    try {
      final result = await _ongoingRequest!;
      
      // 캐시 업데이트
      _cachedEntitlements = result;
      _lastEntitlementCheck = DateTime.now();
      
      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SubscriptionRepository] 권한 조회 실패: $e');
      }
      return _getDefaultEntitlements();
    } finally {
      _ongoingRequest = null;
    }
  }

  /// 🎯 서버에서 권한 조회 (새로운 Apple 권장 방식)
  Future<Map<String, dynamic>> _fetchFromServer(String userId) async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
      final callable = functions.httpsCallable('subCheckSubscriptionStatus');
      
      final result = await callable.call({
        // 🎯 서버에서 캐시 우선 사용 + 필요시 App Store Server API 호출
      });
      
      if (kDebugMode) {
        debugPrint('🔍 [SubscriptionRepository] Firebase Functions 응답 타입: ${result.data.runtimeType}');
      }
      
      // 🎯 안전한 타입 변환
      final responseData = _safeMapConversion(result.data);
      if (responseData == null) {
        if (kDebugMode) {
          debugPrint('⚠️ [SubscriptionRepository] 응답 데이터 변환 실패');
        }
        return _getDefaultEntitlements();
      }
      
      // 🎯 새로운 서버 응답 구조 확인
      final success = responseData['success'] as bool? ?? false;
      final dataSource = responseData['dataSource'] as String?;
      final version = responseData['version'] as String?;
      
      if (kDebugMode) {
        debugPrint('🔍 [SubscriptionRepository] 새로운 서버 응답:');
        debugPrint('   - 성공 여부: $success');
        debugPrint('   - 데이터 소스: $dataSource');
        debugPrint('   - 버전: $version');
        
        // 🎯 데이터 소스별 응답 분석
        switch (dataSource) {
          case 'cache':
            debugPrint('⚡ [Apple Best Practice] 캐시 사용 - 빠른 응답');
            break;
          case 'fresh-api':
            debugPrint('🎯 [Apple Best Practice] 최신 API 데이터 - 정확한 상태');
            break;
          case 'test-account':
            debugPrint('🧪 [Apple Best Practice] 테스트 계정 처리');
            break;
          default:
            debugPrint('🔍 [Apple Best Practice] 기본 처리');
        }
      }
      
      if (!success) {
        if (kDebugMode) {
          debugPrint('⚠️ [SubscriptionRepository] 서버에서 실패 응답');
        }
        return _getDefaultEntitlements();
      }
      
      final subscription = _safeMapConversion(responseData['subscription']);
      if (subscription == null) {
        if (kDebugMode) {
          debugPrint('⚠️ [SubscriptionRepository] subscription 필드 없음');
        }
        return _getDefaultEntitlements();
      }
      
      final entitlement = subscription['entitlement'] as String? ?? 'free';
      final subscriptionStatus = subscription['subscriptionStatus'] as String? ?? 'cancelled';
      final hasUsedTrial = subscription['hasUsedTrial'] as bool? ?? false;
      
      if (kDebugMode) {
        debugPrint('✅ [SubscriptionRepository] 서버 응답 파싱 완료: $entitlement/$subscriptionStatus');
        debugPrint('   - 캐시 연령: ${dataSource == 'cache' ? '캐시 사용' : '최신 데이터'}');
        debugPrint('   - 프리미엄 권한: ${entitlement == 'premium' ? '✅' : '❌'}');
        debugPrint('   - 체험 권한: ${entitlement == 'trial' ? '✅' : '❌'}');
      }
      
      return {
        'entitlement': entitlement,
        'subscriptionStatus': subscriptionStatus,
        'hasUsedTrial': hasUsedTrial,
        'isPremium': entitlement == 'premium',
        'isTrial': entitlement == 'trial',
        'isExpired': subscriptionStatus == 'expired',
        'statusMessage': _generateStatusMessage(entitlement, subscriptionStatus),
        'isActive': _isActiveStatus(entitlement, subscriptionStatus),
        '_timestamp': DateTime.now().toIso8601String(),
      };
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SubscriptionRepository] 서버 조회 실패: $e');
      }
      throw e;
    }
  }

  /// 🎯 안전한 Map 변환 헬퍼
  Map<String, dynamic>? _safeMapConversion(dynamic data) {
    if (data == null) return null;
    
    try {
      if (data is Map<String, dynamic>) {
        return data;
      } else if (data is Map) {
        // _Map<Object?, Object?> 등을 Map<String, dynamic>으로 변환
        return Map<String, dynamic>.from(data.map((key, value) => MapEntry(key.toString(), value)));
      } else {
        if (kDebugMode) {
          debugPrint('⚠️ [SubscriptionRepository] 예상치 못한 데이터 타입: ${data.runtimeType}');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SubscriptionRepository] Map 변환 실패: $e');
      }
      return null;
    }
  }

  /// 🎯 상태 메시지 생성
  String _generateStatusMessage(String entitlement, String subscriptionStatus) {
    if (entitlement == 'premium') {
      switch (subscriptionStatus) {
        case 'active':
          return '프리미엄 구독 중';
        case 'cancelled':
        case 'cancelling':
          return '프리미엄 구독 취소됨';
        case 'expired':
          return '프리미엄 구독 만료';
        default:
          return '프리미엄';
      }
    } else if (entitlement == 'trial') {
      switch (subscriptionStatus) {
        case 'active':
          return '무료체험 중';
        case 'cancelled':
        case 'cancelling':
          return '무료체험 취소됨';
        case 'expired':
          return '무료체험 완료';
        default:
          return '무료체험';
      }
    } else {
      return '무료 플랜';
    }
  }

  /// 🎯 활성 상태 확인
  bool _isActiveStatus(String entitlement, String subscriptionStatus) {
    return (entitlement == 'premium' || entitlement == 'trial') && 
           subscriptionStatus == 'active';
  }

  /// 🎯 기본 권한 (로그아웃/에러시)
  Map<String, dynamic> _getDefaultEntitlements() {
    return {
      'entitlement': 'free',
      'subscriptionStatus': 'cancelled',
      'hasUsedTrial': false,
      'isPremium': false,
      'isTrial': false,
      'isExpired': false,
      'statusMessage': '무료 플랜',
      'isActive': false,
      '_timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// 🎯 프리미엄 기능 사용 가능 여부
  Future<bool> canUsePremiumFeatures() async {
    final entitlements = await getSubscriptionEntitlements();
    return entitlements['isPremium'] == true || entitlements['isTrial'] == true;
  }

  /// 🎯 캐시 무효화
  void invalidateCache() {
    _cachedEntitlements = null;
    _lastEntitlementCheck = null;
    _ongoingRequest = null;
    
    if (kDebugMode) {
      debugPrint('🗑️ [SubscriptionRepository] 캐시 무효화');
    }
  }

  /// 🆕 BannerManager를 위한 전체 서버 응답 반환
  /// 
  /// BannerManager.getActiveBannersFromServerResponse에서 사용
  Future<Map<String, dynamic>> getRawServerResponse({bool forceRefresh = false}) async {
    if (kDebugMode) {
      debugPrint('🎯 [SubscriptionRepository] 전체 서버 응답 조회 (forceRefresh: $forceRefresh)');
    }
    
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      if (kDebugMode) {
        debugPrint('⚠️ [SubscriptionRepository] 로그아웃 상태 - 기본 응답 반환');
      }
      return {
        'success': false,
        'subscription': {
          'entitlement': 'free',
          'subscriptionStatus': 'cancelled',
          'hasUsedTrial': false,
        }
      };
    }
    
    final currentUserId = currentUser.uid;
    
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
      final callable = functions.httpsCallable('subCheckSubscriptionStatus');
      
      final result = await callable.call({
        // 🎯 서버에서 캐시 우선 사용 + 필요시 App Store Server API 호출
      });
      
      if (kDebugMode) {
        debugPrint('🔍 [SubscriptionRepository] BannerManager용 서버 응답 반환');
      }
      
      // 🎯 안전한 타입 변환
      final responseData = _safeMapConversion(result.data);
      if (responseData == null) {
        if (kDebugMode) {
          debugPrint('⚠️ [SubscriptionRepository] 응답 데이터 변환 실패');
        }
        return {
          'success': false,
          'subscription': {
            'entitlement': 'free',
            'subscriptionStatus': 'cancelled',
            'hasUsedTrial': false,
          }
        };
      }
      
      return responseData;
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SubscriptionRepository] 전체 서버 응답 조회 실패: $e');
      }
      return {
        'success': false,
        'subscription': {
          'entitlement': 'free',
          'subscriptionStatus': 'cancelled',
          'hasUsedTrial': false,
        }
      };
    }
  }

  /// 🎯 사용자 변경 시 캐시 초기화
  void clearUserCache() {
    _cachedEntitlements = null;
    _lastEntitlementCheck = null;
    _ongoingRequest = null;
    _lastUserId = null;
    
    if (kDebugMode) {
      debugPrint('🔄 [SubscriptionRepository] 사용자 변경으로 인한 캐시 초기화');
    }
  }

  /// 🎯 현재 캐시된 상태 (즉시 반환)
  Map<String, dynamic>? get cachedEntitlements => _cachedEntitlements;
  bool get isPremium => _cachedEntitlements?['isPremium'] ?? false;
  bool get isTrial => _cachedEntitlements?['isTrial'] ?? false;

  /// 🎯 설정 화면에서 사용할 수 있는 즉시 권한 확인
  /// 
  /// 캐시된 데이터가 있으면 즉시 반환, 없으면 기본값 반환
  /// UI 블로킹 없이 빠른 응답을 위해 사용
  Map<String, dynamic> getEntitlementsSync() {
    if (_cachedEntitlements != null) {
      return _cachedEntitlements!;
    }
    return _getDefaultEntitlements();
  }

  /// 🎯 활성 배너 포함 완전한 SubscriptionState 반환
  /// 
  /// HomeLifecycleCoordinator의 복잡성을 제거하고 직접적인 구조로 변경
  Future<SubscriptionState> getSubscriptionStateWithBanners() async {
    try {
      if (kDebugMode) {
        debugPrint('🎯 [SubscriptionRepository] 완전한 구독 상태 + 배너 조회');
      }
      
      // 🎯 병렬 처리: 권한 정보와 전체 서버 응답 동시 가져오기
      final futures = await Future.wait([
        getSubscriptionEntitlements(),
        getRawServerResponse(),
      ]);
      
      final entitlements = futures[0] as Map<String, dynamic>;
      final serverResponse = futures[1] as Map<String, dynamic>;
      
      // 🎯 BannerManager로 활성 배너 결정
      final activeBanners = await _bannerManager.getActiveBannersFromServerResponse(
        serverResponse,
        forceRefresh: false,
      );
      
      if (kDebugMode) {
        debugPrint('🎯 [SubscriptionRepository] 활성 배너 결정 완료: ${activeBanners.length}개');
        debugPrint('   배너 타입: ${activeBanners.map((e) => e.name).toList()}');
      }
      
      // SubscriptionState로 변환
      return SubscriptionState(
        entitlement: Entitlement.fromString(entitlements['entitlement']),
        subscriptionStatus: SubscriptionStatus.fromString(entitlements['subscriptionStatus']),
        hasUsedTrial: entitlements['hasUsedTrial'],
        hasUsageLimitReached: false, // 사용량은 별도 확인
        activeBanners: activeBanners,
        statusMessage: entitlements['statusMessage'] as String? ?? '상태 확인 중',
      );
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [SubscriptionRepository] 완전한 구독 상태 조회 실패: $e');
      }
      // 실패시 기본 상태
      return SubscriptionState.defaultState();
    }
  }
}

// 🎯 기존 호환성을 위한 별칭
typedef UnifiedSubscriptionManager = SubscriptionRepository; 