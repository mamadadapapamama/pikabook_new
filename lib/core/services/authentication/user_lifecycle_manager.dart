import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'user_account_service.dart';
import '../cache/event_cache_manager.dart';
import '../common/usage_limit_service.dart';
import '../payment/in_app_purchase_service.dart';
import '../subscription/unified_subscription_manager.dart';

/// 🎯 사용자 인증 상태 변화에 따른 후속 작업을 관리하는 서비스
class UserLifecycleManager {
  final AuthService _authService;
  final UserAccountService _userAccountService;

  StreamSubscription? _authSubscription;
  String? _lastUserId;
  bool _isInitialized = false;

  UserLifecycleManager(this._authService, this._userAccountService);

  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;

    _authSubscription = _authService.authStateChanges.listen((User? user) async {
      final currentUserId = user?.uid;
      
      if (_lastUserId != currentUserId) {
        if (kDebugMode) {
          debugPrint('🔄 [UserLifecycleManager] 인증 상태 변경: ${_lastUserId ?? "없음"} → ${currentUserId ?? "없음"}');
        }

        // 사용자 변경 또는 로그아웃 시
        if (_lastUserId != null) {
          _handleUserChange();
        }

        _lastUserId = currentUserId;

        // 새로운 사용자로 로그인 시
        if (user != null) {
          // Firestore 데이터 동기화는 AuthService에서 로그인 성공 시 이미 처리함
          // 여기서는 로그인 후 필요한 다른 서비스 초기화 작업을 수행
          _forceRefreshSubscriptionOnLogin();
        }
      }
    });
  }

  void _handleUserChange() {
    if (kDebugMode) {
      debugPrint('🔄 [UserLifecycleManager] 사용자 변경/로그아웃 감지 - 관련 서비스 정리');
    }
    // 모든 관련 서비스의 캐시/상태를 초기화
    InAppPurchaseService().clearUserCache();
    UsageLimitService().clearUserCache();
    UnifiedSubscriptionManager().invalidateCache();
    EventCacheManager().clearAllCache();
  }

  Future<void> _forceRefreshSubscriptionOnLogin() async {
    try {
      if (kDebugMode) {
        debugPrint('🔄 [UserLifecycleManager] 로그인 후 구독 정보 새로고침');
      }
      // UnifiedSubscriptionManager를 통해 구독 정보 강제 갱신
      await UnifiedSubscriptionManager().getSubscriptionState(forceRefresh: true);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [UserLifecycleManager] 로그인 후 구독 새로고침 실패: $e');
      }
    }
  }

  void dispose() {
    _authSubscription?.cancel();
    _isInitialized = false;
  }
} 